import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/artic_theme.dart';
import '../services/yandex/yandex_audio_provider.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

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
        title: Text('Загрузки', style: TextStyle(color: ArticTheme.primary)),
      ),
      body: AnimatedBuilder(
        animation: cache,
        builder: (context, _) {
          final active = cache.activeDownloadIds;
          final pinned = cache.pinnedEntries;

          if (active.isEmpty && pinned.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_done,
                      size: 64, color: ArticTheme.secondary),
                  const SizedBox(height: 16),
                  Text('Нет загрузок',
                      style: TextStyle(color: ArticTheme.secondary)),
                  const SizedBox(height: 8),
                  Text('Закрепите треки через долгое нажатие',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ArticTheme.secondary.withValues(alpha: 0.5),
                        fontSize: 12,
                      )),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (active.isNotEmpty) ...[
                _sectionHeader('Загружается (${active.length})'),
                const SizedBox(height: 8),
                ...active.map((id) => _ActiveDownloadTile(trackId: id)),
                const SizedBox(height: 24),
              ],
              if (pinned.isNotEmpty) ...[
                _sectionHeader('Готово (${pinned.length})'),
                const SizedBox(height: 8),
                ...pinned.map((e) => _PinnedTile(
                      title: e.title,
                      artist: e.artist,
                      sizeMb: e.sizeBytes / (1024 * 1024),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: TextStyle(
        color: ArticTheme.primary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ActiveDownloadTile extends StatelessWidget {
  final String trackId;
  const _ActiveDownloadTile({required this.trackId});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ArticTheme.backgroundDarkest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: Padding(
              padding: EdgeInsets.all(4),
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFA94E93)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Загрузка трека...',
                    style:
                        TextStyle(color: ArticTheme.primary, fontSize: 14)),
                const SizedBox(height: 2),
                Text('ID: $trackId',
                    style: TextStyle(
                        color: ArticTheme.secondary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PinnedTile extends StatelessWidget {
  final String title;
  final String artist;
  final double sizeMb;

  const _PinnedTile({
    required this.title,
    required this.artist,
    required this.sizeMb,
  });

  String _fmt() {
    if (sizeMb < 1) return '${(sizeMb * 1024).toStringAsFixed(0)} KB';
    return '${sizeMb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ArticTheme.backgroundDarkest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: ArticTheme.accent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: ArticTheme.primary, fontSize: 14)),
                const SizedBox(height: 2),
                Text('$artist • ${_fmt()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: ArticTheme.secondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}