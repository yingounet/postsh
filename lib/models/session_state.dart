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
    this.mayNeedTmuxAttach = false,
    this.tmuxAttachSuggested = false,
    this.hasUnconfirmedCommands = false,
  });

  final ConnectionStatus status;
  final List<CommandItem> commands;
  final List<String> output;
  final String? error;
  final bool mayNeedTmuxAttach;
  final bool tmuxAttachSuggested;
  final bool hasUnconfirmedCommands;

  SessionState copyWith({
    ConnectionStatus? status,
    List<CommandItem>? commands,
    List<String>? output,
    String? error,
    bool? mayNeedTmuxAttach,
    bool? tmuxAttachSuggested,
    bool? hasUnconfirmedCommands,
  }) {
    return SessionState(
      status: status ?? this.status,
      commands: commands ?? this.commands,
      output: output ?? this.output,
      error: error ?? this.error,
      mayNeedTmuxAttach: mayNeedTmuxAttach ?? this.mayNeedTmuxAttach,
      tmuxAttachSuggested: tmuxAttachSuggested ?? this.tmuxAttachSuggested,
      hasUnconfirmedCommands:
          hasUnconfirmedCommands ?? this.hasUnconfirmedCommands,
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
