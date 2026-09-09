import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/network/android_core_controller.dart';
import 'core/network/core_controller.dart';
import 'data/clash/clash_to_singbox_transformer.dart';
import 'data/clash/proxy_group.dart';
import 'data/profiles/profile_repository.dart';
import 'data/subscription/subscription_client.dart';
import 'data/subscription/subscription_service.dart';

void main() {
  runApp(const LeopardCatApp());
}

class LeopardCatApp extends StatelessWidget {
  const LeopardCatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LeopardCat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF101114),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB7F36B),
          brightness: Brightness.dark,
          surface: const Color(0xFF191B20),
        ),
        fontFamily: 'sans',
      ),
      home: const ShellPage(),
    );
  }
}

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _selectedIndex = 0;
  bool _isConnected = false;
  String? _coreError;
  TrafficSnapshot _traffic =
      const TrafficSnapshot(uplinkBytes: 0, downlinkBytes: 0);
  int? _lastDelay;
  bool _isDelayTesting = false;
  String? _delayMessage;
  String _coreVersion = '读取中...';
  final Map<String, String> _selectedOutbounds = {};
  final Map<String, int?> _outboundDelays = {};
  final Set<String> _testingOutbounds = {};
  Timer? _trafficTimer;
  final CoreController _coreController = AndroidCoreController();
  final ProfileRepository _profileRepository = ProfileRepository();
  final SubscriptionService _subscriptionService = SubscriptionService(
    client: HttpSubscriptionClient(),
    transformer: const ClashToSingboxTransformer(),
  );
  ProfileState _profileState = ProfileState.defaults();
  bool _profilesLoaded = false;

  String get _configJson => const ClashToSingboxTransformer()
      .transformYamlToJson(_profileState.activeProfile.content);

  String? get _delayTestOutbound {
    final config = const ClashToSingboxTransformer()
        .transformYaml(_profileState.activeProfile.content);
    final outbound =
        (config['route'] as Map<String, dynamic>)['final'] as String?;
    return outbound == 'DIRECT' || outbound == 'REJECT' ? null : outbound;
  }

  List<ClashProxyGroup> get _proxyGroups =>
      parseClashProxyGroups(_profileState.activeProfile.content);

  List<StaticResource> get _staticResources {
    final resources = <String, StaticResource>{};
    const transformer = ClashToSingboxTransformer();
    for (final profile in _profileState.profiles) {
      for (final resource in transformer.staticResources(profile.content)) {
        resources.putIfAbsent(resource.tag, () => resource);
      }
    }
    return resources.values.toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _loadCoreVersion();
  }

  Future<void> _loadCoreVersion() async {
    try {
      final version = await _coreController.coreVersion();
      if (mounted) setState(() => _coreVersion = version);
    } on PlatformException {
      if (mounted) setState(() => _coreVersion = '不可用');
    } on MissingPluginException {
      if (mounted) setState(() => _coreVersion = '仅支持 Android');
    }
  }

  Future<void> _loadProfiles() async {
    final profileState = await _profileRepository.load();
    if (!mounted) return;
    setState(() {
      _profileState = profileState;
      _profilesLoaded = true;
    });
  }

  Future<void> _toggleCore() async {
    try {
      final status = _isConnected
          ? await _coreController.stop()
          : await _coreController.start(configJson: _configJson);
      final resolvedStatus =
          status == CoreStatus.starting ? await _awaitCoreStart() : status;
      if (!mounted) return;
      setState(() {
        _isConnected = resolvedStatus == CoreStatus.running;
        _coreError = _coreController.lastError;
        if (!_isConnected) {
          _traffic = const TrafficSnapshot(uplinkBytes: 0, downlinkBytes: 0);
        }
      });
      _syncTrafficPolling();
    } on PlatformException {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _coreError = '无法连接 Android 核心服务';
        });
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _coreError = '当前平台不支持 Android 核心服务';
        });
      }
    }
  }

  Future<CoreStatus> _awaitCoreStart() async {
    for (var attempt = 0; attempt < 10; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final status = await _coreController.status();
      if (status != CoreStatus.stopped && status != CoreStatus.starting) {
        return status;
      }
    }
    return _coreController.status();
  }

  void _syncTrafficPolling() {
    _trafficTimer?.cancel();
    if (!_isConnected) return;
    _refreshTraffic();
    _trafficTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _refreshTraffic());
  }

  Future<void> _refreshTraffic() async {
    try {
      final traffic = await _coreController.queryTraffic();
      if (mounted && _isConnected) setState(() => _traffic = traffic);
    } on PlatformException {
      // The connection state is handled independently by the core status bridge.
    } on MissingPluginException {
      // The connection state is handled independently by the core status bridge.
    }
  }

  Future<void> _selectProfile(String profileId) async {
    final nextState = _profileState.copyWith(activeProfileId: profileId);
    await _profileRepository.save(nextState);
    if (!mounted) return;
    setState(() {
      _profileState = nextState;
      _selectedOutbounds.clear();
      _outboundDelays.clear();
    });
    _lastDelay = null;
    _delayMessage = null;
    if (!_isConnected) return;

    try {
      final status = await _coreController.reload(_configJson);
      if (!mounted) return;
      setState(() {
        _isConnected = status == CoreStatus.running;
        _coreError = _coreController.lastError;
      });
      _syncTrafficPolling();
    } on PlatformException {
      if (mounted) setState(() => _coreError = '无法重载当前配置');
    }
  }

  Future<void> _addProfile() async {
    final result = await showDialog<_ProfileDraft>(
      context: context,
      builder: (context) => const _ProfileFormDialog(),
    );
    if (result == null ||
        result.name.isEmpty ||
        result.content.trim().isEmpty) {
      return;
    }

    try {
      const ClashToSingboxTransformer().transformYamlToJson(result.content);
      final profile = ProxyProfile(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: result.name,
        content: result.content,
        updatedAt: DateTime.now(),
      );
      final nextState = _profileState.copyWith(
        profiles: [..._profileState.profiles, profile],
        activeProfileId: profile.id,
      );
      await _profileRepository.save(nextState);
      if (!mounted) return;
      setState(() {
        _profileState = nextState;
        _selectedOutbounds.clear();
        _outboundDelays.clear();
      });
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Clash YAML 格式无效')));
    }
  }

  Future<void> _importSubscription() async {
    final result = await showDialog<_SubscriptionDraft>(
      context: context,
      builder: (context) => const _SubscriptionFormDialog(),
    );
    if (result == null || result.name.isEmpty || result.url.isEmpty) return;

    final url = Uri.tryParse(result.url);
    if (url == null) {
      _showProfileMessage('订阅地址无效');
      return;
    }
    try {
      final profile = await _subscriptionService.importSubscription(
          name: result.name, url: url);
      final nextState = _profileState.copyWith(
        profiles: [..._profileState.profiles, profile],
        activeProfileId: profile.id,
      );
      await _profileRepository.save(nextState);
      if (!mounted) return;
      setState(() {
        _profileState = nextState;
        _selectedOutbounds.clear();
        _outboundDelays.clear();
      });
    } on SubscriptionException catch (error) {
      _showProfileMessage(error.message);
    }
  }

  Future<void> _refreshSubscription(String profileId) async {
    final profile =
        _profileState.profiles.firstWhere((item) => item.id == profileId);
    try {
      final refreshed = await _subscriptionService.refresh(profile);
      final nextState = _profileState.copyWith(
        profiles: [
          for (final item in _profileState.profiles)
            item.id == profileId ? refreshed : item,
        ],
      );
      await _profileRepository.save(nextState);
      if (!mounted) return;
      setState(() => _profileState = nextState);
      if (_isConnected && _profileState.activeProfileId == profileId) {
        await _selectProfile(profileId);
      }
    } on SubscriptionException catch (error) {
      _showProfileMessage(error.message);
    }
  }

  Future<ProviderFile?> _refreshProvider(ProviderFile providerFile) async {
    final profile = _profileState.activeProfile;
    try {
      final refreshed =
          await _subscriptionService.refreshProvider(profile, providerFile);
      final nextState = _profileState.copyWith(
        profiles: [
          for (final item in _profileState.profiles)
            item.id == profile.id ? refreshed : item,
        ],
      );
      await _profileRepository.save(nextState);
      if (!mounted) return null;
      setState(() {
        _profileState = nextState;
        _selectedOutbounds.clear();
        _outboundDelays.clear();
      });
      if (_isConnected) {
        final status = await _coreController.reload(_configJson);
        if (!mounted) return null;
        setState(() {
          _isConnected = status == CoreStatus.running;
          _coreError = _coreController.lastError;
        });
        _syncTrafficPolling();
      }
      _showProfileMessage('${providerFile.name} 已刷新');
      return refreshed.providerFiles.firstWhere(
        (file) =>
            file.name == providerFile.name && file.kind == providerFile.kind,
      );
    } on SubscriptionException catch (error) {
      _showProfileMessage(error.message);
    } on PlatformException {
      _showProfileMessage('provider 已更新，但核心重载失败');
    }
    return null;
  }

  Future<void> _showProviderFile(ProviderFile providerFile) {
    var displayedFile = providerFile;
    var isRefreshing = false;
    return showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(displayedFile.name),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayedFile.kind == ProviderFileKind.proxy
                    ? '代理 provider'
                    : '规则 provider'),
                const SizedBox(height: 4),
                SelectableText(displayedFile.url),
                const SizedBox(height: 16),
                const Text('文件内容'),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(displayedFile.content),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isRefreshing ? null : () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
            FilledButton.icon(
              onPressed: isRefreshing
                  ? null
                  : () async {
                      setDialogState(() => isRefreshing = true);
                      final refreshed = await _refreshProvider(displayedFile);
                      if (!context.mounted) return;
                      setDialogState(() {
                        isRefreshing = false;
                        if (refreshed != null) displayedFile = refreshed;
                      });
                    },
              icon: isRefreshing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(isRefreshing ? '刷新中' : '刷新'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProfileDetails(String profileId) {
    final profile =
        _profileState.profiles.firstWhere((item) => item.id == profileId);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(profile.name),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(profile.subscriptionUrl == null ? '本地配置' : '订阅地址'),
              if (profile.subscriptionUrl != null) ...[
                const SizedBox(height: 4),
                SelectableText(profile.subscriptionUrl!),
              ],
              const SizedBox(height: 16),
              const Text('Clash YAML'),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(profile.content),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _deleteProfile(String profileId) async {
    final profile =
        _profileState.profiles.firstWhere((item) => item.id == profileId);
    if (_profileState.profiles.length <= 1) {
      _showProfileMessage('至少保留一个配置');
      return;
    }
    final label = profile.subscriptionUrl == null ? '配置' : '订阅';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除$label'),
        content: Text('确定删除“${profile.name}”吗？此操作无法撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final wasActive = _profileState.activeProfileId == profileId;
    final nextState = _profileState.removeProfile(profileId);
    await _profileRepository.save(nextState);
    if (!mounted) return;
    setState(() {
      _profileState = nextState;
      if (wasActive) {
        _lastDelay = null;
        _delayMessage = null;
        _selectedOutbounds.clear();
        _outboundDelays.clear();
      }
    });
    if (!wasActive || !_isConnected) return;
    try {
      final status = await _coreController.reload(_configJson);
      if (!mounted) return;
      setState(() {
        _isConnected = status == CoreStatus.running;
        _coreError = _coreController.lastError;
      });
      _syncTrafficPolling();
    } on PlatformException {
      if (mounted) setState(() => _coreError = '无法重载当前配置');
    }
  }

  void _showProfileMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _runDelayTest() async {
    final outbound = _delayTestOutbound;
    if (outbound == null || !_isConnected || _isDelayTesting) return;
    setState(() {
      _isDelayTesting = true;
      _lastDelay = null;
      _delayMessage = null;
    });
    try {
      final delay = await _coreController.delayTest(outbound);
      if (!mounted) return;
      setState(() {
        _lastDelay = delay;
        _delayMessage = delay == null ? '测试失败' : null;
      });
    } on PlatformException {
      if (mounted) setState(() => _delayMessage = '测试失败');
    } on MissingPluginException {
      if (mounted) setState(() => _delayMessage = '当前平台不支持测速');
    } finally {
      if (mounted) setState(() => _isDelayTesting = false);
    }
  }

  Future<void> _runOutboundDelayTest(String outbound) async {
    if (!_isConnected || _testingOutbounds.contains(outbound)) return;
    setState(() => _testingOutbounds.add(outbound));
    try {
      final delay = await _coreController.delayTest(outbound);
      if (mounted) setState(() => _outboundDelays[outbound] = delay);
    } on PlatformException {
      _showProfileMessage('节点测速失败');
    } on MissingPluginException {
      _showProfileMessage('当前平台不支持测速');
    } finally {
      if (mounted) setState(() => _testingOutbounds.remove(outbound));
    }
  }

  Future<void> _selectOutbound(ClashProxyGroup group, String outbound) async {
    if (!_isConnected ||
        !group.isSelectable ||
        _testingOutbounds.contains(group.name)) {
      return;
    }
    setState(() => _testingOutbounds.add(group.name));
    try {
      final selected =
          await _coreController.selectOutbound(group.name, outbound);
      if (!mounted) return;
      if (selected) {
        setState(() => _selectedOutbounds[group.name] = outbound);
      } else {
        _showProfileMessage('未能切换到 $outbound');
      }
    } on PlatformException {
      _showProfileMessage('节点切换失败');
    } on MissingPluginException {
      _showProfileMessage('当前平台不支持节点切换');
    } finally {
      if (mounted) setState(() => _testingOutbounds.remove(group.name));
    }
  }

  @override
  void dispose() {
    _trafficTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(
        isConnected: _isConnected,
        errorMessage: _coreError,
        traffic: _traffic,
        activeProfileName: _profileState.activeProfile.name,
        coreVersion: _coreVersion,
        delayTestOutbound: _delayTestOutbound,
        delay: _lastDelay,
        isDelayTesting: _isDelayTesting,
        delayMessage: _delayMessage,
        onToggleConnection: _toggleCore,
        onDelayTest: _runDelayTest,
      ),
      ProxyPage(
        groups: _proxyGroups,
        providerFiles: _profileState.activeProfile.providerFiles,
        isConnected: _isConnected,
        selectedOutbounds: _selectedOutbounds,
        outboundDelays: _outboundDelays,
        testingOutbounds: _testingOutbounds,
        onDelayTest: _runOutboundDelayTest,
        onSelectOutbound: _selectOutbound,
        onViewProvider: _showProviderFile,
      ),
      ProfilesPage(
        profiles: _profileState.profiles,
        activeProfileId: _profileState.activeProfileId,
        isLoading: !_profilesLoaded,
        onSelect: _selectProfile,
        onView: _showProfileDetails,
        onDelete: _deleteProfile,
        onAdd: _addProfile,
        onImportSubscription: _importSubscription,
        onRefreshSubscription: _refreshSubscription,
      ),
      SettingsPage(staticResources: _staticResources),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                if (isWide)
                  _NavigationRail(
                    selectedIndex: _selectedIndex,
                    onSelected: (index) =>
                        setState(() => _selectedIndex = index),
                  ),
                Expanded(child: pages[_selectedIndex]),
              ],
            ),
          ),
          bottomNavigationBar: isWide
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) =>
                      setState(() => _selectedIndex = index),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: '概览',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.route_outlined),
                      selectedIcon: Icon(Icons.route),
                      label: '代理',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.layers_outlined),
                      selectedIcon: Icon(Icons.layers),
                      label: '配置',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.tune_outlined),
                      selectedIcon: Icon(Icons.tune),
                      label: '设置',
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail(
      {required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      color: const Color(0xFF17181C),
      child: Column(
        children: [
          const SizedBox(height: 22),
          const _BrandMark(),
          const SizedBox(height: 42),
          Expanded(
            child: NavigationRail(
              backgroundColor: Colors.transparent,
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelected,
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: Text('概览'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.route_outlined),
                  selectedIcon: Icon(Icons.route),
                  label: Text('代理'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.layers_outlined),
                  selectedIcon: Icon(Icons.layers),
                  label: Text('配置'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune),
                  label: Text('设置'),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 24),
            child: Icon(Icons.help_outline, color: Color(0xFF7C808A)),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFB7F36B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.pets, color: Color(0xFF161817), size: 25),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    required this.isConnected,
    required this.errorMessage,
    required this.traffic,
    required this.activeProfileName,
    required this.coreVersion,
    required this.delayTestOutbound,
    required this.delay,
    required this.isDelayTesting,
    required this.delayMessage,
    required this.onToggleConnection,
    required this.onDelayTest,
    super.key,
  });

  final bool isConnected;
  final String? errorMessage;
  final TrafficSnapshot traffic;
  final String activeProfileName;
  final String coreVersion;
  final String? delayTestOutbound;
  final int? delay;
  final bool isDelayTesting;
  final String? delayMessage;
  final Future<void> Function() onToggleConnection;
  final Future<void> Function() onDelayTest;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const _PageHeader(
                eyebrow: 'LEOPARD CAT / CORE',
                title: '控制台',
                subtitle: '保持连接，专注当下。',
              ),
              const SizedBox(height: 28),
              _ConnectionCard(
                isConnected: isConnected,
                errorMessage: errorMessage,
                onToggle: onToggleConnection,
              ),
              const SizedBox(height: 18),
              _TrafficOverview(traffic: traffic),
              const SizedBox(height: 18),
              const _SectionTitle(title: '当前状态', action: '查看日志'),
              const SizedBox(height: 10),
              _StatusRow(
                icon: Icons.dns_outlined,
                title: '活动配置',
                value: '$activeProfileName · Rule 模式',
                accent: const Color(0xFF9F84F7),
              ),
              _StatusRow(
                icon: Icons.speed_outlined,
                title: '延迟测试',
                value: _delayValue(),
                accent: const Color(0xFFF0A35B),
                onTap:
                    delayTestOutbound == null || !isConnected || isDelayTesting
                        ? null
                        : onDelayTest,
              ),
              _StatusRow(
                icon: Icons.shield_outlined,
                title: '内核服务',
                value: 'sing-box · $coreVersion',
                accent: const Color(0xFF63C7D8),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  String _delayValue() {
    if (delayTestOutbound == null) return '当前配置没有可测速的节点';
    if (!isConnected) return '连接后可测试 $delayTestOutbound';
    if (isDelayTesting) return '正在测试 $delayTestOutbound';
    if (delay != null) return '$delay ms · $delayTestOutbound';
    return delayMessage ?? '测试 $delayTestOutbound';
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.isConnected,
    required this.errorMessage,
    required this.onToggle,
  });

  final bool isConnected;
  final String? errorMessage;
  final Future<void> Function() onToggle;

  @override
  Widget build(BuildContext context) {
    final color =
        isConnected ? const Color(0xFFB7F36B) : const Color(0xFF777D89);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C21),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isConnected
                ? color.withValues(alpha: .35)
                : const Color(0xFF292C33)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
                color: color.withValues(alpha: .12), shape: BoxShape.circle),
            child: Icon(isConnected ? Icons.bolt : Icons.power_settings_new,
                color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isConnected ? '服务运行中' : '服务未连接',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                Text(
                  isConnected
                      ? '流量正在通过 LeopardCat'
                      : errorMessage ?? '点击右侧按钮启动核心服务',
                  style: const TextStyle(color: Color(0xFF898E98)),
                ),
              ],
            ),
          ),
          Switch(value: isConnected, onChanged: (_) => onToggle()),
        ],
      ),
    );
  }
}

