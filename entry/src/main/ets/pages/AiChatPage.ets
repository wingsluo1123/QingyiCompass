import { Message } from '../service/AiService';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import ApiConfigService from '../service/ApiConfigService';
import ConversationService, { Conversation } from '../service/ConversationService';
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { hdsEffect } from '@kit.UIDesignKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { EventSource, EventSourceEvent } from '../service/EventSourceUtil';
import AuthService from '../service/AuthService';
import { Markdown, EMarkdownMode } from 'fluid-markdown';

interface StreamDelta {
  role: string;
  content: string;
}

interface StreamChoice {
  index: number;
  delta: StreamDelta;
}

interface StreamChunk {
  choices: StreamChoice[];
}

interface ChatRequestBody {
  model: string;
  messages: Message[];
  max_tokens: number;
  temperature: number;
  stream: boolean;
}

interface RagDocumentSummary {
  id: string;
  name: string;
  source: string;
  category: string;
  visibility: string;
  chunk_count: number;
}

@Entry
@ComponentV2
export struct AiChatPage {
  @Local chatHistory: Message[] = [];
  @Local inputText: string = '';
  @Local isLoading: boolean = false;
  @Local streamingContent: string = '';
  @Local thoughtContent: string = '';
  @Local isStreaming: boolean = false;
  @Local showSettings: boolean = false;
  @Local showHistory: boolean = false;
  @Local apiKeyInput: string = '';
  @Local baseUrlInput: string = '';
  @Local modelInput: string = '';
  @Local ragUrlInput: string = '';
  @Local ragTokenInput: string = '';
  @Local ragEnabled: boolean = true;
  @Local conversations: Conversation[] = [];
  @Local activeConvId: string = '';
  @Local historyRefreshKey: number = 0;
  @Local deletingConvId: string = '';
  private scroller: Scroller = new Scroller();
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private activeRequest: http.HttpRequest | null = null;
  private abortFlag: boolean = false;
  @Local controller: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController();

  aboutToAppear(): void {
    ApiConfigService.init(this.context);
    AuthService.init(this.context);
    ConversationService.init(this.context);
    this.loadConfig();
    this.initChat();
  }

  private async loadConfig(): Promise<void> {
    this.apiKeyInput = await ApiConfigService.getApiKey();
    this.baseUrlInput = await ApiConfigService.getBaseUrl();
    this.modelInput = await ApiConfigService.getModel();
    this.ragUrlInput = await ApiConfigService.getRagUrl();
    this.ragTokenInput = await ApiConfigService.getRagToken();
    this.ragEnabled = await ApiConfigService.isRagEnabled();
  }

  private async saveConfig(): Promise<void> {
    await ApiConfigService.saveApiKey(this.apiKeyInput);
    if (this.baseUrlInput.trim().length > 0) {
      await ApiConfigService.saveBaseUrl(this.baseUrlInput.trim());
    }
    if (this.modelInput.trim().length > 0) {
      await ApiConfigService.saveModel(this.modelInput.trim());
    }
    if (this.ragUrlInput.trim().length > 0) {
      await ApiConfigService.saveRagUrl(this.ragUrlInput.trim());
    }
    await ApiConfigService.saveRagToken(this.ragTokenInput.trim());
    await ApiConfigService.setRagEnabled(this.ragEnabled);
    this.showSettings = false;
  }

  private async initChat(): Promise<void> {
    this.conversations = await ConversationService.getConversations();
    await this.newConversation();
  }

  private async saveCurrentConversation(): Promise<void> {
    if (this.activeConvId.length === 0) {
      return;
    }
    let userMsgs: Message[] = this.chatHistory.filter(m => m.role === 'user');
    if (userMsgs.length === 0) {
      return;
    }
    let title: string = userMsgs[0].content;
    if (title.length > 20) {
      title = title.substring(0, 20) + '...';
    }
    let conv: Conversation = {
      id: this.activeConvId,
      title: title,
      messages: this.chatHistory.map(m => ({ role: m.role, content: m.content }) as Message),
      createdAt: Date.now()
    };
    await ConversationService.saveConversation(conv);
    this.historyRefreshKey++;
  }

