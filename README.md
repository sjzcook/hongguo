# 红果短剧 · Flutter 客户端

这是一个通过可配置元数据网关和播放解析接口获取真实短剧数据的 Flutter 客户端。**已移除内置演示剧库、示例视频和本地演示登录**；未配置真实网关时，应用会提示配置错误，不会伪装成真实内容。

> 本项目为第三方客户端，与红果短剧官方无关联。请仅接入你有权使用的接口和媒体内容，不绕过付费或访问控制。

## 配置来源

读取自 [MiniReel sources.json](MiniReel-0.3.2-android-arm64-v8a/assets/flutter_assets/assets/config/sources.json) 的设置位于 `lib/data/source/hongguo_gateway_config.dart`：

- 网站 Referer：`https://hongguoduanju.com/`
- 播放解析接口：`https://djapi.999888456.xyz/api/hongguo/play`
- 应用接口参考地址：`https://api5-normal-sinfonlineb.fqnovel.com`
- 超时 12 秒、最多 3 次播放解析尝试、分页大小 24
- 应用 User-Agent 与设备参数作为参考配置保留

播放解析地址可在构建时覆盖：

```bash
flutter pub get
flutter run \
  --dart-define=HONGGUO_GATEWAY=https://你的真实元数据网关 \
  --dart-define=HONGGUO_TOKEN=你的网关APIKey \
  --dart-define=HONGGUO_PLAYBACK_ENDPOINT=https://djapi.999888456.xyz/api/hongguo/play
```

## 重要：两个接口职责不同

`HONGGUO_GATEWAY` 是客户端使用的元数据 API，必须返回真实剧库数据并实现：

```
GET /feed?page=1&category=都市
GET /rank?type=hot|new|finished|ai&page=1
GET /search?q=关键词&page=1
GET /drama/{id}
GET /drama/{id}/episodes
GET /categories
```

`HONGGUO_PLAYBACK_ENDPOINT` 是播放解析接口。分集元数据没有直接视频 URL 时，客户端会尝试使用 `series_id` 和 `ep` 请求解析，并兼容响应中的 `data.url`、`result.url`、`url`、`video_url` 或 `play_url` 字段。

**仅凭 `sources.json` 不能推导出元数据接口的真实路径、请求参数、响应结构或授权规则。** 因此，不要把网站首页或 `appBaseUrl` 直接当作已经验证的元数据 API。本仓库当前不会伪造红果私有签名，也不声称上述第三方播放接口已在线验证。只有接入有效的真实元数据网关、接口返回可播放的授权媒体地址，并在真机上成功播放，才能确认真实短剧播放完成。

## 项目功能

- 真实数据源驱动的发现、榜单、搜索、详情与选集 UI
- 视频播放器、倍速、切集与自动连播
- 收藏、观看历史、断点续播
- 网关认证接口（需要真实网关实现 `/auth/*`）
- 错误提示与重试，不再回退到演示剧库

## 开发验证

```bash
flutter pub get
flutter analyze
flutter test
```

播放解析的单元测试使用 MockClient 验证请求和字段映射；它不代表第三方服务在线可用。请检查 GitHub Actions 结果，并用实际网关及真实媒体 URL 做端到端测试。
