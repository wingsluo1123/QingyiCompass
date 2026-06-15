import { common } from '@kit.AbilityKit';
import { buffer } from '@kit.ArkTS';

export interface KnowledgeChunk {
  id: number
  title: string
  content: string
  source: string
  category: string
  keywords: string
}

interface UserKnowledgeIndex {
  files: string[];
}

const BUILTIN_FILES: string[] = ['knowledge_bazhai.txt', 'knowledge_dili.txt'];

export class KnowledgeService {
  private static instance: KnowledgeService;
  private chunks: KnowledgeChunk[] = [];
  private loaded: boolean = false;
  private loadPromise: Promise<void> | null = null;

  static getInstance(): KnowledgeService {
    if (!KnowledgeService.instance) {
      KnowledgeService.instance = new KnowledgeService();
    }
    return KnowledgeService.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    if (this.loadPromise) {
      return this.loadPromise;
    }
    this.loadPromise = this.doInit(context);
    return this.loadPromise;
  }

  private async doInit(context: common.UIAbilityContext): Promise<void> {
    await this.loadBuiltinKnowledge(context);
    await this.loadUserKnowledge(context);
    this.loaded = true;
    this.loadPromise = null;
  }

  private async loadBuiltinKnowledge(context: common.UIAbilityContext): Promise<void> {
    for (let fileName of BUILTIN_FILES) {
      let title: string = this.fileNameToTitle(fileName);
      let source: string = '内置经典';
      let category: string = '风水经典';

      let rawData: Uint8Array = context.resourceManager.getRawFileContentSync(fileName);
      let text: string = buffer.from(rawData).toString();
      let pieces: string[] = this.chunkText(text, 400);

      for (let i = 0; i < pieces.length; i++) {
        let keywords: string = this.extractKeywords(pieces[i]);
        this.chunks.push({
          id: this.chunks.length,
          title: title + ' (第' + (i + 1).toString() + '段)',
          content: pieces[i],
          source: source,
          category: category,
          keywords: keywords
        });
      }
    }
  }

  private async loadUserKnowledge(context: common.UIAbilityContext): Promise<void> {
    let baseDir: string = context.filesDir;
    let dirPath: string = baseDir + '/user_knowledge/';

    try {
      let files: string[] = [];
      let indexContent: string = '';
      try {
        let indexData: Uint8Array = context.resourceManager.getRawFileContentSync('user_knowledge_index.json');
        indexContent = buffer.from(indexData).toString();
      } catch (e) {
        // No user knowledge yet
        return;
      }
      if (indexContent.length === 0) {
        return;
      }
      let index: UserKnowledgeIndex = JSON.parse(indexContent) as UserKnowledgeIndex;
      files = index.files;
      for (let fileName of files) {
        try {
          let rawData: Uint8Array = context.resourceManager.getRawFileContentSync(fileName);
          let text: string = buffer.from(rawData).toString();
          let title: string = fileName.replace('.txt', '').replace('.md', '');
          let pieces: string[] = this.chunkText(text, 400);
          for (let i = 0; i < pieces.length; i++) {
            let keywords: string = this.extractKeywords(pieces[i]);
            this.chunks.push({
              id: this.chunks.length,
              title: title + ' (第' + (i + 1).toString() + '段)',
              content: pieces[i],
              source: '用户上传',
              category: '自定义知识',
              keywords: keywords
            });
          }
        } catch (e) {
          // Skip missing files
        }
      }
    } catch (e) {
      // User knowledge dir doesn't exist yet
    }
  }

  chunkText(text: string, chunkSize: number): string[] {
    let result: string[] = [];
    let paragraphs: string[] = text.split(/\n{2,}/);
    let current: string = '';
    for (let p of paragraphs) {
      p = p.trim();
      if (p.length === 0) {
        continue;
      }
      if ((current + p).length > chunkSize && current.length > 0) {
        result.push(current.trim());
        current = p;
      } else {
        current += (current.length > 0 ? '\n\n' : '') + p;
      }
    }
    if (current.trim().length > 0) {
      result.push(current.trim());
    }
    return result;
  }

  extractKeywords(text: string): string {
    let keywords: string[] = [];
    let keywordPatterns: string[] = [
      '八宅明镜', '地理五诀', '八卦', '九星', '贪狼', '巨门', '禄存', '文曲',
      '廉贞', '武曲', '破军', '左辅', '右弼', '生气', '天医', '延年',
      '绝命', '五鬼', '六煞', '祸害', '坎宅', '离宅', '震宅', '巽宅',
      '坤宅', '艮宅', '乾宅', '兑宅', '龙脉', '穴位', '青龙', '白虎',
      '朱雀', '玄武', '明堂', '案山', '朝山', '天门', '地户', '二十四山',
      '正东', '正南', '正西', '正北', '东南', '东北', '西南', '西北',
      '属木', '属火', '属土', '属金', '属水', '五行', '东西四宅', '东四命',
      '西四命', '立向', '砂法', '水法', '穴法', '龙法', '向法',
      '安床', '开门', '安灶', '选宅', '阳宅', '阴宅', '坐向', '朝向'
    ];
    for (let kw of keywordPatterns) {
      if (text.indexOf(kw) >= 0) {
        keywords.push(kw);
      }
    }
    return keywords.join(' ');
  }

  private fileNameToTitle(fileName: string): string {
    if (fileName.indexOf('bazhai') >= 0) {
      return '八宅明镜';
    }
    if (fileName.indexOf('dili') >= 0) {
      return '地理五诀';
    }
    return fileName.replace('.txt', '').replace('.md', '');
  }

  getAllChunks(): KnowledgeChunk[] {
    return this.chunks;
  }

  getChunkCount(): number {
    return this.chunks.length;
  }

  getBuiltinCount(): number {
    let count: number = 0;
    for (let c of this.chunks) {
      if (c.source === '内置经典') {
        count++;
      }
    }
    return count;
  }

  getUserCount(): number {
    let count: number = 0;
    for (let c of this.chunks) {
      if (c.source === '用户上传') {
        count++;
      }
    }
    return count;
  }

  reset(): void {
    this.chunks = [];
    this.loaded = false;
  }
}

export default KnowledgeService.getInstance();
