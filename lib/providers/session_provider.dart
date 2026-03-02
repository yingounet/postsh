import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../models/app_settings.dart';
import '../models/command_item.dart';
import '../models/connection_config.dart';
import '../models/session_entry.dart';
import '../models/session_state.dart';
import '../services/storage_service.dart';

export '../models/connection_config.dart';
export '../models/session_state.dart';

/// 从 config 生成会话 key：有 id 用 id，否则用 quick-host:port:user
String sessionKeyFromConfig(ConnectionConfig config) {
  if (config.id != null && config.id!.trim().isNotEmpty) {
    return config.id!.trim();
  }
  return 'quick-${config.host}:${config.port}:${config.username}';
}

/// 去掉 PTY 输出中的 ANSI 转义序列
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
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    if (path == '~') return home;
    if (path.startsWith('~/')) return '$home${path.substring(1)}';
    return path;
  }
  return path;
}

/// 多会话状态：当前选中的 Tab id + 所有会话
class SessionsState {
  const SessionsState({this.currentSessionId, this.sessions = const {}});

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

  /// 添加或切换到指定会话
  Future<void> addOrSwitchToTab(
    String sessionKey,
    ConnectionConfig config,
  ) async {
    final sessions = Map<String, SessionEntry>.from(state.sessions);
    final existing = sessions[sessionKey];

    if (existing != null &&
        (existing.state.status == ConnectionStatus.connected ||
            existing.state.status == ConnectionStatus.connecting)) {
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

    final globalUsePty = await _getGlobalUsePty();
    final terminal = globalUsePty ? Terminal() : null;
    final entry = SessionEntry(
      config: config.copyWith(usePty: globalUsePty),
      state: SessionState(status: ConnectionStatus.connecting),
      terminal: terminal,
      cancelToken: SessionCancelToken(),
    );
    sessions[sessionKey] = entry;
    state = state.copyWith(sessions: sessions);
    await _connectForKey(sessionKey, entry.config, entry, sessions);
  }

  Future<bool> _getGlobalUsePty() async {
    final raw = await StorageService.getConfig(AppSettings.storageUsePty);
    return raw == 'true';
  }

  /// 检查历史命令中是否有 tmux/screen 使用
  Future<bool> _checkTmuxUsage(ConnectionConfig config) async {
    try {
      final historyKey = StorageService.historyKeyFromConfig(config);
      final history = await StorageService.getCommandHistory(historyKey);

      // 检查历史命令中是否包含 tmux/screen 相关命令
      final tmuxKeywords = [
        'tmux',
        'tmux new',
        'tmux attach',
        'tmux a',
        'screen',
        'screen -r',
      ];
      for (final cmd in history) {
        final cmdLower = cmd.toLowerCase();
        for (final keyword in tmuxKeywords) {
          if (cmdLower.contains(keyword.toLowerCase())) {
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  void switchToTab(String sessionKey) {
    if (state.sessions.containsKey(sessionKey)) {
      state = state.copyWith(currentSessionId: sessionKey);
    }
  }

  Future<void> closeTab(String sessionKey) async {
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
    Map<String, SessionEntry> sessions, {
    bool isReconnect = false,
  }) async {
    final cancelToken = entry.cancelToken;
    await _cleanupConnection(entry);
    if (cancelToken?.isCancelled == true) return;

    entry.state = entry.state.copyWith(
      status: isReconnect
          ? ConnectionStatus.reconnecting
          : ConnectionStatus.connecting,
      error: null,
    );
    state = state.copyWith(sessions: Map.from(sessions));

    try {
      entry.socket = await SSHSocket.connect(config.host, config.port);

      if (cancelToken?.isCancelled == true) {
        await _cleanupConnection(entry);
        return;
      }

      List<SSHKeyPair>? identities;
      if (config.privateKeyPath != null &&
          config.privateKeyPath!.trim().isNotEmpty) {
        final path = _expandPath(config.privateKeyPath!.trim());
        final pem = await File(path).readAsString();
        final passphrase = config.privateKeyPassphrase?.isNotEmpty == true
            ? config.privateKeyPassphrase
            : null;
        identities = SSHKeyPair.fromPem(pem, passphrase);
      }

      entry.client = SSHClient(
        entry.socket!,
        username: config.username,
        identities: identities,
        onPasswordRequest:
            identities == null &&
                config.password != null &&
                config.password!.isNotEmpty
            ? () => config.password!
            : null,
      );
      await entry.client!.authenticated;

      if (cancelToken?.isCancelled == true) {
        await _cleanupConnection(entry);
        return;
      }

      entry.client!.done
          .then((_) {
            _handleRemoteDisconnect(sessionKey, null);
          })
          .catchError((error) {
            _handleRemoteDisconnect(sessionKey, error.toString());
          });

      entry.usePty = config.usePty;
      if (entry.usePty) {
        await _setupPtySession(sessionKey, entry, sessions, cancelToken);
        if (cancelToken?.isCancelled == true) {
          await _cleanupConnection(entry);
          return;
        }
      }

      entry.running = true;
      entry.shouldReconnect = true;
      entry.hasConnected = true;
      entry.reconnectAttempts = 0;

      // 检测是否需要 tmux attach 建议（仅在重连时）
      bool mayNeedTmuxAttach = false;
      if (isReconnect && config.usePty) {
        mayNeedTmuxAttach = await _checkTmuxUsage(config);
      }

      entry.state = entry.state.copyWith(
        status: ConnectionStatus.connected,
        error: null,
        mayNeedTmuxAttach: mayNeedTmuxAttach,
      );
      sessions[sessionKey] = entry;
      state = state.copyWith(sessions: Map.from(sessions));
      _processQueueLoop(sessionKey);
    } catch (e) {
      if (cancelToken?.isCancelled == true) return;
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

  Future<void> _setupPtySession(
    String sessionKey,
    SessionEntry entry,
    Map<String, SessionEntry> sessions,
    SessionCancelToken? cancelToken,
  ) async {
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

    if (cancelToken?.isCancelled == true) return;

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
      entry.outputSub = entry.shellSession!.stdout.listen(
        (bytes) => term.write(utf8.decode(bytes, allowMalformed: true)),
        onError: (e) => _appendPtyOutput(sessionKey, 'Stream error: $e'),
      );
      entry.stderrSub = entry.shellSession!.stderr.listen(
        (bytes) => term.write(utf8.decode(bytes, allowMalformed: true)),
        onError: (e) => _appendPtyOutput(sessionKey, 'Stream error: $e'),
      );
    } else if (entry.shellSession != null) {
      entry.outputSub = entry.shellSession!.stdout.listen(
        (bytes) => _appendPtyOutput(
          sessionKey,
          _stripAnsi(utf8.decode(bytes, allowMalformed: true)),
        ),
        onError: (e) => _appendPtyOutput(sessionKey, 'Stream error: $e'),
      );
      entry.stderrSub = entry.shellSession!.stderr.listen(
        (bytes) => _appendPtyOutput(
          sessionKey,
          _stripAnsi(utf8.decode(bytes, allowMalformed: true)),
        ),
        onError: (e) => _appendPtyOutput(sessionKey, 'Stream error: $e'),
      );
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

    // 检查是否有已发送但未收到回显的命令
    final hasSending = entry.state.commands.any(
      (c) => c.status == CommandStatus.sending,
    );

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
      hasUnconfirmedCommands: hasSending,
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
    entry.reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      final latest = state.sessions[sessionKey];
      if (latest == null || !latest.shouldReconnect) return;
      final globalUsePty = await _getGlobalUsePty();
      final updatedConfig = latest.config.copyWith(usePty: globalUsePty);
      if (globalUsePty && latest.terminal == null) {
        latest.terminal = Terminal();
      }
      latest.config = updatedConfig;
      _connectForKey(
        sessionKey,
        updatedConfig,
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
    entry.state = entry.state.copyWith(output: [...entry.state.output, s]);
    sessions[sessionKey] = entry;
    state = state.copyWith(sessions: sessions);
  }

  void updateSessionState(String sessionKey, SessionState newState) {
    final sessions = Map<String, SessionEntry>.from(state.sessions);
    final entry = sessions[sessionKey];
    if (entry == null) return;
    entry.state = newState;
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
      _processQueueLoop(sessionKey);
    }
  }

  /// 使用循环处理命令队列，避免递归栈溢出
  void _processQueueLoop(String sessionKey) {
    Future(() async {
      while (true) {
        final sessions = Map<String, SessionEntry>.from(state.sessions);
        final entry = sessions[sessionKey];
        if (entry == null || entry.client == null || !entry.running) return;

        final current = entry.state;
        final pending = current.commands
            .where((c) => c.status == CommandStatus.pending)
            .toList();
        if (pending.isEmpty) return;

        final item = pending.first;
        final shouldContinue = await _processCommand(
          sessionKey,
          entry,
          sessions,
          item,
        );
        if (!shouldContinue) return;

        await Future.delayed(Duration.zero);
      }
    });
  }

  /// 处理单条命令，返回是否应继续处理
  Future<bool> _processCommand(
    String sessionKey,
    SessionEntry entry,
    Map<String, SessionEntry> sessions,
    CommandItem item,
  ) async {
    var sessionsRef = Map<String, SessionEntry>.from(state.sessions);
    var entryRef = sessionsRef[sessionKey];
    if (entryRef == null) return false;

    entryRef.state = entryRef.state.copyWith(
      commands: entryRef.state.commands.map((c) {
        if (c.id == item.id) {
          return c.copyWith(status: CommandStatus.sending);
        }
        return c;
      }).toList(),
    );
    sessionsRef[sessionKey] = entryRef;
    state = state.copyWith(sessions: sessionsRef);

    if (entryRef.usePty && entryRef.shellSession != null) {
      final newOutput = entryRef.terminal == null
          ? [...entryRef.state.output, '\$ ${item.text}']
          : entryRef.state.output;
      entryRef.shellSession!.write(utf8.encode('${item.text}\n'));
      entryRef.state = entryRef.state.copyWith(
        commands: entryRef.state.commands.map((c) {
          if (c.id == item.id) {
            return c.copyWith(status: CommandStatus.completed);
          }
          return c;
        }).toList(),
        output: newOutput,
      );
      sessionsRef[sessionKey] = entryRef;
      state = state.copyWith(sessions: sessionsRef);
      return true;
    }

    try {
      final result = await entryRef.client!.run(item.text);
      final output = utf8.decode(result);
      sessionsRef = Map<String, SessionEntry>.from(state.sessions);
      entryRef = sessionsRef[sessionKey];
      if (entryRef == null) return false;

      entryRef.state = entryRef.state.copyWith(
        commands: entryRef.state.commands.map((c) {
          if (c.id == item.id) {
            return c.copyWith(status: CommandStatus.completed, output: output);
          }
          return c;
        }).toList(),
        output: [...entryRef.state.output, '\$ ${item.text}', output],
      );
      sessionsRef[sessionKey] = entryRef;
      state = state.copyWith(sessions: sessionsRef);
      return true;
    } catch (e) {
      sessionsRef = Map<String, SessionEntry>.from(state.sessions);
      entryRef = sessionsRef[sessionKey];
      if (entryRef == null) return false;

      entryRef.state = entryRef.state.copyWith(
        commands: entryRef.state.commands.map((c) {
          if (c.id == item.id) {
            return c.copyWith(
              status: CommandStatus.failed,
              error: e.toString(),
            );
          }
          return c;
        }).toList(),
        output: [...entryRef.state.output, '\$ ${item.text}', 'Error: $e'],
      );
      sessionsRef[sessionKey] = entryRef;
      state = state.copyWith(sessions: sessionsRef);
      return false;
    }
  }

  Future<void> disconnect(String sessionKey) async {
    final sessions = Map<String, SessionEntry>.from(state.sessions);
    final entry = sessions[sessionKey];
    if (entry == null) return;

    entry.cancelToken?.cancel();
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
    entry.cancelToken?.reset();
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

final sessionsProvider = NotifierProvider<SessionsNotifier, SessionsState>(
  SessionsNotifier.new,
);

/// 当前会话的 SessionState
final currentSessionStateProvider = Provider<SessionState?>((ref) {
  final state = ref.watch(sessionsProvider);
  return state.currentEntry?.state;
});

/// 当前会话的 Terminal（PTY 时）
final currentTerminalProvider = Provider<Terminal?>((ref) {
  final state = ref.watch(sessionsProvider);
  return state.currentEntry?.terminal;
});

/// 当前会话的 ConnectionConfig
final currentSessionConfigProvider = Provider<ConnectionConfig?>((ref) {
  final state = ref.watch(sessionsProvider);
  return state.currentEntry?.config;
});
