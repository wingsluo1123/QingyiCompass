import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { promptAction, router } from '@kit.ArkUI';
import { authentication, LoginWithHuaweiIDButton, loginComponentManager } from '@kit.AccountKit';
import AuthService, { HuaweiAuthCredential, HuaweiUserProfile, HuaweiUserSession } from '../service/AuthService';

@Entry
@Component
export struct LoginPage {
  @State private isLoggedIn: boolean = false;
  @State private unionID: string = '';
  @State private openID: string = '';
  @State private nickName: string = '';
  @State private avatarUri: string = '';
  @State private accountLevel: number = 0;
  @State private hasServerSession: boolean = false;
  @State private isLoading: boolean = false;

  private controller: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .onClickLoginWithHuaweiIDButton((error: BusinessError, response: loginComponentManager.HuaweiIDCredential) => {
        if (error) {
          this.handleLoginError(error);
          return;
        }
        if (response) {
          this.handleHuaweiCredential(response);
        }
      });

  aboutToAppear(): void {
    this.initPage();
  }

  private async initPage(): Promise<void> {
    let context: common.UIAbilityContext = AppStorage.get<common.UIAbilityContext>('Context') as common.UIAbilityContext;
    await AuthService.init(context);
    await this.refreshSession();
  }

  private async refreshSession(): Promise<void> {
    let session: HuaweiUserSession | null = await AuthService.getCurrentUser();
    this.isLoggedIn = session !== null;
    this.unionID = session?.unionID ?? '';
    this.openID = session?.openID ?? '';
    this.nickName = session?.nickName ?? '';
    this.avatarUri = session?.avatarUri ?? '';
    this.accountLevel = session?.accountLevel ?? 0;
    this.hasServerSession = (session?.appSessionToken ?? '').length > 0;
    console.log('level: ' + this.accountLevel + ', has server session: ' + this.hasServerSession);
  }

  private async handleHuaweiCredential(response: loginComponentManager.HuaweiIDCredential): Promise<void> {
    this.isLoading = true;
    try {
      let credential: HuaweiAuthCredential = {
        unionID: response.unionID,
        openID: response.openID,
        authorizationCode: response.authorizationCode,
        idToken: response.idToken ?? ''
      };

      let profile: HuaweiUserProfile = await this.requestHuaweiProfile();
      await AuthService.signInWithHuawei(credential, profile);
      await this.refreshSession();
      promptAction.showToast({ message: '登录成功', duration: 1500 });
    } catch (err) {
      promptAction.showToast({ message: '登录状态保存失败', duration: 1800 });
    } finally {
      this.isLoading = false;
    }
  }

  private async requestHuaweiProfile(): Promise<HuaweiUserProfile> {
    let profile: HuaweiUserProfile = { nickName: '', avatarUri: '' };
    try {
      let context: common.UIAbilityContext = AppStorage.get<common.UIAbilityContext>('Context') as common.UIAbilityContext;
      let provider: authentication.HuaweiIDProvider = new authentication.HuaweiIDProvider();
      let request: authentication.AuthorizationWithHuaweiIDRequest = provider.createAuthorizationWithHuaweiIDRequest();
      request.scopes = ['profile'];
      request.forceAuthorization = true;

      let controller: authentication.AuthenticationController = new authentication.AuthenticationController(context);
      let response: authentication.AuthorizationWithHuaweiIDResponse =
        await controller.executeRequest(request) as authentication.AuthorizationWithHuaweiIDResponse;
      let credential: authentication.AuthorizationWithHuaweiIDCredential | undefined = response.data;
      profile.nickName = credential?.nickName ?? '';
      profile.avatarUri = credential?.avatarUri ?? '';
    } catch (err) {
      return profile;
    }
    return profile;
  }

  private handleLoginError(error: BusinessError): void {
    let message: string = '登录失败';
    if (error.code === 1001502012) {
      message = '已取消登录';
    } else if (error.code === 1001502005) {
      message = '网络异常，请稍后再试';
    } else if (error.code === 1001500001) {
      message = '应用签名或指纹配置不正确';
    } else if (error.code === 1001502002) {
      message = '应用未获得华为账号授权';
    }
    promptAction.showToast({ message: message, duration: 1800 });
  }

