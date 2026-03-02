import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import 'connection_config.dart';
import 'session_state.dart';

/// 单条会话：配置、状态、Terminal、SSH 资源
class SessionEntry {
  SessionEntry({
    required this.config,
    required this.state,
    this.terminal,
    this.cancelToken,
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

  ConnectionConfig config;
  SessionState state;
  Terminal? terminal;
  final SessionCancelToken? cancelToken;
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
