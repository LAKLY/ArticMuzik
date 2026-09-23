import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/artic_theme.dart';
import '../services/yandex/yandex_audio_provider.dart';
import '../services/cache/track_cache_manager.dart';

class StorageManagerScreen extends StatefulWidget {
  const StorageManagerScreen({super.key});

  @override
  State<StorageManagerScreen> createState() => _StorageManagerScreenState();
}

class _StorageManagerScreenState extends State<StorageManagerScreen> {
  bool _busy = false;
  int _totalDiskBytes = 0;
  int _freeDiskBytes = 0;

  @override
  void initState() {
    super.initState();
    _loadDiskInfo();
  }

  Future<void> _loadDiskInfo() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      // Читаем через statvfs-эмуляцию: попытаемся записать тестовый файл
      // и через df на Android это сложно — поэтому берём через FileSystemEntity.
      // В проде — через `disk_space` пакет, но без него ограничимся
      // только тем, что есть.
      _totalDiskBytes = 0;
      _freeDiskBytes = 0;
      // заглушка: в будущем — реальные данные
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('disk info error: $e');
    }
  }

  String _fmtBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  Future<void> _confirmAndRun(
    String title,
    String message,
    Future<void> Function() action,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ArticTheme.backgroundDarkest,
        title: Text(title, style: TextStyle(color: ArticTheme.primary)),
        content: Text(message, style: TextStyle(color: ArticTheme.secondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена',
                style: TextStyle(color: ArticTheme.secondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Подтвердить',
                style: TextStyle(color: ArticTheme.accent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<YandexAudioProvider>(context);
    final cache = provider.cacheManager;

    return Scaffold(
      backgroundColor: ArticTheme.backgroundDeep,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: ArticTheme.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Хранилище', style: TextStyle(color: ArticTheme.primary)),
      ),
      body: AnimatedBuilder(
        animation: cache,
        builder: (context, _) {
          final stats = cache.getStats();
          final pinned = cache.pinnedEntries;
          final temp = cache.tempEntries;

          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _OverviewCard(
                    stats: stats,
                    fmt: _fmtBytes,
                  ),
                  const SizedBox(height: 20),

                  // ---------- Pinned ----------
                  _SectionHeader(
                    title: 'Закреплённые',
                    count: stats.pinnedCount,
                    totalBytes: stats.pinnedBytes,
                    fmt: _fmtBytes,
                    onAction: stats.pinnedCount == 0
                        ? null
                        : () => _confirmAndRun(
                              'Удалить все закреплённые?',
                              'Будет удалено ${stats.pinnedCount} трек(ов) • ${_fmtBytes(stats.pinnedBytes)}.',
                              () async => cache.clearAll(),
                            ),
                    actionLabel: 'Удалить все',
                  ),
                  const SizedBox(height: 8),
                  if (pinned.isEmpty)
                    _EmptySection(
                      icon: Icons.push_pin_outlined,
                      text: 'Нет закреплённых треков',
                      hint: 'Долгое нажатие на трек → «Закрепить в кэше»',
                    )
                  else
                    ...pinned.map((e) => _CacheTile(
                          entry: e,
                          onRemove: () => _confirmAndRun(
                            'Удалить трек?',
                            '«${e.title}» будет удалён из кэша.',
                            () async => cache.unpin(e.trackId),
                          ),
                        )),

                  const SizedBox(height: 24),

                  // ---------- Temp ----------
                  _SectionHeader(
                    title: 'Временный кэш',
                    count: stats.tempCount,
                    totalBytes: stats.tempBytes,
                    fmt: _fmtBytes,
                    onAction: stats.tempCount == 0
                        ? null
                        : () => _confirmAndRun(
                              'Очистить временный кэш?',
                              'Будет удалено ${stats.tempCount} трек(ов) • ${_fmtBytes(stats.tempBytes)}.',
                              () async => cache.clearTemp(),
                            ),
                    actionLabel: 'Очистить',
                  ),
                  const SizedBox(height: 8),
                  if (temp.isEmpty)
                    _EmptySection(
                      icon: Icons.hourglass_empty,
                      text: 'Временный кэш пуст',
                      hint: 'Треки попадают сюда при воспроизведении (макс. 10)',
                    )
                  else
                    ...temp.map((e) => _CacheTile(
                          entry: e,
                          onRemove: null,
                          subtitle: 'Авто-удаление при переполнении',
                        )),

                  const SizedBox(height: 24),

                  // ---------- Info ----------
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: ArticTheme.backgroundDarkest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: ArticTheme.secondary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: ArticTheme.secondary, size: 18),
                            const SizedBox(width: 8),
                            Text('Как работает кэш',
                                style: TextStyle(
                                  color: ArticTheme.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                )),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _InfoLine(
                          dot: ArticTheme.accent,
                          text:
                              'Закреплённые — доступны офлайн, удаляются только вручную',
                        ),
                        const SizedBox(height: 6),
                        _InfoLine(
                          dot: ArticTheme.secondary,
                          text:
                              'Временные — скачиваются на лету, хранятся максимум 10 треков',
                        ),
                        const SizedBox(height: 6),
                        _InfoLine(
                          dot: ArticTheme.secondary.withValues(alpha: 0.5),
                          text:
                              'Формат: lossless (FLAC). Один трек ≈ 25–40 МБ',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
              if (_busy)
                Positioned.fill(
                  child: Container(
                    color: Colors.black54,
                    child: Center(
                      child: CircularProgressIndicator(
                          color: ArticTheme.accent),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------- Overview ----------

class _OverviewCard extends StatelessWidget {
  final CacheStats stats;
  final String Function(int) fmt;

  const _OverviewCard({required this.stats, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final totalBytes = stats.totalBytes;
    final pinnedFraction = totalBytes == 0
        ? 0.0
        : stats.pinnedBytes / totalBytes;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: ArticTheme.surfaceGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ArticTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            height: 110,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 110,
                  height: 110,
                  child: CircularProgressIndicator(
                    value: totalBytes == 0 ? 0.0 : 1.0,
                    strokeWidth: 8,
                    valueColor: AlwaysStoppedAnimation(
                      ArticTheme.accent.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                SizedBox(
                  width: 110,
                  height: 110,
                  child: CircularProgressIndicator(
                    value: pinnedFraction,
                    strokeWidth: 8,
                    valueColor:
                        AlwaysStoppedAnimation(ArticTheme.accent),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${stats.totalCount}',
                      style: TextStyle(
                        color: ArticTheme.primary,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'треков',
                      style: TextStyle(
                        color: ArticTheme.secondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Использовано',
                    style: TextStyle(
                        color: ArticTheme.secondary, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  fmt(totalBytes),
                  style: TextStyle(
                    color: ArticTheme.primary,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                _LegendRow(
                  color: ArticTheme.accent,
                  label: 'Закреплено',
                  value: fmt(stats.pinnedBytes),
                ),
                const SizedBox(height: 4),
                _LegendRow(
                  color: ArticTheme.secondary,
                  label: 'Временный',
                  value: fmt(stats.tempBytes),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: ArticTheme.secondary, fontSize: 12)),
        ),
        Text(value,
            style: TextStyle(
                color: ArticTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ---------- Section header ----------

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final int totalBytes;
  final String Function(int) fmt;
  final VoidCallback? onAction;
  final String actionLabel;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.totalBytes,
    required this.fmt,
    required this.onAction,
    required this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: ArticTheme.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count == 0 ? 'пусто' : '$count • ${fmt(totalBytes)}',
                  style: TextStyle(
                      color: ArticTheme.secondary, fontSize: 12),
                ),
              ],
            ),
          ),
          if (onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(
                actionLabel,
                style: TextStyle(color: ArticTheme.accent, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------- Empty ----------

class _EmptySection extends StatelessWidget {
  final IconData icon;
  final String text;
  final String hint;

  const _EmptySection({
    required this.icon,
    required this.text,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: ArticTheme.backgroundDarkest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: ArticTheme.secondary),
          const SizedBox(height: 8),
          Text(text,
              style: TextStyle(color: ArticTheme.secondary, fontSize: 13)),
          const SizedBox(height: 4),
          Text(hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ArticTheme.secondary.withValues(alpha: 0.5),
                fontSize: 11,
              )),
        ],
      ),
    );
  }
}

// ---------- Cache tile ----------

class _CacheTile extends StatelessWidget {
  final CacheEntry entry;
  final VoidCallback? onRemove;
  final String? subtitle;

  const _CacheTile({
    required this.entry,
    required this.onRemove,
    this.subtitle,
  });

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final cover = entry.cover;
    final Widget tile = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ArticTheme.backgroundDarkest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: cover.isEmpty
                ? _placeholder()
                : CachedNetworkImage(
                    imageUrl: cover,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    memCacheWidth: 88,
                    memCacheHeight: 88,
                    placeholder: (_, __) => _placeholder(),
                    errorWidget: (_, __, ___) => _placeholder(),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ArticTheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.artist} • ${_fmtSize(entry.sizeBytes)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: ArticTheme.secondary, fontSize: 12),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                        color: ArticTheme.secondary.withValues(alpha: 0.5),
                        fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: ArticTheme.secondary, size: 20),
              onPressed: onRemove,
              tooltip: 'Удалить',
            ),
        ],
      ),
    );

    if (onRemove == null) return tile;

    return Dismissible(
      key: ValueKey('storage_${entry.trackId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(14),
        ),
        child:
            Icon(Icons.delete_outline, color: Colors.redAccent, size: 26),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: ArticTheme.backgroundDarkest,
                title: Text('Удалить трек?',
                    style: TextStyle(color: ArticTheme.primary)),
                content: Text('«${entry.title}» будет удалён из кэша.',
                    style: TextStyle(color: ArticTheme.secondary)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('Отмена',
                        style: TextStyle(color: ArticTheme.secondary)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text('Удалить',
                        style: TextStyle(color: ArticTheme.accent)),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => onRemove!(),
      child: tile,
    );
  }

  Widget _placeholder() {
    return Container(
      width: 44,
      height: 44,
      color: Colors.white10,
      child: const Icon(Icons.music_note, color: Colors.white30, size: 22),
    );
  }
}

// ---------- Info line ----------

class _InfoLine extends StatelessWidget {
  final Color dot;
  final String text;

  const _InfoLine({required this.dot, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 5),
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: ArticTheme.secondary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}