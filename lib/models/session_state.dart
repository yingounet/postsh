import 'command_item.dart';

/// 会话连接状态
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
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

/// 用于取消会话操作的令牌
class SessionCancelToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;
  void cancel() => _isCancelled = true;
  void reset() => _isCancelled = false;
}
