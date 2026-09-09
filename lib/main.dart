import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/network/android_core_controller.dart';
import 'core/network/core_controller.dart';
import 'data/clash/clash_to_singbox_transformer.dart';
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
  TrafficSnapshot _traffic = const TrafficSnapshot(uplinkBytes: 0, downlinkBytes: 0);
  int? _lastDelay;
  bool _isDelayTesting = false;
  String? _delayMessage;
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
    final outbound = (config['route'] as Map<String, dynamic>)['final'] as String?;
    return outbound == 'DIRECT' || outbound == 'REJECT' ? null : outbound;
  }

  @override
  void initState() {
    super.initState();
    _loadProfiles();
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
      final resolvedStatus = status == CoreStatus.starting
          ? await _awaitCoreStart()
          : status;
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
    _trafficTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshTraffic());
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
    setState(() => _profileState = nextState);
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
    final nameController = TextEditingController();
    final contentController = TextEditingController(text: defaultProfileContent);
    final result = await showDialog<_ProfileDraft>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加本地配置'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: '名称')),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                decoration: const InputDecoration(labelText: 'Clash YAML'),
                minLines: 6,
                maxLines: 10,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _ProfileDraft(nameController.text.trim(), contentController.text),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    nameController.dispose();
    contentController.dispose();
    if (result == null || result.name.isEmpty || result.content.trim().isEmpty) return;

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
      setState(() => _profileState = nextState);
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clash YAML 格式无效')));
    }
  }

  Future<void> _importSubscription() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final result = await showDialog<_SubscriptionDraft>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入订阅'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: '名称')),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: '订阅地址'),
              keyboardType: TextInputType.url,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _SubscriptionDraft(nameController.text.trim(), urlController.text.trim()),
            ),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    nameController.dispose();
    urlController.dispose();
    if (result == null || result.name.isEmpty || result.url.isEmpty) return;

    final url = Uri.tryParse(result.url);
    if (url == null) {
      _showProfileMessage('订阅地址无效');
      return;
    }
    try {
      final profile = await _subscriptionService.importSubscription(name: result.name, url: url);
      final nextState = _profileState.copyWith(
        profiles: [..._profileState.profiles, profile],
        activeProfileId: profile.id,
      );
      await _profileRepository.save(nextState);
      if (!mounted) return;
      setState(() => _profileState = nextState);
    } on SubscriptionException catch (error) {
      _showProfileMessage(error.message);
    }
  }

  Future<void> _refreshSubscription(String profileId) async {
    final profile = _profileState.profiles.firstWhere((item) => item.id == profileId);
    try {
      final refreshed = await _subscriptionService.refresh(profile);
      final nextState = _profileState.copyWith(
        profiles: [
          for (final item in _profileState.profiles) item.id == profileId ? refreshed : item,
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

  void _showProfileMessage(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
        delayTestOutbound: _delayTestOutbound,
        delay: _lastDelay,
        isDelayTesting: _isDelayTesting,
        delayMessage: _delayMessage,
        onToggleConnection: _toggleCore,
        onDelayTest: _runDelayTest,
      ),
      ProfilesPage(
        profiles: _profileState.profiles,
        activeProfileId: _profileState.activeProfileId,
        isLoading: !_profilesLoaded,
        onSelect: _selectProfile,
        onAdd: _addProfile,
        onImportSubscription: _importSubscription,
        onRefreshSubscription: _refreshSubscription,
      ),
      const SettingsPage(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                if (isWide) _NavigationRail(
                  selectedIndex: _selectedIndex,
                  onSelected: (index) => setState(() => _selectedIndex = index),
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
  const _NavigationRail({required this.selectedIndex, required this.onSelected});

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
                onTap: delayTestOutbound == null || !isConnected || isDelayTesting
                    ? null
                    : onDelayTest,
              ),
              const _StatusRow(
                icon: Icons.shield_outlined,
                title: '内核服务',
                value: 'Meta · v1.19.12',
                accent: Color(0xFF63C7D8),
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
    final color = isConnected ? const Color(0xFFB7F36B) : const Color(0xFF777D89);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C21),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isConnected ? color.withValues(alpha: .35) : const Color(0xFF292C33)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(color: color.withValues(alpha: .12), shape: BoxShape.circle),
            child: Icon(isConnected ? Icons.bolt : Icons.power_settings_new, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isConnected ? '服务运行中' : '服务未连接', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
      decoration: BoxDecoration(color: const Color(0xFF191B20), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('流量概览', style: TextStyle(color: Color(0xFF9B9FA9), fontSize: 13)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _Metric(label: '下载', value: _formatBytes(traffic.downlinkBytes), icon: Icons.arrow_downward, color: const Color(0xFF63C7D8))),
              const SizedBox(width: 20),
              Expanded(child: _Metric(label: '上传', value: _formatBytes(traffic.uplinkBytes), icon: Icons.arrow_upward, color: const Color(0xFFF0A35B))),
              const SizedBox(width: 20),
              Expanded(child: _Metric(label: '总计', value: _formatBytes(traffic.uplinkBytes + traffic.downlinkBytes), icon: Icons.data_usage, color: const Color(0xFF9F84F7))),
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
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 17),
      const SizedBox(height: 8),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(color: Color(0xFF777C86), fontSize: 12)),
    ]);
  }
}

class ProfilesPage extends StatelessWidget {
  const ProfilesPage({
    required this.profiles,
    required this.activeProfileId,
    required this.isLoading,
    required this.onSelect,
    required this.onAdd,
    required this.onImportSubscription,
    required this.onRefreshSubscription,
    super.key,
  });

  final List<ProxyProfile> profiles;
  final String activeProfileId;
  final bool isLoading;
  final ValueChanged<String> onSelect;
  final Future<void> Function() onAdd;
  final Future<void> Function() onImportSubscription;
  final ValueChanged<String> onRefreshSubscription;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(24, 28, 24, 48), children: [
      const _PageHeader(eyebrow: 'CONFIGURATION', title: '配置', subtitle: '管理订阅与本地配置。'),
      const SizedBox(height: 28),
      Row(children: [
        Expanded(child: FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('添加配置'))),
        const SizedBox(width: 12),
        Expanded(child: OutlinedButton.icon(onPressed: onImportSubscription, icon: const Icon(Icons.link), label: const Text('导入订阅'))),
      ]),
      const SizedBox(height: 18),
      if (isLoading)
        const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
      else
        ...profiles.map((profile) => _ProfileTile(
              name: profile.name,
              detail: '本地配置 · ${profile.updatedAt.year}-${profile.updatedAt.month.toString().padLeft(2, '0')}-${profile.updatedAt.day.toString().padLeft(2, '0')}',
              active: profile.id == activeProfileId,
              onTap: () => onSelect(profile.id),
              onRefresh: profile.subscriptionUrl == null ? null : () => onRefreshSubscription(profile.id),
            )),
    ]);
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.name, required this.detail, required this.active, required this.onTap, this.onRefresh});
  final String name;
  final String detail;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: const Color(0xFF191B20), borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Icon(active ? Icons.radio_button_checked : Icons.radio_button_off, color: active ? const Color(0xFFB7F36B) : const Color(0xFF626772)),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(detail),
        trailing: onRefresh == null
          ? const Icon(Icons.chevron_right)
          : IconButton(tooltip: '更新订阅', onPressed: onRefresh, icon: const Icon(Icons.refresh)),
      ),
    );
  }
}