class _TrafficOverview extends StatelessWidget {
  const _TrafficOverview({required this.traffic});

  final TrafficSnapshot traffic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
          color: const Color(0xFF191B20),
          borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('流量概览',
              style: TextStyle(color: Color(0xFF9B9FA9), fontSize: 13)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _Metric(
                      label: '下载',
                      value: _formatBytes(traffic.downlinkBytes),
                      icon: Icons.arrow_downward,
                      color: const Color(0xFF63C7D8))),
              const SizedBox(width: 20),
              Expanded(
                  child: _Metric(
                      label: '上传',
                      value: _formatBytes(traffic.uplinkBytes),
                      icon: Icons.arrow_upward,
                      color: const Color(0xFFF0A35B))),
              const SizedBox(width: 20),
              Expanded(
                  child: _Metric(
                      label: '总计',
                      value: _formatBytes(
                          traffic.uplinkBytes + traffic.downlinkBytes),
                      icon: Icons.data_usage,
                      color: const Color(0xFF9F84F7))),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

class _Metric extends StatelessWidget {
  const _Metric(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 17),
      const SizedBox(height: 8),
      Text(value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      const SizedBox(height: 3),
      Text(label,
          style: const TextStyle(color: Color(0xFF777C86), fontSize: 12)),
    ]);
  }
}

