import { promptAction, router } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';

@Entry
@Component
export struct AppAboutPage {
  private copyToClipboard(text: string, label: string): void {
    let pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
    systemPasteboard.setData(pasteData);
    promptAction.showToast({ message: `${label}已复制`, duration: 1500 });
  }

  @Builder
  featurePill(icon: Resource, label: string, color: ResourceColor) {
    Column({ space: 6 }) {
      Image(icon)
        .width(20)
        .height(20)
        .fillColor(color)
      Text(label)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
    }
    .width(72)
    .height(64)
    .borderRadius(8)
    .backgroundColor($r('app.color.card_background'))
    .shadow({ radius: 8, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 2 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  contactRow(icon: Resource, label: string, value: string, copyLabel: string) {
    Row({ space: 14 }) {
      Column() {
        Image(icon)
          .width(20)
          .height(20)
          .fillColor($r('app.color.light_blue'))
      }
      .width(44)
      .height(44)
      .borderRadius(11)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 2 }) {
        Text(label)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Text(value)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Medium)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        Text('复制')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
      }
      .width(54)
      .height(32)
      .fontColor($r('app.color.button_text'))
      .backgroundColor($r('app.color.button_background'))
      .borderRadius(16)
      .onClick(() => {
        this.copyToClipboard(value, copyLabel);
      })
    }
    .width('100%')
  }

  build() {
    Column() {
      Row() {
        Text('<')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.muted_icon'))
          .onClick(() => {
            router.back();
          })
        Text('关于清一罗盘')
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
        Column() {
          Column({ space: 12 }) {
            Image($r('app.media.qingyi'))
              .width(96)
              .height(96)
              .borderRadius(24)
              .shadow({ radius: 24, color: '#1A3D4A1A', offsetX: 0, offsetY: 8 })

            Text('清一罗盘')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .fontFamily('serif')

            Text('灵气所钟 · 堪舆之道')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .letterSpacing(4)
          }
          .width('100%')
          .height(236)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)

          Row({ space: 12 }) {
            this.featurePill($r('app.media.tab_compass'), '罗盘', $r('app.color.light_blue'))
            this.featurePill($r('app.media.tab_star'), '星盘', $r('app.color.light_blue'))
            // Offline release: restore the AI feature pill when cloud AI is enabled again.
            // this.featurePill($r('app.media.tab_ai'), 'AI', $r('app.color.light_blue'))
          }
          .justifyContent(FlexAlign.Center)
          .margin({ top: -18, bottom: 32 })

          Column({ space: 10 }) {
            Text('应用简介')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .letterSpacing(1.5)
              .padding({ left: 4 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Row({ space: 14 }) {
            Image($r('app.media.qingyi'))
              .width(44)
              .height(44)
              .fillColor($r('app.color.elegant_blue'))

            Text('清一罗盘是为华人风水爱好者设计的离线罗盘应用，融合传统堪舆智慧与现代技术，提供方位测定与星盘排盘功能。')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .lineHeight(24)
              .layoutWeight(1)
          }
          .width('100%')
          .padding(18)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(8)
          .alignItems(VerticalAlign.Top)

          Column({ space: 10 }) {
            Text('联系开发者')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .letterSpacing(1.5)
              .padding({ left: 4 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 36 })

          Column() {
            this.contactRow($r('app.media.icon_email'), '邮箱地址', '2906545455@qq.com', '邮箱')

            Divider()
              .height(1)
              .color($r('app.color.divider'))
              .margin({ top: 4, bottom: 4 })

            this.contactRow($r('app.media.icon_qq_group'), 'QQ交流群', '256153808', 'Q群号')
          }
          .width('100%')
          .padding(18)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(8)

          Text('清一罗盘 · 传承中华堪舆之术')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 32, bottom: 40 })
        }
        .width('100%')
        .padding({ left: 24, right: 24 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.start_window_background'))
  }
}
