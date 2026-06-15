import { common } from '@kit.AbilityKit';
import { buffer } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'LocalKnowledge';
const DOMAIN = 0x0001;

const BUILTIN_FILES: string[] = ['knowledge_bazhai.txt', 'knowledge_dili.txt'];

const STOP_WORDS: string[] = [
  '的', '是', '在', '有', '和', '了', '不', '人', '我', '他', '它', '她',
  '这', '那', '之', '与', '为', '以', '及', '或', '而', '也', '但', '就',
  '都', '要', '会', '可', '能', '吗', '呢', '啊', '吧', '么', '哦', '嗯',
  '什么', '怎么', '如何', '为什么', '哪个', '哪', '怎样', '多少', '几个'
];

const FENG_SHUI_KEYWORDS: string[] = [
  '八宅', '东西四宅', '东四宅', '西四宅', '东四命', '西四命',
  '八卦', '乾', '坎', '艮', '震', '巽', '离', '坤', '兑',
  '九星', '贪狼', '巨门', '禄存', '文曲', '廉贞', '武曲', '破军', '左辅', '右弼',
  '生气', '天医', '延年', '绝命', '五鬼', '六煞', '祸害',
  '开门', '安床', '灶位', '作灶', '命卦',
  '阳宅', '阴宅', '朝向', '方位', '风水', '地形',
  '龙脉', '真龙', '寻龙', '点穴', '明堂', '砂法', '水法', '向法',
  '青龙', '白虎', '朱雀', '玄武', '案山', '朝山', '靠山',
  '二十四山', '罗经', '五行', '金', '木', '水', '火', '土',
  '选址', '龙法', '穴法', '天门', '地户', '贪狼水', '武曲水', '巨门水',
  '文笔砂', '仓库砂', '印绶砂', '玉带砂', '来水', '去水', '水口',
  '窝钳乳突', '窝', '钳', '乳', '突'
];

interface KnowledgeChunk {
  source: string;
  sectionTitle: string;
  content: string;
  keywords: Set<string>;
}

export class LocalKnowledgeService {
  private chunks: KnowledgeChunk[] = [];
  private loaded: boolean = false;

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    for (let fileName of BUILTIN_FILES) {
      try {
        let source = this.fileNameToTitle(fileName);
        let rawData = await context.resourceManager.getRawFileContent(fileName);
        let text = buffer.from(rawData).toString();
        let sections = this.parseSections(text, source);
        for (let s of sections) {
          this.chunks.push(s);
        }
        hilog.info(DOMAIN, TAG, 'Loaded %{public}s, %{public}d sections', fileName, sections.length);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'Load %{public}s failed: %{public}s', fileName, JSON.stringify(err));
      }
    }
    this.loaded = true;
    hilog.info(DOMAIN, TAG, 'LocalKnowledgeService loaded, total %{public}d sections', this.chunks.length);
  }

  private fileNameToTitle(fileName: string): string {
    if (fileName.indexOf('bazhai') >= 0) {
      return '八宅明镜';
    }
    if (fileName.indexOf('dili') >= 0) {
      return '地理五诀';
    }
    return fileName;
  }

  private parseSections(text: string, source: string): KnowledgeChunk[] {
    let result: KnowledgeChunk[] = [];

    let sectionRegex = /【(卷[^】]+)】(?:[^\n]*)\n([\s\S]*?)(?=【卷|$)/g;
    let match: RegExpExecArray | null;

    while ((match = sectionRegex.exec(text)) !== null) {
      let title = match[1].trim();
      let content = match[2].trim();
      if (content.length > 10) {
        result.push({
          source: source,
          sectionTitle: title,
          content: content,
          keywords: this.extractKeywords(content)
        });
      }
    }

    if (result.length === 0) {
      let subsections = text.split(/\n(?=【)/);
      for (let sec of subsections) {
        let titleMatch = sec.match(/【([^】]+)】/);
        let title = titleMatch ? titleMatch[1].trim() : '';
        let content = sec.trim();
        if (content.length > 10) {
          result.push({
            source: source,
            sectionTitle: title,
            content: content,
            keywords: this.extractKeywords(content)
          });
        }
      }
    }

    return result;
  }

  private extractKeywords(text: string): Set<string> {
    let keywords = new Set<string>();
    for (let kw of FENG_SHUI_KEYWORDS) {
      if (text.indexOf(kw) >= 0) {
        keywords.add(kw);
      }
    }
    return keywords;
  }

  search(query: string, maxResults: number): KnowledgeChunk[] {
    if (this.chunks.length === 0) {
      return [];
    }

    let queryTerms: string[] = this.tokenizeQuery(query);
    if (queryTerms.length === 0) {
      return [];
    }

    let scored: Array<{ chunk: KnowledgeChunk; score: number }> = [];

    for (let chunk of this.chunks) {
      let score = 0;
      let content: string = chunk.sectionTitle + ' ' + chunk.content;

      for (let term of queryTerms) {
        if (chunk.keywords.has(term)) {
          score += 5;
        }

        let count = this.countOccurrences(content, term);
        score += count * 2;

        let position = content.indexOf(term);
        if (position >= 0 && position < 50) {
          score += 3;
        }
      }

      let titleMatch = 0;
      for (let term of queryTerms) {
        if (chunk.sectionTitle.indexOf(term) >= 0) {
          titleMatch++;
        }
      }
      score += titleMatch * 10;

      if (score > 0) {
        scored.push({ chunk, score });
      }
    }

    scored.sort((a, b) => b.score - a.score);

    let results: KnowledgeChunk[] = [];
    for (let i = 0; i < Math.min(maxResults, scored.length); i++) {
      results.push(scored[i].chunk);
    }

    hilog.info(DOMAIN, TAG, 'Search for "%{public}s": %{public}d results from %{public}d scored',
      query.substring(0, 30), results.length, scored.length);

    return results;
  }

  private tokenizeQuery(query: string): string[] {
    let terms: string[] = [];

    for (let kw of FENG_SHUI_KEYWORDS) {
      if (query.indexOf(kw) >= 0) {
        terms.push(kw);
      }
    }

    let segments = query.split(/[，。！？,!\?\s]+/);
    for (let seg of segments) {
      seg = seg.trim();
      if (seg.length >= 2 && STOP_WORDS.indexOf(seg) < 0) {
        if (terms.indexOf(seg) < 0) {
          terms.push(seg);
        }
      }
    }

    if (terms.length === 0) {
      for (let seg of segments) {
        seg = seg.trim();
        if (seg.length >= 2) {
          terms.push(seg);
        }
      }
    }

    return terms;
  }

  private countOccurrences(text: string, term: string): number {
    let count = 0;
    let pos = text.indexOf(term);
    while (pos >= 0) {
      count++;
      pos = text.indexOf(term, pos + 1);
    }
    return count;
  }

  buildContextPrompt(query: string, maxResults: number): string {
    let results = this.search(query, maxResults);
    if (results.length === 0) {
      return '';
    }

    let context = '\n\n以下是从风水经典文献中检索到的相关知识，请基于这些知识来回答问题：\n\n';
    for (let i = 0; i < results.length; i++) {
      let r = results[i];
      context += `【参考${i + 1}】《${r.source}》${r.sectionTitle}\n${r.content}\n\n`;
    }
    context += '请基于以上经典文献的内容，用专业但易懂的语言回答用户的问题。如果引用了文献内容，请在回答中指出。';

    hilog.info(DOMAIN, TAG, 'Context prompt built, %{public}d references, length: %{public}d',
      results.length, context.length);
    return context;
  }

  isLoaded(): boolean {
    return this.loaded;
  }
}

export default new LocalKnowledgeService();