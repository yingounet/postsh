import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/session_provider.dart';

/// 本地存储服务：配置、历史、密钥等。
class StorageService {
  StorageService._();

  static const _prefsPrefix = 'postsh_';
  static const _connListKey = 'connection_list';
  static const _connPwdPrefix = 'conn_pwd_';
  static const _connPpkPrefix = 'conn_ppk_';
  static const _cmdHistoryPrefix = 'cmd_history_';
  static const _cmdHistoryLimit = 200;

  /// 跨平台安全存储：Android 为 EncryptedSharedPreferences，iOS/macOS 为系统密钥链，Windows 等由插件选择后端。
  static const _secureStorage = FlutterSecureStorage();

  /// 读取配置（shared_preferences）
  static Future<String?> getConfig(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefsPrefix$key');
  }

  /// 保存配置
  static Future<void> setConfig(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefsPrefix$key', value);
  }

  /// 删除配置
  static Future<void> removeConfig(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefsPrefix$key');
  }

  /// 读取密钥：先尝试安全存储，若无则读 SharedPreferences（安全存储不可用时的回退）。
  static Future<String?> getSecret(String key) async {
    try {
      final v = await _secureStorage.read(key: '$_prefsPrefix$key');
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    return getConfig(key);
  }

  /// 保存密钥：优先安全存储；失败时回退到 SharedPreferences，保证密码能保存成功。
  static Future<void> setSecret(String key, String value) async {
    try {
      await _secureStorage.write(key: '$_prefsPrefix$key', value: value);
      return;
    } catch (_) {}
    await setConfig(key, value);
  }

  /// 删除密钥（安全存储与回退 key 一并删除）
  static Future<void> deleteSecret(String key) async {
    try {
      await _secureStorage.delete(key: '$_prefsPrefix$key');
    } catch (_) {}
    await removeConfig(key);
  }

  /// 已保存连接列表（按最近使用倒序），不含密码。
  static Future<List<ConnectionConfig>> getConnectionList() async {
    final raw = await getConfig(_connListKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final configs = <ConnectionConfig>[];
      for (final e in list) {
        final map = e as Map<String, dynamic>;
        configs.add(ConnectionConfig.fromJson(map));
      }
      configs.sort((a, b) {
        final aT = a.lastUsedAt ?? DateTime(0);
        final bT = b.lastUsedAt ?? DateTime(0);
        return bT.compareTo(aT);
      });
      return configs;
    } catch (_) {
      return [];
    }
  }

  /// 保存或更新连接；password/privateKeyPassphrase 若提供则写入（安全存储或回退到 SharedPreferences）。
  static Future<bool> saveConnection(
    ConnectionConfig config, {
    String? password,
    String? privateKeyPassphrase,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefsPrefix$_connListKey';
    List<dynamic> list = [];
    final raw = prefs.getString(key);
    if (raw != null && raw.isNotEmpty) {
      try {
        list = jsonDecode(raw) as List<dynamic>;
      } catch (_) {}
    }
    final id = config.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final updated = config.copyWith(
      id: id,
      lastUsedAt: config.lastUsedAt ?? DateTime.now(),
    );
    final map = updated.toJson();
    final idx = list.indexWhere(
      (e) => (e as Map<String, dynamic>)['id'] == id,
    );
    if (idx >= 0) {
      list[idx] = map;
    } else {
      list.insert(0, map);
    }
    await prefs.setString(key, jsonEncode(list));
    if (password != null) {
      if (password.isEmpty) {
        await deleteSecret('$_connPwdPrefix$id');
      } else {
        await setSecret('$_connPwdPrefix$id', password);
      }
    }
    if (privateKeyPassphrase != null) {
      if (privateKeyPassphrase.isEmpty) {
        await deleteSecret('$_connPpkPrefix$id');
      } else {
        await setSecret('$_connPpkPrefix$id', privateKeyPassphrase);
      }
    }
    return true;
  }

  /// 删除已保存连接
  static Future<void> deleteConnection(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefsPrefix$_connListKey';
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .where((e) => (e as Map<String, dynamic>)['id'] != id)
          .toList();
      await prefs.setString(key, jsonEncode(list));
    } catch (_) {}
    await deleteSecret('$_connPwdPrefix$id');
    await deleteSecret('$_connPpkPrefix$id');
  }

  /// 读取某连接的保存密码（供编辑页「留空保持原密码」用，不对外暴露明文时可不调用）。
  static Future<String?> getConnectionPassword(String id) async {
    return getSecret('$_connPwdPrefix$id');
  }

  /// 根据 id 加载完整配置（含安全存储中的密码/密语）
  static Future<ConnectionConfig?> getConnectionConfig(String id) async {
    final list = await getConnectionList();
    ConnectionConfig? config;
    try {
      config = list.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
    final password = await getSecret('$_connPwdPrefix$id');
    final ppk = await getSecret('$_connPpkPrefix$id');
    return config.copyWith(
      password: password,
      privateKeyPassphrase: ppk,
    );
  }

  /// 更新指定连接的最后使用时间
  static Future<void> updateLastUsed(String id, DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefsPrefix$_connListKey';
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (var i = 0; i < list.length; i++) {
        final map = Map<String, dynamic>.from(list[i] as Map<String, dynamic>);
        if (map['id'] == id) {
          map['lastUsedAt'] = time.toIso8601String();
          list[i] = map;
          break;
        }
      }
      await prefs.setString(key, jsonEncode(list));
    } catch (_) {}
  }

  /// 命令历史：按 host/port/user 维度存储（无密码）。
  static String historyKeyFromConfig(ConnectionConfig config) {
    return '${config.host}:${config.port}:${config.username}';
  }

  /// 读取命令历史（最新在前）。
  static Future<List<String>> getCommandHistory(String historyKey) async {
    final raw = await getConfig('$_cmdHistoryPrefix$historyKey');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
      return list;
    } catch (_) {
      return [];
    }
  }

  /// 追加命令历史：去重、置顶并截断到上限。
  static Future<void> addCommandHistory(
    String historyKey,
    String command,
  ) async {
    final cleaned = command.trim();
    if (cleaned.isEmpty) return;
    final list = await getCommandHistory(historyKey);
    list.removeWhere((e) => e == cleaned);
    list.insert(0, cleaned);
    if (list.length > _cmdHistoryLimit) {
      list.removeRange(_cmdHistoryLimit, list.length);
    }
    await setConfig(
      '$_cmdHistoryPrefix$historyKey',
      jsonEncode(list),
    );
  }
}