class ProxyPage extends StatelessWidget {
  const ProxyPage({
    required this.groups,
    required this.providerFiles,
    required this.isConnected,
    required this.selectedOutbounds,
    required this.outboundDelays,
    required this.testingOutbounds,
    required this.onDelayTest,
    required this.onSelectOutbound,
    required this.onViewProvider,
    super.key,
  });

  final List<ClashProxyGroup> groups;
  final List<ProviderFile> providerFiles;
  final bool isConnected;
  final Map<String, String> selectedOutbounds;
  final Map<String, int?> outboundDelays;
  final Set<String> testingOutbounds;
  final Future<void> Function(String outbound) onDelayTest;
  final Future<void> Function(ClashProxyGroup group, String outbound)
      onSelectOutbound;
  final Future<void> Function(ProviderFile providerFile) onViewProvider;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
      children: [
        _PageHeader(
          eyebrow: 'PROXY GROUPS',
          title: '代理',
          subtitle: '测速节点并为策略组选择出站。',
          action: providerFiles.isEmpty
              ? null
              : PopupMenuButton<ProviderFile>(
                  tooltip: '查看 provider 文件',
                  icon: const Icon(Icons.folder_open_outlined),
                  onSelected: onViewProvider,
                  itemBuilder: (context) => [
                    for (final file in providerFiles)
                      PopupMenuItem(
                        value: file,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(file.kind == ProviderFileKind.proxy
                              ? Icons.dns_outlined
                              : Icons.rule_folder_outlined),
                          title: Text(file.name),
                          subtitle: Text(file.kind == ProviderFileKind.proxy
                              ? '代理 provider'
                              : '规则 provider'),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 20),
        if (!isConnected) const _ProxyConnectionHint(),
        if (!isConnected) const SizedBox(height: 18),
        if (groups.isEmpty)
          const _ProxyEmptyState()
        else
          ...groups.map(
            (group) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _ProxyGroupCard(
                group: group,
                isConnected: isConnected,
                selectedOutbound:
                    selectedOutbounds[group.name] ?? group.selectedProxy,
                outboundDelays: outboundDelays,
                testingOutbounds: testingOutbounds,
                onDelayTest: onDelayTest,
                onSelectOutbound: onSelectOutbound,
              ),
            ),
          ),
      ],
    );
  }
}

