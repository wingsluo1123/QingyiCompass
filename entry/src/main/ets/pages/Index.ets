import { CompassPage } from "./CompassPage"
import { ChartEntry } from "./Chart"
import { About } from "./About"
// Offline release: restore this import when the knowledge-base feature is enabled again.
import { KnowledgePage } from "./KnowledgePage"
import { AiChatPage } from "./AiChatPage"
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';

@Component
@Entry
struct Index {
  @State currentIndex: number = 0;
  @State customMaterialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.EXQUISITE;
  private tabIcons: Resource[] = [
    $r('app.media.tab_compass'),
    $r('app.media.tab_star'),
    $r('app.media.tab_knowledge'),
    $r('app.media.tab_ai'),
    $r('app.media.tab_info')
  ];

  aboutToAppear(): void {
    let materialTypes: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
    if (materialTypes.indexOf(hdsMaterial.MaterialType.IMMERSIVE) < 0) {
      this.customMaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
    }
  }

  @Builder tabBuilder(label: string, index: number) {
    Column() {
      Image(this.tabIcons[index])
        .width(22)
        .height(22)
        .fillColor(this.currentIndex === index ? $r('app.color.elegant_blue') : $r('app.color.light_blue'))

      Text(label)
        .fontSize(12)
        .fontColor(this.currentIndex === index ? $r('app.color.elegant_blue') : $r('app.color.text_secondary'))
        .margin({ top: 4 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      HdsTabs({
        index: this.currentIndex
      }) {
        TabContent() {
          CompassPage()
        }
        .tabBar(this.tabBuilder('罗盘', 0))

        TabContent() {
          ChartEntry()
        }
        .tabBar(this.tabBuilder('星盘', 1))

        // Offline release: restore this tab when the knowledge-base feature is enabled again.
        TabContent() {
          KnowledgePage()
        }
        .tabBar(this.tabBuilder('知识库', 2))

        TabContent() {
          AiChatPage()
        }
        .tabBar(this.tabBuilder('AI', 3))

        TabContent() {
          About()
        }
        .tabBar(this.tabBuilder('我的', 4))
      }
      .barOverlap(true)
      .barHeight(48)
      .barMode(BarMode.Fixed)
      .barPosition(BarPosition.End)
      .scrollable(false) //设置是否能滑动切换
      .barFloatingStyle({
        barBottomMargin: 3,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: this.customMaterialLevel
        }
      })
      .onChange((index: number) => {
        this.currentIndex = index;
        AppStorage.setOrCreate('tabIndex', index);
      })
    }
    .backgroundColor($r('app.color.start_window_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }
}
