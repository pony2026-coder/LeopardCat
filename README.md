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

当前机器已生成 Android 原生目录并通过 Flutter 分析、测试和真机启动验证。

## 本地运行

安装 Flutter stable 和 Android SDK 后，在项目根目录执行：

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d <android-device-id>
```

下一步会将生成的 sing-box JSON 传入 `LeopardCatVpnService`，完成 sing-box/libbox 生命周期和 TUN fd 桥接。

## 配置转换

转换器位于 `lib/data/clash/clash_to_singbox_transformer.dart`，当前支持：

- `ss`、`vmess`、`vless`、`trojan`、`hysteria2` 节点
- `select`、`fallback`、`url-test` 策略组
- `DOMAIN`、`DOMAIN-SUFFIX`、`DOMAIN-KEYWORD`、`IP-CIDR`、`GEOIP`、`MATCH` 规则
- Android 推荐的 gVisor TUN 入站和 TLS/HTTP sniffing
- 代理节点 TLS Fragment 与直连 Fragment 参数注入