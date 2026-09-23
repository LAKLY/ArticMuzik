import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yandex_music/yandex_music.dart';

import 'yandex_auth_service.dart';

class YandexAudioProvider extends ChangeNotifier {
  final YandexAuthService _authService;
  YandexMusic? _yandexMusic;

  // Списки треков
  List<Map<String, String>> _tracks = [];
  List<Map<String, String>> _searchResults = [];
  List<Map<String, String>> _cachedTracks = [];

  // Состояние
  bool _isLoading = false;
  bool _isSearching = false;
  String? _error;
  bool _isInitialized = false;
  bool _disposed = false;
  bool _hasInternet = true;

  // Временный кэш для скачанных (не закреплённых) треков
  final Map<String, String> _tempCache = {};
  final List<String> _tempOrder = [];

  // Закреплённые треки (локальные файлы)
  final Map<String, String> _pinnedCache = {};
  final Set<String> _pinnedTracks = {};

  // Ожидающие загрузки
  final Map<String, Completer<String?>> _pendingDownloads = {};

  // Кэш избранных ID
  final Set<String> _likedTrackIds = {};

  // Кэш стриминговых ссылок
  final Map<String, String> _streamingUrlCache = {};
  final Map<String, DateTime> _streamingUrlCacheTime = {};
  static const Duration _streamingUrlCacheDuration = Duration(minutes: 5);

  // Версионирование для отмены устаревших запросов
  int _loadVersion = 0;
  int _searchVersion = 0;

  static const int _maxTempTracks = 10;

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
  List<Map<String, String>> get cachedTracks => _cachedTracks;
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  String? get error => _error;
  bool get hasInternet => _hasInternet;
  // Добавляем геттер в конец списка геттеров
  bool get isReady => _isInitialized && _error == null; 

  bool isDownloading(String trackId) => _pendingDownloads.containsKey(trackId);
  bool isTrackPinned(String trackId) => _pinnedTracks.contains(trackId);

  YandexAudioProvider(this._authService);

  // ---- ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ----
  String _getFullCoverUrl(String? coverUri) {
    if (coverUri == null || coverUri.isEmpty) return '';
    if (coverUri.startsWith('http')) return coverUri;
    return 'https://${coverUri.replaceFirst('%%', '200x200')}';
  }

  Future<bool> _validateToken() async {
    if (_yandexMusic == null) return false;
    try {
      await _yandexMusic!.search.tracks('test');
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _savePinnedTracks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pinned_tracks', _pinnedTracks.toList());
  }

  Future<void> _loadPinnedTracks() async {
    final prefs = await SharedPreferences.getInstance();
    final pinned = prefs.getStringList('pinned_tracks') ?? [];
    final docsDir = await getApplicationDocumentsDirectory();
    for (final trackId in pinned) {
      final file = File('${docsDir.path}/$trackId.mp3');
      if (await file.exists()) {
        _pinnedCache[trackId] = file.path;
        _pinnedTracks.add(trackId);
      }
    }
  }

  // Загрузка/сохранение метаданных закреплённых треков
  Future<void> loadCachedTracks() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedList = prefs.getStringList('cached_tracks_metadata');
    if (cachedList != null) {
      _cachedTracks = cachedList.map((jsonStr) {
        try {
          final raw = json.decode(jsonStr) as Map<String, dynamic>;
          final map = raw.map((key, value) => MapEntry(key, value.toString()));
          if (!map.containsKey('isFavorite')) {
            map['isFavorite'] = 'true';
          }
          return map;
        } catch (e) {
          return <String, String>{};
        }
      }).where((map) => map.isNotEmpty).toList();
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> reloadCachedTracks() async {
    await loadCachedTracks();
  }

  Future<void> _saveCachedTracks() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = _cachedTracks.map((track) => json.encode(track)).toList();
    await prefs.setStringList('cached_tracks_metadata', encoded);
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
      await _loadPinnedTracks();
      await loadCachedTracks();
      _isInitialized = true;
      await loadFavorites();
      if (!_disposed) notifyListeners();
    } catch (e) {
      _error = e.toString();
      if (!_disposed) notifyListeners();
    }
  }

