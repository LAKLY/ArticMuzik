part of 'main_screen.dart';

/// Экран поиска с оптимизированной производительностью и управлением фокусом
class _SearchContent extends StatefulWidget {
  final VoidCallback onPlay;
  final Function(Map<String, String>) onLongPressTrack;
  final VoidCallback onRequestSwitchStart;
  final VoidCallback onRequestSwitchEnd;
  final String? currentTrackId;

  const _SearchContent({
    required this.onPlay,
    required this.onLongPressTrack,
    required this.onRequestSwitchStart,
    required this.onRequestSwitchEnd,
    this.currentTrackId,
  });

  @override
  State<_SearchContent> createState() => _SearchContentState();
}

class _SearchContentState extends State<_SearchContent> with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  int? _loadingSearchIndex;
  String? _currentTrackId;
  Timer? _debounceTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _currentTrackId = widget.currentTrackId;
  }

  @override
  void didUpdateWidget(covariant _SearchContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentTrackId != oldWidget.currentTrackId) {
      setState(() {
        _currentTrackId = widget.currentTrackId;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // ========== ВОСПРОИЗВЕДЕНИЕ ИЗ СПИСКА ==========
  Future<void> _playTracksFromList(List<Map<String, String>> tracks, int selectedIndex) async {
    FocusScope.of(context).unfocus();

    final audioHandler = Provider.of<AppAudioHandler>(context, listen: false);
    final provider = Provider.of<YandexAudioProvider>(context, listen: false);

    widget.onRequestSwitchStart();
    setState(() => _loadingSearchIndex = selectedIndex);

    final futures = tracks.map((track) async {
      final trackId = track['trackId']!;
      final url = await provider.getDirectUrl(trackId);
      if (url == null) return null;
      return MediaItem(
        id: url,
        album: "",
        title: track["title"]!,
        artist: track["artist"]!,
        artUri: Uri.parse(track["cover"]!),
        extras: {"trackId": trackId},
      );
    }).toList();

    final items = await Future.wait(futures);
    final validItems = items.whereType<MediaItem>().toList();

    setState(() => _loadingSearchIndex = null);

    if (validItems.isEmpty) {
      widget.onRequestSwitchEnd();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Не удалось загрузить треки")),
      );
      return;
    }

    final selectedTrackId = tracks[selectedIndex]['trackId']!;
    final startIdx = validItems.indexWhere((item) => item.extras?['trackId'] == selectedTrackId);
    if (startIdx == -1) {
      widget.onRequestSwitchEnd();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Не удалось загрузить выбранный трек")),
      );
      return;
    }

    try {
      await audioHandler.ready;
      await audioHandler.setTracksAndPlay(validItems, startIdx);
      widget.onPlay();
      widget.onRequestSwitchEnd();
    } catch (e) {
      widget.onRequestSwitchEnd();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ошибка воспроизведения: $e")),
        );
      }
    }
  }

  Future<void> _onItemTap(BuildContext context, int index, Map<String, String> item) async {
    final provider = Provider.of<YandexAudioProvider>(context, listen: false);
    final type = item['type'];
    if (type == 'artist') {
      final artistName = item['title']!;
      final artistId = item['trackId'];
      final tracks = await provider.getArtistTracks(
        artistName,
        artistId: (artistId != null && artistId.isNotEmpty) ? artistId : null,
      );
      _showTracksDialog('Все треки исполнителя: $artistName', tracks);
    } else if (type == 'album') {
      final albumTitle = item['title']!;
      final artistName = item['artist']!;
      final tracks = await provider.getAlbumTracks(albumTitle, artistName);
      _showTracksDialog('Треки альбома: $albumTitle', tracks);
    } else {
      final allTrackResults = provider.searchResults.where((r) => r['type'] == 'track').toList();
      if (allTrackResults.isNotEmpty) {
        await _playTracksFromList(allTrackResults, index);
      } else {
        await _playTracksFromList([item], 0);
      }
    }
  }

  void _showTracksDialog(String title, List<Map<String, String>> tracks) {
    FocusScope.of(context).unfocus();

    final audioHandler = Provider.of<AppAudioHandler>(context, listen: false);
    showModalBottomSheet(
      context: context,
      backgroundColor: ArticTheme.backgroundDarkest,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: TextStyle(color: ArticTheme.primary, fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: tracks.length,
                itemBuilder: (context, i) {
                  final track = tracks[i];
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: track["cover"]!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: Colors.white10),
                        errorWidget: (_, __, ___) => Container(color: Colors.white10, child: const Icon(Icons.music_note)),
                      ),
                    ),
                    title: Text(track["title"]!, style: TextStyle(color: ArticTheme.primary)),
                    subtitle: Text(track["artist"]!, style: TextStyle(color: ArticTheme.secondary)),
                    onTap: () async {
                      Navigator.pop(context);
                      await _playTracksFromList(tracks, i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _performSearch(String query) {
    _debounceTimer?.cancel();
    if (query.isEmpty) {
      Provider.of<YandexAudioProvider>(context, listen: false).clearSearch();
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        Provider.of<YandexAudioProvider>(context, listen: false).search(query);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final screenWidth = MediaQuery.of(context).size.width;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(screenWidth * 0.04),
          child: Column(
            children: [
              _SearchTextField(
                controller: _controller,
                focusNode: _focusNode,
                onSearch: _performSearch,
                onClear: () {
                  _controller.clear();
                  Provider.of<YandexAudioProvider>(context, listen: false).clearSearch();
                  _focusNode.unfocus();
                },
              ),
              const SizedBox(height: 12),
              _SearchFilters(
                searchType: Provider.of<YandexAudioProvider>(context, listen: false).searchType,
                onTypeChanged: (type) {
                  Provider.of<YandexAudioProvider>(context, listen: false).searchType = type;
                  _focusNode.unfocus();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _SearchResultsList(
            loadingIndex: _loadingSearchIndex,
            currentTrackId: _currentTrackId,
            onItemTap: _onItemTap,
            onLongPress: widget.onLongPressTrack,
          ),
        ),
      ],
    );
  }
}

// ============= ВСПОМОГАТЕЛЬНЫЕ ВИДЖЕТЫ =============

/// Текстовое поле поиска (изолированное)
class _SearchTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Function(String) onSearch;
  final VoidCallback onClear;

  const _SearchTextField({
    required this.controller,
    required this.focusNode,
    required this.onSearch,
    required this.onClear,
  });

  @override
  State<_SearchTextField> createState() => __SearchTextFieldState();
}

class __SearchTextFieldState extends State<_SearchTextField> {
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      style: TextStyle(color: ArticTheme.primary),
      decoration: InputDecoration(
        hintText: 'Поиск музыки...',
        hintStyle: TextStyle(color: ArticTheme.secondary),
        prefixIcon: Icon(Icons.search, color: ArticTheme.accent),
        suffixIcon: Selector<YandexAudioProvider, bool>(
          selector: (_, provider) => provider.isSearching,
          builder: (context, isSearching, child) {
            if (isSearching) {
              return const SizedBox(
                width: 24,
                height: 24,
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return IconButton(
              icon: Icon(Icons.clear, color: ArticTheme.accent),
              onPressed: widget.onClear,
            );
          },
        ),
        filled: true,
        fillColor: ArticTheme.backgroundDarkest.withValues(alpha: 0.6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: ArticTheme.accent, width: 1.5),
        ),
      ),
      onChanged: widget.onSearch,
      onSubmitted: (query) {
        if (query.isNotEmpty) widget.onSearch(query);
      },
    );
  }
}

/// Фильтры поиска
class _SearchFilters extends StatelessWidget {
  final String searchType;
  final ValueChanged<String> onTypeChanged;

  const _SearchFilters({
    required this.searchType,
    required this.onTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _SearchFilterChip(
          label: 'Треки',
          isSelected: searchType == 'track',
          onSelected: () => onTypeChanged('track'),
        ),
        const SizedBox(width: 12),
        _SearchFilterChip(
          label: 'Исполнители',
          isSelected: searchType == 'artist',
          onSelected: () => onTypeChanged('artist'),
        ),
        const SizedBox(width: 12),
        _SearchFilterChip(
          label: 'Альбомы',
          isSelected: searchType == 'album',
          onSelected: () => onTypeChanged('album'),
        ),
      ],
    );
  }
}

class _SearchFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  const _SearchFilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label, style: TextStyle(color: isSelected ? ArticTheme.primary : ArticTheme.secondary)),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      backgroundColor: ArticTheme.backgroundDarkest.withValues(alpha: 0.6),
      selectedColor: ArticTheme.accent,
      checkmarkColor: ArticTheme.primary,
    );
  }
}

