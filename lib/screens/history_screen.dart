import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../theme/artic_theme.dart';
import '../services/audio_handler.dart';
import '../services/yandex/yandex_audio_provider.dart';
import '../services/history/history_store.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<YandexAudioProvider>(context);
    final store = provider.historyStore;

    return Scaffold(
      backgroundColor: ArticTheme.backgroundDeep,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: ArticTheme.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('История', style: TextStyle(color: ArticTheme.primary)),
        actions: [
          AnimatedBuilder(
            animation: store,
            builder: (context, _) {
              if (store.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(Icons.delete_outline, color: ArticTheme.secondary),
                tooltip: 'Очистить историю',
                onPressed: () => _confirmClear(context, provider),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          if (store.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: ArticTheme.secondary),
                  const SizedBox(height: 16),
                  Text('История пуста',
                      style: TextStyle(color: ArticTheme.secondary)),
                  const SizedBox(height: 8),
                  Text(
                    'Треки, которые вы слушали больше 5 секунд,\nпоявятся здесь',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ArticTheme.secondary.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }

          final groups = _groupByDay(store.entries);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _playAllBanner(context, provider, store.entries),
              const SizedBox(height: 16),
              for (final g in groups) ...[
                _sectionHeader(g.label),
                const SizedBox(height: 8),
                for (final entry in g.entries) ...[
                  _HistoryTile(
                    entry: entry,
                    onTap: () => _playFromHistory(
                      context,
                      provider,
                      store.entries,
                      entry.trackId,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                const SizedBox(height: 20),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(
      BuildContext context, YandexAudioProvider provider) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ArticTheme.backgroundDarkest,
        title: Text('Очистить историю?',
            style: TextStyle(color: ArticTheme.primary)),
        content: Text('Все записи будут удалены.',
            style: TextStyle(color: ArticTheme.secondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена',
                style: TextStyle(color: ArticTheme.secondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Очистить',
                style: TextStyle(color: ArticTheme.accent)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await provider.clearHistory();
    }
  }

  Widget _playAllBanner(BuildContext context, YandexAudioProvider provider,
      List<PlayHistoryEntry> entries) {
    return GestureDetector(
      onTap: () =>
          _playFromHistory(context, provider, entries, entries.first.trackId),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: ArticTheme.surfaceGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ArticTheme.accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: ArticTheme.accentGradient,
                boxShadow: ArticTheme.glow(radius: 16),
              ),
              child: Icon(Icons.play_arrow_rounded,
                  color: ArticTheme.primary, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Воспроизвести всё',
                      style: TextStyle(
                        color: ArticTheme.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 2),
                  Text('${entries.length} трек(ов) из истории',
                      style: TextStyle(
                          color: ArticTheme.secondary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Text(
      label,
      style: TextStyle(
        color: ArticTheme.primary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Future<void> _playFromHistory(
    BuildContext context,
    YandexAudioProvider provider,
    List<PlayHistoryEntry> entries,
    String startTrackId,
  ) async {
    final audioHandler = Provider.of<AppAudioHandler>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);

    final futures = entries.map((e) async {
      final url = await provider.getDirectUrl(e.trackId);
      if (url == null || url.isEmpty) return null;
      return MediaItem(
        id: url,
        album: '',
        title: e.title,
        artist: e.artist,
        artUri: e.cover.isNotEmpty ? Uri.parse(e.cover) : null,
        extras: {'trackId': e.trackId},
      );
    }).toList();

    final items = (await Future.wait(futures)).whereType<MediaItem>().toList();

    if (items.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить треки')),
      );
      return;
    }

    final startIdx =
        items.indexWhere((item) => item.extras?['trackId'] == startTrackId);
    if (startIdx == -1) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить выбранный трек')),
      );
      return;
    }

    await audioHandler.ready;
    await audioHandler.setTracksAndPlay(items, startIdx);
  }

  List<_DayGroup> _groupByDay(List<PlayHistoryEntry> entries) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final todayList = <PlayHistoryEntry>[];
    final yesterdayList = <PlayHistoryEntry>[];
    final weekList = <PlayHistoryEntry>[];
    final olderList = <PlayHistoryEntry>[];

    for (final e in entries) {
      final d = DateTime(e.playedAt.year, e.playedAt.month, e.playedAt.day);
      if (d == today) {
        todayList.add(e);
      } else if (d == yesterday) {
        yesterdayList.add(e);
      } else if (d.isAfter(weekAgo)) {
        weekList.add(e);
      } else {
        olderList.add(e);
      }
    }

    final groups = <_DayGroup>[];
    if (todayList.isNotEmpty) groups.add(_DayGroup('Сегодня', todayList));
    if (yesterdayList.isNotEmpty) {
      groups.add(_DayGroup('Вчера', yesterdayList));
    }
    if (weekList.isNotEmpty) {
      groups.add(_DayGroup('На этой неделе', weekList));
    }
    if (olderList.isNotEmpty) groups.add(_DayGroup('Ранее', olderList));
    return groups;
  }
}

class _DayGroup {
  final String label;
  final List<PlayHistoryEntry> entries;
  _DayGroup(this.label, this.entries);
}

class _HistoryTile extends StatelessWidget {
  final PlayHistoryEntry entry;
  final VoidCallback onTap;

  const _HistoryTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: ArticTheme.backgroundDarkest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: entry.cover.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: entry.cover,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      memCacheWidth: 88,
                      memCacheHeight: 88,
                      placeholder: (_, __) => _placeholder(),
                      errorWidget: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
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
                    entry.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: ArticTheme.secondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.play_circle_outline,
                color: ArticTheme.accent.withValues(alpha: 0.7), size: 24),
          ],
        ),
      ),
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