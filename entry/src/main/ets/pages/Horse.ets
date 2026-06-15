import { router } from '@kit.ArkUI';

@Entry
@Component
struct Horse {
  private timeoutId: number = -1;

  aboutToAppear() {
    // 延迟2秒后自动跳转到Index页面
    this.timeoutId = setTimeout(() => {
      router.replaceUrl({ url: 'pages/Index' }, router.RouterMode.Single);
    }, 2000);
  }

  aboutToDisappear(): void {
    if (this.timeoutId !== -1) {
      clearTimeout(this.timeoutId);
      this.timeoutId = -1;
    }
  }

  build() {
    Column() {
      Stack() {
        Image($r('app.media.qingyi_high'))
          .width(140)
          .height(140)
          .objectFit(ImageFit.Cover)
          .scale({ x: 1.32, y: 1.32 })
      }
      .width(176)
      .height(176)
      .clip(true)
      .borderRadius(88)
      .backgroundColor($r('app.color.splash_logo_surface'))
      .border({ width: 1, color: $r('app.color.splash_logo_border') })
      .shadow({
        radius: 24,
        color: $r('app.color.splash_logo_shadow'),
        offsetX: 0,
        offsetY: 10
      })
        .margin({ bottom: 125 })
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .backgroundColor($r('app.color.splash_background'))
  }
}
