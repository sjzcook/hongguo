# 红果短剧 · Flutter 客户端

一个参考 [真果鉴 / 红果鉴](https://github.com/enginJie/guoapp) 思路写的 Flutter 短剧客户端：
**UI 与数据源彻底解耦，站源可插拔**。内置离线演示站源，`flutter run` 就能跑通「浏览 → 详情 → 播放 → 收藏 → 续播」全链路。

> 本项目为学习 Flutter 与客户端架构而写的第三方示例，与红果短剧官方无任何关联，不内置任何官方内容。

---

## 功能

| 模块 | 说明 |
| --- | --- |
| 发现 | 分类横向切换、双列海报流、下滑自动翻页、下拉刷新、继续观看横滑条 |
| 榜单 | 热播 / 新剧 / 完结 / 漫剧四榜，大号名次 + 热度 |
| 搜索 | 输入 320ms 防抖、热门词、搜索历史、结果富文本卡 |
| 详情 | 沉浸式头图、标签、简介展开、选集网格、当前集高亮、一键续播 |
| 播放 | 竖屏全屏、单击显隐控制栏、上/下滑切集、进度拖动、倍速、选集、自动连播 |
| 登录 | 手机号 + 验证码、协议勾选、记住登录态、退出清理、付费集门禁 |
| 追剧 | 本地收藏、观看历史、断点续播（每 5s 落盘 + 退出落盘） |
| 设置 | 站源切换、自动连播、默认倍速、清空历史、免责声明 |

## 快速开始

```bash
flutter pub get
flutter run                 # 默认演示站源，无需任何配置
```

指定平台：

```bash
flutter run -d android
flutter run -d chrome
```

国内网络建议先设置镜像：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

## 架构

真果鉴的做法是 **Flutter 负责呈现 + Go 核心负责站源签名与解析**（通过 FFI 桥接）。
本项目把同一件事拆得更适合纯 Dart 工程：把「站源」抽成一个接口，签名能力作为可注入依赖。

```
lib/
├─ core/theme/            全局深色主题与配色
├─ data/
│  ├─ models/             Drama / Episode / WatchProgress
│  ├─ source/
│  │  ├─ drama_source.dart      站源抽象（唯一约束 UI 的契约）
│  │  ├─ demo_source.dart       内置离线剧库（22 部 / 可播放）
│  │  ├─ hongguo_source.dart    红果元数据网关与播放地址解析
│  │  └─ hongguo_gateway_config.dart  从 MiniReel sources.json 提取的配置
│  └─ local/local_store.dart    收藏 / 历史 / 偏好持久化
├─ state/app_state.dart   全局状态（ChangeNotifier）
└─ features/              页面与播放器
```

关键设计：

1. **UI 不认识「红果」**。所有页面只依赖 `DramaSource`，换站源不改编排代码。
2. **网关地址可配置**。元数据网关通过 `HONGGUO_GATEWAY` 注入，播放地址解析使用 `sources.json` 中的 `playbackEndpoint`，可单独覆盖。
3. **失败不崩**。封面、分页、播放、详情各自有兜底与重试态；封面加载失败自动降级为标题渐变图。

## MiniReel 配置的网关接入

配置来源：[`MiniReel-0.3.2-android-arm64-v8a/assets/flutter_assets/assets/config/sources.json`](MiniReel-0.3.2-android-arm64-v8a/assets/flutter_assets/assets/config/sources.json)。

`lib/data/source/hongguo_gateway_config.dart` 已提取其中红果源配置，包括：

- 网页站点：`https://hongguoduanju.com`
- 播放解析接口：`https://djapi.999888456.xyz/api/hongguo/play`
- 网页 Referer、媒体 Referer、超时、重试次数、分页大小
- `appBaseUrl`、User-Agent 与应用/设备参数（作为参考配置保留）

播放器源在网关返回的分集没有直接视频 URL、但存在集号时，会请求播放解析接口，并传入 `series_id` 与 `ep` 查询参数。响应解析兼容 `data.url`、`result.url`、`url`、`video_url` 和 `play_url`。播放地址可能带时效，不应长期缓存。

### 运行配置

```bash
flutter run \
  --dart-define=HONGGUO_GATEWAY=https://你的元数据网关地址 \
  --dart-define=HONGGUO_TOKEN=你的网关APIKey
```

如需覆盖播放解析端点，可在构建参数中设置 `HONGGUO_PLAYBACK_ENDPOINT`（如果后续版本启用该覆盖项）；默认值来自上述配置文件。

**注意：** `HONGGUO_GATEWAY` 是客户端自定义的元数据网关，必须实现以下契约并返回 JSON：

```
GET /feed?page=1&category=都市
GET /rank?type=hot|new|finished|ai&page=1
GET /search?q=关键词&page=1
GET /drama/{id}
GET /drama/{id}/episodes
GET /categories          # 可选
```

`sources.json` 还包含一个应用接口域名及设备参数；这并不代表该接口是公开、免签或已授权的 API。本项目不会伪造官方私有签名、绕过付费门禁或解密受保护媒体。真实网关可用性与播放权限仍需在获得授权的前提下单独验证。

## 自建元数据网关

`scripts/setup_gateway_centos.sh` 是一个自包含的部署脚本，**不需要 `npm install`**——网关只用 Node 标准库，脚本从镜像拉 Node tarball，不碰 yum 源：

```bash
scp scripts/setup_gateway_centos.sh root@你的服务器:/root/
ssh root@你的服务器
bash setup_gateway_centos.sh --domain api.example.com --email you@example.com
```

脚本默认使用 mock 数据，便于先验证 UI 与播放链路；它不是红果官方 API 的实现。接自有上游时按脚本中的适配器契约配置。

## 登录与会话

客户端只实现我们自己的 `/auth/*` 契约。红果官方登录可能需要签名与设备指纹；请将网关接到你有权使用的账号体系或官方授权渠道。

## 测试

```bash
flutter pub get
flutter analyze
flutter test
```

`test/hongguo_gateway_config_test.dart` 覆盖配置值和播放解析请求参数。该测试使用 MockClient，不代表真实第三方服务已在线可用或真实视频已成功播放。

## 打包 iOS 未签名 IPA

iOS 产物必须在 macOS 上编译（需要 Xcode 的 clang 与 iOS SDK），Windows / Linux 无法交叉编译。可通过仓库中的 GitHub Actions 工作流构建未签名 IPA。
