part of 'main_screen.dart';

class _LibraryTabs extends StatefulWidget {
  final List<Map<String, String>> allTracks;
  final List<Map<String, String>> cachedTracks;
  final Function(int) onSelectAllTrack;
  final Function(int) onSelectCachedTrack;
  final bool isLoading;
  final int? loadingIndex;
  final Function(Map<String, String>) onLongPressTrack;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onRefreshCached;
  final bool hasInternet;
  final VoidCallback onRetry;

  const _LibraryTabs({
    required this.allTracks,
    required this.cachedTracks,
    required this.onSelectAllTrack,
    required this.onSelectCachedTrack,
    required this.isLoading,
    required this.loadingIndex,
    required this.onLongPressTrack,
    required this.onRefresh,
    required this.onRefreshCached,
    required this.hasInternet,
    required this.onRetry,
  });

  @override
  State<_LibraryTabs> createState() => __LibraryTabsState();
}

class __LibraryTabsState extends State<_LibraryTabs> with TickerProviderStateMixin {
  late TabController _tabController;
  int _lastSelectedTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    if (!widget.hasInternet) {
      _tabController.index = 1;
      _lastSelectedTab = 1;
    }
    
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    
    final newIndex = _tabController.index;
    
    if (newIndex == 0 && !widget.hasInternet) {
      _tabController.index = _lastSelectedTab;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет интернета, доступен только офлайн-режим'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      _lastSelectedTab = newIndex;
      
      if (newIndex == 1) {
        widget.onRefreshCached();
      }
    }
  }

  @override
  void didUpdateWidget(_LibraryTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (!widget.hasInternet && _tabController.index == 0) {
      _tabController.index = 1;
      _lastSelectedTab = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: ArticTheme.accent,
          unselectedLabelColor: ArticTheme.secondary,
          indicatorColor: ArticTheme.accent,
          tabs: const [
            Tab(text: 'ВСЕ'),
            Tab(text: 'КЭШ'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              widget.hasInternet
                  ? _TrackList(
                      key: const PageStorageKey('all_tracks_list'),
                      tracks: widget.allTracks,
                      onSelectTrack: widget.onSelectAllTrack,
                      isLoading: widget.isLoading,
                      loadingIndex: widget.loadingIndex,
                      onLongPressTrack: widget.onLongPressTrack,
                      onRefresh: widget.onRefresh,
                    )
                  : _buildNoInternetWidget(),
              _TrackList(
                key: const PageStorageKey('cached_tracks_list'),
                tracks: widget.cachedTracks,
                onSelectTrack: widget.onSelectCachedTrack,
                isLoading: false,
                loadingIndex: widget.loadingIndex,
                onLongPressTrack: widget.onLongPressTrack,
                onRefresh: widget.onRefreshCached,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoInternetWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, color: ArticTheme.secondary, size: 48),
          const SizedBox(height: 16),
          Text(
            'Нет подключения к интернету',
            style: TextStyle(color: ArticTheme.secondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: widget.onRetry,
            style: ElevatedButton.styleFrom(backgroundColor: ArticTheme.accent),
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

class _TrackList extends StatefulWidget {
  final List<Map<String, String>> tracks;
  final Function(int) onSelectTrack;
  final bool isLoading;
  final int? loadingIndex;
  final Function(Map<String, String>) onLongPressTrack;
  final Future<void> Function() onRefresh;

  const _TrackList({
    super.key,
    required this.tracks,
    required this.onSelectTrack,
    this.isLoading = false,
    this.loadingIndex,
    required this.onLongPressTrack,
    required this.onRefresh,
  });

  @override
  State<_TrackList> createState() => _TrackListState();
}

class _TrackListState extends State<_TrackList> {
  @override
  Widget build(BuildContext context) {
    final audioHandler = Provider.of<AppAudioHandler>(context);
    final mediaItem = audioHandler.mediaItem.value;
    final isPlaying = audioHandler.playbackState.value.playing;

    if (widget.isLoading && widget.tracks.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.all(kVerticalPadding),
        itemCount: 5,
        itemBuilder: (_, __) => const _SkeletonItem(),
      );
    }

    if (widget.tracks.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      color: ArticTheme.accent,
      child: ListView.builder(
        key: widget.key,
        padding: const EdgeInsets.all(kVerticalPadding),
        itemCount: widget.tracks.length,
        itemBuilder: (context, index) {
          final track = widget.tracks[index];
          final isCurrentTrack = mediaItem != null &&
              (mediaItem.id == track["url"] || 
               mediaItem.extras?['trackId'] == track["trackId"]);

          return _TrackTile(
            key: ValueKey(track['trackId']), // Уникальный ключ
            track: track,
            trackIndex: index,
            isCurrentTrack: isCurrentTrack,
            isPlaying: isPlaying && isCurrentTrack,
            loadingIndex: widget.loadingIndex,
            onTap: () => widget.onSelectTrack(index),
            onLongPress: () => widget.onLongPressTrack(track),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_off, size: 64, color: ArticTheme.secondary),
          const SizedBox(height: 16),
          Text(
            "Нет треков",
            style: TextStyle(color: ArticTheme.secondary),
          ),
          const SizedBox(height: 8),
          Text(
            "Добавьте треки в избранное в Яндекс.Музыке",
            style: TextStyle(
              color: ArticTheme.secondary.withValues(alpha: 0.5),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: widget.onRefresh,
            style: ElevatedButton.styleFrom(backgroundColor: ArticTheme.accent),
            child: Text(
              "Обновить",
              style: TextStyle(color: ArticTheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  final Map<String, String> track;
  final int trackIndex;
  final bool isCurrentTrack;
  final bool isPlaying;
  final int? loadingIndex;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _TrackTile({
    super.key, // Ключ передаётся из списка
    required this.track,
    required this.trackIndex,
    required this.isCurrentTrack,
    required this.isPlaying,
    required this.loadingIndex,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isLoading = loadingIndex == trackIndex;
    
    return InkWell(
      onLongPress: onLongPress,
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      splashColor: ArticTheme.accent.withValues(alpha: 0.3),
      highlightColor: ArticTheme.accent.withValues(alpha: 0.1),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: isCurrentTrack
              ? LinearGradient(
                  colors: [
                    ArticTheme.backgroundDarkest.withValues(alpha: 0.5),
                    Colors.transparent,
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          borderRadius: BorderRadius.circular(20),
          border: isCurrentTrack
              ? Border.all(color: ArticTheme.accent, width: 1.2)
              : null,
          color: isCurrentTrack
              ? null
              : ArticTheme.backgroundDarkest.withValues(alpha: 0.6),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: track["cover"]!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                memCacheWidth: 96,
                memCacheHeight: 96,
                placeholder: (_, __) => const _MusicPlaceholder(),
                errorWidget: (_, __, ___) => const _MusicPlaceholder(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          track["title"]!,
                          style: TextStyle(
                            color: isCurrentTrack
                                ? ArticTheme.primary
                                : ArticTheme.primary.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (track["isFavorite"] == "true")
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.favorite,
                            size: 16,
                            color: ArticTheme.accent,
                          ),
                        ),
                      if (track["cached"] == "true")
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.download_done,
                            size: 16,
                            color: ArticTheme.secondary,
                          ),
                        ),
                    ],
                  ),
                  Text(
                    track["artist"]!,
                    style: TextStyle(color: ArticTheme.secondary, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 28,
              height: 28,
              child: isLoading
                  ? const CircularProgressIndicator(strokeWidth: 2.5)
                  : isCurrentTrack && isPlaying
                      ? Icon(
                          Icons.equalizer,
                          color: ArticTheme.primary,
                          size: 28,
                        )
                      : Icon(
                          Icons.play_circle_outline,
                          color: ArticTheme.accent.withValues(alpha: 0.7),
                          size: 28,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonItem extends StatelessWidget {
  const _SkeletonItem();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ArticTheme.backgroundDarkest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 16,
                  color: Colors.white10,
                ),
                const SizedBox(height: 8),
                Container(
                  width: 100,
                  height: 12,
                  color: Colors.white10,
                ),
              ],
            ),
          ),
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: Colors.white10,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _MusicPlaceholder extends StatelessWidget {
  const _MusicPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      color: Colors.white10,
      child: const Icon(Icons.music_note, color: Colors.white38),
    );
  }
}