  // ---- ЗАГРУЗКА ИЗБРАННЫХ (с версионированием) ----
  Future<void> loadFavorites() async {
    if (!_isInitialized || _yandexMusic == null) return;

    final int currentVersion = ++_loadVersion;
    _isLoading = true;
    _error = null;
    if (!_disposed) notifyListeners();

    try {
      final likedTracks = await _yandexMusic!.usertracks.getLiked();
      if (currentVersion != _loadVersion) return;

      _likedTrackIds.clear();
      for (final short in likedTracks) {
        _likedTrackIds.add(short.trackID);
      }

      if (likedTracks.isEmpty) {
        _tracks = [];
        _hasInternet = true;
        return;
      }

      final trackIds = likedTracks.map((short) => short.trackID).toList();
      final fullTracks = await _yandexMusic!.tracks.getTracks(trackIds);
      if (currentVersion != _loadVersion) return;

      final List<Map<String, String>> tracksList = [];
      for (final track in fullTracks) {
        tracksList.add({
          'title': track.title,
          'artist': track.artists.map((a) => a.title).join(', '),
          'url': '',
          'cover': _getFullCoverUrl(track.coverUri),
          'cached': _pinnedTracks.contains(track.id) ? 'true' : 'false',
          'trackId': track.id,
          'isFavorite': 'true',
        });
      }
      _tracks = tracksList;
      _hasInternet = true;
      if (!_disposed) notifyListeners();
    } catch (e) {
      if (currentVersion != _loadVersion) return;
      _hasInternet = false;
      _error = e.toString();
      if (!_disposed) notifyListeners();
    } finally {
      if (currentVersion == _loadVersion) {
        _isLoading = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  // ---- ПОИСК (с версионированием) ----
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
            'cached': _pinnedTracks.contains(track.id) ? 'true' : 'false',
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
      if (!_disposed) notifyListeners();
    } catch (e) {
      if (currentVersion != _searchVersion) return;
      _error = e.toString();
      if (!_disposed) notifyListeners();
    } finally {
      if (currentVersion == _searchVersion) {
        _isSearching = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  // ---- РАБОТА С ИЗБРАННЫМИ ----
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
    for (var track in _tracks) {
      if (track['trackId'] == trackId) {
        track['isFavorite'] = isFav ? 'true' : 'false';
      }
    }
    for (var track in _searchResults) {
      if (track['trackId'] == trackId) {
        track['isFavorite'] = isFav ? 'true' : 'false';
      }
    }
    if (!_disposed) notifyListeners();
  }

  // ---- ПОЛУЧЕНИЕ ССЫЛОК ДЛЯ ВОСПРОИЗВЕДЕНИЯ ----
  Future<String?> getDirectUrl(String trackId) async {
    if (_pinnedCache.containsKey(trackId)) return _pinnedCache[trackId];
    if (_tempCache.containsKey(trackId)) return _tempCache[trackId];

    final cachedUrl = _streamingUrlCache[trackId];
    final cachedTime = _streamingUrlCacheTime[trackId];
    if (cachedUrl != null && cachedTime != null &&
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
      // Удаляем битую ссылку из кэша
      _streamingUrlCache.remove(trackId);
      _streamingUrlCacheTime.remove(trackId);
      return null;
    }
  }

  // ---- ПОЛУЧЕНИЕ ТРЕКОВ ИСПОЛНИТЕЛЯ / АЛЬБОМА ----
  Future<List<Map<String, String>>> getArtistTracks(String artistName, {String? artistId}) async {
    if (!_isInitialized || _yandexMusic == null) return [];
    try {
      final albums = await _yandexMusic!.search.albums(artistName);
      final filteredAlbums = albums.where((album) {
        return album.artists.any((artist) {
          if (artistId != null && artist is OfficialArtist && artist.id == artistId) return true;
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
        } catch (e) {}
      }
      if (allTracks.isEmpty) {
        return await _fallbackArtistTracks(artistName, artistId: artistId);
      }
      return allTracks;
    } catch (e) {
      return await _fallbackArtistTracks(artistName, artistId: artistId);
    }
  }

  Future<List<Map<String, String>>> _fallbackArtistTracks(String artistName, {String? artistId}) async {
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
          if (artistId != null && artist is OfficialArtist && artist.id == artistId) return true;
          return artist.title.toLowerCase() == artistName.toLowerCase();
        });
      }).toList();
      return filteredTracks.map((track) => {
        'title': track.title,
        'artist': track.artists.map((a) => a.title).join(', '),
        'cover': _getFullCoverUrl(track.coverUri),
        'trackId': track.id,
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, String>>> getAlbumTracks(String albumTitle, String artistName) async {
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
        return track.albums.any((album) => album.title.toLowerCase() == albumTitle.toLowerCase());
      }).toList();
      return filteredTracks.map((track) => {
        'title': track.title,
        'artist': track.artists.map((a) => a.title).join(', '),
        'cover': _getFullCoverUrl(track.coverUri),
        'trackId': track.id,
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // ---- ТЕКСТЫ, ПОХОЖИЕ ТРЕКИ, ИНФОРМАЦИЯ ОБ ИСПОЛНИТЕЛЕ ----
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
      return similar.map((track) => {
        'title': track.title,
        'artist': track.artists.map((a) => a.title).join(', '),
        'cover': _getFullCoverUrl(track.coverUri),
        'trackId': track.id,
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

  // ---- ЗАКРЕПЛЕНИЕ В КЭШЕ (С МЕТАДАННЫМИ) ----
  Future<void> pinTrackWithMetadata(String trackId, String title, String artist, String cover) async {
    if (_pinnedTracks.contains(trackId)) return;
    final filePath = await downloadAndCache(trackId);
    if (filePath == null) return;
    _pinnedCache[trackId] = filePath;
    _pinnedTracks.add(trackId);
    final newTrack = {
      'title': title,
      'artist': artist,
      'cover': cover,
      'trackId': trackId,
      'url': filePath,
      'cached': 'true',
      'isFavorite': 'true',
    };
    _cachedTracks.add(newTrack);
    await _saveCachedTracks();
    _updateCachedStatus(trackId, true);
    _savePinnedTracks();
    if (!_disposed) notifyListeners();
  }

  void unpinTrack(String trackId) async {
    if (!_pinnedTracks.contains(trackId)) return;
    final filePath = _pinnedCache.remove(trackId);
    if (filePath != null) File(filePath).delete();
    _pinnedTracks.remove(trackId);
    _cachedTracks.removeWhere((track) => track['trackId'] == trackId);
    await _saveCachedTracks();
    _updateCachedStatus(trackId, false);
    _savePinnedTracks();
    if (!_disposed) notifyListeners();
  }

  void _updateCachedStatus(String trackId, bool pinned) {
    for (var track in _tracks) {
      if (track['trackId'] == trackId) track['cached'] = pinned ? 'true' : 'false';
    }
    for (var track in _searchResults) {
      if (track['trackId'] == trackId) track['cached'] = pinned ? 'true' : 'false';
    }
    if (!_disposed) notifyListeners();
  }

  // ---- ЗАГРУЗКА / ВРЕМЕННОЕ КЭШИРОВАНИЕ ----
  void cancelAllDownloads() {
    for (var completer in _pendingDownloads.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pendingDownloads.clear();
    if (!_disposed) notifyListeners();
  }

  Future<String?> downloadAndCache(String trackId) async {
    if (!_isInitialized || _yandexMusic == null) return null;
    if (_pinnedCache.containsKey(trackId)) return _pinnedCache[trackId];
    if (_tempCache.containsKey(trackId)) return _tempCache[trackId];
    if (_pendingDownloads.containsKey(trackId)) {
      return await _pendingDownloads[trackId]!.future;
    }
    final completer = Completer<String?>();
    _pendingDownloads[trackId] = completer;
    if (!_disposed) notifyListeners();
    try {
      final bytes = await _yandexMusic!.tracks.download(trackId, quality: AudioQuality.lossless);
      final docsDir = await getApplicationDocumentsDirectory();
      final file = File('${docsDir.path}/$trackId.mp3');
      await file.writeAsBytes(bytes);
      _tempCache[trackId] = file.path;
      _tempOrder.add(trackId);
      _enforceTempCacheLimit();
      completer.complete(file.path);
      return file.path;
    } catch (e) {
      completer.complete(null);
      return null;
    } finally {
      _pendingDownloads.remove(trackId);
      if (!_disposed) notifyListeners();
    }
  }

  void _enforceTempCacheLimit() {
    while (_tempOrder.length > _maxTempTracks) {
      final oldestId = _tempOrder.removeAt(0);
      if (!_pinnedTracks.contains(oldestId)) {
        final path = _tempCache.remove(oldestId);
        if (path != null) File(path).delete();
      }
    }
  }

  void clearSearch() {
    _searchResults = [];
    _currentSearchQuery = '';
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancelAllDownloads();
    super.dispose();
  }
}