import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

late AudioHandler audioHandler;

// 定义一个函数签名，用于动态获取 URL
typedef UrlResolver = Future<String?> Function(String mediaId);

class LxAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final List<MediaItem> _queue = [];
  int _currentIndex = 0;
  
  // 注入 URL 解析器
  UrlResolver? urlResolver;
  
  // 注入错误回调
  void Function(String message)? onError;

  LxAudioHandler() {
    // 初始化 playbackState，避免 value 访问时抛异常
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      playing: false,
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      speed: 1.0,
    ));
    _init();
  }

  AudioPlayer get player => _player;

  void _init() {
    _player.playbackEventStream.listen(_broadcastState);
    
    // 监听播放完成
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        // 在 just_audio 中，如果 LoopMode 为 off，播放到末尾会进入 completed
        // 如果 LoopMode 为 one 或 all，通常不会进入 completed (除非列表播放完了)
        skipToNext();
      }
    });

    // 监听索引变化，同步 _currentIndex
    _player.currentIndexStream.listen((index) async {
      if (index != null && index != _currentIndex) {
        _currentIndex = index;
        if (_currentIndex < _queue.length) {
          final item = _queue[_currentIndex];
          mediaItem.add(item);
          
          // 如果是自然切换（如上一首播放完）到了一首没有 URL 的歌，需要解析
          final url = item.extras?['url'];
          if (url == null || (url as String).isEmpty) {
            await skipToQueueItem(_currentIndex);
          }
        }
      }
    });
  }

  // 将播放状态广播给系统控制中心
  void _broadcastState(PlaybackEvent event) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentIndex,
    ));
  }

  @override
  Future<void> play() async {
    // 如果播放器处于空闲/错误状态，先重置再播放
    if (_player.processingState == ProcessingState.idle) {
      await _player.stop();
      if (_player.currentIndex != null) {
        await _player.seek(Duration.zero, index: _player.currentIndex);
      }
    }
    try {
      await _player.play();
    } catch (e) {
      debugPrint('[AudioHandler] play() 失败: $e');
    }
    await super.play();
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      debugPrint('[AudioHandler] pause() 失败: $e');
    }
    await super.pause();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;
    
    // 如果使用了 ConcatenatingAudioSource 且开启了随机模式
    if (_player.shuffleModeEnabled) {
      await _player.seekToNext();
      return;
    }

    int nextIndex = _currentIndex + 1;
    if (nextIndex >= _queue.length) {
      if (playbackState.value.repeatMode == AudioServiceRepeatMode.all || 
          playbackState.value.repeatMode == AudioServiceRepeatMode.one) {
        nextIndex = 0;
      } else {
        return;
      }
    }
    
    // 更新当前索引
    _currentIndex = nextIndex;
    
    final item = _queue[nextIndex];
    final url = item.extras?['url'];
    if (url == null || (url as String).isEmpty) {
      await skipToQueueItem(nextIndex);
    } else {
      // 检查当前 source 是否包含该 index 且 URL 正确
      if (_player.audioSource is ConcatenatingAudioSource) {
        mediaItem.add(item);
        await _player.seek(Duration.zero, index: nextIndex);
        await _player.play();
      } else {
        await skipToQueueItem(nextIndex);
      }
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;

    if (_player.shuffleModeEnabled) {
      await _player.seekToPrevious();
      return;
    }

    int prevIndex = _currentIndex - 1;
    if (prevIndex < 0) {
      if (playbackState.value.repeatMode == AudioServiceRepeatMode.all ||
          playbackState.value.repeatMode == AudioServiceRepeatMode.one) {
        prevIndex = _queue.length - 1;
      } else {
        return;
      }
    }
    
    // 更新当前索引
    _currentIndex = prevIndex;
    
    final item = _queue[prevIndex];
    final url = item.extras?['url'];
    if (url == null || (url as String).isEmpty) {
      await skipToQueueItem(prevIndex);
    } else {
      if (_player.audioSource is ConcatenatingAudioSource) {
        mediaItem.add(item);
        await _player.seek(Duration.zero, index: prevIndex);
        await _player.play();
      } else {
        await skipToQueueItem(prevIndex);
      }
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    
    final item = _queue[index];
    
    // 如果已经在这一首，且正在播放或正在加载，通常不需要重复操作
    // 但如果 URL 为空，则可能需要继续解析
    String? currentUrl = item.extras?['url'];
    
    // 更新当前索引，表示我们“意图”切换到这一项
    _currentIndex = index;
    mediaItem.add(item);

    try {
      String? url = currentUrl;
      
      if (url == null || url.isEmpty) {
        if (urlResolver != null) {
          // 在解析期间，我们可以广播正在缓冲的状态
          playbackState.add(playbackState.value.copyWith(
            processingState: AudioProcessingState.buffering,
          ));
          url = await urlResolver!(item.id);
        }
      }

      // 关键稳定性修复：检查在异步解析过程中，用户是否已经切换到了其他歌曲
      // 如果 _currentIndex 已经不再是 index，说明在此期间有更近的播放请求
      if (_currentIndex != index) {
        return;
      }

      // 当 URL 解析失败时，停止播放器避免播放静音 about:blank
      if (url == null || url.isEmpty) {
        if (_player.playing) {
          await _player.pause();
        }
      }

      if (url != null && url.isNotEmpty) {
        // 更新队列中该项的 URL，防止下次还需要解析
        final updatedItem = item.copyWith(extras: {...?item.extras, 'url': url});
        _queue[index] = updatedItem;
        queue.add(List.from(_queue)); // 确保发送的是列表副本以触发流更新
        
        mediaItem.add(updatedItem);
        
        // 更新播放源中的 URL
        if (_player.audioSource is ConcatenatingAudioSource) {
          final source = _player.audioSource as ConcatenatingAudioSource;
          if (index < source.length) {
            // 检查是否真的需要更新 AudioSource (如果 URL 没变就不重载)
            final currentSource = source.children[index];
            bool needsUpdate = true;
            if (currentSource is UriAudioSource) {
              if (currentSource.uri.toString() == url) {
                needsUpdate = false;
              }
            }

            if (needsUpdate) {
              // 通过 移除+插入 的方式更新特定索引的 URL
              await source.removeAt(index);
              await source.insert(index, AudioSource.uri(Uri.parse(url), tag: updatedItem));
            }
            
            // 如果索引不对或者刚刚更新了 URL，则跳转
            if (_player.currentIndex != index || needsUpdate) {
              await _player.seek(Duration.zero, index: index);
            }
          }
        } else {
          await _player.setAudioSource(AudioSource.uri(Uri.parse(url), tag: updatedItem));
        }

        await _player.play();
      } else {
        debugPrint('[AudioHandler] 无法获取播放链接: ${item.title}');
        onError?.call('无法解析歌曲 "${item.title}" 的播放地址');
        // 如果获取失败，等待 5 秒后自动下一首
        if (_queue.length > 1 && _currentIndex == index) {
          await Future.delayed(const Duration(seconds: 5));
          if (_currentIndex == index) {
            skipToNext();
          }
        }
      }
    } catch (e) {
      debugPrint('[AudioHandler] 播放失败: $e');
      if (_currentIndex == index) {
        onError?.call('播放歌曲 "${item.title}" 失败: $e');
        if (_queue.length > 1) {
          await Future.delayed(const Duration(seconds: 5));
          if (_currentIndex == index) {
            skipToNext();
          }
        }
      }
    }
  }

  // 设置播放列表并开始播放
  Future<void> setPlaylist(List<MediaItem> items, {int initialIndex = 0}) async {
    _queue.clear();
    _queue.addAll(items);
    queue.add(List.from(_queue));

    // 使用 ConcatenatingAudioSource 更好地支持切歌和随机播放
    final playlist = ConcatenatingAudioSource(
      children: items.map((item) {
        final url = item.extras?['url'] ?? '';
        // 如果有 URL 则直接使用，否则先占位，播放时动态解析
        return AudioSource.uri(Uri.parse(url.isEmpty ? 'about:blank' : url), tag: item);
      }).toList(),
    );

    await _player.setAudioSource(playlist, initialIndex: initialIndex);
    _currentIndex = initialIndex;
    mediaItem.add(items[initialIndex]);
    
    // 如果没有 URL，需要先解析
    final initialUrl = items[initialIndex].extras?['url'];
    if (initialUrl == null || initialUrl.isEmpty) {
      await skipToQueueItem(initialIndex);
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> updateQueue(List<MediaItem> newQueue) async {
    // 记录当前播放项的信息，尝试在更新后恢复（如果它还在新队列中）
    final String? currentId = mediaItem.value?.id;
    
    _queue.clear();
    _queue.addAll(newQueue);
    queue.add(List.from(_queue));

    // 同步更新播放器的 ConcatenatingAudioSource
    if (_player.audioSource is ConcatenatingAudioSource) {
      final source = _player.audioSource as ConcatenatingAudioSource;
      
      // 优化：使用增量更新而不是 setAudioSource，以避免播放中断
      // 如果新队列完全不同，则只能全量替换
      // 这里为了简单和准确，采用 clear + addAll
      await source.clear();
      await source.addAll(newQueue.map((item) {
        final url = item.extras?['url'] ?? '';
        return AudioSource.uri(Uri.parse(url.isEmpty ? 'about:blank' : url), tag: item);
      }).toList());
      
      // 如果原来的播放项还在，尝试恢复索引
      if (currentId != null) {
        final newIndex = newQueue.indexWhere((item) => item.id == currentId);
        if (newIndex != -1) {
          _currentIndex = newIndex;
        }
      }
    }
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    _queue.add(mediaItem);
    queue.add(List.from(_queue));
    
    if (_player.audioSource is ConcatenatingAudioSource) {
      final source = _player.audioSource as ConcatenatingAudioSource;
      final url = mediaItem.extras?['url'] ?? '';
      await source.add(AudioSource.uri(
        Uri.parse(url.isEmpty ? 'about:blank' : url), 
        tag: mediaItem
      ));
    }
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    final index = _queue.indexWhere((item) => item.id == mediaItem.id);
    if (index != -1) {
      _queue.removeAt(index);
      queue.add(List.from(_queue));
      
      if (_player.audioSource is ConcatenatingAudioSource) {
        final source = _player.audioSource as ConcatenatingAudioSource;
        if (index < source.length) {
          await source.removeAt(index);
        }
      }
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        await _player.setLoopMode(LoopMode.off);
        break;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        await _player.setLoopMode(LoopMode.all);
        break;
      case AudioServiceRepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
        break;
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode == AudioServiceShuffleMode.all;
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
    await _player.setShuffleModeEnabled(enabled);
  }
}
