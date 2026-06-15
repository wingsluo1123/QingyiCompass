import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const STORE_NAME = 'compass_theme';
const KEY_DARK_MODE = 'is_dark_mode';

export default class ThemeService {
  static loadDarkMode(context: common.UIAbilityContext): boolean {
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, {
        name: STORE_NAME
      });
      return store.getSync(KEY_DARK_MODE, false) as boolean;
    } catch (error) {
      console.error(`Failed to load theme preference: ${JSON.stringify(error)}`);
      return false;
    }
  }

  static saveDarkMode(context: common.UIAbilityContext, enabled: boolean): boolean {
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, {
        name: STORE_NAME
      });
      store.putSync(KEY_DARK_MODE, enabled);
      store.flushSync();
      return true;
    } catch (error) {
      console.error(`Failed to save theme preference: ${JSON.stringify(error)}`);
      return false;
    }
  }
}
