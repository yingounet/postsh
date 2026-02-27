/// 命令队列项
enum CommandStatus {
  pending,
  sending,
  completed,
  failed,
}

class CommandItem {
  CommandItem({
    required this.id,
    required this.text,
    required this.timestamp,
    this.status = CommandStatus.pending,
    this.output,
    this.error,
  });

  final String id;
  final String text;
  final DateTime timestamp;
  final CommandStatus status;
  final String? output;
  final String? error;

  CommandItem copyWith({
    CommandStatus? status,
    String? output,
    String? error,
  }) {
    return CommandItem(
      id: id,
      text: text,
      timestamp: timestamp,
      status: status ?? this.status,
      output: output ?? this.output,
      error: error ?? this.error,
    );
  }
}
