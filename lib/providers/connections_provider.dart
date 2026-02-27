import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage_service.dart';
import 'session_provider.dart';

/// 已保存连接列表（按最近使用倒序），用于首页展示。
final connectionsListProvider =
    FutureProvider<List<ConnectionConfig>>((ref) async {
  return StorageService.getConnectionList();
});
