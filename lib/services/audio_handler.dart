import 'dart:async';
import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class AppAudioHandler extends BaseAudioHandler with QueueHandler {
  final AudioPlayer _player = AudioPlayer();
  final SharedPreferences _prefs;
  final Completer<void> _readyCompleter = Completer<void>();
  Timer? _saveDebounceTimer;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration> get durationStream =>
      _player.durationStream.where((d) => d != null).cast<Duration>();

  Future<void> get ready => _readyCompleter.future;

  AppAudioHandler({required SharedPreferences prefs}) : _prefs = prefs {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_player.loopMode != LoopMode.one) {
          skipToNext().catchError((e) {
            debugPrint('skipToNext on completion error: $e');
            // При ошибке пытаемся переключиться на следующий трек вручную
            _attemptSkipToNextWithFallback();
          });
        } else {
          _player.seek(Duration.zero);
          _player.play();
        }
      }
    });

    _player.durationStream.listen((d) {
      if (d != null && queue.value.isNotEmpty && _player.currentIndex != null) {
        final idx = _player.currentIndex!;
        if (idx < queue.value.length) {
          final updated = queue.value[idx].copyWith(duration: d);
          queue.value[idx] = updated;
          mediaItem.add(updated);
        }
      }
    });

    _initEmptySource();
    _restoreState();
  }

  Future<void> _initEmptySource() async {
    await _player.setAudioSource(ConcatenatingAudioSource(children: []));
    await Future.delayed(const Duration(milliseconds: 50));
    _readyCompleter.complete();
  }

  Future<void> _restoreState() async {
    final savedQueueJson = _prefs.getStringList('queue_items');
    final savedIndex = _prefs.getInt('queue_index');
    final savedPositionMs = _prefs.getInt('position_ms');

    if (savedQueueJson == null || savedQueueJson.isEmpty) return;

    try {
      final List<MediaItem> restoredItems = [];
      for (final jsonStr in savedQueueJson) {
        final map = json.decode(jsonStr) as Map<String, dynamic>;
        final item = MediaItem(
          id: map['id']!,
          album: map['album'] ?? '',
          title: map['title']!,
          artist: map['artist'],
          artUri: map['artUri'] != null ? Uri.parse(map['artUri']) : null,
          duration: map['duration'] != null ? Duration(milliseconds: map['duration']) : null,
          extras: map['extras'] as Map<String, dynamic>?,
        );
        restoredItems.add(item);
      }

      if (restoredItems.isEmpty) return;

      queue.add(restoredItems);
      int startIndex = savedIndex ?? 0;
      if (startIndex >= restoredItems.length) startIndex = 0;

      final sources = restoredItems.map((item) {
        final id = item.id;
        if (id.startsWith('http://') || id.startsWith('https://')) {
          return AudioSource.uri(Uri.parse(id));
        } else {
          return AudioSource.file(id);
        }
      }).toList();

      await _player.setAudioSource(
        ConcatenatingAudioSource(children: sources),
        initialIndex: startIndex,
      );
      mediaItem.add(restoredItems[startIndex]);

      if (savedPositionMs != null && savedPositionMs > 0) {
        await _player.seek(Duration(milliseconds: savedPositionMs));
      }
    } catch (e) {
      debugPrint('Failed to restore state: $e');
      // Сбрасываем очередь при ошибке восстановления
      queue.add([]);
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
    try {
      if (queue.value.isNotEmpty && _player.currentIndex != null) {
        final List<String> queueJson = queue.value.map((item) {
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
        await _prefs.setStringList('queue_items', queueJson);
        await _prefs.setInt('queue_index', _player.currentIndex!);
        await _prefs.setInt('position_ms', _player.position.inMilliseconds);
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
      case LoopMode.off: return AudioServiceRepeatMode.none;
      case LoopMode.one: return AudioServiceRepeatMode.one;
      case LoopMode.all: return AudioServiceRepeatMode.all;
    }
  }

  AudioProcessingState _getProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle: return AudioProcessingState.idle;
      case ProcessingState.loading: return AudioProcessingState.loading;
      case ProcessingState.buffering: return AudioProcessingState.buffering;
      case ProcessingState.ready: return AudioProcessingState.ready;
      case ProcessingState.completed: return AudioProcessingState.completed;
      default: return AudioProcessingState.idle;
    }
  }

  void setLoopMode(LoopMode mode) {
    _player.setLoopMode(mode);
    playbackState.add(_transformEvent(PlaybackEvent(currentIndex: _player.currentIndex ?? 0)));
  }

  LoopMode getLoopMode() => _player.loopMode;

  Future<void> setTracksAndPlay(List<MediaItem> items, int startIndex) async {
    if (items.isEmpty) return;
    await ready;

    if (_player.playing) {
      await _player.stop();
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
      queue.add(items);
      if (startIndex < items.length) {
        mediaItem.add(items[startIndex]);
      }

      await _player.play();
      await saveCurrentState();

      if (_player.duration != null && _player.duration! > Duration.zero) {
        final idx = _player.currentIndex!;
        if (idx < queue.value.length) {
          final updated = queue.value[idx].copyWith(duration: _player.duration);
          queue.value[idx] = updated;
          mediaItem.add(updated);
        }
      }
    } catch (e) {
      debugPrint('setTracksAndPlay error: $e');
      // Пробуем перезапустить плеер
      try {
        await _player.stop();
        await _player.setAudioSource(ConcatenatingAudioSource(children: []));
        await Future.delayed(const Duration(milliseconds: 500));
        await _player.setAudioSource(
          ConcatenatingAudioSource(children: sources),
          initialIndex: startIndex,
        );
        await _player.play();
        debugPrint('Recovered from setTracksAndPlay error');
      } catch (e2) {
        debugPrint('Recovery failed: $e2');
        rethrow;
      }
    }
  }

  @override Future<void> play() async { await _player.play(); await saveCurrentState(); }
  @override Future<void> pause() async { await _player.pause(); await saveCurrentState(); }
  Future<void> playOrPause() async { if (_player.playing) { await pause(); } else { await play(); } }
  @override Future<void> seek(Duration position) async { await _player.seek(position); await saveCurrentState(); }

  @override Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await _player.seek(Duration.zero, index: index);
    await _player.play();
    if (index < queue.value.length) mediaItem.add(queue.value[index]);
    await saveCurrentState();
  }

  @override Future<void> skipToNext() async {
    try {
      final nextIndex = (_player.currentIndex ?? 0) + 1;
      if (nextIndex < queue.value.length) {
        await skipToQueueItem(nextIndex);
      } else if (_player.loopMode == LoopMode.all) {
        await skipToQueueItem(0);
      }
    } catch (e) {
      debugPrint('skipToNext error: $e');
      // Пытаемся переключиться на следующий трек вручную
      await _attemptSkipToNextWithFallback();
    }
  }

  // Вспомогательный метод для попытки переключения на следующий трек при ошибке
  Future<void> _attemptSkipToNextWithFallback() async {
    try {
      final currentIndex = _player.currentIndex ?? 0;
      final nextIndex = currentIndex + 1;
      if (nextIndex < queue.value.length) {
        await skipToQueueItem(nextIndex);
      } else {
        // Если больше нет треков, останавливаем
        await stop();
        debugPrint('No more tracks to play, stopped.');
      }
    } catch (e) {
      debugPrint('Fallback skipToNext also failed: $e');
      await stop();
    }
  }

  @override Future<void> skipToPrevious() async {
    try {
      final prevIndex = (_player.currentIndex ?? 0) - 1;
      if (prevIndex >= 0) {
        await skipToQueueItem(prevIndex);
      } else if (_player.loopMode == LoopMode.all) {
        await skipToQueueItem(queue.value.length - 1);
      }
    } catch (e) {
      debugPrint('skipToPrevious error: $e');
      // При ошибке пытаемся переключиться на предыдущий трек вручную
      try {
        final currentIndex = _player.currentIndex ?? 0;
        final prevIndex = currentIndex - 1;
        if (prevIndex >= 0) {
          await skipToQueueItem(prevIndex);
        } else {
          await stop();
        }
      } catch (e2) {
        debugPrint('Fallback skipToPrevious failed: $e2');
        await stop();
      }
    }
  }

  @override Future<void> stop() async {
    await _player.stop();
    await saveStateNow();
    await super.stop();
  }
}