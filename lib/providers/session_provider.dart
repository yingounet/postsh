import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../models/command_item.dart';
import '../models/session_state.dart';

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
  /// 为 true 时使用 PTY shell 通道（支持 tmux/screen），否则使用 exec 单次执行。
  final bool usePty;
  /// 保存连接的唯一 id，用于存储与最近使用排序。
  final String? id;
  /// 连接名/别名，用于列表展示。
  final String? name;
  /// 最后连接时间。
  final DateTime? lastUsedAt;

  /// 列表展示用标题：优先别名，否则 username@host。
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
      privateKeyPassphrase: privateKeyPassphrase ?? json['privateKeyPassphrase'] as String?,
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

/// 从 config 生成会话 key：有 id 用 id，否则用 quick- host:port:user。
String sessionKeyFromConfig(ConnectionConfig config) {
  if (config.id != null && config.id!.trim().isNotEmpty) {
    return config.id!.trim();
  }
  return 'quick-${config.host}:${config.port}:${config.username}';
}

/// 去掉 PTY 输出中的 ANSI 转义序列（颜色、光标等），避免显示为乱码。
String _stripAnsi(String s) {
  return s
      .replaceAll(RegExp(r'\x1b\[[\x20-\x3f]*[\x40-\x7e]'), '')
      .replaceAll(RegExp(r'\x9b[\x20-\x3f]*[\x40-\x7e]'), '')
      .replaceAll(RegExp(r'\x1b\][^\x07]*\x07'), '')
      .replaceAll(RegExp(r'\x1b\][^\x1b]*\x1b\\'), '')
      .replaceAll(RegExp(r'\x1b[=\(][\x20-\x7e]?'), '');
}

String _expandPath(String path) {
  if (path.startsWith('~')) {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    if (path == '~') return home;
    if (path.startsWith('~/')) return '$home${path.substring(1)}';
    return path;
  }
  return path;
}

/// 会话状态（连接、队列、输出）
class SessionState {
  SessionState({
    this.status = ConnectionStatus.disconnected,
    this.commands = const [],
    this.output = const [],
    this.error,
  });

  final ConnectionStatus status;
  final List<CommandItem> commands;
  final List<String> output;
  final String? error;

  SessionState copyWith({
    ConnectionStatus? status,
    List<CommandItem>? commands,
    List<String>? output,
    String? error,
  }) {
    return SessionState(
      status: status ?? this.status,
      commands: commands ?? this.commands,
      output: output ?? this.output,
      error: error,
    );
  }
}

/// 单条会话：配置、状态、Terminal、SSH 资源。
class SessionEntry {
  SessionEntry({
    required this.config,
    required this.state,
    this.terminal,
    this.client,
    this.socket,
    this.shellSession,
    this.outputSub,
    this.stderrSub,
    this.running = false,
    this.usePty = false,
    this.shouldReconnect = true,
    this.hasConnected = false,
    this.reconnectAttempts = 0,
    this.reconnectTimer,
  });

  final ConnectionConfig config;
  SessionState state;
  final Terminal? terminal;
  SSHClient? client;
  SSHSocket? socket;
  SSHSession? shellSession;
  StreamSubscription? outputSub;
  StreamSubscription? stderrSub;
  bool running;
  bool usePty;
  bool shouldReconnect;
  bool hasConnected;
  int reconnectAttempts;
  Timer? reconnectTimer;
}

/// 多会话状态：当前选中的 Tab id + 所有会话。
class SessionsState {
  const SessionsState({
    this.currentSessionId,
    this.sessions = const {},
  });

  final String? currentSessionId;
  final Map<String, SessionEntry> sessions;

  SessionsState copyWith({
    String? currentSessionId,
    Map<String, SessionEntry>? sessions,
  }) {
    return SessionsState(
      currentSessionId: currentSessionId ?? this.currentSessionId,
      sessions: sessions ?? this.sessions,
    );
  }

  SessionEntry? get currentEntry =>
      currentSessionId != null ? sessions[currentSessionId] : null;
}

class SessionsNotifier extends Notifier<SessionsState> {
  @override
  SessionsState build() => const SessionsState();

  /// 添加或切换到指定会话：已存在且已连接则只切换 current；已存在且连接中则只切换 current；已存在但断开则重连；不存在则新建并连接。
  Future<void> addOrSwitchToTab(String sessionKey, ConnectionConfig config) async {
    final sessions = Map<String, SessionEntry>.from(state.sessions);
    final existing = sessions[sessionKey];

    if (existing != null && existing.state.status == ConnectionStatus.connected) {
      state = state.copyWith(currentSessionId: sessionKey);
      return;
    }
    if (existing != null && existing.state.status == ConnectionStatus.connecting) {
      state = state.copyWith(currentSessionId: sessionKey);
      return;
    }

    state = state.copyWith(currentSessionId: sessionKey);

    if (existing != null) {
      existing.shouldReconnect = true;
      existing.reconnectAttempts = 0;
      existing.reconnectTimer?.cancel();
      existing.reconnectTimer = null;
      await _connectForKey(sessionKey, config, existing, sessions);
      return;
    }

    final terminal = config.usePty ? Terminal() : null;
    final entry = SessionEntry(
      config: config,
      state: SessionState(status: ConnectionStatus.connecting),
      terminal: terminal,
    );
    sessions[sessionKey] = entry;
    state = state.copyWith(sessions: sessions);
    await _connectForKey(sessionKey, config, entry, sessions);
  }

