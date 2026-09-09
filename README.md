# LeopardCat

基于 Flutter 的跨平台代理客户端，首个目标平台为 Android。UI 参考 FlClash，工程边界按 `core / data / features` 演进。

## 当前状态

已完成第一版 Android-first UI 壳：

- 响应式导航：窄屏使用底部导航，宽屏使用侧边导航
- 控制台：服务启停、配置状态、流量概览和内核信息
- 配置页：本地配置创建、选择、持久化与订阅导入/更新
- 设置页：运行偏好与关于信息
- Android 宿主：`MethodChannel`、VPN 权限申请、前台 `VpnService` 和 TUN fd 桥接
- 配置转换：Clash YAML 转 sing-box JSON，支持节点、策略组、规则、TUN 和 TLS Fragment
- 核心桥接：配置 JSON 已传入 Android service，支持 `start`、`reload`、`stop`、`status`、`queryTraffic`、`delayTest`
- sing-box 核心：已接入 v1.14.0 多 ABI `libbox.aar`，使用官方 `Libbox.checkConfig()` 校验配置
- 运行状态：Android `PlatformInterface` 监控非 VPN 默认网络；真机已验证 TUN 代理 HTTPS 数据面
- 遥测：通过 libbox `CommandClient` 获取上下行累计流量，并对策略组/节点执行异步 URL 延迟测试

当前机器已生成 Android 原生目录并通过 Flutter 分析、测试和真机启动验证。

## 本地运行

安装 Flutter stable 和 Android SDK 后，在项目根目录执行：

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d <android-device-id>
```

项目包含官方 sing-box v1.14.0 多 ABI AAR，`LibboxEngineAdapter` 会调用
`Libbox.checkConfig()` 校验配置，并通过 `CommandServer.startOrReloadService()` 启动核心。
Android `VpnService.Builder` 已实现 TUN fd 建立和 `protect(fd)`，并通过 `CommandClient`
订阅真实累计流量与 URL 测试结果。AAR 的 SHA-256 为
`31270a9f33111b699bd52e283802d991308348db58c931e5fff610c6f24b63a0`。
该产物来自 [sing-box v1.14.0](https://github.com/SagerNet/sing-box/tree/v1.14.0)
官方 `build_libbox` 和 `merge_aar` 流程，覆盖 `arm64-v8a`、`armeabi-v7a`、`x86_64`。

重新构建 Go 内核 AAR：

```bash
./tool/build_libbox_android.sh
```

## 配置转换

转换器位于 `lib/data/clash/clash_to_singbox_transformer.dart`，当前支持：

- `ss`、`vmess`、`vless`、`trojan`、`hysteria2` 节点
- `select`、`fallback`、`url-test` 策略组
- `DOMAIN`、`DOMAIN-SUFFIX`、`DOMAIN-KEYWORD`、`IP-CIDR`、`GEOIP`、`MATCH` 规则
- WebSocket、gRPC、HTTP、HTTP Upgrade 传输参数
- Reality、uTLS 指纹、UDP、Shadowsocks 插件参数
- Android 推荐的 gVisor TUN 入站和路由 sniff
- 代理节点 TLS Fragment 与直连 Fragment 参数注入

## 配置与订阅

本地配置和当前选中的配置会保存到 Android 应用存储。配置页支持手动创建 Clash YAML
配置，或通过 HTTP/HTTPS 地址导入订阅。订阅下载成功后会先转换并校验，只有可转换的
Clash YAML 才会写入本地；订阅配置可通过其更新按钮重新拉取。连接中的状态下切换当前
配置会触发内核重载。

延迟测试由控制台的“延迟测试”行触发。它仅在已连接且当前配置的最终路由指向代理
节点或策略组时可用；空配置或 `DIRECT` 路由不会发送无意义的测速请求。