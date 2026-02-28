/// 连接配置
class ConnectionConfig {
  const ConnectionConfig({
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.privateKeyPath,
    this.privateKeyPassphrase,
    this.usePty = false,
    this.id,
    this.name,
    this.lastUsedAt,
  });

  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKeyPath;
  final String? privateKeyPassphrase;
  final bool usePty;
  final String? id;
  final String? name;
  final DateTime? lastUsedAt;

  String get displayTitle => (name != null && name!.trim().isNotEmpty)
      ? name!.trim()
      : '$username@$host';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'privateKeyPath': privateKeyPath,
      'privateKeyPassphrase': privateKeyPassphrase,
      'usePty': usePty,
      'lastUsedAt': lastUsedAt?.toIso8601String(),
    };
  }

  static ConnectionConfig fromJson(
    Map<String, dynamic> json, {
    String? password,
    String? privateKeyPassphrase,
  }) {
    final lastUsedAt = json['lastUsedAt'] as String?;
    return ConnectionConfig(
      id: json['id'] as String?,
      name: json['name'] as String?,
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: json['username'] as String? ?? '',
      password: password,
      privateKeyPath: json['privateKeyPath'] as String?,
      privateKeyPassphrase:
          privateKeyPassphrase ?? json['privateKeyPassphrase'] as String?,
      usePty: json['usePty'] as bool? ?? false,
      lastUsedAt: lastUsedAt != null ? DateTime.tryParse(lastUsedAt) : null,
    );
  }

  ConnectionConfig copyWith({
    String? host,
    int? port,
    String? username,
    String? password,
    String? privateKeyPath,
    String? privateKeyPassphrase,
    bool? usePty,
    String? id,
    String? name,
    DateTime? lastUsedAt,
  }) {
    return ConnectionConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      privateKeyPath: privateKeyPath ?? this.privateKeyPath,
      privateKeyPassphrase: privateKeyPassphrase ?? this.privateKeyPassphrase,
      usePty: usePty ?? this.usePty,
      id: id ?? this.id,
      name: name ?? this.name,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }
}
