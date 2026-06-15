import { promptAction, router } from '@kit.ArkUI';
import KnowledgeService, { KnowledgeChunk } from '../service/KnowledgeService';
import { common } from '@kit.AbilityKit';
import ApiConfigService from '../service/ApiConfigService';
import { http } from '@kit.NetworkKit';
import { buffer } from '@kit.ArkTS';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import AuthService from '../service/AuthService';

interface DocInfo {
  id: string;
  name: string;
  chunks: KnowledgeChunk[];
  source: string;
  chunkCount: number;
}

interface RemoteDocSummary {
  id: string;
  name: string;
  source: string;
  category: string;
  chunk_count: number;
}

interface UploadResponse {
  file_name: string;
  title: string;
  chunk_count: number;
  total_chunk_count: number;
}

@Entry
@Component
export struct KnowledgePage {
  @State documents: DocInfo[] = [];
  @State showDetail: boolean = false;
  @State selectedDoc: DocInfo | null = null;
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State isUploading: boolean = false;
  @State remoteChunkCount: number = 0;
  @State remoteBuiltinCount: number = 0;
  @State remoteUserCount: number = 0;
  @State lastSyncError: string = '';
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;

  aboutToAppear(): void {
    ApiConfigService.init(this.context);
    AuthService.init(this.context);
    this.loadDocuments();
    this.loadRemoteDocuments();
  }

  loadDocuments(): void {
    let allChunks: KnowledgeChunk[] = KnowledgeService.getAllChunks();
    let docMap: Map<string, KnowledgeChunk[]> = new Map();

    for (let chunk of allChunks) {
      let key: string = chunk.source + '|' + chunk.title.split(' (第')[0];
      if (!docMap.has(key)) {
        docMap.set(key, []);
      }
      let arr: KnowledgeChunk[] | undefined = docMap.get(key);
      if (arr) {
        arr.push(chunk);
      }
    }

    this.documents = [];
    let keys: string[] = [];
    docMap.forEach((_v: KnowledgeChunk[], k: string) => {
      keys.push(k);
    });

    for (let key of keys) {
      let parts: string[] = key.split('|');
      let source: string = parts[0];
      let name: string = parts.length > 1 ? parts[1] : key;
      let chunks: KnowledgeChunk[] | undefined = docMap.get(key);
      this.documents.push({
        id: key,
        name: name,
        chunks: chunks || [],
        source: source,
        chunkCount: chunks ? chunks.length : 0
      });
    }
  }

  private async loadRemoteDocuments(): Promise<boolean> {
    try {
      let ragUrl: string = await ApiConfigService.getRagUrl();
      let ragToken: string = await ApiConfigService.getRagToken();
      await AuthService.init(this.context);
      let appSessionToken: string = await AuthService.getAppSessionToken();
      if (ragUrl.trim().length === 0) {
        this.lastSyncError = 'RAG URL empty';
        return false;
      }

      let httpRequest = http.createHttp();
      let response = await httpRequest.request(
        ragUrl + '/v1/rag/documents',
        {
          method: http.RequestMethod.GET,
          header: {
            'Authorization': 'Bearer ' + ragToken,
            'X-App-Session': appSessionToken,
            'User-Agent': 'Compass/1.0 HarmonyOS'
          },
          connectTimeout: 5000,
          readTimeout: 10000
        }
      );
      httpRequest.destroy();

      if (response.responseCode !== 200) {
        this.lastSyncError = 'HTTP ' + response.responseCode.toString();
        return false;
      }

      let body: Record<string, object> = JSON.parse(response.result as string) as Record<string, object>;
      let summaries: RemoteDocSummary[] = (body['documents'] as RemoteDocSummary[]) || [];
      if (summaries.length === 0) {
        this.documents = [];
        this.remoteChunkCount = 0;
        this.remoteBuiltinCount = 0;
        this.remoteUserCount = 0;
        return true;
      }

      let builtinCount: number = 0;
      let userCount: number = 0;
      let remoteDocs: DocInfo[] = [];
      for (let summary of summaries) {
        let count: number = summary.chunk_count || 0;
        if (summary.source.indexOf('用户') >= 0 || summary.source === 'user_upload') {
          userCount += count;
        } else {
          builtinCount += count;
        }
        remoteDocs.push({
          id: summary.id,
          name: summary.name,
          source: summary.source,
          chunks: new Array<KnowledgeChunk>(count),
          chunkCount: count
        });
      }

      this.documents = remoteDocs;
      this.remoteChunkCount = builtinCount + userCount;
      this.remoteBuiltinCount = builtinCount;
      this.remoteUserCount = userCount;
      return true;
    } catch (e) {
      // Keep local built-in list if the RAG server is offline.
      this.lastSyncError = 'network error';
      return false;
    }
  }

  private normalizeDocName(title: string): string {
    let idx: number = title.indexOf(' (');
    if (idx >= 0) {
      return title.substring(0, idx);
    }
    return title;
  }