class _ProxyConnectionHint extends StatelessWidget {
  const _ProxyConnectionHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF22242A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF343741)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Color(0xFFF0A35B)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '启动服务后可测速并切换节点。',
              style: TextStyle(color: Color(0xFFB7BBC5)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProxyEmptyState extends StatelessWidget {
  const _ProxyEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C21),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF292C33)),
      ),
      child: const Column(
        children: [
          Icon(Icons.route_outlined, size: 30, color: Color(0xFF777C86)),
          SizedBox(height: 12),
          Text('当前配置没有可用的策略组'),
          SizedBox(height: 4),
          Text('请在配置中导入包含 proxy-groups 的 Clash YAML。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF898E98))),
        ],
      ),
    );
  }
}

class _ProxyGroupCard extends StatelessWidget {
  const _ProxyGroupCard({
    required this.group,
    required this.isConnected,
    required this.selectedOutbound,
    required this.outboundDelays,
    required this.testingOutbounds,
    required this.onDelayTest,
    required this.onSelectOutbound,
  });

  final ClashProxyGroup group;
  final bool isConnected;
  final String selectedOutbound;
  final Map<String, int?> outboundDelays;
  final Set<String> testingOutbounds;
  final Future<void> Function(String outbound) onDelayTest;
  final Future<void> Function(ClashProxyGroup group, String outbound)
      onSelectOutbound;

