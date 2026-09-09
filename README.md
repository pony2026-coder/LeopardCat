# LeopardCat

基于 Flutter 的跨平台代理客户端，首个目标平台为 Android。UI 参考 FlClash，工程边界按 `core / data / features` 演进。

## 当前状态

已完成第一版 Android-first UI 壳：

- 响应式导航：窄屏使用底部导航，宽屏使用侧边导航
- 控制台：服务启停、配置状态、流量概览和内核信息
- 配置页：本地/订阅配置列表入口
- 设置页：运行偏好与关于信息
- Android 宿主：`MethodChannel`、VPN 权限申请和 `VpnService` 生命周期占位
- 配置转换：Clash YAML 转 sing-box JSON，支持节点、策略组、规则、TUN 和 TLS Fragment
- 核心桥接：配置 JSON 已传入 Android service，支持 `start`、`reload`、`stop`、`status`、`queryTraffic`、`delayTest`
- sing-box 核心：已接入 v1.14.0 多 ABI `libbox.aar`，使用官方 `Libbox.checkConfig()` 校验配置

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
`Libbox.checkConfig()` 校验配置；由于 TUN fd 和平台接口尚未完成，核心启动仍返回
`unavailable`，流量查询返回零值，测速返回空值，不会伪造代理核心已运行。下一步是实现
真实 TUN fd 和核心生命周期。AAR 的 SHA-256 为
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
- Android 推荐的 gVisor TUN 入站和 TLS/HTTP sniffing
- 代理节点 TLS Fragment 与直连 Fragment 参数注入