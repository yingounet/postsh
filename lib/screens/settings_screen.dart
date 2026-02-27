import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const List<({String key, String label})> _seedColorOptions = [
    (key: 'blue', label: '蓝'),
    (key: 'green', label: '绿'),
    (key: 'purple', label: '紫'),
    (key: 'orange', label: '橙'),
  ];

  static const List<({double scale, String label})> _fontScaleOptions = [
    (scale: 0.9, label: '小'),
    (scale: 1.0, label: '中'),
    (scale: 1.2, label: '大'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: settingsAsync.when(
        data: (s) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '主题',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
            ),
            ListTile(
              title: const Text('主题模式'),
              subtitle: Text(_themeModeLabel(s.themeMode)),
              trailing: DropdownButton<ThemeMode>(
                value: s.themeMode,
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text('浅色'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.dark,
                    child: Text('深色'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('跟随系统'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    ref.read(settingsProvider.notifier).updateThemeMode(v);
                  }
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('主题色'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                children: _seedColorOptions.map((o) {
                  final selected = s.seedColorKey == o.key;
                  return FilterChip(
                    label: Text(o.label),
                    selected: selected,
                    onSelected: (_) {
                      ref
                          .read(settingsProvider.notifier)
                          .updateSeedColor(o.key);
                    },
                  );
                }).toList(),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(
                '字体',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<double>(
                segments: _fontScaleOptions
                    .map((o) => ButtonSegment<double>(
                          value: o.scale,
                          label: Text(o.label),
                        ))
                    .toList(),
                selected: {
                  _fontScaleOptions
                      .map((o) => o.scale)
                      .fold<double>(
                        _fontScaleOptions.first.scale,
                        (best, scale) =>
                            (s.fontScale - scale).abs() <
                                (s.fontScale - best).abs()
                            ? scale
                            : best,
                      )
                },
                onSelectionChanged: (set) {
                  final v = set.isNotEmpty ? set.first : 1.0;
                  ref.read(settingsProvider.notifier).updateFontScale(v);
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(
                '终端',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
            ),
            SwitchListTile(
              title: const Text('使用 PTY（支持 tmux/screen）'),
              subtitle: const Text(
                '开启后可在远程使用 tmux、screen 等需终端的程序',
              ),
              value: s.usePty,
              onChanged: (v) {
                ref.read(settingsProvider.notifier).updateUsePty(v);
              },
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载失败: $e', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(settingsProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _themeModeLabel(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }
}