  @override
  Widget build(BuildContext context) {
    final isGroupSwitching = testingOutbounds.contains(group.name);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C21),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF292C33)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined,
                    color: Color(0xFF63C7D8)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(
                        group.isSelectable
                            ? '手动选择 · ${group.type}'
                            : '自动选择 · ${group.type}',
                        style: const TextStyle(
                            color: Color(0xFF898E98), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (isGroupSwitching)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF292C33)),
          ...group.proxies.map((outbound) {
            final isSelected = outbound == selectedOutbound;
            final isTesting = testingOutbounds.contains(outbound);
            final delay = outboundDelays[outbound];
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 16, right: 6),
              enabled: isConnected && !isGroupSwitching,
              leading: Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected
                    ? const Color(0xFFB7F36B)
                    : const Color(0xFF777C86),
              ),
              title:
                  Text(outbound, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: isTesting
                  ? const Text('正在测速')
                  : Text(delay == null ? '未测速' : '$delay ms'),
              onTap: !group.isSelectable || !isConnected || isGroupSwitching
                  ? null
                  : () => onSelectOutbound(group, outbound),
              trailing: IconButton(
                tooltip: '测速',
                onPressed: !isConnected || isTesting || isGroupSwitching
                    ? null
                    : () => onDelayTest(outbound),
                icon: isTesting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.speed_outlined),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class ProfilesPage extends StatelessWidget {
  const ProfilesPage({
    required this.profiles,
    required this.activeProfileId,
    required this.isLoading,
    required this.onSelect,
    required this.onView,
    required this.onDelete,
    required this.onAdd,
    required this.onImportSubscription,
    required this.onRefreshSubscription,
    super.key,
  });

  final List<ProxyProfile> profiles;
  final String activeProfileId;
  final bool isLoading;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onView;
  final ValueChanged<String> onDelete;
  final Future<void> Function() onAdd;
  final Future<void> Function() onImportSubscription;
  final ValueChanged<String> onRefreshSubscription;

  @override
  Widget build(BuildContext context) {
    return ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
        children: [
          const _PageHeader(
              eyebrow: 'CONFIGURATION', title: '配置', subtitle: '管理订阅与本地配置。'),
          const SizedBox(height: 28),
          Row(children: [
            Expanded(
                child: FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                    label: const Text('添加配置'))),
            const SizedBox(width: 12),
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: onImportSubscription,
                    icon: const Icon(Icons.link),
                    label: const Text('导入订阅'))),
          ]),
          const SizedBox(height: 18),
          if (isLoading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator()))
          else
            ...profiles.map((profile) => _ProfileTile(
                  name: profile.name,
                  detail:
                      '本地配置 · ${profile.updatedAt.year}-${profile.updatedAt.month.toString().padLeft(2, '0')}-${profile.updatedAt.day.toString().padLeft(2, '0')}',
                  active: profile.id == activeProfileId,
                  onTap: () => onSelect(profile.id),
                  onView: () => onView(profile.id),
                  onDelete:
                      profiles.length > 1 ? () => onDelete(profile.id) : null,
                  onRefresh: profile.subscriptionUrl == null
                      ? null
                      : () => onRefreshSubscription(profile.id),
                )),
        ]);
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.name,
    required this.detail,
    required this.active,
    required this.onTap,
    required this.onView,
    this.onDelete,
    this.onRefresh,
  });
  final String name;
  final String detail;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onView;
  final VoidCallback? onDelete;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF191B20),
          borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Icon(
            active ? Icons.radio_button_checked : Icons.radio_button_off,
            color: active ? const Color(0xFFB7F36B) : const Color(0xFF626772)),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(detail),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                tooltip: '查看配置',
                onPressed: onView,
                icon: const Icon(Icons.visibility_outlined)),
            if (onRefresh != null)
              IconButton(
                  tooltip: '更新订阅',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh)),
            if (onDelete != null)
              IconButton(
                  tooltip: '删除配置',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline)),
          ],
        ),
      ),
    );
  }
}