  private maskIdentity(value: string): string {
    console.log('Masking identity value: ' + value);
    if (value.length <= 12) {
      return value;
    }
    return value.substring(0, 6) + '...' + value.substring(value.length - 6);
  }

  private async logout(): Promise<void> {
    await AuthService.clearSession();
    await this.refreshSession();
    promptAction.showToast({ message: '已退出登录', duration: 1500 });
  }

  @Builder
  statusPill(text: string, color: ResourceColor, background: ResourceColor) {
    Text(text)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(color)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(background)
      .borderRadius(14)
  }

  build() {
    Column() {
      Row() {
        Text('<')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor('#666')
          .onClick(() => {
            router.back();
          })
        
        

        Text('账号与登录')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Blank()
          .width(44)
      }
      .width('100%')
      .height(64)
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column({ space: 18 }) {
          Column({ space: 14 }) {
            if (this.isLoggedIn && this.avatarUri.length > 0) {
              Image(this.avatarUri)
                .width(72)
                .height(72)
                .borderRadius(36)
                .objectFit(ImageFit.Cover)
                .shadow({ radius: 18, color: '#163D4A1A', offsetX: 0, offsetY: 6 })
            } else {
              Image($r('app.media.qingyi'))
                .width(72)
                .height(72)
                .borderRadius(18)
                .shadow({ radius: 18, color: '#163D4A1A', offsetX: 0, offsetY: 6 })
            }

            Text(this.isLoggedIn ? (this.nickName.length > 0 ? this.nickName : '已登录华为账号') : '登录后使用个人知识库')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))

            Text(this.isLoggedIn ? '你的上传文档后续可按账号隔离和同步。' : '使用 Huawei Account Kit 获取稳定的 UnionID，避免不同用户共享同一份 RAG 文档。')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .lineHeight(22)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 20, bottom: 8 })

          if (this.isLoggedIn) {
            Column({ space: 14 }) {
              Row() {
                Text('登录状态')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
                this.statusPill('Active', '#176B43', '#E4F5EA')
              }
              .width('100%')

              Divider().color('#EEF2EE')

              if (this.nickName.length > 0) {
                Row() {
                  Text('昵称')
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                    .layoutWeight(1)
                  Text(this.nickName)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                }
                .width('100%')
              }

              Row() {
                Text('UnionID')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
                Text(this.maskIdentity(this.unionID))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
              }
              .width('100%')

              Row() {
                Text('OpenID')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
                Text(this.maskIdentity(this.openID))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
              }
              .width('100%')

              Row() {
                Text('Server session')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
                this.statusPill(this.hasServerSession ? 'Ready' : 'Local only',
                  this.hasServerSession ? '#176B43' : '#8B6F47',
                  this.hasServerSession ? '#E4F5EA' : '#FFF4D8')
              }
              .width('100%')

              Row() {
                Text('Account level')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
                this.statusPill('Level ' + this.accountLevel.toString(),
                  this.accountLevel >= 3 ? '#176B43' : '#8B6F47',
                  this.accountLevel >= 3 ? '#E4F5EA' : '#FFF4D8')
              }
              .width('100%')
            }
            .width('100%')
            .padding(18)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)

            Button('退出登录')
              .width('100%')
              .height(48)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.accent_red'))
              .backgroundColor('#FFFFFF')
              .borderRadius(8)
              .onClick(() => {
                this.logout();
              })
          } else {
            Column({ space: 12 }) {
              LoginWithHuaweiIDButton({
                params: {
                  style: loginComponentManager.Style.BUTTON_RED,
                  borderRadius: 8,
                  loginType: loginComponentManager.LoginType.ID,
                  supportDarkMode: true,
                  verifyPhoneNumber: true
                },
                controller: this.controller
              })
                .width('100%')
                .height(48)

              Text(this.isLoading ? '正在建立登录状态...' : '登录仅用于识别用户身份，不会在 App 端展示你的华为账号敏感信息。')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .lineHeight(18)
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .padding(18)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
          }
        }
        .width('100%')
        .padding({ left: 24, right: 24, bottom: 32 })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.start_window_background'))
  }
}