  void switchToTab(String sessionKey) {
    if (state.sessions.containsKey(sessionKey)) {
      state = state.copyWith(currentSessionId: sessionKey);
    }
  }

  void closeTab(String sessionKey) async {
    await disconnect(sessionKey);
    final sessions = Map<String, SessionEntry>.from(state.sessions);
    sessions.remove(sessionKey);
    String? newCurrent = state.currentSessionId;
    if (state.currentSessionId == sessionKey) {
      final keys = sessions.keys.toList();
      final idx = keys.indexOf(sessionKey);
      if (keys.isEmpty) {
        newCurrent = null;
      } else if (idx <= 0) {
        newCurrent = keys.first;
      } else {
        newCurrent = keys[idx - 1];
      }
    }
    state = state.copyWith(currentSessionId: newCurrent, sessions: sessions);
  }

  Future<void> _connectForKey(
    String sessionKey,
    ConnectionConfig config,
    SessionEntry entry,
    Map<String, SessionEntry> sessions,
    {bool isReconnect = false}
  ) async {
    await _cleanupConnection(entry);
    entry.state = entry.state.copyWith(
      status: isReconnect
          ? ConnectionStatus.reconnecting
          : ConnectionStatus.connecting,
      error: null,
    );
    state = state.copyWith(sessions: Map.from(sessions));

    try {
      entry.socket = await SSHSocket.connect(config.host, config.port);

      List<SSHKeyPair>? identities;
      if (config.privateKeyPath != null &&
          config.privateKeyPath!.trim().isNotEmpty) {
        final path = _expandPath(config.privateKeyPath!.trim());
        final pem = await File(path).readAsString();
        final passphrase = config.privateKeyPassphrase != null &&
                config.privateKeyPassphrase!.isNotEmpty
            ? config.privateKeyPassphrase
            : null;
        identities = SSHKeyPair.fromPem(pem, passphrase);
      }

      entry.client = SSHClient(
        entry.socket!,
        username: config.username,
        identities: identities,
        onPasswordRequest: identities == null &&
                config.password != null &&
                config.password!.isNotEmpty
            ? () => config.password!
            : null,
      );
      await entry.client!.authenticated;
      entry.client!.done.then((_) {
        _handleRemoteDisconnect(sessionKey, null);
      }).catchError((error) {
        _handleRemoteDisconnect(sessionKey, error.toString());
      });

      entry.usePty = config.usePty;
      if (entry.usePty) {
        const envUtf8 = {'LANG': 'en_US.UTF-8', 'LC_ALL': 'en_US.UTF-8'};
        final ptyConfig = entry.terminal != null
            ? SSHPtyConfig(
                width: entry.terminal!.viewWidth,
                height: entry.terminal!.viewHeight,
              )
            : const SSHPtyConfig();
        try {
          entry.shellSession = await entry.client!.shell(
            environment: envUtf8,
            pty: ptyConfig,
          );
        } on SSHChannelRequestError {
          try {
            entry.shellSession = await entry.client!.shell(pty: ptyConfig);
          } on SSHChannelRequestError {
            try {
              entry.shellSession = await entry.client!.shell(pty: null);
            } on SSHChannelRequestError {
              entry.shellSession = null;
              entry.usePty = false;
            }
          }
        }
        if (entry.shellSession != null && entry.terminal != null) {
          final term = entry.terminal!;
          term.onOutput = (data) {
            if (entry.shellSession != null && entry.running) {
              entry.shellSession!.write(utf8.encode(data));
            }
          };
          term.onResize = (width, height, pixelWidth, pixelHeight) {
            if (entry.shellSession != null && entry.running) {
              entry.shellSession!.resizeTerminal(
                width,
                height,
                pixelWidth,
                pixelHeight,
              );
            }
          };
          entry.outputSub = entry.shellSession!.stdout.listen((bytes) {
            term.write(utf8.decode(bytes, allowMalformed: true));
          });
          entry.stderrSub = entry.shellSession!.stderr.listen((bytes) {
            term.write(utf8.decode(bytes, allowMalformed: true));
          });
        } else if (entry.shellSession != null) {
          entry.outputSub = entry.shellSession!.stdout.listen((bytes) {
            final decoded = utf8.decode(bytes, allowMalformed: true);
            _appendPtyOutput(sessionKey, _stripAnsi(decoded));
          });
          entry.stderrSub = entry.shellSession!.stderr.listen((bytes) {
            final decoded = utf8.decode(bytes, allowMalformed: true);
            _appendPtyOutput(sessionKey, _stripAnsi(decoded));
          });
        }
      }

      entry.running = true;
      entry.shouldReconnect = true;
      entry.hasConnected = true;
      entry.reconnectAttempts = 0;
      entry.state = entry.state.copyWith(
        status: ConnectionStatus.connected,
        error: null,
      );
      sessions[sessionKey] = entry;
      state = state.copyWith(sessions: Map.from(sessions));
      _processQueue(sessionKey);
    } catch (e) {
      entry.running = false;
      entry.state = entry.state.copyWith(
        status: ConnectionStatus.error,
        error: e.toString(),
      );
      sessions[sessionKey] = entry;
      state = state.copyWith(sessions: Map.from(sessions));
      if (entry.shouldReconnect && entry.hasConnected) {
        _scheduleReconnect(sessionKey, entry, sessions);
      }
    }
  }

