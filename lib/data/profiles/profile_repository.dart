import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const defaultProfileContent = '''
proxies: []
proxy-groups: []
rules: []
''';

enum ProviderFileKind { proxy, rule }

class ProviderFile {
  const ProviderFile({
    required this.name,
    required this.kind,
    required this.url,
    required this.content,
    required this.updatedAt,
  });

  final String name;
  final ProviderFileKind kind;
  final String url;
  final String content;
  final DateTime updatedAt;

  Map<String, String> toJson() => {
        'name': name,
        'kind': kind.name,
        'url': url,
        'content': content,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ProviderFile.fromJson(Map<String, dynamic> json) => ProviderFile(
        name: json['name'] as String,
        kind: ProviderFileKind.values.byName(json['kind'] as String),
        url: json['url'] as String,
        content: json['content'] as String,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  ProviderFile copyWith({String? content, DateTime? updatedAt}) => ProviderFile(
        name: name,
        kind: kind,
        url: url,
        content: content ?? this.content,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class ProxyProfile {
  const ProxyProfile({
    required this.id,
    required this.name,
    required this.content,
    required this.updatedAt,
    this.subscriptionUrl,
    this.sourceContent,
    this.providerFiles = const [],
  });

  final String id;
  final String name;
  final String content;
  final DateTime updatedAt;
  final String? subscriptionUrl;
  final String? sourceContent;
  final List<ProviderFile> providerFiles;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'content': content,
        'updatedAt': updatedAt.toIso8601String(),
        if (subscriptionUrl != null) 'subscriptionUrl': subscriptionUrl!,
        if (sourceContent != null) 'sourceContent': sourceContent!,
        if (providerFiles.isNotEmpty)
          'providerFiles': providerFiles.map((file) => file.toJson()).toList(),
      };

  factory ProxyProfile.fromJson(Map<String, dynamic> json) {
    return ProxyProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      content: json['content'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      subscriptionUrl: json['subscriptionUrl'] as String?,
      sourceContent: json['sourceContent'] as String?,
      providerFiles: (json['providerFiles'] as List<dynamic>? ?? const [])
          .map((file) => ProviderFile.fromJson(
              (file as Map<Object?, Object?>).cast<String, dynamic>()))
          .toList(),
    );
  }

  ProxyProfile copyWith({
    String? content,
    DateTime? updatedAt,
    String? sourceContent,
    List<ProviderFile>? providerFiles,
  }) {
    return ProxyProfile(
      id: id,
      name: name,
      content: content ?? this.content,
      updatedAt: updatedAt ?? this.updatedAt,
      subscriptionUrl: subscriptionUrl,
      sourceContent: sourceContent ?? this.sourceContent,
      providerFiles: providerFiles ?? this.providerFiles,
    );
  }
}

class ProfileState {
  const ProfileState({required this.profiles, required this.activeProfileId});

  final List<ProxyProfile> profiles;
  final String activeProfileId;

  factory ProfileState.defaults() {
    final profile = ProxyProfile(
      id: 'default',
      name: '默认',
      content: defaultProfileContent,
      updatedAt: DateTime.now(),
    );
    return ProfileState(profiles: [profile], activeProfileId: profile.id);
  }

  ProxyProfile get activeProfile {
    return profiles.firstWhere(
      (profile) => profile.id == activeProfileId,
      orElse: () => profiles.first,
    );
  }

  ProfileState copyWith(
      {List<ProxyProfile>? profiles, String? activeProfileId}) {
    return ProfileState(
      profiles: profiles ?? this.profiles,
      activeProfileId: activeProfileId ?? this.activeProfileId,
    );
  }

  ProfileState removeProfile(String profileId) {
    if (profiles.length <= 1) {
      throw StateError('At least one profile must remain');
    }
    final remainingProfiles =
        profiles.where((profile) => profile.id != profileId).toList();
    if (remainingProfiles.length == profiles.length) return this;
    return ProfileState(
      profiles: remainingProfiles,
      activeProfileId: activeProfileId == profileId
          ? remainingProfiles.first.id
          : activeProfileId,
    );
  }

  Map<String, dynamic> toJson() => {
        'activeProfileId': activeProfileId,
        'profiles': profiles.map((profile) => profile.toJson()).toList(),
      };

  factory ProfileState.fromJson(Map<String, dynamic> json) {
    final profiles = (json['profiles'] as List)
        .cast<Map<Object?, Object?>>()
        .map(
            (profile) => ProxyProfile.fromJson(profile.cast<String, dynamic>()))
        .toList();
    if (profiles.isEmpty) throw const FormatException('No profiles found');
    final activeProfileId = json['activeProfileId'] as String?;
    return ProfileState(
      profiles: profiles,
      activeProfileId: profiles.any((profile) => profile.id == activeProfileId)
          ? activeProfileId!
          : profiles.first.id,
    );
  }
}

abstract interface class ProfileStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPreferencesProfileStorage implements ProfileStorage {
  SharedPreferencesProfileStorage({Future<SharedPreferences>? preferences})
      : _preferences = preferences ?? SharedPreferences.getInstance();

  static const _key = 'leopard_cat.profile_state';

  final Future<SharedPreferences> _preferences;

  @override
  Future<String?> read() async => (await _preferences).getString(_key);

  @override
  Future<void> write(String value) async {
    await (await _preferences).setString(_key, value);
  }
}

class ProfileRepository {
  ProfileRepository({ProfileStorage? storage})
      : _storage = storage ?? SharedPreferencesProfileStorage();

  final ProfileStorage _storage;

  Future<ProfileState> load() async {
    final rawState = await _storage.read();
    if (rawState == null) return ProfileState.defaults();
    try {
      return ProfileState.fromJson(
          jsonDecode(rawState) as Map<String, dynamic>);
    } on FormatException {
      return ProfileState.defaults();
    } on TypeError {
      return ProfileState.defaults();
    }
  }

  Future<void> save(ProfileState state) =>
      _storage.write(jsonEncode(state.toJson()));
}