class _ProfileDraft {
  const _ProfileDraft(this.name, this.content);

  final String name;
  final String content;
}

class _ProfileFormDialog extends StatefulWidget {
  const _ProfileFormDialog();

  @override
  State<_ProfileFormDialog> createState() => _ProfileFormDialogState();
}

class _ProfileFormDialogState extends State<_ProfileFormDialog> {
  final _nameController = TextEditingController();
  final _contentController = TextEditingController(text: defaultProfileContent);

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加本地配置'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: '名称')),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              decoration: const InputDecoration(labelText: 'Clash YAML'),
              minLines: 6,
              maxLines: 10,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _ProfileDraft(_nameController.text.trim(), _contentController.text),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _SubscriptionDraft {
  const _SubscriptionDraft(this.name, this.url);

  final String name;
  final String url;
}

class _SubscriptionFormDialog extends StatefulWidget {
  const _SubscriptionFormDialog();

  @override
  State<_SubscriptionFormDialog> createState() =>
      _SubscriptionFormDialogState();
}

class _SubscriptionFormDialogState extends State<_SubscriptionFormDialog> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入订阅'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: '名称')),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(labelText: '订阅地址'),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _SubscriptionDraft(
                _nameController.text.trim(), _urlController.text.trim()),
          ),
          child: const Text('导入'),
        ),
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.staticResources = const []});

  final List<StaticResource> staticResources;

  void _showStaticResources(
      BuildContext context, StaticResourceKind kind) {
    final resources = staticResources
        .where((resource) => resource.kind == kind)
        .toList(growable: false);
    final title = switch (kind) {
      StaticResourceKind.geoip => 'GEOIP',
      StaticResourceKind.geosite => 'GEOSite',
    };
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: resources.isEmpty
              ? const Text('当前配置未引用此类静态资源。')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: resources.length,
                  separatorBuilder: (_, __) => const Divider(height: 24),
                  itemBuilder: (context, index) {
                    final resource = resources[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(resource.tag,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        SelectableText(
                          resource.url,
                          style: const TextStyle(
                              color: Color(0xFF8D929C), fontSize: 12),
                        ),
                      ],
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭')),
        ],
      ),
    );
  }

  int _resourceCount(StaticResourceKind kind) =>
      staticResources.where((resource) => resource.kind == kind).length;

  @override
  Widget build(BuildContext context) {
    return ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
        children: [
          const _PageHeader(
              eyebrow: 'PREFERENCES',
              title: '设置',
              subtitle: '调整 LeopardCat 的行为。'),
          const SizedBox(height: 24),
          const _SettingsGroup(title: '运行偏好', children: [
            _SettingItem(icon: Icons.language, title: '语言', value: '简体中文'),
            _SettingItem(
                icon: Icons.dark_mode_outlined, title: '主题', value: '深色'),
            _SettingItem(icon: Icons.vibration, title: '启动时连接', value: '关闭'),
          ]),
          const SizedBox(height: 18),
          _SettingsGroup(title: '静态资源', children: [
            _SettingItem(
              icon: Icons.public,
              title: 'GEOIP',
              value: '${_resourceCount(StaticResourceKind.geoip)} 项',
              onTap: () =>
                  _showStaticResources(context, StaticResourceKind.geoip),
            ),
            _SettingItem(
              icon: Icons.travel_explore,
              title: 'GEOSite',
              value: '${_resourceCount(StaticResourceKind.geosite)} 项',
              onTap: () =>
                  _showStaticResources(context, StaticResourceKind.geosite),
            ),
          ]),
          const SizedBox(height: 18),
          const _SettingsGroup(title: '关于', children: [
            _SettingItem(icon: Icons.info_outline, title: '版本', value: '0.1.0'),
            _SettingItem(
                icon: Icons.article_outlined, title: '开源许可', value: '查看'),
          ]),
        ]);
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(color: Color(0xFF858A94), fontSize: 13)),
        const SizedBox(height: 9),
        Material(
          color: const Color(0xFF191B20),
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children)),
      ]);
}

