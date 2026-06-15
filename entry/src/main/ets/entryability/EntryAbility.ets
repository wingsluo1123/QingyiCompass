/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the ""License"");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an ""AS IS"" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, ConfigurationConstant, UIAbility, Want, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { CompassController } from '../controller/CompassController';
import { BusinessError } from '@kit.BasicServicesKit';
import ThemeService from '../service/ThemeService';
// Offline release: restore KnowledgeSetUp when the knowledge-base feature is enabled again.
// import KnowledgeSetUp from '../service/KnowledgeSetUp';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      const isDarkMode: boolean = ThemeService.loadDarkMode(this.context);
      AppStorage.setOrCreate<boolean>('isDarkMode', isDarkMode);
      this.context.getApplicationContext().setColorMode(isDarkMode ?
        ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
        ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'onCreate error: %{public}s', JSON.stringify(err));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    AppStorage.setOrCreate<common.UIAbilityContext>('Context', this.context);

    // Offline release: local knowledge-base initialization is disabled.
    // this.initRAGSystem();

    windowStage.loadContent('pages/Horse', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the Horse content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the Horse content.');
    });
  }

  // Offline release: restore this method when the knowledge-base feature is enabled again.
  // private async initRAGSystem(): Promise<void> {
  //   let setUp: KnowledgeSetUp = new KnowledgeSetUp();
  //   try {
  //     hilog.info(DOMAIN, 'testTag', 'Starting KnowledgeSetUp initTable');
  //     await setUp.initTable();
  //     hilog.info(DOMAIN, 'testTag', 'KnowledgeSetUp initTable done, starting insertData');
  //     await setUp.insertData();
  //     AppStorage.setOrCreate<KnowledgeSetUp>('SetUpObject', setUp);
  //     hilog.info(DOMAIN, 'testTag', 'KnowledgeSetUp completed');
  //   } catch (err) {
  //     hilog.error(DOMAIN, 'testTag', 'KnowledgeSetUp failed: %{public}s', JSON.stringify(err));
  //   }
  // }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
    // Offline release: no knowledge-base store is opened.
    // try {
    //   const setup = AppStorage.get<KnowledgeSetUp>('SetUpObject') as KnowledgeSetUp;
    //   if (setup) {
    //     setup.closeStore();
    //   }
    // } catch (err) {
    //   hilog.error(DOMAIN, 'testTag', 'closeStore error: %{public}s', JSON.stringify(err));
    // }
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    try {
      const controller = AppStorage.get<CompassController>('compassController');
      if (controller) {
        controller.register();
      }
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'onForeground error: %{public}s', JSON.stringify(err));
    }
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    try {
      const controller = AppStorage.get<CompassController>('compassController');
      if (controller) {
        controller.destory();
      }
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'onBackground error: %{public}s', JSON.stringify(err));
    }
  }
};
