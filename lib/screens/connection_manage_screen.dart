import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/session_state.dart';
import '../providers/connections_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../services/storage_service.dart';

/// 连接管理页：新增或编辑已保存连接。
class ConnectionManageScreen extends ConsumerStatefulWidget {
  const ConnectionManageScreen({
    super.key,
    this.connectionId,
  });

  /// 为 null 表示新增，否则为编辑指定 id 的连接。
  final String? connectionId;

  @override
  ConsumerState<ConnectionManageScreen> createState() =>
      _ConnectionManageScreenState();
}

class _ConnectionManageScreenState extends ConsumerState<ConnectionManageScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController(text: 'localhost');
  final _portController = TextEditingController(text: '22');
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _privateKeyPathController = TextEditingController();
  final _privateKeyPassphraseController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _loadedPassword;

  bool get _isEdit => widget.connectionId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loadConnection();
    } else {
      _loading = false;
    }
  }

  Future<void> _loadConnection() async {
    final id = widget.connectionId!;
    final config = await StorageService.getConnectionConfig(id);
    if (config == null || !mounted) return;
    final pwd = await StorageService.getConnectionPassword(id);
    setState(() {
      _nameController.text = config.name ?? '';
      _hostController.text = config.host;
      _portController.text = '${config.port}';
      _userController.text = config.username;
      _passwordController.text = '';
      _privateKeyPathController.text = config.privateKeyPath ?? '';
      _privateKeyPassphraseController.text =
          config.privateKeyPassphrase ?? '';
      _loadedPassword = pwd;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _privateKeyPathController.dispose();
    _privateKeyPassphraseController.dispose();
    super.dispose();
  }

  ConnectionConfig _configFromForm({String? password, String? ppk}) {
    final pwd = password ?? (_passwordController.text.trim().isNotEmpty
        ? _passwordController.text.trim()
        : _loadedPassword);
    final pkPath = _privateKeyPathController.text.trim();
    final pkPhrase = ppk ?? (pkPath.isEmpty
        ? null
        : _privateKeyPassphraseController.text.trim());
    return ConnectionConfig(
      id: widget.connectionId,
      name: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 22,
      username: _userController.text.trim(),
      password: pwd?.isEmpty == true ? null : pwd,
      privateKeyPath: pkPath.isEmpty ? null : pkPath,
      privateKeyPassphrase: pkPhrase?.isEmpty == true ? null : pkPhrase,
      usePty: false,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final username = _userController.text.trim();
    final password = _passwordController.text.trim();
    final pkPath = _privateKeyPathController.text.trim();
    if (username.isEmpty) {
      _showSnackBar('请输入用户名');
      return;
    }
    if (pkPath.isEmpty && password.isEmpty && !_isEdit) {
      _showSnackBar('请填写密码或私钥路径');
      return;
    }
    if (_isEdit && pkPath.isEmpty && password.isEmpty) {
      if (_loadedPassword == null || _loadedPassword!.isEmpty) {
        _showSnackBar('请填写密码或私钥路径');
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final config = _configFromForm(
        password: password.isEmpty ? null : password,
        ppk: _privateKeyPassphraseController.text.trim().isEmpty
            ? null
            : _privateKeyPassphraseController.text.trim(),
      );
      await StorageService.saveConnection(
        config,
        password: password.isNotEmpty ? password : null,
        privateKeyPassphrase:
            _privateKeyPassphraseController.text.trim().isNotEmpty
                ? _privateKeyPassphraseController.text.trim()
                : null,
      );
      if (!mounted) return;
      ref.invalidate(connectionsListProvider);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _showSnackBar('保存失败: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    final username = _userController.text.trim();
    final password = _passwordController.text.trim();
    final pkPath = _privateKeyPathController.text.trim();
    if (username.isEmpty) {
      _showSnackBar('请输入用户名');
      return;
    }
    if (pkPath.isEmpty && password.isEmpty && !_isEdit) {
      _showSnackBar('请填写密码或私钥路径');
      return;
    }
    if (_isEdit && pkPath.isEmpty && password.isEmpty && _loadedPassword == null) {
      _showSnackBar('请填写密码或私钥路径');
      return;
    }
    setState(() => _testing = true);
    try {
      final config = _configFromForm(
        password: password.isNotEmpty ? password : _loadedPassword,
        ppk: _privateKeyPassphraseController.text.trim().isNotEmpty
            ? _privateKeyPassphraseController.text.trim()
            : null,
      );
      final usePty = ref.read(settingsProvider).valueOrNull?.usePty ?? false;
      const testKey = '_test';
      await ref.read(sessionsProvider.notifier).addOrSwitchToTab(
        testKey,
        config.copyWith(usePty: usePty),
      );
      final entry = ref.read(sessionsProvider).sessions[testKey];
      if (entry?.state.status == ConnectionStatus.error) {
        await ref.read(sessionsProvider.notifier).disconnect(testKey);
        ref.read(sessionsProvider.notifier).closeTab(testKey);
        throw Exception(entry!.state.error);
      }
      await ref.read(sessionsProvider.notifier).disconnect(testKey);
      ref.read(sessionsProvider.notifier).closeTab(testKey);
      if (!mounted) return;
      _showSnackBar('连接成功');
    } catch (e) {
      if (mounted) _showSnackBar('连接失败: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除连接'),
        content: const Text('确定要删除该连接吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true || widget.connectionId == null) return;
    setState(() => _saving = true);
    try {
      await StorageService.deleteConnection(widget.connectionId!);
      if (!mounted) return;
      ref.invalidate(connectionsListProvider);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _showSnackBar('删除失败: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(_isEdit ? '编辑连接' : '新增连接')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑连接' : '新增连接'),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
              tooltip: '删除',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '连接名/别名（可选）',
                hintText: '用于列表展示',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: '主机',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '请输入主机' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: '端口',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _userController,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '请输入用户名' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '密码',
                hintText: _isEdit ? '留空则保持原密码' : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _privateKeyPathController,
              decoration: const InputDecoration(
                labelText: '私钥路径',
                hintText: '~/.ssh/id_rsa',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _privateKeyPassphraseController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '私钥密语（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: (_saving || _testing) ? null : _testConnection,
              child: _testing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('测试连接'),
            ),
          ],
        ),
      ),
    );
  }
}
