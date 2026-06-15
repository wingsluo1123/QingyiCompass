import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Message } from '../service/AiService';

const STORE_NAME = 'compass_conversations';
const KEY_LIST = 'conversation_list';
const KEY_ACTIVE = 'active_conversation_id';

export interface Conversation {
  id: string;
  title: string;
  messages: Message[];
  createdAt: number;
}

export class ConversationService {
  private static instance: ConversationService;
  private store: preferences.Preferences | null = null;

  static getInstance(): ConversationService {
    if (!ConversationService.instance) {
      ConversationService.instance = new ConversationService();
    }
    return ConversationService.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.store) {
      return;
    }
    this.store = await preferences.getPreferences(context, STORE_NAME);
  }

  async getConversations(): Promise<Conversation[]> {
    if (!this.store) {
      return [];
    }
    let json: string = await this.store.get(KEY_LIST, '[]') as string;
    try {
      return JSON.parse(json) as Conversation[];
    } catch (e) {
      return [];
    }
  }

  async saveConversation(conv: Conversation): Promise<void> {
    if (!this.store) {
      return;
    }
    let list: Conversation[] = await this.getConversations();
    let idx: number = list.findIndex(c => c.id === conv.id);
    if (idx >= 0) {
      list[idx] = conv;
    } else {
      list.unshift(conv);
    }
    await this.store.put(KEY_LIST, JSON.stringify(list));
    await this.store.flush();
  }

  async deleteConversation(id: string): Promise<void> {
    if (!this.store) {
      return;
    }
    let list: Conversation[] = await this.getConversations();
    list = list.filter(c => c.id !== id);
    await this.store.put(KEY_LIST, JSON.stringify(list));
    await this.store.flush();
  }

  async createConversation(title: string): Promise<Conversation> {
    let conv: Conversation = {
      id: Date.now().toString(),
      title: title,
      messages: [],
      createdAt: Date.now()
    };
    await this.saveConversation(conv);
    return conv;
  }

  async getActiveId(): Promise<string> {
    if (!this.store) {
      return '';
    }
    return await this.store.get(KEY_ACTIVE, '') as string;
  }

  async setActiveId(id: string): Promise<void> {
    if (!this.store) {
      return;
    }
    await this.store.put(KEY_ACTIVE, id);
    await this.store.flush();
  }

  generateId(): string {
    return Date.now().toString() + Math.random().toString(36).substring(2, 8);
  }
}

export default ConversationService.getInstance();
