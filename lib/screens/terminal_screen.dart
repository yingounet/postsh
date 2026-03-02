import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../data/static_commands.dart';
import '../providers/connections_provider.dart';
import '../providers/session_provider.dart';
import '../services/completion_service.dart';
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
  final _inputFocusNode = FocusNode();
  final Set<String> _lastUsedUpdated = {};
  final List<String> _history = [];
  List<String> _suggestions = [];
  int _selectedIndex = 0;
  String? _historyKey;
  bool _loadingHistory = false;

  @override
  void initState() {
    super.initState();
    final key =
        widget.initialConnectionId ??
        sessionKeyFromConfig(widget.initialConfig);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(sessionsProvider.notifier)
          .addOrSwitchToTab(key, widget.initialConfig);
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _maybeLoadHistory(ConnectionConfig config) async {
    final key = StorageService.historyKeyFromConfig(config);
    if (_historyKey == key || _loadingHistory) return;
    _loadingHistory = true;
    try {
      final history = await StorageService.getCommandHistory(key);
      if (!mounted) return;
      setState(() {
        _historyKey = key;
        _history
          ..clear()
          ..addAll(history);
        _suggestions = [];
        _selectedIndex = 0;
      });
    } finally {
      _loadingHistory = false;
    }
  }

  void _updateSuggestions(String value) {
    final suggestions = CompletionService.buildSuggestions(
      input: value,
      history: _history,
      staticCommands: staticUnixCommands,
    );
    setState(() {
      _suggestions = suggestions;
      _selectedIndex = 0;
    });
  }

  void _applySelectedSuggestion() {
    if (_suggestions.isEmpty) return;
    final suggestion = _suggestions[_selectedIndex];
    final nextText = CompletionService.applySuggestion(
      _inputController.text,
      suggestion,
    );
    _inputController.text = nextText;
    _inputController.selection = TextSelection.collapsed(
      offset: _inputController.text.length,
    );
    _updateSuggestions(_inputController.text);
  }

  void _handleKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;
    if (_suggestions.isEmpty) return;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % _suggestions.length;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex =
            (_selectedIndex - 1 + _suggestions.length) % _suggestions.length;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      _applySelectedSuggestion();
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() {
        _suggestions = [];
        _selectedIndex = 0;
      });
    }
  }

  void _submitCommand() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    final currentId = ref.read(sessionsProvider).currentSessionId;
    if (currentId == null) return;
    ref.read(sessionsProvider.notifier).addCommand(currentId, text);
    if (_historyKey != null) {
      StorageService.addCommandHistory(_historyKey!, text);
      _history.removeWhere((e) => e == text);
      _history.insert(0, text);
    }
    _inputController.clear();
    setState(() {
      _suggestions = [];
      _selectedIndex = 0;
    });
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
    if (config != null) {
      _maybeLoadHistory(config);
    }

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
          if (sessionState != null &&
              (sessionState.status == ConnectionStatus.disconnected ||
                  sessionState.status == ConnectionStatus.error))
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                final id = ref.read(sessionsProvider).currentSessionId;
                if (id != null) {
                  ref.read(sessionsProvider.notifier).reconnect(id);
                }
              },
              tooltip: '重连',
            ),
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
                          onPressed: () => Navigator.of(context).pop(),
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
              focusNode: _inputFocusNode,
              enabled: sessionState?.status == ConnectionStatus.connected,
              onSubmit: _submitCommand,
              onChanged: _updateSuggestions,
              onKey: _handleKey,
              suggestions: _suggestions,
              selectedIndex: _selectedIndex,
              onSuggestionTap: (value) {
                _inputController.text = CompletionService.applySuggestion(
                  _inputController.text,
                  value,
                );
                _inputController.selection = TextSelection.collapsed(
                  offset: _inputController.text.length,
                );
                _updateSuggestions(_inputController.text);
                _inputFocusNode.requestFocus();
              },
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
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
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
  const _StatusChip({required this.status, this.errorMessage});

  final ConnectionStatus status;
  final String? errorMessage;

  void _showErrorDialog(BuildContext context) {
    final message = errorMessage ?? '';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('错误原因'),
        content: SingleChildScrollView(child: SelectableText(message)),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message));
              ScaffoldMessenger.of(
                ctx,
              ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
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
    final isErrorWithMessage =
        status == ConnectionStatus.error &&
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
  const _OutputArea({required this.output, required this.scrollController});

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

class _CommandInput extends StatefulWidget {
  const _CommandInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSubmit,
    required this.onChanged,
    required this.onKey,
    required this.suggestions,
    required this.selectedIndex,
    required this.onSuggestionTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final void Function()? onSubmit;
  final void Function(String value) onChanged;
  final void Function(RawKeyEvent event) onKey;
  final List<String> suggestions;
  final int selectedIndex;
  final void Function(String value) onSuggestionTap;

  @override
  State<_CommandInput> createState() => _CommandInputState();
}

class _CommandInputState extends State<_CommandInput> {
  final _keyboardFocusNode = FocusNode();

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.suggestions.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.suggestions.length,
                  itemBuilder: (context, i) {
                    final item = widget.suggestions[i];
                    final selected = i == widget.selectedIndex;
                    return InkWell(
                      onTap: () => widget.onSuggestionTap(item),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        color: selected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Colors.transparent,
                        child: Text(
                          item,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          Row(
            children: [
              Text(
                '\$ ',
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: widget.enabled ? Colors.green : Colors.grey,
                  fontSize: 16,
                ),
              ),
              Expanded(
                child: RawKeyboardListener(
                  focusNode: _keyboardFocusNode,
                  onKey: widget.onKey,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    enabled: widget.enabled,
                    decoration: const InputDecoration(
                      hintText: '输入命令，Enter 提交',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                    onChanged: widget.onChanged,
                    onSubmitted: widget.enabled && widget.onSubmit != null
                        ? (_) => widget.onSubmit!()
                        : null,
                  ),
                ),
              ),
              FilledButton(
                onPressed: widget.enabled && widget.onSubmit != null
                    ? widget.onSubmit
                    : null,
                child: const Text('执行'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
