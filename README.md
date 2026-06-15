# 清一罗盘

## 简介

清一罗盘是一款基于 HarmonyOS 的传统堪舆罗盘应用，集成了电子罗盘、紫微星盘与 AI 智能助手，帮助风水爱好者与从业者快速获取方位、星盘数据。

## 环境要求

- HarmonyOS API 6.0.0 Release（API 20）及以上
- DevEco Studio 6.0.0 Release 及以上

## 功能模块

### 🧭 罗盘

- 实时传感器采集方向数据，指针始终指向正北
- 显示当前坐向（二十四山定向：八宫配二十四山）
- 洛书数理计算：根据年份与向方自动推导洛书九宫
- 自定义度数输入，快速查看指定方向
- 方向信息弹窗（坤山艮向、子山午向等详解）

### ⭐ 星盘

- 紫微斗数星盘展示：显示紫微、天府十二星分布
- 四化（化禄、化权、化科、化忌）天干地支推算
- 命宫定位与科名星（台辅、封诰、文昌、文曲等）展示
- 流年、流月输入分析
- 火星、铃星、左右辅星等辅星计算

### 🤖 AI 助手

- 基于 DeepSeek API 的智能对话
- 支持多轮对话，完整保留上下文
- 气泡式聊天界面，用户消息与 AI 回复左右分区

### 📖 关于

- 应用信息与使用说明

## 技术特性

- **沉浸光感**：底部页签栏适配华为 HDS 沉浸光感效果，根据设备算力自适应材质级别
- **传感器融合**：融合方向传感器、磁力传感器、气压传感器、GPS 定位
- **自定义 Canvas 绘制**：罗盘与星盘均使用 Canvas 自绘，支持多层同心圆叠加与动态旋转
- **响应式布局**：界面适配不同屏幕比例，避免固定像素导致的组件重叠
- **AI 集成**：通过 `@kit.NetworkKit` 直接调用 DeepSeek API，无额外后端服务

## 工程目录

```
entry/src/main/ets/
├─ common/
│  ├─ CompassConstants.ets       // 八卦、天干地支、洛书等常量
│  ├─ Constants.ets              // 通用常量
│  └─ Logger.ets                 // 日志工具类
├─ component/
│  ├─ CompassView.ets            // 罗盘自定义 Canvas 组件
│  ├─ ChartView.ets              // 星盘自定义 Canvas 组件
│  └─ DirectionInfoDialog.ets    // 方向信息弹窗
├─ controller/
│  └─ CompassController.ets      // 传感器控制器
├─ model/
│  ├─ DirectionInfo.ets          // 方向信息数据模型
│  └─ KeMing.ets                 // 科名星数据模型
├─ pages/
│  ├─ Index.ets                  // 主入口（HdsTabs 页签导航）
│  ├─ CompassPage.ets            // 罗盘页面
│  ├─ Chart.ets                  // 星盘页面
│  ├─ AiChatPage.ets             // AI 对话页面
│  ├─ About.ets                  // 关于页面
│  └─ Horse.ets                  // 附加页面
├─ service/
│  └─ AiService.ets              // AI API 网络请求层
└─ entryability/
   └─ EntryAbility.ets
```

## 权限说明

| 权限 | 用途 |
|------|------|
| `ohos.permission.INTERNET` | AI 对话网络请求 |
| `ohos.permission.APPROXIMATELY_LOCATION` | 获取设备大致位置 |
| `ohos.permission.LOCATION` | 获取设备精确经纬度 |

## AI 功能配置

1. 申请 [DeepSeek API Key](https://platform.deepseek.com/api_keys)
2. 在 `entry/src/main/ets/service/AiService.ets` 中替换 `API_KEY` 常量
3. 编译运行，点击底部「🤖 AI」页签即可使用

## 参考文档

- [@ohos.sensor（传感器）](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-sensor)
- [@ohos.geoLocationManager（位置服务）](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-geolocationmanager)
- [HDS 沉浸光感](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-component-material)
- [DeepSeek API 文档](https://api-docs.deepseek.com/zh-cn/)
