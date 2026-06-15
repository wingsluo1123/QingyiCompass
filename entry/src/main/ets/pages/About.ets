// Offline release: restore AbilityKit and AuthService imports when account features are enabled again.
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import ThemeService from '../service/ThemeService';
// import AuthService, { HuaweiUserSession } from '../service/AuthService';

@Entry
@Component
export struct About {
  @StorageLink('isDarkMode') private isDarkMode: boolean = false;
  // Offline release: restore these states and lifecycle methods with account/knowledge-base features.
  // @State private isLoggedIn: boolean = false;
  // @State private accountLabel: string = '登录华为账号';
  // @State private accountHint: string = '用于个人知识库与文档权限';
  // @StorageLink('authIsLoggedIn') private authIsLoggedIn: boolean = false;
  // @StorageLink('authNickName') private authNickName: string = '';
  // @StorageLink('authAvatarUri') private authAvatarUri: string = '';
  // @StorageLink('authLabel') private authLabel: string = 'Guest';
  // @StorageLink('authLevel') private authLevel: number = 0;
  //
  // aboutToAppear(): void {
  //   this.loadAccountState();
  // }
  //
  // onPageShow(): void {
  //   this.loadAccountState();
  // }
  //
  // private async loadAccountState(): Promise<void> {
  //   let context: common.UIAbilityContext =
  //     AppStorage.get<common.UIAbilityContext>('Context') as common.UIAbilityContext;
  //   await AuthService.init(context);
  //   let session: HuaweiUserSession | null = await AuthService.getCurrentUser();
  //   this.isLoggedIn = session !== null;
  //   let nickName: string = session?.nickName ?? '';
  //   this.accountLabel = this.isLoggedIn ? (nickName.length > 0 ? nickName : 'Huawei account') : '登录华为账号';
  //   this.accountHint = this.isLoggedIn ? '个人文档已按账号隔离' : '登录后启用个人知识库隔离';
  // }
  //
  // private getDisplayName(): string {
  //   if (this.authIsLoggedIn && this.authLabel.length > 0) {
  //     return this.authLabel;
  //   }
  //   return this.accountLabel;
  // }

  private navigateTo(targetUrl: string): void {
    if (targetUrl.length === 0) {
      return;
    }
    router.pushUrl({ url: targetUrl });
  }