  private async newConversation(): Promise<void> {
    this.chatHistory = [];
    this.activeConvId = ConversationService.generateId();
    await ConversationService.setActiveId(this.activeConvId);
    this.conversations = await ConversationService.getConversations();
    this.showHistory = false;
    this.historyRefreshKey++;
  }

  //切换对话
  private async switchConversation(id: string): Promise<void> {
    await this.saveCurrentConversation();
    this.activeConvId = id;
    await ConversationService.setActiveId(id);
    this.conversations = await ConversationService.getConversations();
    let conv: Conversation | undefined = this.conversations.find(c => c.id === id);
    if (conv) {
      this.chatHistory = [...conv.messages];
    }
    this.showHistory = false;
    this.streamingContent = '';
    this.thoughtContent = '';
    this.isStreaming = false;
    this.isLoading = false;
    this.scrollToBottomAfterLayout();
  }

  private async deleteConversation(id: string): Promise<void> {
    await ConversationService.deleteConversation(id);
    this.conversations = await ConversationService.getConversations();
    this.historyRefreshKey++;

    if (id === this.activeConvId) {
      if (this.conversations.length > 0) {
        await this.switchConversation(this.conversations[0].id);
      } else {
        await this.newConversation();
      }
    }
  }

  //发送消息给ai
  private async send(): Promise<void> {
    if (!this.inputText.trim()) {
      promptAction.showToast({ message: '请输入内容', duration: 2000 });
      return;
    }

    let apiKey = await ApiConfigService.getApiKey();
    if (apiKey.length === 0) {
      promptAction.showToast({ message: '请先配置 API Key', duration: 2000 });
      this.showSettings = true;
      return;
    }
    // Scroll to bottom when new message is sent
    this.scrollToBottom();
    let userMsg: Message = { role: 'user', content: this.inputText };
    this.chatHistory = [...this.chatHistory, userMsg];
    let queryText: string = this.inputText;
    this.inputText = '';
    this.isLoading = true;
    this.isStreaming = true;
    this.streamingContent = '';
    this.thoughtContent = '';
    this.abortFlag = false;

    // Fetch RAG context first, then call LLM
    if (this.ragEnabled) {
      let contextMessages: Message[] = await this.fetchRagContext(queryText);
      this.callLLM(contextMessages);
    } else {
      this.callLLM([...this.chatHistory]);
    }

    
  }