  private getDisplayChunkCount(): number {
    return this.remoteChunkCount > 0 ? this.remoteChunkCount : KnowledgeService.getChunkCount();
  }

  private getDisplayBuiltinCount(): number {
    return this.remoteChunkCount > 0 ? this.remoteBuiltinCount : KnowledgeService.getBuiltinCount();
  }

  private getDisplayUserCount(): number {
    return this.remoteChunkCount > 0 ? this.remoteUserCount : KnowledgeService.getUserCount();
  }

  private async refreshRemoteDocuments(): Promise<void> {
    if (this.isRefreshing) {
      return;
    }
    this.isRefreshing = true;
    try {
      let synced: boolean = await this.loadRemoteDocuments();
      if (synced) {
        promptAction.showToast({ message: '知识库列表已同步', duration: 1500 });
      } else {
        promptAction.showToast({ message: '同步失败: ' + this.lastSyncError, duration: 1800 });
      }
    } catch (e) {
      promptAction.showToast({ message: '同步失败: ' + this.lastSyncError, duration: 1800 });
    } finally {
      this.isRefreshing = false;
    }
  }

  private async uploadUserDocument(): Promise<void> {
    if (this.isUploading) {
      return;
    }

    try {
      let options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.txt', '.md', '.markdown'];
      let documentPicker = new picker.DocumentViewPicker(this.context);
      let uris: string[] = await documentPicker.select(options);
      if (!uris || uris.length === 0) {
        return;
      }

      this.isUploading = true;
      let uri: string = uris[0];
      let fileName: string = this.getFileNameFromUri(uri);
      let content: string = this.readTextFile(uri);
      if (content.trim().length === 0) {
        promptAction.showToast({ message: '文档内容为空', duration: 1800 });
        return;
      }

      let ragUrl: string = await ApiConfigService.getRagUrl();
      let ragToken: string = await ApiConfigService.getRagToken();
      await AuthService.init(this.context);
      let appSessionToken: string = await AuthService.getAppSessionToken();
      let httpRequest = http.createHttp();
      let response = await httpRequest.request(
        ragUrl + '/v1/rag/upload/text',
        {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + ragToken,
            'X-App-Session': appSessionToken,
            'User-Agent': 'Compass/1.0 HarmonyOS'
          },
          extraData: JSON.stringify({
            title: fileName.replace('.txt', '').replace('.md', '').replace('.markdown', ''),
            file_name: fileName,
            content: content
          }),
          connectTimeout: 10000,
          readTimeout: 120000
        }
      );
      httpRequest.destroy();

      if (response.responseCode === 200) {
        let result: UploadResponse = JSON.parse(response.result as string) as UploadResponse;
        promptAction.showToast({
          message: '上传成功，已向量化 ' + result.chunk_count.toString() + ' 个片段',
          duration: 2200
        });
        await this.loadRemoteDocuments();
      } else {
        promptAction.showToast({ message: '上传失败：RAG 服务返回 ' + response.responseCode.toString(), duration: 2200 });
      }
    } catch (e) {
      promptAction.showToast({ message: '上传失败，请检查 RAG 服务地址和文件格式', duration: 2200 });
    } finally {
      this.isUploading = false;
    }
  }

  private readTextFile(uri: string): string {
    let stat = fs.statSync(uri);
    let file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      let arrayBuffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, arrayBuffer);
      return buffer.from(new Uint8Array(arrayBuffer)).toString();
    } finally {
      fs.closeSync(file);
    }
  }

  private getFileNameFromUri(uri: string): string {
    let cleanUri: string = uri.split('?')[0];
    let parts: string[] = cleanUri.split('/');
    let name: string = parts.length > 0 ? parts[parts.length - 1] : 'upload.txt';
    try {
      return decodeURIComponent(name);
    } catch (e) {
      return name;
    }
  }

  private async loadDocumentChunks(doc: DocInfo): Promise<KnowledgeChunk[]> {
    if (this.remoteChunkCount === 0 && doc.chunks.length > 0) {
      return doc.chunks;
    }
    if (doc.id.length === 0 || this.remoteChunkCount === 0) {
      return doc.chunks;
    }

    let ragUrl: string = await ApiConfigService.getRagUrl();
    let ragToken: string = await ApiConfigService.getRagToken();
    await AuthService.init(this.context);
    let appSessionToken: string = await AuthService.getAppSessionToken();
    let httpRequest = http.createHttp();
    let response = await httpRequest.request(
      ragUrl + '/v1/rag/documents/' + doc.id + '/chunks',
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

  async showDocDetail(doc: DocInfo): Promise<void> {
    router.pushUrl({
      url: 'pages/KnowledgeDetailPage',
      params: {//注意要在路由另一端定义好接口，因为鸿蒙的强类型特性
        id: doc.id,
        name: doc.name,
        source: doc.source,
        chunkCount: doc.chunkCount,
        isRemote: this.remoteChunkCount > 0
      }
    });
  }

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Text('←')
            .fontSize(20)
            .fontColor('#666')
        }
        .width(44)
        .height(44)
        .backgroundColor('#00000000')
        .onClick(() => {
          if (this.showDetail) {
            this.showDetail = false;
            this.selectedDoc = null;
          } else {
            // Navigate back
          }
        })

        Text(this.showDetail ? '文档详情' : '知识库管理')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)

        if (!this.showDetail) {
          Row({ space: 8 }) {
            Button(this.isRefreshing ? '同步中' : '同步')
              .fontSize(13)
              .fontColor($r('app.color.elegant_blue'))
              .height(36)
              .padding({ left: 14, right: 14 })
              .backgroundColor('#FFFFFF')
              .border({ width: 1, color: $r('app.color.elegant_blue') })
              .borderRadius(18)
              .enabled(!this.isRefreshing && !this.isUploading)
              .onClick(() => {
                this.refreshRemoteDocuments();
              })

            Button(this.isUploading ? '向量化中' : '上传文档')
              .fontSize(13)
              .fontColor('#FFFFFF')
              .height(36)
              .padding({ left: 14, right: 14 })
              .backgroundColor(this.isUploading ? '#999999' : $r('app.color.elegant_blue'))
              .borderRadius(18)
              .enabled(!this.isUploading && !this.isRefreshing)
              .onClick(() => {
                this.uploadUserDocument();
              })
          }
        }
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 12, bottom: 8 })

      if (this.showDetail && this.selectedDoc) {
        Column() {
          Row() {
            Text(this.selectedDoc.source)
              .fontSize(12)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Medium)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor(this.selectedDoc.source === '内置经典' ? $r('app.color.elegant_blue') : '#E5534B')
              .borderRadius(10)
          }
          .width('100%')
          .margin({ top: 12, bottom: 8 })

          Text(this.selectedDoc.name)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          Text(this.selectedDoc.chunks.length.toString() + ' 个知识片段')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4, bottom: 20 })

          List() {
            ForEach(this.selectedDoc.chunks, (chunk: KnowledgeChunk, idx: number) => {
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
                    .maxLines(10)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .padding(16)
                .backgroundColor('#FFFFFF')
                .borderRadius(12)
              }
              .width('100%')
            })
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 24, right: 24 })
      } else {
        Row() {
          Column() {
            Text(this.getDisplayChunkCount().toString())
              .fontSize(36)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.elegant_blue'))
            Text('总知识片段')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .padding(20)
          .backgroundColor('#FFFFFF')
          .borderRadius({topLeft: 14, bottomLeft: 14})
          .layoutWeight(1)

          Column() {
            Text(this.getDisplayBuiltinCount().toString())
              .fontSize(36)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_green'))
            Text('内置经典')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .padding(20)
          .backgroundColor('#FFFFFF')
          // .borderRadius(14)
          .layoutWeight(1)

          Column() {
            Text(this.getDisplayUserCount().toString())
              .fontSize(36)
              .fontWeight(FontWeight.Bold)
              .fontColor('#E5534B')
            Text('用户上传')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .padding(20)
          .backgroundColor('#FFFFFF')
          .borderRadius({topRight: 14, bottomRight: 14})
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 16, bottom: 8 })

        if (this.documents.length > 0) {
          Column() {
            Row() {
              Text('知识文档列表')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .padding({ left: 4 })
            }
            .width('100%')
            .padding({ left: 24, right: 24, top: 24, bottom: 8 })
          }
          .width('100%')
        }

        List() {
          ForEach(this.documents, (doc: DocInfo, idx: number) => {
            ListItem() {
              Row({ space: 14 }) {
                Column() {
                  Text(doc.source === '内置经典' ? '经' : '用')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFF')
                }
                .width(44)
                .height(44)
                .borderRadius(11)
                .backgroundColor(doc.source === '内置经典' ? $r('app.color.elegant_blue') : '#E5534B')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)

                Column({ space: 4 }) {
                  Text(doc.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))

                  Row({ space: 8 }) {
                    Text(doc.source)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                    Text(doc.chunks.length.toString() + ' 片段')
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button({ type: ButtonType.Circle, stateEffect: true }) {
                  Text('→')
                    .fontSize(16)
                    .fontColor('#999')
                }
                .width(36)
                .height(36)
                .backgroundColor('#00000000')
              }
              .width('100%')
              .padding({ left: 16, right: 8, top: 4, bottom: 4 })
              .onClick(() => {
                this.showDocDetail(doc);
              })
            }
            .width('100%')

            ListItem() {
              Row() {
              }
              .width('80%')
              .height(0.5)
              .backgroundColor('#F0F0F0')
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0, startMargin: 0, endMargin: 0 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.start_window_background'))
  }
}
