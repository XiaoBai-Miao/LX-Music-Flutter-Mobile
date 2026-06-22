import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../domain/player_service.dart';
import '../domain/music_item.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../../core/audio/audio_handler.dart';

final playerServiceProvider = Provider<PlayerService>((ref) {
  return PlayerService();
});

// 监听当前的 MediaItem (来自 audio_service)
final currentMediaItemProvider = StreamProvider<MediaItem?>((ref) {
  return audioHandler.mediaItem;
});

// 转换 MediaItem 为项目通用的 MusicItem
final currentMusicProvider = Provider<MusicItem?>((ref) {
  final mediaItem = ref.watch(currentMediaItemProvider).value;
  if (mediaItem == null) return null;

  // 从 extras 中恢复 MusicItem 对象
  if (mediaItem.extras != null) {
    return MusicItem.fromJson(mediaItem.extras!);
  }

  // 如果没有 extras，手动构建
  return MusicItem(
    id: mediaItem.id,
    name: mediaItem.title,
    singer: mediaItem.artist ?? '未知歌手',
    album: mediaItem.album ?? '',
    duration: mediaItem.duration ?? Duration.zero,
    source: 'unknown',
    artwork: mediaItem.artUri?.toString(),
  );
});

// 监听播放状态
final playbackStateProvider = StreamProvider<PlaybackState>((ref) {
  return audioHandler.playbackState;
});

// 实时进度：用 Timer 轮询 just_audio 的 position（比 StreamProvider 更可靠）
final playerPositionProvider = StateNotifierProvider<PositionNotifier, Duration>((ref) {
  if (audioHandler is LxAudioHandler) {
    return PositionNotifier((audioHandler as LxAudioHandler).player);
  }
  return PositionNotifier(null);
});

// 适配 MiniPlayer 的别名提供者
final positionProvider = playerPositionProvider;

// 播放状态简化
final isPlayingProvider = Provider<AsyncValue<bool>>((ref) {
  final state = ref.watch(playbackStateProvider);
  return state.whenData((s) => s.playing);
});

// 播放器实际音频时长（从 just_audio 获取）
final audioDurationProvider = StreamProvider<Duration?>((ref) {
  if (audioHandler is LxAudioHandler) {
    return (audioHandler as LxAudioHandler).player.durationStream;
  }
  return Stream.value(null);
});

// 当前歌曲时长：优先使用播放器实际时长，回退到元数据时长
final durationProvider = Provider<AsyncValue<Duration>>((ref) {
  final audioDuration = ref.watch(audioDurationProvider).value;
  if (audioDuration != null && audioDuration > Duration.zero) {
    return AsyncValue.data(audioDuration);
  }
  final music = ref.watch(currentMusicProvider);
  return AsyncValue.data(music?.duration ?? Duration.zero);
});

// 播放模式枚举
enum PlayMode {
  repeatOne,    // 单曲循环
  sequential,   // 顺序播放
  shuffle,      // 随机播放
}

// 播放模式切换 (RepeatOne, Sequential, Shuffle)
final playModeProvider = StateProvider<PlayMode>((ref) {
  return PlayMode.sequential;
});

/// 用 Timer 轮询播放器位置，避免 StreamProvider 单订阅流丢失问题
class PositionNotifier extends StateNotifier<Duration> {
  final AudioPlayer? _player;
  Timer? _timer;

  PositionNotifier(this._player) : super(Duration.zero) {
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_player != null) {
        state = _player.position;
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// 监听当前歌曲变化，自动记录到最近播放
final recentPlayRecorderProvider = Provider<void>((ref) {
  final music = ref.watch(currentMusicProvider);
  if (music != null) {
    final playlistService = ref.read(playlistServiceProvider);
    playlistService.addToRecent(music);
  }
});

// 定时停止播放
class SleepTimerNotifier extends StateNotifier<Duration?> {
  Timer? _timer;
  DateTime? _endTime;

  SleepTimerNotifier() : super(null);

  DateTime? get endTime => _endTime;

  void startTimer(Duration duration) {
    _timer?.cancel();
    _endTime = DateTime.now().add(duration);
    state = duration;

    _timer = Timer(duration, () {
      // 停止播放
      audioHandler.pause();
      state = null;
      _endTime = null;
    });
  }

  void cancelTimer() {
    _timer?.cancel();
    _timer = null;
    state = null;
    _endTime = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final sleepTimerProvider = StateNotifierProvider<SleepTimerNotifier, Duration?>((ref) {
  return SleepTimerNotifier();
});

final sleepTimerEndProvider = Provider<DateTime?>((ref) {
  ref.watch(sleepTimerProvider);
  return ref.read(sleepTimerProvider.notifier).endTime;
});

// 全局播放消息通知（用于展示 SnackBar）
final playerMessageProvider = StateProvider<String?>((ref) => null);
