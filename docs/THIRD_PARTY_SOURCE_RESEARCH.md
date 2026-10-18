# 第三方红果短剧接口调研与接入边界

更新时间：2026-10-18

## 核查结论

本仓库原有 `HongguoDramaSource` 访问的是本项目定义的网关契约，不是已验证可直接调用的红果官方 API。客户端可通过 `HONGGUO_GATEWAY` 配置第三方/自建桥接服务。

优先研究的公开项目：

- [N3urda/hongguoTV](https://github.com/N3urda/hongguoTV)：提供独立客户端、Node 服务、接口说明与测试脚本。仓库声明 GPL-3.0。这里只参考架构和验证流程，不复制其实现。
- [zhenyong97/hongguo-downloader](https://github.com/zhenyong97/hongguo-downloader)：`src/native/hongguo.js` 集中处理分集与视频模型。仓库声明 GPL-3.0。这里只作为字段/调用顺序的研究资料，不复制实现。
- [woshishiq1/drpys](https://github.com/woshishiq1/drpys)：`红果果[短].js` 含站源请求和播放代理流程，仓库声明 GPL-3.0。其实现依赖专用运行时，不能当成可直接粘贴的 Dart SDK。

这些仓库的源码和许可证信息不等于接口实时可用、内容获授权或普通播放器可以播放。当前未对第三方服务执行真实账号请求，也未验证任意具体剧集的播放地址；因此不能宣称真实播放已验收。

## 当前适配器契约

客户端只请求配置的网关：

- `GET /feed?page=1&category=推荐`
- `GET /rank?type=hot&page=1`
- `GET /search?q=关键词&page=1`
- `GET /drama/{id}`
- `GET /drama/{id}/episodes`
- `GET /categories`（可选）

响应可用 `data`、`result` 包装。列表支持 `list`、`items`、`results`；剧集列表支持 `list`、`episodes`、`items`。字段别名兼容常见的 `series_id`、`series_title`、`cover_url`、`total`、`vid_index`、`play_url`。

## 播放限制

- `Episode.videoUrl` 应是用户有权播放、且播放器可直接处理的 HTTP(S) 媒体地址。
- 取到 URL 不等于媒体可播放；仍需验证有效期、重定向、HTTP Range、编码格式和平台解码支持。
- 不在 Flutter 客户端实现绕过访问控制的签名仿造、密钥提取或 DRM/CENC 解密。若第三方返回的是加密媒体，必须使用内容提供方授权的播放 SDK/服务。
- 不要把个人账号 Cookie、设备标识或长期密钥硬编码进仓库。网关令牌只通过运行时配置提供。

## 验证步骤

1. 使用自己部署或明确授权的第三方网关。
2. 对 `/feed`、`/drama/{id}`、`/drama/{id}/episodes` 运行适配器测试。
3. 选取一条授权且标准播放器兼容的测试媒体 URL，验证 Android/iOS 实机播放。
4. 只有真实网关返回有效元数据并且授权媒体能播放后，才标记端到端验收通过。
