import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import ApiConfigService from './ApiConfigService';

const STORE_NAME = 'compass_auth';
const KEY_USER_SESSION = 'user_session';
const STORAGE_AUTH_IS_LOGGED_IN = 'authIsLoggedIn';
const STORAGE_AUTH_NICK_NAME = 'authNickName';
const STORAGE_AUTH_AVATAR_URI = 'authAvatarUri';
const STORAGE_AUTH_LABEL = 'authLabel';
const STORAGE_AUTH_LEVEL = 'authLevel';

export interface HuaweiAuthCredential {
  unionID: string;
  openID: string;
  authorizationCode: string;
  idToken: string;
}

export interface HuaweiUserProfile {
  nickName: string;
  avatarUri: string;
}

export interface HuaweiUserSession {
  provider: string;
  unionID: string;
  openID: string;
  idToken: string;
  nickName: string;
  avatarUri: string;
  appSessionToken: string;
  accountLevel: number;
  loggedInAt: number;
}

interface HuaweiLoginRequest {
  union_id: string;
  open_id: string;
  authorization_code: string;
  id_token: string;
}

interface HuaweiLoginResponse {
  session_token: string;
  union_id: string;
  open_id: string;
  level: number;
}

export class AuthService {
  private static instance: AuthService;
  private store: preferences.Preferences | null = null;

  static getInstance(): AuthService {
    if (!AuthService.instance) {
      AuthService.instance = new AuthService();
    }
    return AuthService.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.store) {
      return;
    }
    this.store = await preferences.getPreferences(context, STORE_NAME);
    let session: HuaweiUserSession | null = await this.getCurrentUser();
    this.publishSession(session);
  }

  async getCurrentUser(): Promise<HuaweiUserSession | null> {
    if (!this.store) {
      return null;
    }
    let raw: string = await this.store.get(KEY_USER_SESSION, '') as string;
    if (raw.length === 0) {
      return null;
    }
    try {
      let session: HuaweiUserSession = JSON.parse(raw) as HuaweiUserSession;
      if (session.accountLevel === undefined) {
        session.accountLevel = 1;
      }
      this.publishSession(session);
      return session;
    } catch (err) {
      await this.clearSession();
      return null;
    }
  }

  async getAppSessionToken(): Promise<string> {
    let session: HuaweiUserSession | null = await this.getCurrentUser();
    return session?.appSessionToken ?? '';
  }

  async signInWithHuawei(credential: HuaweiAuthCredential, profile?: HuaweiUserProfile): Promise<HuaweiUserSession> {
    let loginResponse: HuaweiLoginResponse = await this.exchangeHuaweiCredential(credential);

    let session: HuaweiUserSession = {
      provider: 'huawei',
      unionID: credential.unionID,
      openID: credential.openID,
      idToken: credential.idToken,
      nickName: profile?.nickName ?? '',
      avatarUri: profile?.avatarUri ?? '',
      appSessionToken: loginResponse.session_token,
      accountLevel: loginResponse.level,
      loggedInAt: Date.now()
    };

    await this.saveSession(session);
    return session;
  }

  async clearSession(): Promise<void> {
    if (!this.store) {
      return;
    }
    await this.store.delete(KEY_USER_SESSION);
    await this.store.flush();
    this.publishSession(null);
  }

  private async saveSession(session: HuaweiUserSession): Promise<void> {
    if (!this.store) {
      return;
    }
    await this.store.put(KEY_USER_SESSION, JSON.stringify(session));
    await this.store.flush();
    this.publishSession(session);
  }

  private publishSession(session: HuaweiUserSession | null): void {
    let isLoggedIn: boolean = session !== null;
    let nickName: string = session?.nickName ?? '';
    let avatarUri: string = session?.avatarUri ?? '';
    let accountLevel: number = session?.accountLevel ?? 0;
    let label: string = isLoggedIn ? (nickName.length > 0 ? nickName : 'Huawei account') : 'Guest';

    AppStorage.setOrCreate<boolean>(STORAGE_AUTH_IS_LOGGED_IN, isLoggedIn);
    AppStorage.setOrCreate<string>(STORAGE_AUTH_NICK_NAME, nickName);
    AppStorage.setOrCreate<string>(STORAGE_AUTH_AVATAR_URI, avatarUri);
    AppStorage.setOrCreate<string>(STORAGE_AUTH_LABEL, label);
    AppStorage.setOrCreate<number>(STORAGE_AUTH_LEVEL, accountLevel);
  }

  private async exchangeHuaweiCredential(credential: HuaweiAuthCredential): Promise<HuaweiLoginResponse> {
    let ragUrl: string = await ApiConfigService.getRagUrl();
    let ragToken: string = await ApiConfigService.getRagToken();
    let url: string = ragUrl.replace(/\/$/, '') + '/v1/auth/huawei/login';

    let body: HuaweiLoginRequest = {
      union_id: credential.unionID,
      open_id: credential.openID,
      authorization_code: credential.authorizationCode,
      id_token: credential.idToken
    };

    let httpRequest = http.createHttp();
    let response = await httpRequest.request(
      url,
      {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + ragToken,
          'User-Agent': 'Compass/1.0 HarmonyOS'
        },
        extraData: JSON.stringify(body),
        connectTimeout: 8000,
        readTimeout: 8000
      }
    );
    httpRequest.destroy();

    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error('Auth server rejected Huawei login');
    }
    let result: HuaweiLoginResponse = JSON.parse(response.result as string) as HuaweiLoginResponse;
    return result;
  }
}

export default AuthService.getInstance();