/// Список результатов поиска – вынесен в отдельный виджет с подпиской на провайдер
class _SearchResultsList extends StatelessWidget {
  final int? loadingIndex;
  final String? currentTrackId;
  final Future<void> Function(BuildContext, int, Map<String, String>) onItemTap;
  final Function(Map<String, String>) onLongPress;

  const _SearchResultsList({
    required this.loadingIndex,
    required this.currentTrackId,
    required this.onItemTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<YandexAudioProvider>(
      builder: (context, provider, child) {
        final searchResults = provider.searchResults;
        final isSearching = provider.isSearching;

        if (searchResults.isEmpty && !isSearching) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search, size: 64, color: ArticTheme.secondary),
                const SizedBox(height: 16),
                Text("Введите запрос для поиска", style: TextStyle(color: ArticTheme.secondary)),
              ],
            ),
          );
        }

        if (isSearching && searchResults.isEmpty) {
          return Center(child: CircularProgressIndicator(color: ArticTheme.accent));
        }

        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width * 0.04),
          itemCount: searchResults.length,
          itemBuilder: (context, index) {
            final item = searchResults[index];
            final isCurrentTrack = currentTrackId != null && item['trackId'] == currentTrackId;
            return _SearchResultTile(
              key: ValueKey(item['trackId']), // Уникальный ключ
              item: item,
              onTap: () => onItemTap(context, index, item),
              onLongPress: () => onLongPress(item),
              isLoading: loadingIndex == index,
              isCurrentTrack: isCurrentTrack,
            );
          },
        );
      },
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final Map<String, String> item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isLoading;
  final bool isCurrentTrack;

  const _SearchResultTile({
    super.key, // Ключ принимается
    required this.item,
    required this.onTap,
    required this.onLongPress,
    this.isLoading = false,
    this.isCurrentTrack = false,
  });

  @override
  Widget build(BuildContext context) {
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
          color: isCurrentTrack
              ? ArticTheme.accent.withValues(alpha: 0.1)
              : ArticTheme.backgroundDarkest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: isCurrentTrack ? Border.all(color: ArticTheme.accent, width: 1.2) : null,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: item["cover"]!,
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
                        child: Text(item["title"]!,
                            style: TextStyle(
                              color: isCurrentTrack ? ArticTheme.accent : ArticTheme.primary,
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (item["isFavorite"] == "true") Icon(Icons.favorite, size: 16, color: ArticTheme.accent),
                      const SizedBox(width: 4),
                      if (item["cached"] == "true") Icon(Icons.download_done, size: 16, color: ArticTheme.secondary),
                    ],
                  ),
                  Text(item["artist"] ?? '', style: TextStyle(color: isCurrentTrack ? ArticTheme.accent : ArticTheme.secondary, fontSize: 13)),
                ],
              ),
            ),
            if (isLoading)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else if (isCurrentTrack)
              Icon(Icons.equalizer, color: ArticTheme.primary, size: 28)
            else
              Icon(Icons.play_circle_outline, color: ArticTheme.accent.withValues(alpha: 0.7), size: 28),
          ],
        ),
      ),
    );
  }
}