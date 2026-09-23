import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yandex_music/yandex_music.dart';
import '../../utils/log.dart';

import '../cache/track_cache_manager.dart';
import '../history/history_store.dart';
import 'yandex_auth_service.dart';

/// Режим сортировки библиотеки (избранное).
enum LibrarySortMode { dateAdded, title, artist }

extension LibrarySortModeX on LibrarySortMode {
  String get label {
    switch (this) {
      case LibrarySortMode.dateAdded:
        return 'По дате';
      case LibrarySortMode.title:
        return 'По названию';
      case LibrarySortMode.artist:
        return 'По исполнителю';
    }
  }
}

class YandexAudioProvider extends ChangeNotifier {
  final YandexAuthService _authService;
  YandexMusic? _yandexMusic;

  // Списки треков
  List<Map<String, String>> _tracks = [];
  List<Map<String, String>> _searchResults = [];

  // Сортировка библиотеки
  LibrarySortMode _sortMode = LibrarySortMode.dateAdded;
  static const String _sortPrefsKey = 'library_sort';

  // Состояние
  bool _isLoading = false;
  bool _isSearching = false;
  String? _error;
  bool _isInitialized = false;
  bool _disposed = false;
  bool _hasInternet = true;

  // Кэш избранных ID
  final Set<String> _likedTrackIds = {};

  // Кэш стриминговых ссылок
  final Map<String, String> _streamingUrlCache = {};
  final Map<String, DateTime> _streamingUrlCacheTime = {};
  static const Duration _streamingUrlCacheDuration = Duration(minutes: 5);

  // Периодическая проверка сети
  Timer? _connectivityTimer;
  static const Duration _connectivityInterval = Duration(seconds: 45);
  static const Duration _connectivityTimeout = Duration(seconds: 5);

  // Версионирование
  int _loadVersion = 0;
  int _searchVersion = 0;

  // Менеджер кэша
  late final TrackCacheManager cacheManager = TrackCacheManager(
    downloader: _downloadTrackBytes,
  );

  // История прослушиваний
  late final HistoryStore historyStore = HistoryStore();

  // Отложенная запись в историю
  Timer? _historyDebounce;
  String? _pendingHistoryTrackId;
  static const Duration _historyDelay = Duration(seconds: 5);

  // Поиск
  String _searchType = 'track';
  String get searchType => _searchType;
  set searchType(String value) {
    if (_searchType != value) {
      _searchType = value;
      if (_currentSearchQuery.isNotEmpty) {
        search(_currentSearchQuery);
      }
      notifyListeners();
    }
  }

  String _currentSearchQuery = '';

  // Геттеры
  List<Map<String, String>> get tracks => _tracks;
  List<Map<String, String>> get searchResults => _searchResults;
  List<Map<String, String>> get cachedTracks => cacheManager.pinnedEntries
      .map((e) => e.toUiMap())
      .toList(growable: false);
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  String? get error => _error;
  bool get hasInternet => _hasInternet;
  bool get isReady => _isInitialized && _error == null;

  LibrarySortMode get sortMode => _sortMode;

  bool isDownloading(String trackId) => cacheManager.isDownloading(trackId);
  bool isTrackPinned(String trackId) => cacheManager.isPinned(trackId);

  YandexAudioProvider(this._authService);

  // ---- ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ----
  String _getFullCoverUrl(String? coverUri) {
    if (coverUri == null || coverUri.isEmpty) return '';
    if (coverUri.startsWith('http')) return coverUri;
    return 'https://${coverUri.replaceFirst('%%', '200x200')}';
  }

  int _intOf(String? s) => int.tryParse(s ?? '') ?? 0;