class _SettingItem extends StatelessWidget {
  const _SettingItem(
      {required this.icon,
      required this.title,
      required this.value,
      this.onTap});
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: Icon(icon, color: const Color(0xFFB3B7C1)),
        title: Text(title),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: const TextStyle(color: Color(0xFF8D929C))),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right,
                  color: Color(0xFF70757F), size: 20),
            ],
          ],
        ),
      );
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.action,
  });
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(eyebrow,
                    style: const TextStyle(
                        color: Color(0xFFB7F36B),
                        letterSpacing: 1.4,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1.1)),
                const SizedBox(height: 8),
                Text(subtitle,
                    style: const TextStyle(
                        color: Color(0xFF858A94), fontSize: 15)),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.action});
  final String title;
  final String action;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        TextButton(onPressed: () {}, child: Text(action)),
      ]);
}

class _StatusRow extends StatelessWidget {
  const _StatusRow(
      {required this.icon,
      required this.title,
      required this.value,
      required this.accent,
      this.onTap});
  final IconData icon;
  final String title;
  final String value;
  final Color accent;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap == null ? null : () => onTap!(),
        contentPadding: EdgeInsets.zero,
        leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: accent, size: 20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(value),
        trailing: onTap == null
            ? const Icon(Icons.chevron_right, color: Color(0xFF656A74))
            : const Icon(Icons.play_arrow, color: Color(0xFFF0A35B)),
      );
}