  private setDarkMode(enabled: boolean): void {
    const context: common.UIAbilityContext =
      AppStorage.get<common.UIAbilityContext>('Context') as common.UIAbilityContext;
    ThemeService.saveDarkMode(context, enabled);
    this.isDarkMode = enabled;
    context.getApplicationContext().setColorMode(enabled ?
      ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
  }

  // Offline release: restore levelBadge() with account features.
  // @Builder
  // levelBadge() {
  //   Row({ space: 6 }) {
  //     Text('H')
  //       .fontSize(12)
  //       .fontWeight(FontWeight.Bold)
  //       .fontColor('#FFFFFF')
  //     Text(this.authIsLoggedIn ? 'Level ' + this.authLevel.toString() : 'Guest')
  //       .fontSize(13)
  //       .fontWeight(FontWeight.Medium)
  //       .fontColor($r('app.color.text_primary'))
  //   }
  //   .height(34)
  //   .padding({ left: 12, right: 14 })
  //   .backgroundColor('#EEF6F1')
  //   .borderRadius(17)
  // }

  @Builder
  sectionTitle(title: string) {
    Row({ space: 8 }) {
      Blank()
        .width(4)
        .height(18)
        .backgroundColor($r('app.color.elegant_blue'))
        .borderRadius(2)

      Text(title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .padding({ left: 4, top: 6, bottom: 2 })
  }

  @Builder
  menuItem(marker: string, title: string, subtitle: string, tint: ResourceColor, targetUrl: string, showDivider: boolean) {
    Column() {
      Row({ space: 14 }) {
      //   Column() {
      //     Text(marker)
      //       .fontSize(16)
      //       .fontWeight(FontWeight.Bold)
      //       .fontColor(tint)
      //   }
      //   .width(48)
      //   .height(48)
      //   .borderRadius(12)
      //   .backgroundColor('#F3F7F4')
      //   .justifyContent(FlexAlign.Center)
      //   .alignItems(HorizontalAlign.Center)

        Column({ space: 4 }) {
          Text(title)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (subtitle.length > 0) {
            Text(subtitle)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('>')
          .fontSize(18)
          .fontColor($r('app.color.muted_icon'))
      }
      .width('100%')
      .height(76)
      .padding({ left: 16, right: 16 })
      .onClick(() => {
        this.navigateTo(targetUrl);
      })

      if (showDivider) {
        Divider()
          .color($r('app.color.divider'))
          .margin({ left: 78, right: 16 })
      }
    }
    .width('100%')
  }

  @Builder
  contactItem(label: string, value: string, showDivider: boolean) {
    Column() {
      Row() {
        Column({ space: 3 }) {
          Text(label)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))

          Text(value)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height(68)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      if (showDivider) {
        Divider()
          .color($r('app.color.divider'))
          .margin({ left: 16, right: 16 })
      }
    }
    .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 20 }) {
        Row() {
          Text('我的')
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          // Offline release: account settings entry is disabled.
          // Button({ type: ButtonType.Circle, stateEffect: true }) {
          //   Image($r('app.media.icon_settings'))
          //     .width(22)
          //     .height(22)
          // }
          // .width(52)
          // .height(52)
          // .backgroundColor('#FFFFFF')
          // .border({ width: 1, color: '#DFE8E2' })
          // .onClick(() => {
          //   this.navigateTo('pages/LoginPage');
          // })
        }
        .width('100%')
        .padding({ top: 30 })

        // Offline release: the account and personal knowledge-base card is disabled.
        /*
        Column() {
          Row({ space: 18 }) {
            if (this.authIsLoggedIn && this.authAvatarUri.length > 0) {
              Image(this.authAvatarUri)
                .width(92)
                .height(92)
                .borderRadius(46)
                .objectFit(ImageFit.Cover)
                .border({ width: 3, color: '#B8D8FF' })
            } else {
              Image($r('app.media.qingyi'))
                .width(92)
                .height(92)
                .borderRadius(46)
                .objectFit(ImageFit.Cover)
                .border({ width: 3, color: '#B8D8FF' })
            }

            Column({ space: 9 }) {
              Row({ space: 10 }) {
                Text(this.getDisplayName())
                  .fontSize(24)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)

                this.levelBadge()
              }
              .width('100%')

              Text(this.accountHint)
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 24, bottom: 22 })

          Divider()
            .color('#E7EEE9')
            .margin({ left: 20, right: 20 })

          Row() {
            Column({ space: 5 }) {
              Text(this.authIsLoggedIn ? '个人知识库已启用' : '解锁个人知识库')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text(this.accountHint)
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Button(this.authIsLoggedIn ? '管理' : '登录')
              .height(38)
              .padding({ left: 18, right: 18 })
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .backgroundColor($r('app.color.primary_green'))
              .borderRadius(19)
              .onClick(() => {
                this.navigateTo('pages/LoginPage');
              })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 18, bottom: 20 })
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(8)
        .shadow({ radius: 18, color: '#163D4A12', offsetX: 0, offsetY: 8 })
        */

        Column() {
          Row({ space: 18 }) {
            Image($r('app.media.qingyi'))
              .width(88)
              .height(88)
              .borderRadius(44)
              .objectFit(ImageFit.Cover)
              .border({ width: 3, color: '#B8D8FF' })

            Column({ space: 8 }) {
              Text('清一罗盘')
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))

              Text('专业的罗盘与星盘')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))

              Text('后端能力敬请期待')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.elegant_blue'))
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .backgroundColor($r('app.color.badge_background'))
                .borderRadius(12)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 24, bottom: 24 })
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .border({ width: 1, color: $r('app.color.surface_border') })
        .shadow({ radius: 16, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 6 })

        this.sectionTitle('常用设置')

        Column() {
          Row() {
            Column({ space: 4 }) {
              Text('夜间模式')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))

              Text('使用深色界面，降低夜间亮度')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.isDarkMode })
              .selectedColor($r('app.color.elegant_blue'))
              .onChange((isOn: boolean) => {
                this.setDarkMode(isOn);
              })
          }
          .width('100%')
          .height(76)
          .padding({ left: 16, right: 16 })

          Divider()
            .color($r('app.color.divider'))
            .margin({ left: 16, right: 16 })

          // Offline release: restore the account entry with account/knowledge-base features.
          // this.menuItem('A', '账号与登录',
          //   this.authIsLoggedIn ? '管理华为账号、头像昵称和登录状态' : '登录后启用个人文档隔离',
          //   $r('app.color.elegant_blue'), 'pages/LoginPage', true)
          this.menuItem('I', '关于清一罗盘', '应用简介、联系方式与交流信息',
            $r('app.color.elegant_blue'), 'pages/AppAboutPage', false)
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .border({ width: 1, color: $r('app.color.surface_border') })
        .shadow({ radius: 12, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 4 })

        this.sectionTitle('联系信息')

        Column() {
          this.contactItem('QQ群号', '256153808', true)
          this.contactItem('网站', 'wingsluo.com', true)
          this.contactItem('Email', 'wingsluo1123@gmail.com', true)
          this.contactItem('QQ邮箱', '2906545455@qq.com', false)
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .border({ width: 1, color: $r('app.color.surface_border') })
        .shadow({ radius: 12, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 4 })

      }
      .width('100%')
      .padding({ left: 22, right: 22, bottom: 92 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.start_window_background'))
  }
}