  Future<bool> _validateToken() async {
    if (_yandexMusic == null) return false;
    try {
      await _yandexMusic!.search.tracks('test');
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<List<int>> _downloadTrackBytes(String trackId) async {
    if (_yandexMusic == null) {
      throw StateError('YandexMusic не инициализирован');
    }
    return _yandexMusic!.tracks
        .download(trackId, quality: AudioQuality.lossless);
  }

  void _onCacheChanged() {
    if (_disposed) return;
    bool changed = false;
    for (final t in _tracks) {
      final id = t['trackId'];
      if (id == null) continue;
      final isPinned = cacheManager.isPinned(id) ? 'true' : 'false';
      if (t['cached'] != isPinned) {
        t['cached'] = isPinned;
        changed = true;
      }
    }
    for (final t in _searchResults) {
      final id = t['trackId'];
      if (id == null) continue;
      final isPinned = cacheManager.isPinned(id) ? 'true' : 'false';
      if (t['cached'] != isPinned) {
        t['cached'] = isPinned;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void _markOffline() {
    if (_disposed) return;
    if (_hasInternet) {
      _hasInternet = false;
      notifyListeners();
      debugPrint('Network: offline');
    }
  }

  void _markOnline() {
    if (_disposed) return;
    if (!_hasInternet) {
      _hasInternet = true;
      notifyListeners();
      debugPrint('Network: online');
    }
  }

  @override
  void notifyListeners() {
    ArticLog.evt('Provider.notifyListeners',
        'tracks=${_tracks.length} search=${_searchResults.length} loading=$_isLoading');
    super.notifyListeners();
  }

  // ---- СОРТИРОВКА ----

  Future<void> _loadSortMode() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_sortPrefsKey) ?? 'dateAdded';
    _sortMode = LibrarySortMode.values.firstWhere(
      (m) => m.name == s,
      orElse: () => LibrarySortMode.dateAdded,
    );
  }

  Future<void> setSortMode(LibrarySortMode mode) async {
    if (_sortMode == mode) return;
    _sortMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortPrefsKey, mode.name);
    _applySortInPlace();
    notifyListeners();
  }

  /// Сортирует `_tracks` на месте. Список тот же инстанс —
  /// любой, кто держит ссылку, увидит новый порядок.
  void _applySortInPlace() {
    switch (_sortMode) {
      case LibrarySortMode.dateAdded:
        _tracks.sort((a, b) =>
            _intOf(a['_sortIndex']).compareTo(_intOf(b['_sortIndex'])));
        break;
      case LibrarySortMode.title:
        _tracks.sort((a, b) => (a['title'] ?? '')
            .toLowerCase()
            .compareTo((b['title'] ?? '').toLowerCase()));
        break;
      case LibrarySortMode.artist:
        _tracks.sort((a, b) {
          final c = (a['artist'] ?? '')
              .toLowerCase()
              .compareTo((b['artist'] ?? '').toLowerCase());
          if (c != 0) return c;
          return (a['title'] ?? '')
              .toLowerCase()
              .compareTo((b['title'] ?? '').toLowerCase());
        });
        break;
    }
  }

  // ---- ИНИЦИАЛИЗАЦИЯ ----
  Future<void> init() async {
    if (_isInitialized) return;
    final token = await _authService.getAccessToken();
    if (token == null) return;
    try {
      _yandexMusic = YandexMusic(token: token);
      await _yandexMusic!.init();
      if (!await _validateToken()) {
        _error = 'Неверный или просроченный токен';
        return;
      }

      await _loadSortMode();

      cacheManager.addListener(_onCacheChanged);
      await cacheManager.init();

      await historyStore.init();

      _isInitialized = true;
      await loadFavorites();
      _startConnectivityWatch();
      if (!_disposed) notifyListeners();
    } catch (e) {
      _error = e.toString();
      if (!_disposed) notifyListeners();
    }
  }

  void _startConnectivityWatch() {
    _connectivityTimer?.cancel();
    _connectivityTimer = Timer.periodic(_connectivityInterval, (_) {
      if (_disposed || !_isInitialized) return;
      if (!_hasInternet) checkConnectivity();
    });
  }

  // ---- ЗАГРУЗКА ИЗБРАННЫХ ----
  Future<void> loadFavorites() async {
    if (!_isInitialized || _yandexMusic == null) {
      ArticLog.evt('Provider.loadFavorites.skipped');
      return;
    }

    final int currentVersion = ++_loadVersion;
    _isLoading = true;
    _error = null;
    if (!_disposed) notifyListeners();
    ArticLog.tick('Provider.loadFavorites.begin');

    try {
      final likedTracks = await _yandexMusic!.usertracks.getLiked();
      ArticLog.tick('Provider.getLiked.done', 'count=${likedTracks.length}');
      if (currentVersion != _loadVersion) {
        ArticLog.evt('Provider.loadFavorites.stale');
        return;
      }

      _likedTrackIds.clear();
      for (final short in likedTracks) {
        _likedTrackIds.add(short.trackID);
      }

      if (likedTracks.isEmpty) {
        _tracks = [];
        _markOnline();
        return;
      }

      final trackIds = likedTracks.map((short) => short.trackID).toList();
      final fullTracks = await _yandexMusic!.tracks.getTracks(trackIds);
      ArticLog.tick('Provider.getTracks.done', 'count=${fullTracks.length}');
      if (currentVersion != _loadVersion) return;

      final List<Map<String, String>> tracksList = [];
      for (int i = 0; i < fullTracks.length; i++) {
        final track = fullTracks[i];
        tracksList.add({
          'title': track.title,
          'artist': track.artists.map((a) => a.title).join(', '),
          'url': '',
          'cover': _getFullCoverUrl(track.coverUri),
          'cached': cacheManager.isPinned(track.id) ? 'true' : 'false',
          'trackId': track.id,
          'isFavorite': 'true',
          // внутренний индекс для "по дате добавления"
          '_sortIndex': i.toString(),
        });
      }
      _tracks = tracksList;
      _applySortInPlace();
      _markOnline();
      if (!_disposed) notifyListeners();
      ArticLog.tick('Provider.loadFavorites.notified');
    } catch (e) {
      ArticLog.tick('Provider.loadFavorites.error', e);
      if (currentVersion != _loadVersion) return;
      _markOffline();
      _error = e.toString();
      if (!_disposed) notifyListeners();
    } finally {
      if (currentVersion == _loadVersion) {
        _isLoading = false;
        if (!_disposed) notifyListeners();
      }
      ArticLog.tick('Provider.loadFavorites.finally');
    }
  }

  // ---- ПОИСК ----
  Future<void> search(String query, {String? type}) async {
    if (!_isInitialized || _yandexMusic == null) return;
    if (query.isEmpty) return;

    final int currentVersion = ++_searchVersion;
    _currentSearchQuery = query;
    final searchType = type ?? _searchType;
    _isSearching = true;
    _error = null;
    if (!_disposed) notifyListeners();

    try {
      final List<Map<String, String>> resultsList = [];

      if (searchType == 'track') {
        final tracks = await _yandexMusic!.search.tracks(query);
        if (currentVersion != _searchVersion) return;
        for (final track in tracks) {
          if (currentVersion != _searchVersion) return;
          final isFav = _likedTrackIds.contains(track.id);
          resultsList.add({
            'title': track.title,
            'artist': track.artists.map((a) => a.title).join(', '),
            'url': '',
            'cover': _getFullCoverUrl(track.coverUri),
            'cached': cacheManager.isPinned(track.id) ? 'true' : 'false',
            'trackId': track.id,
            'isFavorite': isFav ? 'true' : 'false',
            'type': 'track',
          });
        }
      } else if (searchType == 'artist') {
        final artists = await _yandexMusic!.search.artists(query);
        if (currentVersion != _searchVersion) return;
        for (final artist in artists) {
          if (currentVersion != _searchVersion) return;
          String cover = '';
          String artistId = '';
          if (artist is OfficialArtist) {
            cover = _getFullCoverUrl(artist.coverUri);
            artistId = artist.id;
          }
          resultsList.add({
            'title': artist.title,
            'artist': '',
            'cover': cover,
            'cached': 'false',
            'trackId': artistId,
            'isFavorite': 'false',
            'type': 'artist',
          });
        }
      } else if (searchType == 'album') {
        final albums = await _yandexMusic!.search.albums(query);
        if (currentVersion != _searchVersion) return;
        for (final album in albums) {
          if (currentVersion != _searchVersion) return;
          resultsList.add({
            'title': album.title,
            'artist': album.artists.map((a) => a.title).join(', '),
            'cover': _getFullCoverUrl(album.coverUri),
            'cached': 'false',
            'trackId': album.id.toString(),
            'isFavorite': 'false',
            'type': 'album',
          });
        }
      }

      if (currentVersion != _searchVersion) return;
      _searchResults = resultsList;
      _markOnline();
      if (!_disposed) notifyListeners();
    } catch (e) {
      if (currentVersion != _searchVersion) return;
      _markOffline();
      _error = e.toString();
      if (!_disposed) notifyListeners();
    } finally {
      if (currentVersion == _searchVersion) {
        _isSearching = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  // ---- ИЗБРАННОЕ ----
  Future<bool> isTrackFavorite(String trackId) async {
    if (_likedTrackIds.isEmpty && _isInitialized) {
      try {
        final liked = await _yandexMusic!.usertracks.getLiked();
        _likedTrackIds.clear();
        for (final short in liked) {
          _likedTrackIds.add(short.trackID);
        }
      } catch (e) {
        return false;
      }
    }
    return _likedTrackIds.contains(trackId);
  }

  Future<bool> likeTrack(String trackId) async {
    if (!_isInitialized || _yandexMusic == null) return false;
    try {
      await _yandexMusic!.usertracks.like([trackId]);
      _likedTrackIds.add(trackId);
      _updateFavoriteStatus(trackId, true);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> unlikeTrack(String trackId) async {
    if (!_isInitialized || _yandexMusic == null) return false;
    try {
      await _yandexMusic!.usertracks.unlike([trackId]);
      _likedTrackIds.remove(trackId);
      _updateFavoriteStatus(trackId, false);
      return true;
    } catch (e) {
      return false;
    }
  }

  void _updateFavoriteStatus(String trackId, bool isFav) {
    bool changed = false;
    for (var track in _tracks) {
      if (track['trackId'] == trackId) {
        track['isFavorite'] = isFav ? 'true' : 'false';
        changed = true;
      }
    }
    for (var track in _searchResults) {
      if (track['trackId'] == trackId) {
        track['isFavorite'] = isFav ? 'true' : 'false';
        changed = true;
      }
    }
    if (changed && !_disposed) notifyListeners();
  }

  // ---- ССЫЛКИ ДЛЯ ВОСПРОИЗВЕДЕНИЯ ----
  Future<String?> getDirectUrl(String trackId) async {
    final local = await cacheManager.get(trackId);
    if (local != null) return local;

    if (!_hasInternet) return null;

    final cachedUrl = _streamingUrlCache[trackId];
    final cachedTime = _streamingUrlCacheTime[trackId];
    if (cachedUrl != null &&
        cachedTime != null &&
        DateTime.now().difference(cachedTime) < _streamingUrlCacheDuration) {
      return cachedUrl;
    }

    final url = await getStreamingUrl(trackId);
    if (url != null) {
      _streamingUrlCache[trackId] = url;
      _streamingUrlCacheTime[trackId] = DateTime.now();
    }
    return url;
  }

  Future<String?> getStreamingUrl(String trackId, {AudioQuality? quality}) async {
    if (_yandexMusic == null) return null;
    try {
      final link = await _yandexMusic!.tracks.getDownloadLink(
        trackId,
        quality: quality ?? AudioQuality.normal,
      );
      if (link.isEmpty) return null;
      if (!link.startsWith('http://') && !link.startsWith('https://')) {
        return 'https://$link';
      }
      return link;
    } catch (e) {
      debugPrint('getStreamingUrl error for $trackId: $e');
      _streamingUrlCache.remove(trackId);
      _streamingUrlCacheTime.remove(trackId);
      _markOffline();
      return null;
    }
  }

  void preloadNextTrack(String? nextTrackId) {
    if (nextTrackId == null || nextTrackId.isEmpty) return;
    if (!_hasInternet) return;
    if (_streamingUrlCache.containsKey(nextTrackId)) return;
    if (cacheManager.isCached(nextTrackId)) return;

    getStreamingUrl(nextTrackId).then((url) {
      if (url != null && !_disposed) {
        _streamingUrlCache[nextTrackId] = url;
        _streamingUrlCacheTime[nextTrackId] = DateTime.now();
      }
    });
  }

  // ---- ИСТОРИЯ ----
  void scheduleHistoryAdd({
    required String trackId,
    required String title,
    required String artist,
    required String cover,
  }) {
    if (trackId.isEmpty) return;
    if (_pendingHistoryTrackId == trackId) return;

    _historyDebounce?.cancel();
    _pendingHistoryTrackId = trackId;

    _historyDebounce = Timer(_historyDelay, () async {
      if (_disposed) return;
      if (_pendingHistoryTrackId != trackId) return;
      await historyStore.add(
        trackId: trackId,
        title: title,
        artist: artist,
        cover: cover,
      );
      _pendingHistoryTrackId = null;
    });
  }

  Future<void> clearHistory() async {
    _historyDebounce?.cancel();
    _pendingHistoryTrackId = null;
    await historyStore.clear();
  }

  // ---- СЕТЬ ----
  Future<bool> checkConnectivity() async {
    if (_yandexMusic == null) return false;
    try {
      await _yandexMusic!.search.tracks('a').timeout(_connectivityTimeout);
      _markOnline();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- ИСПОЛНИТЕЛЬ / АЛЬБОМ ----
  Future<List<Map<String, String>>> getArtistTracks(String artistName,
      {String? artistId}) async {
    if (!_isInitialized || _yandexMusic == null) return [];
    try {
      final albums = await _yandexMusic!.search.albums(artistName);
      final filteredAlbums = albums.where((album) {
        return album.artists.any((artist) {
          if (artistId != null &&
              artist is OfficialArtist &&
              artist.id == artistId) return true;
          return artist.title.toLowerCase() == artistName.toLowerCase();
        });
      }).toList();
      Set<String> trackIds = {};
      List<Map<String, String>> allTracks = [];
      for (final album in filteredAlbums) {
        try {
          final albumId = int.parse(album.id);
          final rawAlbum = await _yandexMusic!.albums.getAlbum(albumId);
          final volumes = rawAlbum['volumes'] as List?;
          if (volumes != null) {
            for (final volume in volumes) {
              final tracks = volume as List;
              for (final trackJson in tracks) {
                final track = Track(trackJson);
                if (!trackIds.contains(track.id)) {
                  trackIds.add(track.id);
                  allTracks.add({
                    'title': track.title,
                    'artist': track.artists.map((a) => a.title).join(', '),
                    'cover': _getFullCoverUrl(track.coverUri),
                    'trackId': track.id,
                  });
                }
              }
            }
          }
        } catch (e) {
          debugPrint('getArtistTracks album error: $e');
        }
      }
      if (allTracks.isEmpty) {
        return await _fallbackArtistTracks(artistName, artistId: artistId);
      }
      return allTracks;
    } catch (e) {
      return await _fallbackArtistTracks(artistName, artistId: artistId);
    }
  }

  Future<List<Map<String, String>>> _fallbackArtistTracks(String artistName,
      {String? artistId}) async {
    try {
      List<Track> allTracks = [];
      int currentPage = 0;
      const int pageSize = 50;
      bool hasMore = true;
      while (hasMore) {
        final searchResult = await _yandexMusic!.search.search(
          artistName,
          types: const [SearchTypes.track],
          page: currentPage,
          pageSize: pageSize,
        );
        final tracksOnPage = searchResult.tracks;
        if (tracksOnPage.isEmpty) break;
        allTracks.addAll(tracksOnPage);
        if (tracksOnPage.length < pageSize) {
          hasMore = false;
        } else {
          currentPage++;
          if (currentPage > 10) hasMore = false;
        }
      }
      final filteredTracks = allTracks.where((track) {
        return track.artists.any((artist) {
          if (artistId != null &&
              artist is OfficialArtist &&
              artist.id == artistId) return true;
          return artist.title.toLowerCase() == artistName.toLowerCase();
        });
      }).toList();
      return filteredTracks.map((track) {
        return {
          'title': track.title,
          'artist': track.artists.map((a) => a.title).join(', '),
          'cover': _getFullCoverUrl(track.coverUri),
          'trackId': track.id,
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, String>>> getAlbumTracks(
      String albumTitle, String artistName) async {
    if (!_isInitialized || _yandexMusic == null) return [];
    try {
      final query = '$artistName $albumTitle';
      List<Track> allTracks = [];
      int currentPage = 0;
      const int pageSize = 50;
      bool hasMore = true;
      while (hasMore) {
        final searchResult = await _yandexMusic!.search.search(
          query,
          types: const [SearchTypes.track],
          page: currentPage,
          pageSize: pageSize,
        );
        final tracksOnPage = searchResult.tracks;
        if (tracksOnPage.isEmpty) break;
        allTracks.addAll(tracksOnPage);
        if (tracksOnPage.length < pageSize) {
          hasMore = false;
        } else {
          currentPage++;
          if (currentPage > 10) hasMore = false;
        }
      }
      final filteredTracks = allTracks.where((track) {
        return track.albums.any(
            (album) => album.title.toLowerCase() == albumTitle.toLowerCase());
      }).toList();
      return filteredTracks.map((track) {
        return {
          'title': track.title,
          'artist': track.artists.map((a) => a.title).join(', '),
          'cover': _getFullCoverUrl(track.coverUri),
          'trackId': track.id,
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // ---- ТЕКСТ / ПОХОЖИЕ / ИСПОЛНИТЕЛЬ ----
  Future<String?> getLyrics(String trackId) async {
    if (!_isInitialized || _yandexMusic == null) return null;
    try {
      final lyrics = await _yandexMusic!.tracks.getLyrics(trackId);
      final response = await http.get(Uri.parse(lyrics.downloadUrl));
      if (response.statusCode == 200) return response.body;
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<Map<String, String>>> getSimilarTracks(String trackId) async {
    if (!_isInitialized || _yandexMusic == null) return [];
    try {
      final similar = await _yandexMusic!.tracks.getSimilar(trackId);
      return similar.map((track) {
        return {
          'title': track.title,
          'artist': track.artists.map((a) => a.title).join(', '),
          'cover': _getFullCoverUrl(track.coverUri),
          'trackId': track.id,
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<String?> getArtistNameFromTrack(String trackId) async {
    if (!_isInitialized || _yandexMusic == null) return null;
    try {
      final track = (await _yandexMusic!.tracks.getTracks([trackId])).first;
      if (track.artists.isNotEmpty) return track.artists.first.title;
      return null;
    } catch (e) {
      return null;
    }
  }

  // ---- КЭШ ----
  Future<void> pinTrackWithMetadata(
      String trackId, String title, String artist, String cover) async {
    await cacheManager.pin(
      trackId: trackId,
      title: title,
      artist: artist,
      cover: cover,
    );
  }

  Future<void> unpinTrack(String trackId) async {
    await cacheManager.unpin(trackId);
  }

  Future<void> reloadCachedTracks() async {
    if (!_disposed) notifyListeners();
  }

  void clearSearch() {
    _searchResults = [];
    _currentSearchQuery = '';
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _connectivityTimer?.cancel();
    _connectivityTimer = null;
    _historyDebounce?.cancel();
    _historyDebounce = null;
    cacheManager.removeListener(_onCacheChanged);
    cacheManager.dispose();
    historyStore.dispose();
    super.dispose();
  }
}