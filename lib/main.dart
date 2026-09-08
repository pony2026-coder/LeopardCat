import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/network/android_core_controller.dart';
import 'core/network/core_controller.dart';

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
  final CoreController _coreController = AndroidCoreController();

  Future<void> _toggleCore() async {
    try {
      final status = _isConnected
          ? await _coreController.stop()
          : await _coreController.start();
      if (!mounted) return;
      setState(() {
        _isConnected = status == CoreStatus.running || status == CoreStatus.starting;
      });
    } on PlatformException {
      if (mounted) setState(() => _isConnected = false);
    } on MissingPluginException {
      if (mounted) setState(() => _isConnected = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(
        isConnected: _isConnected,
        onToggleConnection: _toggleCore,
      ),
      const ProfilesPage(),
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
  const HomePage({required this.isConnected, required this.onToggleConnection, super.key});

  final bool isConnected;
  final Future<void> Function() onToggleConnection;

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
                onToggle: onToggleConnection,
              ),
              const SizedBox(height: 18),
              const _TrafficOverview(),
              const SizedBox(height: 18),
              const _SectionTitle(title: '当前状态', action: '查看日志'),
              const SizedBox(height: 10),
              const _StatusRow(
                icon: Icons.dns_outlined,
                title: '活动配置',
                value: '默认 · Rule 模式',
                accent: Color(0xFF9F84F7),
              ),
              const _StatusRow(
                icon: Icons.speed_outlined,
                title: '延迟测试',
                value: '尚未测试',
                accent: Color(0xFFF0A35B),
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
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.isConnected, required this.onToggle});

  final bool isConnected;
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
                Text(isConnected ? '流量正在通过 LeopardCat' : '点击右侧按钮启动核心服务', style: const TextStyle(color: Color(0xFF898E98))),
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
  const _TrafficOverview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(color: const Color(0xFF191B20), borderRadius: BorderRadius.circular(20)),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('流量概览', style: TextStyle(color: Color(0xFF9B9FA9), fontSize: 13)),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _Metric(label: '下载', value: '0 B/s', icon: Icons.arrow_downward, color: Color(0xFF63C7D8))),
              SizedBox(width: 20),
              Expanded(child: _Metric(label: '上传', value: '0 B/s', icon: Icons.arrow_upward, color: Color(0xFFF0A35B))),
              SizedBox(width: 20),
              Expanded(child: _Metric(label: '总计', value: '0 B', icon: Icons.data_usage, color: Color(0xFF9F84F7))),
            ],
          ),
        ],
      ),
    );
  }
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
  const ProfilesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(24, 28, 24, 48), children: [
      const _PageHeader(eyebrow: 'CONFIGURATION', title: '配置', subtitle: '管理订阅与本地配置。'),
      const SizedBox(height: 28),
      FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.add), label: const Text('添加配置')),
      const SizedBox(height: 18),
      const _ProfileTile(name: '默认', detail: '本地配置 · 12 条规则', active: true),
      const _ProfileTile(name: '工作网络', detail: '订阅配置 · 2 小时前更新', active: false),
    ]);
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.name, required this.detail, required this.active});
  final String name;
  final String detail;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: const Color(0xFF191B20), borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Icon(active ? Icons.radio_button_checked : Icons.radio_button_off, color: active ? const Color(0xFFB7F36B) : const Color(0xFF626772)),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(detail),
        trailing: const Icon(Icons.more_horiz),
      ),
    );
  }
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
  const _StatusRow({required this.icon, required this.title, required this.value, required this.accent});
  final IconData icon;
  final String title;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: accent, size: 20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(value),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF656A74)),
      );
}