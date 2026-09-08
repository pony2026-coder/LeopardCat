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

当前机器已生成 Android 原生目录并通过 Flutter 分析、测试和真机启动验证。

## 本地运行

安装 Flutter stable 和 Android SDK 后，在项目根目录执行：

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d <android-device-id>
```

当前仓库尚未放入 sing-box `libbox.aar`，因此 `LibboxEngineAdapter` 会校验并保存配置后返回 `unavailable`；流量查询返回零值，测速返回空值，不会伪造代理核心已运行。下一步是接入对应 ABI 的 `libbox.aar`，实现 TUN fd 和真实核心生命周期。

## 配置转换

转换器位于 `lib/data/clash/clash_to_singbox_transformer.dart`，当前支持：

- `ss`、`vmess`、`vless`、`trojan`、`hysteria2` 节点
- `select`、`fallback`、`url-test` 策略组
- `DOMAIN`、`DOMAIN-SUFFIX`、`DOMAIN-KEYWORD`、`IP-CIDR`、`GEOIP`、`MATCH` 规则
- Android 推荐的 gVisor TUN 入站和 TLS/HTTP sniffing
- 代理节点 TLS Fragment 与直连 Fragment 参数注入