import { UIAbility, common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { buffer } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'KnowledgeSetUp';
const DOMAIN = 0x0001;

const BUILTIN_FILES: string[] = ['knowledge_bazhai.txt', 'knowledge_dili.txt'];

export default class KnowledgeSetUp extends UIAbility {
  storeName: string = 'compass_knowledge.db';
  storeConfig: relationalStore.StoreConfig = {
    name: this.storeName,
    securityLevel: relationalStore.SecurityLevel.S3,
    enableSemanticIndex: true,
    tokenizer: relationalStore.Tokenizer.CUSTOM_TOKENIZER
  };
  store?: relationalStore.RdbStore;

  async getStore(): Promise<relationalStore.RdbStore | undefined> {
    try {
      if (!this.store) {
        let context = AppStorage.get<common.UIAbilityContext>('Context') as common.UIAbilityContext;
        this.store = await relationalStore.getRdbStore(context, this.storeConfig);
        hilog.info(DOMAIN, TAG, 'getStore success');
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Init DB failed: %{public}s', JSON.stringify(err));
    }
    return this.store;
  }

  async initTable(): Promise<void> {
    try {
      const tmpStore = await this.getStore();
      const createTableSql = 'CREATE TABLE IF NOT EXISTS knowledge(' +
        'id INTEGER PRIMARY KEY, ' +
        'title TEXT, ' +
        'content TEXT, ' +
        'source TEXT, ' +
        'category TEXT);';
      await tmpStore?.execute(createTableSql, 0, undefined);
      hilog.info(DOMAIN, TAG, 'InitTable success');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Init DB failed: %{public}s', JSON.stringify(err));
    }
  }

  private chunkText(text: string, chunkSize: number): string[] {
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

  private fileNameToTitle(fileName: string): string {
    if (fileName.indexOf('bazhai') >= 0) {
      return '八宅明镜';
    }
    if (fileName.indexOf('dili') >= 0) {
      return '地理五诀';
    }
    return fileName.replace('.txt', '').replace('.md', '');
  }

  async insertData(): Promise<void> {
    try {
      let context = AppStorage.get<common.UIAbilityContext>('Context') as common.UIAbilityContext;
      let dataIndex: number = 0;
      
      for (let fileName of BUILTIN_FILES) {
        hilog.info(DOMAIN, TAG, 'Loading file: %{public}s', fileName);
        try {
          const rawFileData = await context.resourceManager.getRawFileContent(fileName);
          const fileData: string = buffer.from(rawFileData).toString();
          
          let title: string = this.fileNameToTitle(fileName);
          let source: string = '内置经典';
          let category: string = '风水经典';
          
          let pieces: string[] = this.chunkText(fileData, 400);
          
          for (let i = 0; i < pieces.length; i++) {
            let pieceTitle: string = title + ' (第' + (i + 1).toString() + '段)';
            let content: string = pieces[i].replace(/'/g, '');
            
            let sql = `INSERT OR REPLACE INTO knowledge VALUES(${dataIndex}, '${pieceTitle}', '${content}', '${source}', '${category}');`;
            const tmpStore = await this.getStore();
            await tmpStore?.executeSql(sql);
            dataIndex++;
          }
          
          hilog.info(DOMAIN, TAG, 'File %{public}s loaded, %{public}d chunks', fileName, pieces.length);
        } catch (e) {
          hilog.error(DOMAIN, TAG, 'Load file %{public}s failed: %{public}s', fileName, JSON.stringify(e));
        }
      }
      
      hilog.info(DOMAIN, TAG, 'insertData end, total %{public}d records', dataIndex);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Insert data failed: %{public}s', JSON.stringify(err));
    }
  }

  async closeStore(): Promise<void> {
    try {
      await this.store?.close();
      hilog.info(DOMAIN, TAG, 'Store closed');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Close store failed: %{public}s', JSON.stringify(e));
    }
  }
}