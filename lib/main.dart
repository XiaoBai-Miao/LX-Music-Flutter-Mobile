import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:lx_music_flutter/app.dart';
import 'package:lx_music_flutter/core/audio/audio_handler.dart';
import 'package:lx_music_flutter/features/custom_source/presentation/custom_source_provider.dart';
import 'package:lx_music_flutter/features/search/presentation/search_provider.dart';
import 'package:lx_music_flutter/features/playlist/presentation/playlist_provider.dart';
import 'package:lx_music_flutter/features/download/presentation/download_provider.dart';
import 'package:lx_music_flutter/features/player/domain/music_item.dart';
import 'package:lx_music_flutter/features/settings/presentation/settings_provider.dart';
import 'package:lx_music_flutter/features/player/presentation/player_provider.dart';
import 'package:audio_session/audio_session.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化音频会话，确保正确处理音频焦点
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  // 1. 初始化 audio_service 基础实例
  audioHandler = await AudioService.init(
    builder: () => LxAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.lxmusic.flutter.audio',
      androidNotificationChannelName: 'LX Music Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );

  // 2. 创建 Riverpod Container 以在应用启动前访问 Providers
  final container = ProviderContainer();
  
  // 3. 初始化自定义音源
  await container.read(customSourceServiceProvider).init();
  
  // 3.5 初始化歌单持久化
  await container.read(playlistServiceProvider).init();
  
  // 3.6 初始化下载服务持久化
  await container.read(downloadServiceProvider).init();
  
  // 4. 关键：连接 AudioHandler 和 MusicSourceService
  if (audioHandler is LxAudioHandler) {
    final lxHandler = audioHandler as LxAudioHandler;
    final sourceService = container.read(musicSourceServiceProvider);
    
    // 设置 URL 解析器：当 AudioHandler 需要播放某首歌但没有 URL 时调用
    lxHandler.urlResolver = (mediaId) async {
      debugPrint('[urlResolver] 开始解析: mediaId=$mediaId');
      // 从当前播放项中获取原始 MusicItem 信息
      final currentItem = lxHandler.mediaItem.value;
      if (currentItem != null && currentItem.extras != null) {
        final musicItem = MusicItem.fromJson(currentItem.extras!);
        debugPrint('[urlResolver] 歌曲信息: platform=${musicItem.platform}, source=${musicItem.source}, songmid=${musicItem.songmid}');
        final qualityOption = container.read(audioQualityProvider);
        const qualityMap = {
          AudioQualityOption.low: '128k',
          AudioQualityOption.standard: '192k',
          AudioQualityOption.high: '320k',
          AudioQualityOption.lossless: 'flac',
        };
        final url = await sourceService.getPlayUrl(musicItem, quality: qualityMap[qualityOption] ?? '128k');
        debugPrint('[urlResolver] 解析结果: ${url != null ? "成功(${url.substring(0, url.length > 50 ? 50 : url.length)}...)" : "null"}');
        return url;
      }
      debugPrint('[urlResolver] 无法获取歌曲信息: currentItem=${currentItem != null}');
      return null;
    };

    // 设置错误消息回调
    lxHandler.onError = (message) {
      container.read(playerMessageProvider.notifier).state = message;
    };
  }
  
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const LxMusicApp(),
    ),
  );
}
