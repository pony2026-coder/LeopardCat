# LeopardCat

基于 Flutter 的跨平台代理客户端，首个目标平台为 Android。UI 参考 FlClash，工程边界按 `core / data / features` 演进。

## 当前状态

已完成第一版 Android-first UI 壳：

- 响应式导航：窄屏使用底部导航，宽屏使用侧边导航
- 控制台：服务启停、配置状态、流量概览和内核信息
- 配置页：本地/订阅配置列表入口
- 设置页：运行偏好与关于信息
- Android 宿主：`MethodChannel`、VPN 权限申请和 `VpnService` 生命周期占位

当前机器已生成 Android 原生目录并通过 Flutter 分析；Android SDK 尚未安装，因此暂时无法构建 APK。

## 本地运行

安装 Flutter stable 和 Android SDK 后，在项目根目录执行：

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d <android-device-id>
```

下一步会将 `LeopardCatVpnService` 内部接入 sing-box/libbox，并完成 Clash YAML 到 sing-box JSON 的转换。