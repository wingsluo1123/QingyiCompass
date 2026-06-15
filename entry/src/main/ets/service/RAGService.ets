import { KnowledgeChunk } from './KnowledgeService';
import KnowledgeService from './KnowledgeService';
import { Message } from './AiService';

interface ScoredChunk {
  chunk: KnowledgeChunk;
  score: number;
}

export class RAGService {
  private static instance: RAGService;

  static getInstance(): RAGService {
    if (!RAGService.instance) {
      RAGService.instance = new RAGService();
    }
    return RAGService.instance;
  }

  search(query: string, topK: number): KnowledgeChunk[] {
    let allChunks: KnowledgeChunk[] = KnowledgeService.getAllChunks();
    if (allChunks.length === 0) {
      return [];
    }

    let scoredChunks: ScoredChunk[] = [];

    for (let chunk of allChunks) {
      let score: number = this.calculateBM25Score(query, chunk);
      if (score > 0) {
        scoredChunks.push({ chunk: chunk, score: score });
      }
    }

    scoredChunks.sort((a: ScoredChunk, b: ScoredChunk) => b.score - a.score);

    let results: KnowledgeChunk[] = [];
    for (let i = 0; i < Math.min(topK, scoredChunks.length); i++) {
      results.push(scoredChunks[i].chunk);
    }
    return results;
  }

  private calculateBM25Score(query: string, chunk: KnowledgeChunk): number {
    let k1: number = 1.5;
    let b: number = 0.75;

    let allChunks: KnowledgeChunk[] = KnowledgeService.getAllChunks();
    let totalDocs: number = allChunks.length;
    let avgDocLen: number = 0;
    for (let c of allChunks) {
      avgDocLen += c.content.length;
    }
    avgDocLen = avgDocLen / Math.max(totalDocs, 1);

    let docLen: number = chunk.content.length;
    let queryTerms: string[] = this.segmentChinese(query);
    let score: number = 0;

    for (let term of queryTerms) {
      if (term.length < 2) {
        continue;
      }
      let termFreq: number = this.countTermInText(term, chunk.content);
      if (termFreq === 0) {
        continue;
      }
      let docFreq: number = 0;
      for (let c of allChunks) {
        if (c.content.indexOf(term) >= 0) {
          docFreq++;
        }
      }
      if (docFreq === 0) {
        docFreq = 1;
      }

      let idf: number = Math.log((totalDocs - docFreq + 0.5) / (docFreq + 0.5) + 1);
      let tfPart: number = (termFreq * (k1 + 1)) / (termFreq + k1 * (1 - b + b * docLen / avgDocLen));

      // Bonus: keywords match
      let keywordBonus: number = 0;
      if (chunk.keywords.indexOf(term) >= 0) {
        keywordBonus = 2.0;
      }

      // Bonus: title match
      let titleBonus: number = 0;
      if (chunk.title.indexOf(term) >= 0) {
        titleBonus = 1.5;
      }

      score += idf * tfPart * (1 + keywordBonus + titleBonus);
    }

    return score;
  }

  private segmentChinese(text: string): string[] {
    let terms: string[] = [];

    // Extract bigrams for Chinese text
    let chineseChars: string = '';
    let currentAlpha: string = '';

    for (let i = 0; i < text.length; i++) {
      let char: string = text.charAt(i);
      if (/[\u4e00-\u9fff]/.test(char)) {
        if (currentAlpha.length > 0) {
          terms.push(currentAlpha);
          currentAlpha = '';
        }
        chineseChars += char;
      } else {
        if (chineseChars.length > 0) {
          // Generate bigrams from Chinese chars
          for (let j = 0; j < chineseChars.length - 1; j++) {
            terms.push(chineseChars.substring(j, j + 2));
          }
          chineseChars = '';
        }
        if (/\w/.test(char)) {
          currentAlpha += char.toLowerCase();
        } else {
          if (currentAlpha.length > 0) {
            terms.push(currentAlpha);
            currentAlpha = '';
          }
        }
      }
    }
    // Finalize
    if (chineseChars.length > 0) {
      for (let j = 0; j < chineseChars.length - 1; j++) {
        terms.push(chineseChars.substring(j, j + 2));
      }
    }
    if (currentAlpha.length > 0) {
      terms.push(currentAlpha);
    }

    return terms;
  }

  private countTermInText(term: string, text: string): number {
    let count: number = 0;
    let pos: number = 0;
    while (pos < text.length) {
      let idx: number = text.indexOf(term, pos);
      if (idx < 0) {
        break;
      }
      count++;
      pos = idx + 1;
    }
    return count;
  }

  buildRAGPrompt(userQuery: string, contextChunks: KnowledgeChunk[], chatHistory: Message[]): Message[] {
    if (contextChunks.length === 0) {
      return chatHistory;
    }

    let contextStr: string = '';
    for (let i = 0; i < contextChunks.length; i++) {
      let chunk: KnowledgeChunk = contextChunks[i];
      contextStr += '【参考资料' + (i + 1).toString() + '】来源：' + chunk.title + '\n';
      contextStr += chunk.content + '\n\n';
    }

    let systemPrompt: string = '你是一位深谙中国传统堪舆之术的风水顾问，精通八宅明镜、紫微斗数、地理五诀等经典。你的回答风格严谨，引经据典。\n\n';
    systemPrompt += '以下是知识库中与用户问题相关的经典原文，请基于这些原文回答问题：\n\n';
    systemPrompt += contextStr;
    systemPrompt += '【回答要求】\n';
    systemPrompt += '1. 先引用相关的经典原文片段，再用白话解释\n';
    systemPrompt += '2. 如果原文不足以完全回答，请如实说明\n';
    systemPrompt += '3. 标注引用来源\n';
    systemPrompt += '4. 态度严谨，不随意编造';

    let ragMessages: Message[] = [];
    let sysMsg: Message = { role: 'system', content: systemPrompt };
    ragMessages.push(sysMsg);
    for (let msg of chatHistory) {
      ragMessages.push(msg);
    }

    return ragMessages;
  }
}

export default RAGService.getInstance();
