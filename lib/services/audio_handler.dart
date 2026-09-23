import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import 'database/queue_repository.dart';

class AppAudioHandler extends BaseAudioHandler with QueueHandler {
  final AudioPlayer _player = AudioPlayer();
  final SharedPreferences _prefs;
  final QueueRepository _queueRepo = QueueRepository();
  final Completer<void> _readyCompleter = Completer<void>();
  Timer? _saveDebounceTimer;
  bool _isInitialized = false;
  bool _disposed = false;

  final Set<String> _brokenTrackIds = {};
  DateTime? _lastSwitchAt;

  /// Сериализация всех операций управления плеером.
  /// Гарантирует, что второй skipToNext не начнётся до завершения первого.
  Future<void> _opChain = Future.value();

  void Function(MediaItem current, String? nextTrackId)? onTrackStarted;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration> get durationStream =>
      _player.durationStream.where((d) => d != null).cast<Duration>();

  Future<void> get ready => _readyCompleter.future;
  bool get isInitialized => _isInitialized;
  Set<String> get brokenTrackIds => Set.unmodifiable(_brokenTrackIds);

  AppAudioHandler({required SharedPreferences prefs}) : _prefs = prefs {
    _setupListeners();
  }

  /// Обёртка над операцией: кладёт её в конец цепочки.
  /// Возвращает Future, который зарезолвится, когда операция отработает.
  Future<T> _queueOp<T>(Future<T> Function() op) {
    final completer = Completer<T>();
    _opChain = _opChain.then((_) async {
      if (_disposed) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('Handler disposed'));
        }
        return;
      }
      try {
        final r = await op();
        if (!completer.isCompleted) completer.complete(r);
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _restoreState();
      if (_player.audioSource == null) {
        await _player.setAudioSource(ConcatenatingAudioSource(children: []));
      }
    } catch (e) {
      debugPrint('AudioHandler.initialize error: $e');
    } finally {
      _isInitialized = true;
      if (!_readyCompleter.isCompleted) _readyCompleter.complete();
    }
  }

  void _setupListeners() {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    _player.playerStateStream.listen((state) {
      if (_disposed) return;
      if (!_isInitialized) return;
      if (state.processingState == ProcessingState.completed) {
        _queueOp(() => _handleTrackCompleted());
      }
    });

    _player.durationStream.listen((d) {
      if (_disposed || d == null) return;
      final idx = _player.currentIndex;
      if (idx == null || idx >= queue.value.length) return;

      final queueItem = queue.value[idx];
      final current = mediaItem.value;
      if (current == null || current.id != queueItem.id) return;

      final updated = queueItem.copyWith(duration: d);
      queue.value[idx] = updated;
      mediaItem.add(updated);
    });
  }

  Future<void> _handleTrackCompleted() async {
    if (_lastSwitchAt != null &&
        DateTime.now().difference(_lastSwitchAt!) <
            const Duration(milliseconds: 1200)) {
      debugPrint('Ignoring stale completed event');
      return;
    }

    if (_player.loopMode == LoopMode.one) {
      try {
        await _player.seek(Duration.zero);
        await _player.play();
      } catch (e) {
        debugPrint('Loop-one replay error: $e');
      }
      return;
    }
    await _safeSkipToNext();
  }

  Future<void> _safeSkipToNext() async {
    final currentIndex = _player.currentIndex ?? 0;
    final nextIndex = currentIndex + 1;

    if (nextIndex >= queue.value.length) {
      if (_player.loopMode == LoopMode.all && queue.value.isNotEmpty) {
        await _tryPlayIndex(0);
      } else {
        await _stopInternal();
      }
      return;
    }

    await _tryPlayIndex(nextIndex);
  }

  Future<void> _safeSkipToPrevious() async {
    final currentIndex = _player.currentIndex ?? 0;
    final prevIndex = currentIndex - 1;

    if (prevIndex < 0) {
      if (_player.loopMode == LoopMode.all && queue.value.isNotEmpty) {
        await _tryPlayIndex(queue.value.length - 1);
      } else {
        try {
          await _player.seek(Duration.zero);
        } catch (e) {
          debugPrint('Seek to zero error: $e');
        }
      }
      return;
    }

    await _tryPlayIndex(prevIndex);
  }

  Future<void> _tryPlayIndex(int index) async {
    if (index < 0 || index >= queue.value.length) return;

    final item = queue.value[index];
    final trackId = item.extras?['trackId'] as String?;

    if (trackId != null && _brokenTrackIds.contains(trackId)) {
      if (index + 1 < queue.value.length) {
        await _tryPlayIndex(index + 1);
      } else {
        await _stopInternal();
      }
      return;
    }

    _lastSwitchAt = DateTime.now();

    try {
      await _player.seek(Duration.zero, index: index);
      await _player.play();
      mediaItem.add(item);

      final nextIndex = index + 1;
      final nextTrackId = nextIndex < queue.value.length
          ? (queue.value[nextIndex].extras?['trackId'] as String?)
          : null;
      onTrackStarted?.call(item, nextTrackId);

      await saveCurrentState();
    } catch (e) {
      debugPrint('Playback error at index $index ($trackId): $e');
      if (trackId != null) _brokenTrackIds.add(trackId);

      if (index + 1 < queue.value.length) {
        await _tryPlayIndex(index + 1);
      } else {
        await _stopInternal();
      }
    }
  }

  Future<void> _restoreState() async {
    final dbState = await _queueRepo.load();
    if (dbState == null || dbState.queueJson.isEmpty) return;

    final queueJson = dbState.queueJson;
    final savedIndex = dbState.currentIndex;
    final savedPositionMs = dbState.positionMs;

    List<dynamic> rawList;
    try {
      final decoded = json.decode(queueJson);
      if (decoded is List) {
        rawList = decoded;
      } else {
        return;
      }
    } catch (e) {
      debugPrint('Restore: bad queue json: $e');
      return;
    }

    final List<AudioSource> validSources = [];
    final List<MediaItem> validItems = [];

    for (final raw in rawList) {
      try {
        final Map<String, dynamic> map;
        if (raw is String) {
          map = json.decode(raw) as Map<String, dynamic>;
        } else if (raw is Map) {
          map = Map<String, dynamic>.from(raw);
        } else {
          continue;
        }

        final item = MediaItem(
          id: map['id']!,
          album: map['album'] ?? '',
          title: map['title']!,
          artist: map['artist'],
          artUri: map['artUri'] != null ? Uri.parse(map['artUri']) : null,
          duration: map['duration'] != null
              ? Duration(milliseconds: map['duration'])
              : null,
          extras: map['extras'] as Map<String, dynamic>?,
        );

        final id = item.id;
        if (id.startsWith('http://') || id.startsWith('https://')) {
          validSources.add(AudioSource.uri(Uri.parse(id)));
          validItems.add(item);
        } else {
          final file = File(id);
          if (file.existsSync()) {
            validSources.add(AudioSource.file(id));
            validItems.add(item);
          } else {
            debugPrint('Restore: skipping missing file $id');
          }
        }
      } catch (e) {
        debugPrint('Restore: bad entry: $e');
      }
    }

    if (validItems.isEmpty) {
      debugPrint('Restore: no valid items after filtering');
      return;
    }

    int targetIndex = savedIndex;
    if (targetIndex >= validItems.length) targetIndex = 0;

    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: validSources),
        initialIndex: targetIndex,
      );

      try {
        queue.add(validItems);
      } catch (e) {
        debugPrint('Restore: queue.add failed (non-fatal): $e');
      }

      mediaItem.add(validItems[targetIndex]);

      if (savedPositionMs > 0) {
        await _player.seek(Duration(milliseconds: savedPositionMs));
      }
    } catch (e) {
      debugPrint('Restore: setAudioSource error: $e');
      try {
        queue.add([]);
      } catch (_) {}
      mediaItem.add(null);
    }
  }

  Future<void> saveCurrentState() async {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(seconds: 2), () async {
      await _saveStateNowInternal();
    });
  }

  Future<void> saveStateNow() async {
    _saveDebounceTimer?.cancel();
    await _saveStateNowInternal();
  }

  Future<void> _saveStateNowInternal() async {
    if (_disposed) return;
    try {
      if (queue.value.isNotEmpty && _player.currentIndex != null) {
        final List<String> queueJsonLines = queue.value.map((item) {
          return json.encode({
            'id': item.id,
            'album': item.album ?? '',
            'title': item.title,
            'artist': item.artist,
            'artUri': item.artUri?.toString(),
            'duration': item.duration?.inMilliseconds,
            'extras': item.extras,
          });
        }).toList();

        await _queueRepo.save(
          queueJson: json.encode(queueJsonLines),
          currentIndex: _player.currentIndex!,
          positionMs: _player.position.inMilliseconds,
        );
      }
    } catch (e) {
      debugPrint('Save state error: $e');
    }
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: _getProcessingState(_player.processingState),
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
      repeatMode: _getRepeatMode(_player.loopMode),
    );
  }

  AudioServiceRepeatMode _getRepeatMode(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return AudioServiceRepeatMode.none;
      case LoopMode.one:
        return AudioServiceRepeatMode.one;
      case LoopMode.all:
        return AudioServiceRepeatMode.all;
    }
  }

  AudioProcessingState _getProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
      default:
        return AudioProcessingState.idle;
    }
  }

  void setLoopMode(LoopMode mode) {
    _player.setLoopMode(mode);
    playbackState.add(
      _transformEvent(PlaybackEvent(currentIndex: _player.currentIndex ?? 0)),
    );
  }

  LoopMode getLoopMode() => _player.loopMode;

  // ---------- ОЧЕРЕДЬ: манипуляции ----------

  bool get _canModifyQueue =>
      _player.audioSource is ConcatenatingAudioSource;

  Future<void> removeFromQueue(int index) {
    return _queueOp(() async {
      if (!_canModifyQueue) return;
      if (index < 0 || index >= queue.value.length) return;

      final source = _player.audioSource as ConcatenatingAudioSource;
      final wasCurrent = _player.currentIndex == index;

      try {
        await source.removeAt(index);

        final updatedItems = queue.value.toList()..removeAt(index);
        queue.add(updatedItems);

        if (wasCurrent) {
          int newIndex;
          if (index < updatedItems.length) {
            newIndex = index;
          } else if (updatedItems.isNotEmpty) {
            newIndex = updatedItems.length - 1;
          } else {
            await _stopInternal();
            return;
          }
          await _tryPlayIndex(newIndex);
        } else if (updatedItems.isEmpty) {
          await _stopInternal();
        } else {
          await saveCurrentState();
        }
      } catch (e) {
        debugPrint('removeFromQueue error: $e');
      }
    });
  }

  Future<void> moveInQueue(int oldIndex, int newIndex) {
    return _queueOp(() async {
      if (!_canModifyQueue) return;
      if (oldIndex < 0 || oldIndex >= queue.value.length) return;
      if (newIndex < 0 || newIndex > queue.value.length) return;
      if (oldIndex == newIndex) return;

      int adjustedNew = newIndex;
      if (newIndex > oldIndex) adjustedNew -= 1;

      final source = _player.audioSource as ConcatenatingAudioSource;
      final currentIdx = _player.currentIndex;

      try {
        await source.move(oldIndex, adjustedNew);

        final updated = queue.value.toList();
        final moved = updated.removeAt(oldIndex);
        updated.insert(adjustedNew, moved);
        queue.add(updated);

        if (currentIdx == oldIndex) {
          mediaItem.add(moved);
        }

        await saveCurrentState();
      } catch (e) {
        debugPrint('moveInQueue error: $e');
      }
    });
  }

  Future<void> playNext(MediaItem item) {
    return _queueOp(() async {
      final source = _player.audioSource;

      if (source is! ConcatenatingAudioSource || queue.value.isEmpty) {
        await _setTracksAndPlayInternal([item], 0);
        return;
      }

      final currentIdx = _player.currentIndex ?? 0;
      final insertAt = currentIdx + 1;

      final newSource = item.id.startsWith('http://') ||
              item.id.startsWith('https://')
          ? AudioSource.uri(Uri.parse(item.id))
          : AudioSource.file(item.id);

      try {
        await source.insert(insertAt, newSource);

        final updated = queue.value.toList();
        updated.insert(insertAt, item);
        queue.add(updated);

        await saveCurrentState();
      } catch (e) {
        debugPrint('playNext error: $e');
      }
    });
  }

  Future<void> addToQueueEnd(MediaItem item) {
    return _queueOp(() async {
      final source = _player.audioSource;

      if (source is! ConcatenatingAudioSource || queue.value.isEmpty) {
        await _setTracksAndPlayInternal([item], 0);
        return;
      }

      final newSource = item.id.startsWith('http://') ||
              item.id.startsWith('https://')
          ? AudioSource.uri(Uri.parse(item.id))
          : AudioSource.file(item.id);

      try {
        await source.add(newSource);

        final updated = queue.value.toList()..add(item);
        queue.add(updated);

        await saveCurrentState();
      } catch (e) {
        debugPrint('addToQueueEnd error: $e');
      }
    });
  }

  Future<void> clearQueue() {
    return _queueOp(() async {
      await _stopInternal();
      try {
        await _player.setAudioSource(ConcatenatingAudioSource(children: []));
      } catch (_) {}
      queue.add([]);
      mediaItem.add(null);
      _brokenTrackIds.clear();
      await _queueRepo.clear();
    });
  }

  // ---------- Основной API ----------

  Future<void> setTracksAndPlay(List<MediaItem> items, int startIndex) {
    return _queueOp(() => _setTracksAndPlayInternal(items, startIndex));
  }

  Future<void> _setTracksAndPlayInternal(
      List<MediaItem> items, int startIndex) async {
    if (items.isEmpty) return;
    if (_disposed) return;

    _brokenTrackIds.clear();

    if (_player.playing) {
      try {
        await _player.stop();
      } catch (e) {
        debugPrint('Stop before setTracks error: $e');
      }
    }

    final sources = items.map((item) {
      final id = item.id;
      if (id.startsWith('http://') || id.startsWith('https://')) {
        return AudioSource.uri(Uri.parse(id));
      } else {
        return AudioSource.file(id);
      }
    }).toList();

    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: sources),
        initialIndex: startIndex,
      );

      try {
        queue.add(items);
      } catch (e) {
        debugPrint('setTracksAndPlay: queue.add failed (non-fatal): $e');
      }

      if (startIndex < items.length) {
        mediaItem.add(items[startIndex]);
      }

      _lastSwitchAt = DateTime.now();

      await _player.play();

      if (startIndex < items.length) {
        final nextIndex = startIndex + 1;
        final nextTrackId = nextIndex < items.length
            ? (items[nextIndex].extras?['trackId'] as String?)
            : null;
        onTrackStarted?.call(items[startIndex], nextTrackId);
      }

      await saveCurrentState();

      if (_player.duration != null && _player.duration! > Duration.zero) {
        final idx = _player.currentIndex;
        if (idx != null && idx < queue.value.length) {
          final updated = queue.value[idx].copyWith(duration: _player.duration);
          queue.value[idx] = updated;
          mediaItem.add(updated);
        }
      }
    } catch (e) {
      debugPrint('setTracksAndPlay error: $e');
      try {
        await _player.stop();
        await _player.setAudioSource(ConcatenatingAudioSource(children: []));
        await Future.delayed(const Duration(milliseconds: 300));
        await _player.setAudioSource(
          ConcatenatingAudioSource(children: sources),
          initialIndex: startIndex,
        );
        _lastSwitchAt = DateTime.now();
        await _player.play();

        if (startIndex < items.length) {
          final nextIndex = startIndex + 1;
          final nextTrackId = nextIndex < items.length
              ? (items[nextIndex].extras?['trackId'] as String?)
              : null;
          onTrackStarted?.call(items[startIndex], nextTrackId);
        }

        debugPrint('setTracksAndPlay recovered');
      } catch (e2) {
        debugPrint('setTracksAndPlay recovery failed: $e2');
        rethrow;
      }
    }
  }

  @override
  Future<void> play() {
    return _queueOp(() async {
      try {
        await _player.play();
        await saveCurrentState();
      } catch (e) {
        debugPrint('play error: $e');
      }
    });
  }

  @override
  Future<void> pause() {
    return _queueOp(() async {
      try {
        await _player.pause();
        await saveCurrentState();
      } catch (e) {
        debugPrint('pause error: $e');
      }
    });
  }

  Future<void> playOrPause() {
    return _queueOp(() async {
      try {
        if (_player.playing) {
          await _player.pause();
        } else {
          await _player.play();
        }
        await saveCurrentState();
      } catch (e) {
        debugPrint('playOrPause error: $e');
      }
    });
  }

  @override
  Future<void> seek(Duration position) {
    return _queueOp(() async {
      try {
        await _player.seek(position);
        await saveCurrentState();
      } catch (e) {
        debugPrint('seek error: $e');
      }
    });
  }

  @override
  Future<void> skipToQueueItem(int index) {
    return _queueOp(() async {
      if (index < 0 || index >= queue.value.length) return;
      await _tryPlayIndex(index);
    });
  }

  @override
  Future<void> skipToNext() {
    return _queueOp(() => _safeSkipToNext());
  }

  @override
  Future<void> skipToPrevious() {
    return _queueOp(() => _safeSkipToPrevious());
  }

  Future<void> _stopInternal() async {
    try {
      await _player.stop();
      await saveStateNow();
      try {
        await super.stop();
      } catch (e) {
        debugPrint('super.stop error (non-fatal): $e');
      }
    } catch (e) {
      debugPrint('Stop error: $e');
    }
  }

  @override
  Future<void> stop() {
    return _queueOp(() => _stopInternal());
  }

  @override
  Future<void> onTaskRemoved() async {
    await saveStateNow();
    await super.onTaskRemoved();
  }

  void dispose() {
    _disposed = true;
    _saveDebounceTimer?.cancel();
    _player.dispose();
  }
}