import { preferences } from '@kit.ArkData';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

const STORE_NAME = 'compass_api_config';
const KEY_API_KEY = 'api_key';
const KEY_BASE_URL = 'base_url';
const KEY_MODEL = 'model';
const KEY_RAG_URL = 'rag_url';
const KEY_RAG_TOKEN = 'rag_token';
const KEY_RAG_ENABLED = 'rag_enabled';

const DEFAULT_BASE_URL = 'https://api.deepseek.com/chat/completions';
const DEFAULT_MODEL = 'deepseek-v4-pro';
const DEFAULT_API_KEY = '';
const DEFAULT_RAG_URL = 'https://rag.wingsluo.com';
const DEFAULT_RAG_TOKEN = '';

export class ApiConfigService {
  private static instance: ApiConfigService;
  private store: preferences.Preferences | null = null;

  static getInstance(): ApiConfigService {
    if (!ApiConfigService.instance) {
      ApiConfigService.instance = new ApiConfigService();
    }
    return ApiConfigService.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.store) {
      return;
    }
    this.store = await preferences.getPreferences(context, STORE_NAME);
  }

  async getApiKey(): Promise<string> {
    if (!this.store) {
      return DEFAULT_API_KEY;
    }
    return (await this.store.get(KEY_API_KEY, DEFAULT_API_KEY) as string);
  }

  async getBaseUrl(): Promise<string> {
    if (!this.store) {
      return DEFAULT_BASE_URL;
    }
    return (await this.store.get(KEY_BASE_URL, DEFAULT_BASE_URL) as string);
  }

  async getModel(): Promise<string> {
    if (!this.store) {
      return DEFAULT_MODEL;
    }
    return (await this.store.get(KEY_MODEL, DEFAULT_MODEL) as string);
  }

  async saveApiKey(key: string): Promise<boolean> {
    if (!this.store) {
      promptAction.showToast({ message: '存储未初始化', duration: 1500 });
      return false;
    }
    await this.store.put(KEY_API_KEY, key);
    await this.store.flush();
    promptAction.showToast({ message: '保存成功', duration: 1500 });
    return true;
  }

  async saveBaseUrl(url: string): Promise<boolean> {
    if (!this.store) {
      return false;
    }
    await this.store.put(KEY_BASE_URL, url);
    await this.store.flush();
    return true;
  }

  async saveModel(model: string): Promise<boolean> {
    if (!this.store) {
      return false;
    }
    await this.store.put(KEY_MODEL, model);
    await this.store.flush();
    return true;
  }

  async hasApiKey(): Promise<boolean> {
    let key = await this.getApiKey();
    return key.length > 0;
  }

  async getRagUrl(): Promise<string> {
    if (!this.store) {
      return DEFAULT_RAG_URL;
    }
    return (await this.store.get(KEY_RAG_URL, DEFAULT_RAG_URL) as string);
  }

  async getRagToken(): Promise<string> {
    if (!this.store) {
      return DEFAULT_RAG_TOKEN;
    }
    let token: string = (await this.store.get(KEY_RAG_TOKEN, DEFAULT_RAG_TOKEN) as string).trim();
    if (token !== DEFAULT_RAG_TOKEN) {
      await this.store.put(KEY_RAG_TOKEN, DEFAULT_RAG_TOKEN);
      await this.store.flush();
      return DEFAULT_RAG_TOKEN;
    }
    return token;
  }

  async saveRagToken(token: string): Promise<boolean> {
    if (!this.store) {
      return false;
    }
    await this.store.put(KEY_RAG_TOKEN, token);
    await this.store.flush();
    return true;
  }

  async saveRagUrl(url: string): Promise<boolean> {
    if (!this.store) {
      return false;
    }
    await this.store.put(KEY_RAG_URL, url);
    await this.store.flush();
    return true;
  }

  async isRagEnabled(): Promise<boolean> {
    if (!this.store) {
      return true;
    }
    return (await this.store.get(KEY_RAG_ENABLED, true) as boolean);
  }

  async setRagEnabled(enabled: boolean): Promise<boolean> {
    if (!this.store) {
      return false;
    }
    await this.store.put(KEY_RAG_ENABLED, enabled);
    await this.store.flush();
    return true;
  }
}

export default ApiConfigService.getInstance();