  /**
   * 调用 Python RAG 服务获取风水经典知识片段，
   * 注入 system prompt 后返回完整的 messages 列表。
   */
  private async fetchRagContext(queryText: string): Promise<Message[]> {
    let ragUrl: string = await ApiConfigService.getRagUrl();
    let ragToken: string = await ApiConfigService.getRagToken();
    await AuthService.init(this.context);
    let appSessionToken: string = await AuthService.getOrCreateAppSessionToken();
    let fetchUrl: string = ragUrl + '/v1/rag/search';
    let catalogContext: string = await this.fetchRagDocumentCatalog(ragUrl, ragToken, appSessionToken);
    if (this.isRagCatalogQuestion(queryText) && catalogContext.length > 0) {
      return this.buildCatalogOnlyMessages(catalogContext);
    }

    try {
      let httpRequest = http.createHttp();
      let response = await httpRequest.request(
        fetchUrl,
        {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + ragToken,
            'X-App-Session': appSessionToken,
            'User-Agent': 'Compass/1.0 HarmonyOS'
          },
          extraData: JSON.stringify({ query: queryText, top_k: 8 }),
          connectTimeout: 5000,
          readTimeout: 10000
        }
      );

      httpRequest.destroy();

      if (response.responseCode === 200) {
        let body: object = JSON.parse(response.result as string) as object;
        let chunks: object[] = (body as Record<string, object>)['chunks'] as object[];
        let total: number = (body as Record<string, number>)['total_hits'] ?? 0;

        if (chunks && chunks.length > 0) {
          // Build context string from chunks
          let contextStr: string = '';
          for (let i = 0; i < chunks.length; i++) {
            let c = chunks[i] as Record<string, string>;
            contextStr += `【参考资料${i + 1}】来源：${c['title']}\n${c['content']}\n\n`;
          }

          let systemPrompt: string =
            '你是一位深谙中国传统堪舆之术的风水顾问，精通八宅明镜、地理五诀等经典。回答风格严谨，引经据典。\n\n' +
            catalogContext +
            '以下是知识库中与用户问题相关的经典原文，请基于这些原文回答问题：\n\n' +
            contextStr +
            '【回答要求】\n' +
            '0. 如果用户询问知识库中有哪些文件、文档或资料，必须优先依据“当前可见知识库文档目录”完整列出，不要只列检索片段来源\n' +
            '1. 先引用相关的经典原文片段，再用白话解释\n' +
            '2. 如果原文不足以完全回答，请如实说明\n' +
            '3. 标注引用来源\n' +
            '4. 态度严谨，不随意编造';

          // Prepend system message to chat history
          let enrichedMessages: Message[] = [
            { role: 'system', content: systemPrompt },
            ...this.chatHistory
          ];

          hilog.info(0x0001, 'AiChatPage', 'RAG: fetched %{public}d chunks, %{public}d total hits',
            chunks.length, total);
          return enrichedMessages;
        }
      } else {
        hilog.warn(0x0001, 'AiChatPage', 'RAG server returned %{public}d', response.responseCode);
      }
    } catch (e) {
      hilog.warn(0x0001, 'AiChatPage', 'RAG fetch failed, falling back to direct LLM: %{public}s',
        JSON.stringify(e));
    }

    if (catalogContext.length > 0) {
      let systemPrompt: string =
        '你是一位深谙中国传统堪舆之术的风水顾问，精通八宅明镜、地理五诀等经典。回答风格严谨，引经据典。\n\n' +
        catalogContext +
        '【回答要求】\n' +
        '1. 如果用户询问知识库中有哪些文件、文档或资料，必须完整列出“当前可见知识库文档目录”中的全部项目\n' +
        '2. 如果用户询问具体内容，但没有检索到相关片段，请说明当前只获取到了文档目录，不能编造正文内容';
      return [
        { role: 'system', content: systemPrompt },
        ...this.chatHistory
      ];
    }

