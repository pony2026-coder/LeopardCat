import 'package:flutter_test/flutter_test.dart';
import 'package:leopard_cat/data/profiles/profile_repository.dart';

void main() {
  test('persists profiles and the active profile selection', () async {
    final storage = _MemoryProfileStorage();
    final repository = ProfileRepository(
      storage: storage,
      providerContentStorage: _MemoryProviderContentStorage(),
    );
    final profile = ProxyProfile(
      id: 'work',
      name: '工作网络',
      content: 'proxies: []\nproxy-groups: []\nrules: []',
      updatedAt: DateTime.utc(2026, 9, 9),
    );
    final state =
        ProfileState(profiles: [profile], activeProfileId: profile.id);

    await repository.save(state);
    final loaded = await repository.load();

    expect(loaded.activeProfile.name, '工作网络');
    expect(loaded.activeProfile.content, profile.content);
  });

  test('persists subscription source and provider files', () async {
    final storage = _MemoryProfileStorage();
    final repository = ProfileRepository(
      storage: storage,
      providerContentStorage: _MemoryProviderContentStorage(),
    );
    final updatedAt = DateTime.utc(2026, 9, 10);
    final profile = ProxyProfile(
      id: 'providers',
      name: 'Provider 订阅',
      content: '{"proxies":[]}',
      sourceContent: 'proxy-providers: {}',
      providerFiles: [
        ProviderFile(
          name: 'airport',
          kind: ProviderFileKind.proxy,
          url: 'https://example.com/airport.yaml',
          content: 'proxies: []',
          updatedAt: updatedAt,
        ),
        ProviderFile(
          name: 'custom',
          kind: ProviderFileKind.rule,
          url: 'https://example.com/custom.yaml',
          content: 'payload: []',
          behavior: 'domain',
          updatedAt: updatedAt,
        ),
      ],
      updatedAt: updatedAt,
      subscriptionUrl: 'https://example.com/sub.yaml',
    );

    await repository.save(
      ProfileState(profiles: [profile], activeProfileId: profile.id),
    );
    final loaded = await repository.load();

    expect(loaded.activeProfile.sourceContent, profile.sourceContent);
    expect(loaded.activeProfile.providerFiles.first.name, 'airport');
    expect(
      loaded.activeProfile.providerFiles.first.kind,
      ProviderFileKind.proxy,
    );
    expect(loaded.activeProfile.providerFiles.first.content, 'proxies: []');
    expect(loaded.activeProfile.providerFiles.last.behavior, 'domain');
  });

  test('uses the default profile when saved data is invalid', () async {
    final repository =
        ProfileRepository(storage: _MemoryProfileStorage('not-json'));

    final state = await repository.load();

    expect(state.profiles, hasLength(1));
    expect(state.activeProfile.id, 'default');
  });

  test('uses the default profile when saved JSON has an invalid structure',
      () async {
    final repository =
        ProfileRepository(storage: _MemoryProfileStorage('{"profiles":{}}'));

    final state = await repository.load();

    expect(state.profiles, hasLength(1));
    expect(state.activeProfile.id, 'default');
  });

  test('removing the active profile selects a remaining profile', () {
    final first = ProxyProfile(
      id: 'first',
      name: '第一个',
      content: defaultProfileContent,
      updatedAt: DateTime.utc(2026),
    );
    final second = ProxyProfile(
      id: 'second',
      name: '第二个',
      content: defaultProfileContent,
      updatedAt: DateTime.utc(2026),
    );

    final state =
        ProfileState(profiles: [first, second], activeProfileId: second.id);
    final updated = state.removeProfile(second.id);

    expect(updated.profiles, [first]);
    expect(updated.activeProfileId, first.id);
  });
}

class _MemoryProfileStorage implements ProfileStorage {
  _MemoryProfileStorage([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class _MemoryProviderContentStorage implements ProviderContentStorage {
  final Map<String, List<ProviderFile>> _files = {};

  @override
  Future<List<ProviderFile>> read(
    String profileId,
    List<ProviderFile> files,
  ) async => _files[profileId] ?? files;

  @override
  Future<void> write(String profileId, List<ProviderFile> files) async {
    _files[profileId] = files;
  }
}