  Future<void> _cleanupConnection(SessionEntry entry) async {
    entry.running = false;
    await entry.outputSub?.cancel();
    await entry.stderrSub?.cancel();
    entry.outputSub = null;
    entry.stderrSub = null;
    if (entry.terminal != null) {
      entry.terminal!.onOutput = null;
      entry.terminal!.onResize = null;
    }
    try {
      entry.shellSession?.close();
    } catch (_) {}
    entry.shellSession = null;
    try {
      entry.client?.close();
    } catch (_) {}
    entry.client = null;
    try {
      await entry.socket?.close();
    } catch (_) {}
    entry.socket = null;
  }

  void _handleRemoteDisconnect(String sessionKey, String? error) {
    final sessions = Map<String, SessionEntry>.from(state.sessions);
    final entry = sessions[sessionKey];
    if (entry == null) return;
    if (!entry.shouldReconnect) {
      entry.state = entry.state.copyWith(
        status: ConnectionStatus.disconnected,
        error: error,
      );
      sessions[sessionKey] = entry;
      state = state.copyWith(sessions: sessions);
      return;
    }
    final updatedCommands = entry.state.commands.map((c) {
      if (c.status == CommandStatus.sending) {
        return c.copyWith(status: CommandStatus.pending);
      }
      return c;
    }).toList();
    entry.state = entry.state.copyWith(
      status: ConnectionStatus.reconnecting,
      commands: updatedCommands,
      error: error,
    );
    sessions[sessionKey] = entry;
    state = state.copyWith(sessions: sessions);
    _scheduleReconnect(sessionKey, entry, sessions);
  }