    // Fallback: no RAG context, send as-is
    return [...this.chatHistory];
  }

  private isRagCatalogQuestion(queryText: string): boolean {
    let q: string = queryText.trim();
    if (q.length === 0) {
      return false;
    }

    let asksForList: boolean =
      q.indexOf('有哪些') >= 0 ||
      q.indexOf('有什么') >= 0 ||
      q.indexOf('有多少') >= 0 ||
      q.indexOf('多少个') >= 0 ||
      q.indexOf('列出') >= 0 ||
      q.indexOf('列举') >= 0 ||
      q.indexOf('全部') >= 0 ||
      q.indexOf('所有') >= 0 ||
      q.indexOf('目录') >= 0 ||
      q.indexOf('清单') >= 0 ||
      q.indexOf('列表') >= 0;

    let asksAboutDocs: boolean =
      q.indexOf('知识库') >= 0 ||
      q.indexOf('文件') >= 0 ||
      q.indexOf('文档') >= 0 ||
      q.indexOf('资料') >= 0 ||
      q.indexOf('书') >= 0 ||
      q.indexOf('经典') >= 0;

    return asksForList && asksAboutDocs;
  }

  private buildCatalogOnlyMessages(catalogContext: string): Message[] {
    let systemPrompt: string =
      '你是一位深谙中国传统堪舆之术的风水顾问，精通八宅明镜、地理五诀等经典。回答风格严谨，引经据典。\n\n' +
      catalogContext +
      '【回答要求】\n' +
      '1. 用户正在询问知识库文档目录，必须完整列出“当前可见知识库文档目录”中的全部项目\n' +
      '2. 不要使用片段检索结果推断目录，因为目录已经由系统完整提供\n' +
      '3. 可以简短说明这些目录已经按当前登录用户权限过滤\n' +
      '4. 不要编造目录中不存在的文件';
    return [
      { role: 'system', content: systemPrompt },
      ...this.chatHistory
    ];
  }

  private async fetchRagDocumentCatalog(ragUrl: string, ragToken: string, appSessionToken: string): Promise<string> {
    try {
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
        hilog.warn(0x0001, 'AiChatPage', 'RAG catalog returned %{public}d', response.responseCode);
        return '';
      }

      let body: Record<string, object> = JSON.parse(response.result as string) as Record<string, object>;
      let documents: RagDocumentSummary[] = (body['documents'] as RagDocumentSummary[]) || [];
      if (documents.length === 0) {
        return '';
      }

      let catalog: string = '【当前可见知识库文档目录】\n';
      catalog += '以下目录已经按当前登录用户权限过滤，包含内置公开文档和当前用户自己的私有文档：\n';
      for (let i = 0; i < documents.length; i++) {
        let doc: RagDocumentSummary = documents[i];
        let name: string = doc.name || '未命名文档';
        let source: string = doc.source || '未知来源';
        let category: string = doc.category || '未分类';
        let chunkCount: number = doc.chunk_count || 0;
        catalog += (i + 1).toString() + '. ' + name +
          '（来源：' + source +
          '，分类：' + category +
          '，片段数：' + chunkCount.toString() + '）\n';
      }
      catalog += '\n';
      return catalog;
    } catch (e) {
      hilog.warn(0x0001, 'AiChatPage', 'RAG catalog fetch failed: %{public}s', JSON.stringify(e));
      return '';
    }
  }

  private async callLLM(messages: Message[]): Promise<void> {
    let apiUrl = await ApiConfigService.getBaseUrl();
    let model = await ApiConfigService.getModel();

    let httpRequest = http.createHttp();
    this.activeRequest = httpRequest;
    let accumulated: string = '';

    let finish = (): void => {
      this.activeRequest = null;
      this.isLoading = false;
      this.isStreaming = false;
      this.streamingContent = '';
      httpRequest.destroy();
    };

    httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      // Abort flag: immediately discard any data arriving after user clicked stop
      if (this.abortFlag) {
        return;
      }
      try {
        let decoder = util.TextDecoder.create('utf-8');
        let str = decoder.decodeToString(new Uint8Array(data));
        for (let resultStr of str.split('data:')) {
          if (resultStr.trim() === '[DONE]') {
            continue;
          }
          if (resultStr.trim().length === 0) {
            continue;
          }
          try {
            let obj: object = JSON.parse(resultStr.trim()) as object;
            let choices: object[] = (obj as object)['choices'] as object[];
            if (choices && choices.length > 0) {
              let delta: object = choices[0]['delta'] as object;
              let content: string = delta['content'] as string;
              if (content) {
                accumulated += content;
                this.streamingContent = accumulated;
                // when AI is generating content, force the list to scroll to bottom
                // this.scrollToBottom();
              }
            }
          } catch (e) {
          }
        }
      } catch (e) {
      }
    });

    httpRequest.on('dataEnd', () => {
      if (accumulated.length > 0) {
        this.chatHistory = [...this.chatHistory, { role: 'assistant', content: accumulated }];
      }
      finish();
      this.saveCurrentConversation();
    });

    let option: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${await ApiConfigService.getApiKey()}`
      },
      extraData: {
        model: model,
        messages: messages,
        max_tokens: 2048,
        temperature: 0.7,
        stream: true
      }
    };

    httpRequest.requestInStream(apiUrl, option).catch((err: BusinessError) => {
      hilog.error(0x0001, 'AiChatPage', 'Request failed: %{public}s', err.message);
      // If accumulated content exists, keep it as partial response
      if (accumulated.length > 0) {
        this.chatHistory = [...this.chatHistory, { role: 'assistant', content: accumulated }];
      } else {
        this.chatHistory = [...this.chatHistory, { role: 'assistant', content: '请求失败: ' + err.message }];
      }
      finish();
      this.saveCurrentConversation();
    });
  }

  /**
   * 中断 AI 回复 — 立即销毁 HTTP 请求，保留已生成的部分内容。
   */
  private stopResponse(): void {
    // Set abort flag first — any in-flight dataReceive callbacks will return immediately
    this.abortFlag = true;
    if (this.activeRequest) {
      // Save whatever has been generated so far
      // Maybe this would cause double push and the list would display two same messages
      // if (this.streamingContent.length > 0) {
      //   this.chatHistory = [...this.chatHistory, { role: 'assistant', content: this.streamingContent }];
      // }
      this.activeRequest.off('dataReceive');
      this.activeRequest.off('dataEnd');
      this.activeRequest.destroy();
      this.activeRequest = null;
    }
    this.isLoading = false;
    this.isStreaming = false;
    this.streamingContent = '';
    this.saveCurrentConversation();
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      if (this.chatHistory.length > 0 || this.isStreaming) {
        this.scroller.scrollEdge(Edge.Bottom);
      }
    }, 50);
  }

  private scrollToBottomAfterLayout(): void {
    if (this.chatHistory.length === 0 && !this.isStreaming) {
      return;
    }

    let delays: number[] = [0, 80, 180, 320];
    for (let delay of delays) {
      setTimeout(() => {
        this.scroller.scrollEdge(Edge.Bottom);
      }, delay);
    }
  }

  aboutToDisappear(): void {
    this.saveCurrentConversation();
  }

  private formatTime(timestamp: number): string {
    let date: Date = new Date(timestamp);
    let month: string = (date.getMonth() + 1).toString();
    let day: string = date.getDate().toString();
    return month + '/' + day;
  }

  @Builder
  markdownContent(content: string) {
    Markdown({
      content: content.length > 0 ? content : ' ',
      mode: EMarkdownMode.Normal,
      onMarkdownAreaChange: () => {},
      onMarkdownNodeClick: data => {},
    })
      .width('100%')
  }

  @Builder
  messageBubble(msg: Message) {
    Row() {
      if (msg.role === 'user') {
        Blank()
      }

      if (msg.role === 'user') {
        Text(msg.content)
          .fontSize(16)
          .fontColor($r('app.color.primary_action_text'))
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.primary_action'))
          .borderRadius(14)
          .constraintSize({ maxWidth: '75%' })
      } else {
        Column() {
          this.markdownContent(msg.content)
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(14)
        .constraintSize({ maxWidth: '85%' })
        .padding({ left: 40, right: 30, top: 10, bottom: 10 })
      }

      if (msg.role === 'assistant') {
        Blank()
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
  }

  @Builder
  streamingBubble() {
    Row() {
      Column() {
        if (this.thoughtContent.length > 0) {
          Text(this.thoughtContent)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .padding(8)
            .width('100%')
        }
        this.markdownContent(this.streamingContent)
      }
      .width('100%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(14)
      .constraintSize({ maxWidth: '85%' })
      .padding({ left: 40, right: 30, top: 10, bottom: 10 })

      Blank()
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
  }

  @Builder
  settingsPanel() {
    Column({ space: 16 }) {
      Row() {
        Text('API 配置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Blank()

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.icon_close'))
            .width(18)
            .height(18)
            .fillColor($r('app.color.muted_icon'))
        }
        .width(44)
        .height(44)
        .backgroundColor($r('app.color.input_background'))
        .onClick(() => {
          this.showSettings = false;
        })
      }
      .width('100%')

      Column({ space: 6 }) {
        Row() {
          Text('API Key')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Text(' *')
            .fontSize(14)
            .fontColor($r('app.color.danger'))
        }

        TextInput({ text: this.apiKeyInput, placeholder: '请输入你的 DeepSeek API Key' })
          .width('100%')
          .height(44)
          .fontSize(15)
          .borderRadius(10)
          .backgroundColor($r('app.color.input_background'))
          .type(InputType.Password)
          .onChange((value: string) => {
            this.apiKeyInput = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        Text('接口地址')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))

        TextInput({ text: this.baseUrlInput, placeholder: 'https://api.deepseek.com/chat/completions' })
          .width('100%')
          .height(44)
          .fontSize(15)
          .borderRadius(10)
          .backgroundColor($r('app.color.input_background'))
          .onChange((value: string) => {
            this.baseUrlInput = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        Text('模型名称')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))

        TextInput({ text: this.modelInput, placeholder: 'deepseek-v4-pro' })
          .width('100%')
          .height(44)
          .fontSize(15)
          .borderRadius(10)
          .backgroundColor($r('app.color.input_background'))
          .onChange((value: string) => {
            this.modelInput = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        Text('RAG 服务地址')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))

        TextInput({ text: this.ragUrlInput, placeholder: 'https://rag.wingsluo.com' })
          .width('100%')
          .height(44)
          .fontSize(15)
          .borderRadius(10)
          .backgroundColor($r('app.color.input_background'))
          .onChange((value: string) => {
            this.ragUrlInput = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        Text('RAG Token')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))

        TextInput({ text: this.ragTokenInput, placeholder: '请输入 RAG 服务访问 Token' })
          .width('100%')
          .height(44)
          .fontSize(15)
          .borderRadius(10)
          .backgroundColor($r('app.color.input_background'))
          .type(InputType.Password)
          .onChange((value: string) => {
            this.ragTokenInput = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row() {
        Text('启用知识库检索 (RAG)')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.ragEnabled })
          .onChange((isOn: boolean) => {
            this.ragEnabled = isOn;
          })
      }
      .width('100%')
      .margin({ top: 4 })

      Button('保存配置')
        .width('100%')
        .height(44)
        .fontSize(16)
        .fontColor($r('app.color.primary_action_text'))
        .backgroundColor($r('app.color.primary_action'))
        .borderRadius(10)
        .onClick(() => {
          this.saveConfig();
        })
    }
    .width('100%')
  }

  @Builder
  deleteConfirmDialog() {
    Column() {
      Column({ space: 20 }) {
        Text('确认删除')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Text('删除后无法恢复，确定要删除这个对话吗？')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(22)
          .textAlign(TextAlign.Center)

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(14)
            .height(44)
            .layoutWeight(1)
            .backgroundColor($r('app.color.input_background'))
            .fontColor($r('app.color.text_primary'))
            .borderRadius(10)
            .onClick(() => {
              this.deletingConvId = '';
            })

          Button('删除')
            .fontSize(14)
            .height(44)
            .layoutWeight(1)
            .backgroundColor($r('app.color.danger'))
            .fontColor($r('app.color.primary_action_text'))
            .borderRadius(10)
            .onClick(() => {
              let id: string = this.deletingConvId;
              this.deletingConvId = '';
              this.deleteConversation(id);
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 24, bottom: 20 })
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(16)
    }
    .width('80%')
    .constraintSize({ maxWidth: 320 })
    .shadow({ radius: 24, color: $r('app.color.panel_shadow'), offsetX: 0, offsetY: 12 })
  }

  @Builder
  historyPanel() {
    Column() {
      Column({ space: 4 }) {
        Row() {
          Text('对话历史')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          Blank()

          // 新建对话
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.icon_plus'))
              .width(20)
              .height(20)
              .fillColor($r('app.color.elegant_blue'))
          }
          .width(44)
          .height(44)
          .backgroundColor($r('app.color.light_blue'))
          .onClick(() => {
            this.newConversation();
          })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 50, bottom: 16 })

      if (this.conversations.length === 0) {
        Column({ space: 16 }) {
          Image($r('app.media.tab_ai'))
            .width(40)
            .height(40)
            .fillColor($r('app.color.text_secondary'))
            .opacity(0.3)
          Text('暂无对话')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Text('点击右上角 + 开始新对话')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .opacity(0.7)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 历史对话列表
        List() {
          ForEach(this.conversations, (conv: Conversation, idx: number) => {
            ListItem() {
              Stack({ alignContent: Alignment.End }) {
                Row() {
                  Column({ space: 4 }) {
                    Text(conv.title)
                      .fontSize(15)
                      .fontColor(this.activeConvId === conv.id ? $r('app.color.elegant_blue') : $r('app.color.text_primary'))
                      .fontWeight(this.activeConvId === conv.id ? FontWeight.Medium : FontWeight.Regular)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Row({ space: 4 }) {
                      Text(this.formatTime(conv.createdAt))
                        .fontSize(11)
                        .fontColor($r('app.color.text_secondary'))
                      Text(conv.messages.length.toString() + ' 条消息')
                        .fontSize(11)
                        .fontColor($r('app.color.text_secondary'))
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 20, top: 4, bottom: 4 })
                  .onClick(async () => {
                    await this.switchConversation(conv.id);
                  })

                  Button('删除')
                    .fontSize(12)
                    .fontColor($r('app.color.danger'))
                    .backgroundColor($r('app.color.danger_background'))
                    .borderRadius(16)
                    .width(70)
                    .height(32)
                    .margin({ right: 16 })
                    .onClick(() => {
                      this.deletingConvId = conv.id;
                    })
                }
                .width('100%')

                if (this.activeConvId === conv.id) {
                  Row() {
                  }
                  .width(4)
                  .height('60%')
                  .backgroundColor($r('app.color.elegant_blue'))
                  .borderRadius(2)
                  .position({ x: 0, y: '20%' })
                }
              }
              .width('100%')
              .height(64)
              .backgroundColor(this.activeConvId === conv.id ? $r('app.color.light_blue') : '#00000000')
              .gesture(
                LongPressGesture({ repeat: false, duration: 500 })
                  .onAction(() => {
                    this.deletingConvId = conv.id;
                  })
              )
            }

            ListItem() {
              Row() {
              }
              .width('80%')
              .height(0.5)
              .backgroundColor($r('app.color.divider'))
            }
          })
        }
        .padding({bottom: 60})
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0, startMargin: 0, endMargin: 0 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius({ topRight: 20, bottomRight: 20 })
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.icon_menu'))
              .width(22)
              .height(22)
              .fillColor($r('app.color.text_secondary'))
          }
          .width(48)
          .height(48)
          .backgroundColor('#00000000')
          .onClick(async () => {
            this.conversations = await ConversationService.getConversations();
            this.showHistory = true;
          })

          Text('AI 助手')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)

          Blank()

          Row({ space: 10 }) {
            Column() {
              Stack() {
              }
              .visualEffect(new hdsEffect.HdsEffectBuilder()
                .shaderEffect({
                  effectType: hdsEffect.EffectType.DUAL_EDGE_FLOW_LIGHT,
                  animation: {
                    duration: 2500,
                    iterations: -1,
                    autoPlay: true,
                    onFinish: () => {
                      console.info('Succeeded in finishing');
                    }
                  },
                  controller: this.controller,
                  params: {
                    firstEdgeFlowLight: {
                      startPos: 0,
                      endPos: 1.0,
                      color: '#1AD0F1',
                    },
                    secondEdgeFlowLight: {
                      startPos: 0.5,
                      endPos: 1.5,
                      color: '#FFA4E5',
                    }
                  }
                })
                .buildEffect())
              .width(24)
              .borderRadius(24)
              .clip(true)
              .height(24)
            }
            .width(48)
            .height(48)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)

            // RAG toggle — 快捷开关
            Button({ stateEffect: true }) {
              Row({ space: 5 }) {
                Text('RAG')
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.ragEnabled ? $r('app.color.primary_action_text') : $r('app.color.elegant_blue'))
                Text(this.ragEnabled ? 'ON' : 'OFF')
                  .fontSize(10)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.ragEnabled ? $r('app.color.badge_background') : $r('app.color.text_secondary'))
              }
              .alignItems(VerticalAlign.Center)
            }
            .height(30)
            .padding({ left: 10, right: 10 })
            .backgroundColor(this.ragEnabled ? $r('app.color.elegant_blue') : $r('app.color.card_background'))
            .border({ width: 1, color: this.ragEnabled ? $r('app.color.elegant_blue') : $r('app.color.surface_border') })
            .borderRadius(15)
            .onClick(() => {
              this.ragEnabled = !this.ragEnabled;
            })

            Button({ type: ButtonType.Circle, stateEffect: true }) {
              Image($r('app.media.icon_settings'))
                .width(22)
                .height(22)
                .fillColor($r('app.color.text_secondary'))
            }
            .width(48)
            .height(48)
            .backgroundColor('#00000000')
            .onClick(() => {
              this.loadConfig();
              this.showSettings = true;
            })
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 15, bottom: 10 })

        List({ space: 15, scroller: this.scroller }) {
          ForEach(this.chatHistory, (msg: Message, idx: number) => {
            ListItem() {
              this.messageBubble(msg)
            }
          })

          if (this.isStreaming) {
            ListItem() {
              this.streamingBubble()
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ top: 10 })
        .backgroundColor($r('app.color.message_list_background'))

        Row({ space: 10 }) {
          TextInput({ text: this.inputText, placeholder: '输入消息...' })
            .layoutWeight(1)
            .height(40)
            .fontSize(16)
            .borderRadius(20)
            .backgroundColor($r('app.color.input_background'))
            .onChange((value: string) => {
              this.inputText = value;
            })
            .onSubmit(() => {
              this.send();
            })

          if (this.isStreaming) {
            Button('停止')
              .fontSize(14)
              .height(40)
              .fontColor($r('app.color.primary_action_text'))
              .backgroundColor($r('app.color.danger'))
              .borderRadius(20)
              .onClick(() => {
                this.stopResponse();
              })
          } else {
            Button('发送')
              .fontSize(14)
              .height(40)
              .fontColor($r('app.color.primary_action_text'))
              .backgroundColor($r('app.color.primary_action'))
              .borderRadius(20)
              .enabled(!this.isLoading && this.inputText.trim().length > 0)
              .onClick(() => {
                this.send();
              })
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 56 })
        .backgroundColor($r('app.color.card_background'))
      }
      .backgroundColor($r('app.color.start_window_background'))
      .width('100%')
      .height('100%')

      if (this.showSettings || this.showHistory) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.4)')
          .onClick(() => {
            this.showSettings = false;
            this.showHistory = false;
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
      }

      if (this.showSettings) {
        Column() {
          this.settingsPanel()
        }
        .width('90%')
        .constraintSize({ maxWidth: 400 })
        .padding({ left: 20, right: 20, top: 20, bottom: 30 })
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(20)
        .transition(
          TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.FastOutSlowIn })
              .combine(TransitionEffect.scale({ x: 0.85, y: 0.85 }).animation({ duration: 250, curve: Curve.FastOutSlowIn })),
            TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseIn })
              .combine(TransitionEffect.scale({ x: 0.85, y: 0.85 }).animation({ duration: 150, curve: Curve.EaseIn }))
          )
        )
        .onClick(() => {})
      }

      if (this.showHistory) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.4)')
          .onClick(() => {
            this.showHistory = false;
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))

        Row() {
          Column() {
            this.historyPanel()
          }
          .width('68%')

          Column()
            .layoutWeight(1)
            .height('100%')
            .onClick(() => {
              this.showHistory = false;
            })
        }
        .width('100%')
        .height('100%')
        .transition(
          TransitionEffect.asymmetric(
            TransitionEffect.translate({ x: -80, y: 0 }).animation({ duration: 250, curve: Curve.FastOutSlowIn })
              .combine(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.FastOutSlowIn })),
            TransitionEffect.translate({ x: -80, y: 0 }).animation({ duration: 150, curve: Curve.EaseIn })
              .combine(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseIn }))
          )
        )
        .onClick(() => {})
      }

      if (this.deletingConvId.length > 0) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.45)')
          .onClick(() => {
            this.deletingConvId = '';
          })

        Column() {
          this.deleteConfirmDialog()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {})
      }
    }
  }
}
