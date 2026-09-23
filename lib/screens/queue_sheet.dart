import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../theme/artic_theme.dart';
import '../services/audio_handler.dart';

class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: ArticTheme.backgroundDarkest,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const QueueSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final handler = Provider.of<AppAudioHandler>(context, listen: false);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return StreamBuilder<List<MediaItem>>(
          stream: handler.queue,
          initialData: handler.queue.value,
          builder: (context, queueSnap) {
            final queue = queueSnap.data ?? [];
            return StreamBuilder<MediaItem?>(
              stream: handler.mediaItem,
              initialData: handler.mediaItem.value,
              builder: (context, mediaSnap) {
                final current = mediaSnap.data;
                final currentId = current?.extras?['trackId'] as String?;

                return Column(
                  children: [
                    _handle(),
                    _header(context, queue, currentId, handler),
                    const Divider(height: 1, color: Colors.white12),
                    Expanded(
                      child: queue.isEmpty
                          ? _empty()
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: queue.length,
                              itemBuilder: (context, i) {
                                final item = queue[i];
                                final id =
                                    item.extras?['trackId'] as String?;
                                final isCurrent =
                                    id != null && id == currentId;
                                return _QueueTile(
                                  key: ValueKey(
                                      '${item.id}_${item.extras?['trackId']}'),
                                  item: item,
                                  index: i,
                                  isCurrent: isCurrent,
                                  onTap: () => handler.skipToQueueItem(i),
                                  onDismissed: () =>
                                      handler.removeFromQueue(i),
                                  onPlayNext: () => _moveToNext(
                                      context, handler, i, isCurrent),
                                  onMoveToEnd: () => _moveToEnd(
                                      context, handler, i, isCurrent),
                                  onRemove: () =>
                                      handler.removeFromQueue(i),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _moveToNext(
      BuildContext context, AppAudioHandler handler, int fromIndex, bool isCurrent) async {
    if (isCurrent) {
      _toast(context, 'Трек уже играет');
      return;
    }
    final currentIdx = handler.queue.value
        .indexWhere((item) => item.id == handler.mediaItem.value?.id);
    if (currentIdx == -1) return;

    // Позиция сразу после текущего
    final target = currentIdx + 1 > fromIndex ? currentIdx + 1 : currentIdx + 1;
    // ReorderableListView не используем — можно напрямую move
    await handler.moveInQueue(fromIndex, target);
    if (context.mounted) _toast(context, 'Играет следующим');
  }

  Future<void> _moveToEnd(
      BuildContext context, AppAudioHandler handler, int fromIndex, bool isCurrent) async {
    if (isCurrent) {
      _toast(context, 'Трек уже играет');
      return;
    }
    final end = handler.queue.value.length;
    await handler.moveInQueue(fromIndex, end);
    if (context.mounted) _toast(context, 'Перемещён в конец');
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: TextStyle(color: ArticTheme.primary)),
        backgroundColor: ArticTheme.backgroundDarkest,
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _handle() {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    List<MediaItem> queue,
    String? currentId,
    AppAudioHandler handler,
  ) {
    final totalSec = queue.fold<int>(
        0, (acc, item) => acc + (item.duration?.inSeconds ?? 0));
    final durationLabel = _formatTotal(totalSec);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Очередь',
                    style: TextStyle(
                      color: ArticTheme.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 2),
                Text(
                  queue.isEmpty
                      ? 'пусто'
                      : '${queue.length} трек(ов) • $durationLabel',
                  style:
                      TextStyle(color: ArticTheme.secondary, fontSize: 12),
                ),
              ],
            ),
          ),
          if (queue.isNotEmpty)
            IconButton(
              icon: Icon(Icons.playlist_remove,
                  color: ArticTheme.secondary, size: 22),
              tooltip: 'Очистить очередь',
              onPressed: () => _confirmClear(context, handler),
            ),
        ],
      ),
    );
  }

  String _formatTotal(int seconds) {
    if (seconds <= 0) return '—';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h} ч ${m} мин';
    return '$m мин';
  }

  Future<void> _confirmClear(
      BuildContext context, AppAudioHandler handler) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ArticTheme.backgroundDarkest,
        title: Text('Очистить очередь?',
            style: TextStyle(color: ArticTheme.primary)),
        content: Text('Воспроизведение остановится.',
            style: TextStyle(color: ArticTheme.secondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена',
                style: TextStyle(color: ArticTheme.secondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text('Очистить', style: TextStyle(color: ArticTheme.accent)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await handler.clearQueue();
      if (context.mounted) Navigator.pop(context);
    }
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.queue_music, size: 48, color: ArticTheme.secondary),
          const SizedBox(height: 12),
          Text('Очередь пуста',
              style: TextStyle(color: ArticTheme.secondary)),
        ],
      ),
    );
  }
}

// ---------- TILE ----------

class _QueueTile extends StatelessWidget {
  final MediaItem item;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onDismissed;
  final VoidCallback onPlayNext;
  final VoidCallback onMoveToEnd;
  final VoidCallback onRemove;

  const _QueueTile({
    super.key,
    required this.item,
    required this.index,
    required this.isCurrent,
    required this.onTap,
    required this.onDismissed,
    required this.onPlayNext,
    required this.onMoveToEnd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('dismiss_${item.id}_$index'),
      direction: isCurrent
          ? DismissDirection.none
          : DismissDirection.endToStart,
      onDismissed: (_) => onDismissed(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.red.withValues(alpha: 0.25),
        child: Icon(Icons.delete_outline, color: Colors.redAccent, size: 26),
      ),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: () => _showActions(context),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: isCurrent
              ? ArticTheme.accent.withValues(alpha: 0.1)
              : Colors.transparent,
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: isCurrent
                    ? Icon(Icons.play_arrow,
                        color: ArticTheme.accent, size: 20)
                    : Text('${index + 1}',
                        style: TextStyle(
                            color: ArticTheme.secondary, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _cover(item.artUri?.toString() ?? ''),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent
                            ? ArticTheme.accent
                            : ArticTheme.primary,
                        fontSize: 14,
                        fontWeight: isCurrent
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.artist ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: ArticTheme.secondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (item.duration != null)
                Text(
                  _fmtDuration(item.duration!),
                  style: TextStyle(
                      color: ArticTheme.secondary.withValues(alpha: 0.6),
                      fontSize: 11),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _cover(String url) {
    if (url.isEmpty) return _placeholder();
    return CachedNetworkImage(
      imageUrl: url,
      width: 40,
      height: 40,
      fit: BoxFit.cover,
      memCacheWidth: 80,
      memCacheHeight: 80,
      errorWidget: (_, __, ___) => _placeholder(),
      placeholder: (_, __) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 40,
      height: 40,
      color: Colors.white10,
      child: const Icon(Icons.music_note, color: Colors.white30, size: 20),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ArticTheme.backgroundDarkest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ArticTheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: ArticTheme.secondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            if (!isCurrent)
              ListTile(
                leading: Icon(Icons.playlist_play,
                    color: ArticTheme.accent, size: 22),
                title: Text('Играть следующим',
                    style: TextStyle(color: ArticTheme.primary)),
                onTap: () {
                  Navigator.pop(ctx);
                  onPlayNext();
                },
              ),
            if (!isCurrent)
              ListTile(
                leading: Icon(Icons.playlist_add,
                    color: ArticTheme.accent, size: 22),
                title: Text('В конец очереди',
                    style: TextStyle(color: ArticTheme.primary)),
                onTap: () {
                  Navigator.pop(ctx);
                  onMoveToEnd();
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Colors.redAccent, size: 22),
              title: Text('Удалить из очереди',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                onRemove();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}