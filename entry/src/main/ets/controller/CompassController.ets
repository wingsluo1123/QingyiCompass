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
import Logger from '../common/Logger';
import { sensor } from '@kit.SensorServiceKit';
import { Constants } from '../common/Constants';

export class CompassController {
  private angle: number = 0;
  private isSensorsRegistered: boolean = false;

  /**
   * Angle and latitude numerical conversion.
   */
  public scalAngle(angle: number) {
    let str = parseInt(angle.toString());
    let position: ResourceStr = $r('app.string.N', str);
    if (str >= 0 && str < 23) {
      position = $r('app.string.N', str);
    } else if (str >= 23 && str < 68) {
      position = $r('app.string.EN', str);
    } else if (str >= 68 && str < 113) {
      position = $r('app.string.E', str);
    } else if (str >= 113 && str < 158) {
      position = $r('app.string.ES', str);
    } else if (str >= 158 && str < 203) {
      position = $r('app.string.S', str);
    } else if (str >= 203 && str < 248) {
      position = $r('app.string.WS', str);
    } else if (str >= 248 && str < 293) {
      position = $r('app.string.W', str);
    } else if (str >= 293 && str < 338) {
      position = $r('app.string.WN', str);
    } else if (str >= 338 && str < 360) {
      position = $r('app.string.N', str);
    }
    return position;
  }

  /**
   * Subscribe to sensor data.
   */
  public getAngle() {
    if (this.isSensorsRegistered) return;
    Logger.info('subscribe to sensor data');
    try {
      sensor.on(
        sensor.SensorId.ORIENTATION,
        this.angleChange,
        {
          interval: Constants.SENSOR_INTERVAL
        });
    } catch (err) {
      Logger.error('sensor error: ' + err);
    }
  }

  /**
   * The callback for orientation sensor event data.
   */
  public angleChange = (data: sensor.OrientationResponse) => {
    //todo 记得解开注释
    // Logger.info(`component: on`);
    // Logger.info(`X-coordinate component: ${data.beta}`);
    // Logger.info(`Y-coordinate component: ${data.gamma}`);
    // Logger.info(`Z-coordinate component: ${data.alpha}`);
    this.angle = Math.round(data.alpha);
    this.notifyAngleChanges();
  };

  /**
   * 注册方向传感器（前台恢复时调用）
   */
  public register() {
    this.isSensorsRegistered = false;
    this.getAngle();
    this.isSensorsRegistered = true;
    Logger.info('orientation sensor registered');
  }

  /**
   * 注销方向传感器（退后台时调用）
   */
  public destory() {
    if (!this.isSensorsRegistered) {
      return; // 已注销，防止重复
    }
    this.isSensorsRegistered = false;

    try {
      sensor.off(sensor.SensorId.ORIENTATION, this.angleChange);
      Logger.info('unsubscribe orientation sensor');
    } catch (err) {
      Logger.error('Failed to unsubscribe orientation: ' + err);
    }
  }

  /**
   * Set angle changed listener.
   */
  public setAngleUpdateListener(listener: (Angle: number) => void) {
    this.angleUpdateListener = listener;
  }

  private angleUpdateListener: (angle: number) => void = () => {
  };

  private notifyAngleChanges() {
    if (this.angleUpdateListener) {
      this.angleUpdateListener(this.angle);
    }
  }
}