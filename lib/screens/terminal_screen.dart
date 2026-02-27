import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../models/session_state.dart';
import '../providers/connections_provider.dart';
import '../providers/session_provider.dart';
import '../services/storage_service.dart';

/// 终端 Tab 容器：多连接以 Tab 形式保留，切换 Tab 即切回该连接的会话内容。
class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({
    super.key,
    required this.initialConfig,
    this.initialConnectionId,
  });

  final ConnectionConfig initialConfig;
  /// 若来自已保存连接，传入 id 以更新最后使用时间并作为 sessionKey。
  final String? initialConnectionId;

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final Set<String> _lastUsedUpdated = {};

  @override
  void initState() {
    super.initState();
    final key = widget.initialConnectionId ??
        sessionKeyFromConfig(widget.initialConfig);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sessionsProvider.notifier).addOrSwitchToTab(
        key,
        widget.initialConfig,
      );
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submitCommand() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    final currentId = ref.read(sessionsProvider).currentSessionId;
    if (currentId == null) return;
    ref.read(sessionsProvider.notifier).addCommand(currentId, text);
    _inputController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessionsState = ref.watch(sessionsProvider);
    final currentId = sessionsState.currentSessionId;
    final sessionState = ref.watch(currentSessionStateProvider);
    final terminal = ref.watch(currentTerminalProvider);
    final config = ref.watch(currentSessionConfigProvider);

    ref.listen<SessionsState>(sessionsProvider, (prev, next) {
      final entry = next.currentEntry;
      if (entry != null &&
          entry.state.status == ConnectionStatus.connected &&
          next.currentSessionId != null &&
          !_lastUsedUpdated.contains(next.currentSessionId)) {
        final id = entry.config.id;
        if (id != null && id.isNotEmpty) {
          _lastUsedUpdated.add(next.currentSessionId!);
          StorageService.updateLastUsed(id, DateTime.now());
          ref.invalidate(connectionsListProvider);
        }
      }
    });

    final sessionIds = sessionsState.sessions.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(config?.displayTitle ?? '终端'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (sessionState != null)
            _StatusChip(
              status: sessionState.status,
              errorMessage: sessionState.error,
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () {
              final id = ref.read(sessionsProvider).currentSessionId;
              if (id != null) {
                ref.read(sessionsProvider.notifier).clearOutput(id);
              }
            },
            tooltip: '清空输出',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final id = ref.read(sessionsProvider).currentSessionId;
              if (id != null) {
                await ref.read(sessionsProvider.notifier).disconnect(id);
              }
            },
            tooltip: '断开',
          ),
        ],
      ),
      body: Column(
        children: [
          if (sessionIds.length > 1) _TabBar(sessionIds: sessionIds),
          Expanded(
            child: currentId == null
                ? const Center(child: Text('无当前会话'))
                : sessionState == null
                    ? const Center(child: CircularProgressIndicator())
                    : sessionState.status == ConnectionStatus.connecting
                        ? const Center(child: CircularProgressIndicator())
                        : sessionState.status == ConnectionStatus.error
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '连接失败: ${sessionState.error}',
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                    const SizedBox(height: 16),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: const Text('返回'),
                                    ),
                                  ],
                                ),
                              )
                            : _buildBody(
                                config: config!,
                                sessionState: sessionState,
                                terminal: terminal,
                              ),
          ),
          if (config != null && !config.usePty)
            _CommandInput(
              controller: _inputController,
              enabled: sessionState?.status == ConnectionStatus.connected,
              onSubmit: _submitCommand,
            ),
        ],
      ),
    );
  }

  Widget _buildBody({
    required ConnectionConfig config,
    required SessionState sessionState,
    Terminal? terminal,
  }) {
    if (config.usePty && terminal != null) {
      return Container(
        color: const Color(0xFF1E1E1E),
        child: TerminalView(
          terminal,
          theme: TerminalThemes.defaultTheme,
          padding: const EdgeInsets.all(16),
          keyboardType: TextInputType.text,
        ),
      );
    }
    return _OutputArea(
      output: sessionState.output,
      scrollController: _scrollController,
    );
  }
}

class _TabBar extends ConsumerWidget {
  const _TabBar({required this.sessionIds});

  final List<String> sessionIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionsProvider);
    final currentId = state.currentSessionId;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: sessionIds.map((id) {
            final entry = state.sessions[id];
            final title = entry?.config.displayTitle ?? id;
            final selected = id == currentId;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Material(
                color: selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () =>
                      ref.read(sessionsProvider.notifier).switchToTab(id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              ref.read(sessionsProvider.notifier).closeTab(id),
                          tooltip: '关闭',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
    this.errorMessage,
  });

  final ConnectionStatus status;
  final String? errorMessage;

  void _showErrorDialog(BuildContext context) {
    final message = errorMessage ?? '';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('错误原因'),
        content: SingleChildScrollView(
          child: SelectableText(message),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('已复制到剪贴板')),
              );
            },
            child: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ConnectionStatus.connected => ('已连接', Colors.green),
      ConnectionStatus.connecting => ('连接中', Colors.orange),
      ConnectionStatus.reconnecting => ('重连中', Colors.orange),
      ConnectionStatus.disconnected => ('已断开', Colors.grey),
      ConnectionStatus.error => ('错误', Colors.red),
    };
    final chip = Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.2),
    );
    final isErrorWithMessage = status == ConnectionStatus.error &&
        errorMessage != null &&
        errorMessage!.isNotEmpty;
    if (isErrorWithMessage) {
      return GestureDetector(
        onTap: () => _showErrorDialog(context),
        child: chip,
      );
    }
    return chip;
  }
}

class _OutputArea extends StatelessWidget {
  const _OutputArea({
    required this.output,
    required this.scrollController,
  });

  final List<String> output;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF1E1E1E),
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: output.length,
        itemBuilder: (context, i) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: SelectableText(
              output[i],
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Color(0xFFD4D4D4),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CommandInput extends StatelessWidget {
  const _CommandInput({
    required this.controller,
    required this.enabled,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool enabled;
  final void Function()? onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Text(
            '\$ ',
            style: TextStyle(
              fontFamily: 'monospace',
              color: enabled ? Colors.green : Colors.grey,
              fontSize: 16,
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              decoration: const InputDecoration(
                hintText: '输入命令，Enter 提交',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              onSubmitted: enabled && onSubmit != null ? (_) => onSubmit!() : null,
            ),
          ),
          FilledButton(
            onPressed: enabled && onSubmit != null ? onSubmit : null,
            child: const Text('执行'),
          ),
        ],
      ),
    );
  }
}