  void _scheduleReconnect(
    String sessionKey,
    SessionEntry entry,
    Map<String, SessionEntry> sessions,
  ) {
    entry.reconnectTimer?.cancel();
    entry.reconnectAttempts += 1;
    final delaySeconds = math.min(30, 1 << (entry.reconnectAttempts - 1));
    entry.reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      final latest = state.sessions[sessionKey];
      if (latest == null || !latest.shouldReconnect) return;
      _connectForKey(
        sessionKey,
        latest.config,
        latest,
        Map<String, SessionEntry>.from(state.sessions),
        isReconnect: true,
      );
    });
    sessions[sessionKey] = entry;
    state = state.copyWith(sessions: Map.from(sessions));
  }

  void _appendPtyOutput(String sessionKey, String s) {
    final sessions = Map<String, SessionEntry>.from(state.sessions);
    final entry = sessions[sessionKey];
    if (entry == null || !entry.running) return;
    entry.state = entry.state.copyWith(
      output: [...entry.state.output, s],
    );
    sessions[sessionKey] = entry;
    state = state.copyWith(sessions: sessions);
  }

  void addCommand(String sessionKey, String text) {
    final sessions = Map<String, SessionEntry>.from(state.sessions);
    final entry = sessions[sessionKey];
    if (entry == null) return;
    final item = CommandItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text.trim(),
      timestamp: DateTime.now(),
    );
    entry.state = entry.state.copyWith(
      commands: [...entry.state.commands, item],
    );
    sessions[sessionKey] = entry;
    state = state.copyWith(sessions: sessions);
    if (entry.running && entry.client != null) {
      _processQueue(sessionKey);
    }
  }

  Future<void> _processQueue(String sessionKey) async {
    final sessions = Map<String, SessionEntry>.from(state.sessions);
    final entry = sessions[sessionKey];
    if (entry == null || entry.client == null || !entry.running) return;

    final current = entry.state;
    final pending = current.commands
        .where((c) => c.status == CommandStatus.pending)
        .toList();
    if (pending.isEmpty) return;

    final item = pending.first;
    entry.state = current.copyWith(
      commands: current.commands.map((c) {
        if (c.id == item.id) {
          return c.copyWith(status: CommandStatus.sending);
        }
        return c;
      }).toList(),
    );
    sessions[sessionKey] = entry;
    state = state.copyWith(sessions: sessions);

    if (entry.usePty && entry.shellSession != null) {
      final newOutput = entry.terminal == null
          ? [...entry.state.output, '\$ ${item.text}']
          : entry.state.output;
      entry.shellSession!.write(utf8.encode('${item.text}\n'));
      entry.state = entry.state.copyWith(
        commands: entry.state.commands.map((c) {
          if (c.id == item.id) {
            return c.copyWith(status: CommandStatus.completed);
          }
          return c;
        }).toList(),
        output: newOutput,
      );
      sessions[sessionKey] = entry;
      state = state.copyWith(sessions: sessions);
      final remaining = entry.state.commands
          .where((c) => c.status == CommandStatus.pending)
          .toList();
      if (remaining.isNotEmpty) {
        _processQueue(sessionKey);
      }
      return;
    }

    try {
      final result = await entry.client!.run(item.text);
      final output = utf8.decode(result);
      entry.state = entry.state.copyWith(
        commands: entry.state.commands.map((c) {
          if (c.id == item.id) {
            return c.copyWith(
              status: CommandStatus.completed,
              output: output,
            );
          }
          return c;
        }).toList(),
        output: [
          ...entry.state.output,
          '\$ ${item.text}',
          output,
        ],
      );
      sessions[sessionKey] = entry;
      state = state.copyWith(sessions: sessions);
      final remaining = entry.state.commands
          .where((c) => c.status == CommandStatus.pending)
          .toList();
      if (remaining.isNotEmpty) {
        _processQueue(sessionKey);
      }
    } catch (e) {
      entry.state = entry.state.copyWith(
        commands: entry.state.commands.map((c) {
          if (c.id == item.id) {
            return c.copyWith(
              status: CommandStatus.failed,
              error: e.toString(),
            );
          }
          return c;
        }).toList(),
        output: [...entry.state.output, '\$ ${item.text}', 'Error: $e'],
      );
      sessions[sessionKey] = entry;
      state = state.copyWith(sessions: sessions);
    }
  }

  Future<void> disconnect(String sessionKey) async {
    final sessions = Map<String, SessionEntry>.from(state.sessions);
    final entry = sessions[sessionKey];
    if (entry == null) return;

    entry.shouldReconnect = false;
    entry.reconnectTimer?.cancel();
    entry.reconnectTimer = null;
    await _cleanupConnection(entry);
    entry.state = entry.state.copyWith(
      status: ConnectionStatus.disconnected,
      error: null,
    );
    sessions[sessionKey] = entry;
    state = state.copyWith(sessions: sessions);
  }

  Future<void> reconnect(String sessionKey) async {
    final sessions = Map<String, SessionEntry>.from(state.sessions);
    final entry = sessions[sessionKey];
    if (entry == null) return;
    entry.shouldReconnect = true;
    entry.reconnectAttempts = 0;
    entry.reconnectTimer?.cancel();
    entry.reconnectTimer = null;
    sessions[sessionKey] = entry;
    state = state.copyWith(sessions: sessions);
    await _connectForKey(
      sessionKey,
      entry.config,
      entry,
      sessions,
      isReconnect: true,
    );
  }

  void clearOutput(String sessionKey) {
    final sessions = Map<String, SessionEntry>.from(state.sessions);
    final entry = sessions[sessionKey];
    if (entry == null) return;
    if (entry.terminal != null) {
      entry.terminal!.buffer.clear();
      entry.terminal!.buffer.setCursor(0, 0);
    }
    entry.state = entry.state.copyWith(output: []);
    sessions[sessionKey] = entry;
    state = state.copyWith(sessions: sessions);
  }
}

final sessionsProvider =
    NotifierProvider<SessionsNotifier, SessionsState>(SessionsNotifier.new);

/// 当前会话的 SessionState，供 UI 使用。
final currentSessionStateProvider = Provider<SessionState?>((ref) {
  final state = ref.watch(sessionsProvider);
  final entry = state.currentEntry;
  return entry?.state;
});

/// 当前会话的 Terminal（PTY 时），供 UI 使用。
final currentTerminalProvider = Provider<Terminal?>((ref) {
  final state = ref.watch(sessionsProvider);
  return state.currentEntry?.terminal;
});

/// 当前会话的 ConnectionConfig。
final currentSessionConfigProvider = Provider<ConnectionConfig?>((ref) {
  final state = ref.watch(sessionsProvider);
  return state.currentEntry?.config;
});
