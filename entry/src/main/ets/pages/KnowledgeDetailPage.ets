import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import ApiConfigService from '../service/ApiConfigService';
import KnowledgeService, { KnowledgeChunk } from '../service/KnowledgeService';
import AuthService from '../service/AuthService';

interface KnowledgeDetailParams {
  id: string;
  name: string;
  source: string;
  chunkCount: number;
  isRemote: boolean;
}

@Entry
@Component
export struct KnowledgeDetailPage {
  @State docId: string = '';
  @State docName: string = '';
  @State docSource: string = '';
  @State chunkCount: number = 0;
  @State isRemote: boolean = false;
  @State chunks: KnowledgeChunk[] = [];
  @State isLoading: boolean = false;
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;

  aboutToAppear(): void {
    ApiConfigService.init(this.context);
    AuthService.init(this.context);
    this.readParams();
    this.loadChunks();
  }

  private readParams(): void {
    let params: KnowledgeDetailParams = router.getParams() as KnowledgeDetailParams;
    this.docId = params.id ?? '';
    this.docName = params.name ?? '文档详情';
    this.docSource = params.source ?? '';
    this.chunkCount = params.chunkCount ?? 0;
    this.isRemote = params.isRemote ?? false;
  }

  private normalizeDocName(title: string): string {
    let idx: number = title.indexOf(' (');
    if (idx >= 0) {
      return title.substring(0, idx);
    }
    return title;
  }

  private async loadChunks(): Promise<void> {
    this.isLoading = true;
    try {
      if (this.isRemote) {
        this.chunks = await this.loadRemoteChunks();
      } else {
        this.chunks = this.loadLocalChunks();
      }
      this.chunkCount = this.chunks.length;
    } catch (e) {
      promptAction.showToast({ message: '文档详情加载失败，请检查 RAG 服务', duration: 2200 });
    } finally {
      this.isLoading = false;
    }
  }

  private async loadRemoteChunks(): Promise<KnowledgeChunk[]> {
    let ragUrl: string = await ApiConfigService.getRagUrl();
    let ragToken: string = await ApiConfigService.getRagToken();
    await AuthService.init(this.context);
    let appSessionToken: string = await AuthService.getOrCreateAppSessionToken();
    let httpRequest = http.createHttp();
    let response = await httpRequest.request(
      ragUrl + '/v1/rag/documents/' + this.docId + '/chunks',
      {
        method: http.RequestMethod.GET,
        header: {
          'Authorization': 'Bearer ' + ragToken,
          'X-App-Session': appSessionToken,
          'User-Agent': 'Compass/1.0 HarmonyOS'
        },
        connectTimeout: 5000,
        readTimeout: 15000
      }
    );
    httpRequest.destroy();

    if (response.responseCode !== 200) {
      throw new Error('RAG server returned ' + response.responseCode.toString());
    }

    let body: Record<string, object> = JSON.parse(response.result as string) as Record<string, object>;
    return (body['chunks'] as KnowledgeChunk[]) || [];
  }

  private loadLocalChunks(): KnowledgeChunk[] {
    let allChunks: KnowledgeChunk[] = KnowledgeService.getAllChunks();
    return allChunks.filter((chunk: KnowledgeChunk) => {
      return chunk.source === this.docSource && this.normalizeDocName(chunk.title) === this.docName;
    });
  }

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Text('←')
            .fontSize(20)
            .fontColor($r('app.color.text_secondary'))
        }
        .width(44)
        .height(44)
        .backgroundColor('#00000000')
        .onClick(() => {
          router.back();
        })

        Text('文档详情')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 12, bottom: 8 })

      Column() {
        Row() {
          Text(this.docSource)
            .fontSize(12)
            .fontColor($r('app.color.primary_action_text'))
            .fontWeight(FontWeight.Medium)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor(this.docSource === '内置经典' ? $r('app.color.elegant_blue') : $r('app.color.danger'))
            .borderRadius(10)
        }
        .width('100%')
        .margin({ top: 12, bottom: 8 })

        Text(this.docName)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Text((this.isLoading ? this.chunkCount : this.chunks.length).toString() + ' 个知识片段')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4, bottom: 20 })

        if (this.isLoading) {
          Column() {
            Text('加载中...')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          List() {
            ForEach(this.chunks, (chunk: KnowledgeChunk, idx: number) => {
              ListItem() {
                Column() {
                  Text('片段 ' + (idx + 1).toString())
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .fontWeight(FontWeight.Medium)
                    .margin({ bottom: 6 })

                  Text(chunk.content)
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .lineHeight(22)
                }
                .width('100%')
                .padding(16)
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(12)
              }
              .width('100%')
            })
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ top: 8 })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 24, right: 24 })
    }
    .padding({bottom: 40})
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.start_window_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
