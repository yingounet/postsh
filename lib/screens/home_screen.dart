import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_provider.dart';
import '../providers/connections_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../services/storage_service.dart';
import 'connection_manage_screen.dart';
import 'settings_screen.dart';
import 'terminal_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static String _formatLastUsed(DateTime? t) {
    if (t == null) return '未连接过';
    final now = DateTime.now();
    final d = now.difference(t);
    if (d.inDays > 0) return '${d.inDays} 天前';
    if (d.inHours > 0) return '${d.inHours} 小时前';
    if (d.inMinutes > 0) return '${d.inMinutes} 分钟前';
    return '刚刚';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionsAsync = ref.watch(connectionsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PostSH'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
            tooltip: '设置',
          ),
          Text(
            'v${ref.watch(appVersionProvider)}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _openQuickConnect(context, ref),
            icon: const Icon(Icons.flash_on, size: 18),
            label: const Text('快速连接'),
          ),
        ],
      ),
      body: connectionsAsync.when(
        data: (list) {
          if (list.isEmpty) {
            return _EmptyState(
              onAddFirst: () => _navigateToManage(context, ref, null),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(connectionsListProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final config = list[i];
                final id = config.id!;
                return ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.terminal),
                  ),
                  title: Text(config.displayTitle),
                  subtitle: Text(
                    '${config.host}:${config.port} · ${_formatLastUsed(config.lastUsedAt)}',
                  ),
                  onTap: () => _connectTo(context, ref, id),
                  onLongPress: () => _showItemMenu(context, ref, id, config),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _navigateToManage(context, ref, id);
                      } else if (value == 'delete') {
                        _deleteConnection(context, ref, id);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit),
                          title: Text('编辑'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('删除'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载失败: $e', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(connectionsListProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToManage(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('新增连接'),
      ),
    );
  }

  void _navigateToManage(BuildContext context, WidgetRef ref, String? id) {
    Navigator.of(context)
        .push<bool>(
      MaterialPageRoute(
        builder: (context) => ConnectionManageScreen(connectionId: id),
      ),
    )
        .then((_) {
      ref.invalidate(connectionsListProvider);
    });
  }

  Future<void> _connectTo(BuildContext context, WidgetRef ref, String id) async {
    final config = await StorageService.getConnectionConfig(id);
    if (config == null || !context.mounted) return;
    var useConfig = config;
    final hasPassword = config.password != null && config.password!.isNotEmpty;
    final hasKey = config.privateKeyPath != null && config.privateKeyPath!.trim().isNotEmpty;
    if (!hasPassword && !hasKey) {
      // 仅保存了密码但未写入安全存储（如 macOS 无 Keychain）时，弹窗让用户输入密码用于本次连接
      final password = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final controller = TextEditingController();
          return AlertDialog(
            title: const Text('输入密码'),
            content: TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                hintText: '该连接未保存密码，输入后仅用于本次连接',
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('连接'),
              ),
            ],
          );
        },
      );
      if (password == null || !context.mounted) return;
      if (password.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请输入密码')),
          );
        }
        return;
      }
      useConfig = config.copyWith(password: password);
    }
    final usePty = ref.read(settingsProvider).valueOrNull?.usePty ?? false;
    final mergedConfig = useConfig.copyWith(usePty: usePty);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TerminalScreen(
          initialConfig: mergedConfig,
          initialConnectionId: id,
        ),
      ),
    );
  }

  void _showItemMenu(
    BuildContext context,
    WidgetRef ref,
    String id,
    dynamic config,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(ctx);
                _navigateToManage(context, ref, id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteConnection(context, ref, id);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteConnection(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
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
    if (confirm != true) return;
    await StorageService.deleteConnection(id);
    if (context.mounted) ref.invalidate(connectionsListProvider);
  }

  void _openQuickConnect(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _QuickConnectSheet(
        ref: ref,
        onConnect: (config, {String? connectionId}) {
          Navigator.pop(ctx);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => TerminalScreen(
                initialConfig: config,
                initialConnectionId: connectionId,
              ),
            ),
          );
        },
        onRecentTap: (id) {
          Navigator.pop(ctx);
          _connectTo(context, ref, id);
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddFirst});

  final VoidCallback onAddFirst;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '还没有保存的服务器',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '添加连接后可按最近使用排序快速连接',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAddFirst,
              icon: const Icon(Icons.add),
              label: const Text('添加第一个服务器'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickConnectSheet extends ConsumerStatefulWidget {
  const _QuickConnectSheet({
    required this.ref,
    required this.onConnect,
    required this.onRecentTap,
  });

  final WidgetRef ref;
  /// 表单连接（不保存）：config；若从最近使用点击则带 connectionId 以更新最后使用时间。
  final void Function(ConnectionConfig config, {String? connectionId}) onConnect;
  /// 点击最近使用某条时：传入连接 id，由外部加载配置并跳转。
  final void Function(String connectionId) onRecentTap;

  @override
  ConsumerState<_QuickConnectSheet> createState() => _QuickConnectSheetState();
}

class _QuickConnectSheetState extends ConsumerState<_QuickConnectSheet> {
  final _hostController = TextEditingController(text: 'localhost');
  final _portController = TextEditingController(text: '22');
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _privateKeyPathController = TextEditingController();
  final _privateKeyPassphraseController = TextEditingController();

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _privateKeyPathController.dispose();
    _privateKeyPassphraseController.dispose();
    super.dispose();
  }

  void _connect() {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 22;
    final username = _userController.text.trim();
    final password = _passwordController.text.trim();
    final privateKeyPath = _privateKeyPathController.text.trim();
    final privateKeyPassphrase = _privateKeyPassphraseController.text.trim();

    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入用户名')),
      );
      return;
    }
    if (privateKeyPath.isEmpty && password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写密码或私钥路径')),
      );
      return;
    }

    final usePty = ref.read(settingsProvider).valueOrNull?.usePty ?? false;
    final config = ConnectionConfig(
      host: host,
      port: port,
      username: username,
      password: password.isNotEmpty ? password : null,
      privateKeyPath:
          privateKeyPath.isNotEmpty ? privateKeyPath : null,
      privateKeyPassphrase:
          privateKeyPassphrase.isNotEmpty ? privateKeyPassphrase : null,
      usePty: usePty,
    );
    widget.onConnect(config);
  }

  @override
  Widget build(BuildContext context) {
    final connectionsAsync = widget.ref.watch(connectionsListProvider);
    final recentList = connectionsAsync.valueOrNull ?? [];
    final recent5 = recentList.take(5).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              if (recent5.isNotEmpty) ...[
                Text(
                  '最近使用',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                ...recent5.map((config) {
                  final id = config.id!;
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.history, size: 20),
                    title: Text(
                      config.displayTitle,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      '${config.host}:${config.port}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: () => widget.onRecentTap(id),
                  );
                }),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
              ],
              const Text(
                '快速连接（不保存）',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: '主机',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: '端口',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _userController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _privateKeyPathController,
                decoration: const InputDecoration(
                  labelText: '私钥路径',
                  hintText: '~/.ssh/id_rsa',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _privateKeyPassphraseController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '私钥密语（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _connect,
                child: const Text('连接'),
              ),
            ],
          ),
        );
      },
    );
  }
}
