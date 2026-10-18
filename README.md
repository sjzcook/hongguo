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
│  │  └─ hongguo_source.dart    红果通道：可注入 RequestSigner + 网关协议
│  └─ local/local_store.dart    收藏 / 历史 / 偏好持久化
├─ state/app_state.dart   全局状态（ChangeNotifier）
├─ features/
│  ├─ shell/              底部三 Tab 框架
│  ├─ home/               发现页
│  ├─ ranking/            榜单页
│  ├─ search/             搜索页
│  ├─ detail/             详情 + 选集
│  ├─ player/             播放器
│  ├─ library/            我的（收藏 / 历史）
│  └─ settings/           设置
└─ widgets/               封面、剧卡、榜单行
```

关键设计：

1. **UI 不认识「红果」**。所有页面只依赖 `DramaSource`，换站源不改编排代码。
2. **签名是可注入的**。`HongguoDramaSource` 接受 `RequestSigner`，把 X-Gorgon / X-Argus 这类设备指纹交给外部实现。
3. **失败不崩**。封面、分页、播放、详情各自有兜底与重试态；封面加载失败自动降级为标题渐变图。

## 接入真实站源

红果官方接口对每个请求都校验签名与设备指纹，纯 Dart 侧无法自行生成，这也是真果鉴要挂一个 Go 核心的原因。两条可行路径：

### 方案 A：自建解析网关（推荐，与真果鉴同构）

```
Flutter (本项目)  ──HTTP──▶  你的网关（Go/Node/Python）  ──签名请求──▶  红果接口
                                  │
                                  └─ 负责签名、设备指纹池、解密、地址下发
```

网关只需实现下面 5 个接口，返回 `{"data": ...}`：

```
GET /feed?page=1&category=都市
GET /rank?type=hot|new|finished|ai&page=1
GET /search?q=关键词&page=1
GET /drama/{id}
GET /drama/{id}/episodes
```

然后启动时注入地址：

```bash
flutter run --dart-define=HONGGUO_GATEWAY=http://192.168.1.10:8080
```

设置页会自动把「红果」站源点亮，一键切换。

### 方案 B：WebView 通道

用系统 WebView 打开官方 H5，拦截页面自身发出的 XHR/fetch 响应（签名由官方页面完成），
把 JSON 回灌给 `HongguoDramaSource`。适合不想自建服务、只要手机端的场景。
Android 端加 `flutter_inappwebview` 后，在 `shouldInterceptRequest` 里把响应体转发即可。

## 已验证

- `flutter analyze` —— **0 issues**
- `flutter build web --release` —— 构建通过
- `test/widget_test.dart` —— 覆盖站源分页 / 排序 / 搜索 / 选集一致性 / 剧卡渲染

> 说明：本机沙箱内 `flutter_tester` 无法建立本地 socket（报 `Invalid WebSocket upgrade request`），
> 测试未能在本机执行；在正常桌面环境 `flutter test` 可直接运行。
> 本机也未安装 Android SDK，故未产出 APK；`flutter build apk --release` 在有 Android 环境时可直接出包。

## 打包 iOS 未签名 IPA

iOS 产物必须在 macOS 上编译（需要 Xcode 的 clang 与 iOS SDK），Windows / Linux 无法交叉编译。
本项目提供两条出包路径，都不需要 Apple 开发者账号。

### 路径一：GitHub Actions（推荐，无需 Mac）

工作流：`.github/workflows/build-ios.yml`，跑在 `macos-14` 上。

```bash
# 打 tag 自动出包，并附到 Release
git tag v1.0.0 && git push origin v1.0.0

# 或到 Actions 页手动触发（Run workflow），可填网关地址
```

产物：`hongguo-<版本>-unsigned.ipa`，在 Actions 运行页的 **Artifacts** 里下载（保留 7 天）。

核心命令就三行：

```bash
flutter build ios --release --no-codesign
mkdir -p Payload && ditto build/ios/iphoneos/Runner.app Payload/Runner.app
zip -qry app-unsigned.ipa Payload
```

### 路径二：本机 Mac 一键脚本

```bash
./scripts/build_ipa.sh
# 带网关：
HONGGUO_GATEWAY=http://192.168.1.10:8080 ./scripts/build_ipa.sh
```

产物在 `build/ipa/hongguo-<版本>-unsigned.ipa`。

### 装到 iPhone 上

未签名 IPA **不能直接安装**，iOS 会校验签名。需要自签：

| 工具 | 说明 |
| --- | --- |
| Sideloadly / AltStore | 用免费 Apple ID 签名，有效期 7 天，到期重签 |
| 爱思助手 | 图形化自签，需要登录 Apple ID |
| 付费开发者账号 | 有效期 1 年，可长期使用 |

自签后首次启动需在「设置 → 通用 → VPN与设备管理」里信任证书。

> iOS 端已配置：显示名「红果短剧」、仅竖屏、Bundle ID `com.zhenguo.hongguo`、最低 iOS 15.0。

## 平台说明

| 平台 | 状态 |
| --- | --- |
| Android / iOS | 完整支持（`video_player` 原生解码） |
| Web | 完整支持（浏览器解码，CORS 需站源配合） |
| Windows / Linux | 界面可用，播放器依赖 `video_player` 无桌面实现，会提示「该平台不支持内置播放器」。接桌面播放可换 `media_kit` |

## 免责声明

本项目仅用于学习 Flutter 客户端架构与播放器实现。内置演示剧库为虚构内容，演示视频来自 Flutter 官方示例资源。
接入真实站源时请遵守目标平台的用户协议与当地法律法规，不得用于商业用途、批量抓取或绕过付费内容。
