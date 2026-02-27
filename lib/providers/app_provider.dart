import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 示例 Provider：演示 Riverpod 用法。
/// 后续阶段将用于会话、命令队列、连接状态等。
final appVersionProvider = Provider<String>((ref) => '1.0.0');
