import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import ApiConfigService from './ApiConfigService';

const STORE_NAME = 'compass_auth';
const KEY_USER_SESSION = 'user_session';
const KEY_GUEST_ID = 'guest_id';
const KEY_GUEST_SESSION = 'guest_session';
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

export interface GuestUserSession {
  guestID: string;
  appSessionToken: string;
  accountLevel: number;
  expiresAt: number;
  createdAt: number;
}

interface HuaweiLoginRequest {
  union_id: string;
  open_id: string;
  authorization_code: string;
  id_token: string;
}

interface GuestLoginRequest {
  guest_id: string;
}

interface CustomerLoginRequest {
  account_id: string;
  access_code: string;
}

interface HuaweiLoginResponse {
  session_token: string;
  union_id: string;
  open_id: string;
  level: number;
  expires_in: number;
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

  async getOrCreateAppSessionToken(): Promise<string> {
    let huaweiToken: string = await this.getAppSessionToken();
    if (huaweiToken.length > 0) {
      return huaweiToken;
    }

    let guestToken: string = await this.getGuestSessionToken();
    if (guestToken.length > 0) {
      return guestToken;
    }

    return await this.createGuestSessionToken();
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

  async signInWithCustomer(accountID: string, accessCode: string): Promise<HuaweiUserSession> {
    let normalizedAccountID: string = accountID.trim();
    let loginResponse: HuaweiLoginResponse = await this.exchangeCustomerCredential(normalizedAccountID, accessCode.trim());

    let session: HuaweiUserSession = {
      provider: 'customer',
      unionID: loginResponse.union_id,
      openID: loginResponse.open_id,
      idToken: '',
      nickName: '客户账号 ' + normalizedAccountID,
      avatarUri: '',
      appSessionToken: loginResponse.session_token,
      accountLevel: loginResponse.level,
      loggedInAt: Date.now()
    };

    await this.saveSession(session);
    await this.clearGuestSession();
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

  private async clearGuestSession(): Promise<void> {
    if (!this.store) {
      return;
    }
    await this.store.delete(KEY_GUEST_SESSION);
    await this.store.flush();
  }

  private async saveSession(session: HuaweiUserSession): Promise<void> {
    if (!this.store) {
      return;
    }
    await this.store.put(KEY_USER_SESSION, JSON.stringify(session));
    await this.store.flush();
    this.publishSession(session);
  }

  private async getOrCreateGuestId(): Promise<string> {
    if (!this.store) {
      return this.generateGuestId();
    }

    let existing: string = await this.store.get(KEY_GUEST_ID, '') as string;
    if (existing.length > 0) {
      return existing;
    }

    let guestId: string = this.generateGuestId();
    await this.store.put(KEY_GUEST_ID, guestId);
    await this.store.flush();
    return guestId;
  }

  private generateGuestId(): string {
    return Date.now().toString(36) + '-' + Math.random().toString(36).substring(2, 12);
  }

  private async getGuestSessionToken(): Promise<string> {
    if (!this.store) {
      return '';
    }

    let raw: string = await this.store.get(KEY_GUEST_SESSION, '') as string;
    if (raw.length === 0) {
      return '';
    }

    try {
      let session: GuestUserSession = JSON.parse(raw) as GuestUserSession;
      if (session.appSessionToken.length > 0 && session.expiresAt > Date.now() + 60000) {
        return session.appSessionToken;
      }
    } catch (err) {
    }

    await this.store.delete(KEY_GUEST_SESSION);
    await this.store.flush();
    return '';
  }

  private async createGuestSessionToken(): Promise<string> {
    if (!this.store) {
      return '';
    }

    let ragUrl: string = await ApiConfigService.getRagUrl();
    let ragToken: string = await ApiConfigService.getRagToken();
    let guestId: string = await this.getOrCreateGuestId();
    let url: string = ragUrl.replace(/\/$/, '') + '/v1/auth/guest/login';

    let body: GuestLoginRequest = {
      guest_id: guestId
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
      throw new Error('Guest auth server rejected login');
    }

    let result: HuaweiLoginResponse = JSON.parse(response.result as string) as HuaweiLoginResponse;
    let expiresIn: number = result.expires_in || 0;
    let guestSession: GuestUserSession = {
      guestID: guestId,
      appSessionToken: result.session_token,
      accountLevel: result.level,
      expiresAt: Date.now() + (expiresIn > 0 ? expiresIn : 60 * 60 * 24 * 30) * 1000,
      createdAt: Date.now()
    };

    await this.store.put(KEY_GUEST_SESSION, JSON.stringify(guestSession));
    await this.store.flush();
    return guestSession.appSessionToken;
  }

  private publishSession(session: HuaweiUserSession | null): void {
    let isLoggedIn: boolean = session !== null;
    let nickName: string = session?.nickName ?? '';
    let avatarUri: string = session?.avatarUri ?? '';
    let accountLevel: number = session?.accountLevel ?? 0;
    let fallbackLabel: string = session?.provider === 'customer' ? 'Customer account' : 'Huawei account';
    let label: string = isLoggedIn ? (nickName.length > 0 ? nickName : fallbackLabel) : 'Guest';

    AppStorage.setOrCreate<boolean>(STORAGE_AUTH_IS_LOGGED_IN, isLoggedIn);
    AppStorage.setOrCreate<string>(STORAGE_AUTH_NICK_NAME, nickName);
    AppStorage.setOrCreate<string>(STORAGE_AUTH_AVATAR_URI, avatarUri);
    AppStorage.setOrCreate<string>(STORAGE_AUTH_LABEL, label);
    AppStorage.setOrCreate<number>(STORAGE_AUTH_LEVEL, accountLevel);
  }

  private async exchangeCustomerCredential(accountID: string, accessCode: string): Promise<HuaweiLoginResponse> {
    let ragUrl: string = await ApiConfigService.getRagUrl();
    let ragToken: string = await ApiConfigService.getRagToken();
    let url: string = ragUrl.replace(/\/$/, '') + '/v1/auth/customer/login';

    let body: CustomerLoginRequest = {
      account_id: accountID,
      access_code: accessCode
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
      throw new Error('Auth server rejected customer login');
    }
    let result: HuaweiLoginResponse = JSON.parse(response.result as string) as HuaweiLoginResponse;
    return result;
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