class _ProfileDraft {
  const _ProfileDraft(this.name, this.content);

  final String name;
  final String content;
}

class _SubscriptionDraft {
  const _SubscriptionDraft(this.name, this.url);

  final String name;
  final String url;
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(24, 28, 24, 48), children: const [
      _PageHeader(eyebrow: 'PREFERENCES', title: '设置', subtitle: '调整 LeopardCat 的行为。'),
      SizedBox(height: 24),
      _SettingsGroup(title: '运行偏好', children: [
        _SettingItem(icon: Icons.language, title: '语言', value: '简体中文'),
        _SettingItem(icon: Icons.dark_mode_outlined, title: '主题', value: '深色'),
        _SettingItem(icon: Icons.vibration, title: '启动时连接', value: '关闭'),
      ]),
      SizedBox(height: 18),
      _SettingsGroup(title: '关于', children: [
        _SettingItem(icon: Icons.info_outline, title: '版本', value: '0.1.0'),
        _SettingItem(icon: Icons.article_outlined, title: '开源许可', value: '查看'),
      ]),
    ]);
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Color(0xFF858A94), fontSize: 13)),
        const SizedBox(height: 9),
        Container(decoration: BoxDecoration(color: const Color(0xFF191B20), borderRadius: BorderRadius.circular(16)), child: Column(children: children)),
      ]);
}

class _SettingItem extends StatelessWidget {
  const _SettingItem({required this.icon, required this.title, required this.value});
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: const Color(0xFFB3B7C1)),
        title: Text(title),
        trailing: Text(value, style: const TextStyle(color: Color(0xFF8D929C))),
      );
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.eyebrow, required this.title, required this.subtitle});
  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(eyebrow, style: const TextStyle(color: Color(0xFFB7F36B), letterSpacing: 1.4, fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1.1)),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(color: Color(0xFF858A94), fontSize: 15)),
      ]);
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.action});
  final String title;
  final String action;

  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        TextButton(onPressed: () {}, child: Text(action)),
      ]);
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.icon, required this.title, required this.value, required this.accent, this.onTap});
  final IconData icon;
  final String title;
  final String value;
  final Color accent;
  final Future<void> Function()? onTap;

  @override
    Widget build(BuildContext context) => ListTile(
      onTap: onTap == null ? null : () => onTap!(),
        contentPadding: EdgeInsets.zero,
        leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: accent, size: 20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(value),
        trailing: onTap == null
            ? const Icon(Icons.chevron_right, color: Color(0xFF656A74))
            : const Icon(Icons.play_arrow, color: Color(0xFFF0A35B)),
      );
}