import 'package:flutter/foundation.dart';
import '../../features/player/domain/music_item.dart';
import '../../features/custom_source/domain/custom_source_service.dart';
import '../music_source/platform/built_in_source_manager.dart';

class MusicSourceService {
  final CustomSourceService _customSourceService;
  final BuiltInSourceManager _builtInSources = BuiltInSourceManager();

  MusicSourceService(this._customSourceService);

  BuiltInSourceManager get builtInSources => _builtInSources;

  Future<List<MusicItem>> search(
    String keyword, {
    String? customSourceId,
    int page = 1,
    int limit = 20,
    String type = 'music',
  }) async {
    final platform = customSourceId ?? 'kw';
    final enabledCustomSources = _customSourceService.enabledSources;

    // 如果用户有自定义脚本，优先用自定义脚本搜索
    if (enabledCustomSources.isNotEmpty) {
      try {
        final results = await _customSourceService.searchWithSource(
          enabledCustomSources.first.id,
          keyword,
          source: platform,
          page: page,
          limit: limit,
          type: type,
        ).timeout(const Duration(seconds: 5));
        if (results.isNotEmpty) {
          return results;
        }
      } catch (e) {
        // Custom source search error, continue to built-in
      }
    }

    // 全网搜索
    if (platform == 'all') {
      return _searchAllPlatforms(keyword, page: page, limit: limit);
    }

    // 指定平台搜索，走内置源
    if (type == 'songlist') {
      final builtInResult = await _builtInSources.searchSongLists(platform, keyword, page: page, limit: limit);
      if (builtInResult.isNotEmpty) return builtInResult;
    } else {
      final builtInResult = await _builtInSources.search(platform, keyword, page: page, limit: limit);
      if (builtInResult.isNotEmpty) return builtInResult;
    }

    // 内置源没结果，尝试自定义源兜底
    if (enabledCustomSources.isNotEmpty) {
      return await _customSourceService.searchWithSource(
        enabledCustomSources.first.id,
        keyword,
        source: platform,
        page: page,
        limit: limit,
        type: type,
      ).catchError((e) {
        return <MusicItem>[];
      });
    }

    return [];
  }

  Future<List<MusicItem>> _searchAllPlatforms(String keyword, {int page = 1, int limit = 20}) async {
    final platforms = _builtInSources.allIds;
    final results = await Future.wait(
      platforms.map((p) => _builtInSources.search(p, keyword, page: page, limit: limit)
          .timeout(const Duration(seconds: 10), onTimeout: () => <MusicItem>[])
          .catchError((_) => <MusicItem>[])),
    );

    final List<MusicItem> combined = [];
    int maxLen = results.map((r) => r.length).fold(0, (max, len) => len > max ? len : max);
    for (int i = 0; i < maxLen; i++) {
      for (var list in results) {
        if (i < list.length) {
          combined.add(list[i]);
        }
      }
    }
    return combined;
  }

  Future<String?> getPlayUrl(MusicItem music, {String quality = '128k'}) async {
    // 1. 优先尝试自定义源
    final enabledSources = _customSourceService.enabledSources;
    for (final source in enabledSources) {
      final url = await _customSourceService.getMusicUrl(source.id, music)
          .catchError((e) {
        return null;
      });
      if (url != null && url.isNotEmpty) {
        return url;
      }
    }

    // 2. 如果自定义源失败，回退到内置源（主平台）
    final platform = music.platform.isNotEmpty ? music.platform : music.source;
    if (platform.isNotEmpty && platform != 'custom' && platform != 'test') {
      final url = await _builtInSources.getMusicUrl(platform, music, quality: quality);
      if (url != null) {
        return url;
      }
    }

    return null;
  }

  Future<String?> getLyric(MusicItem music) async {
    debugPrint('[MusicSourceService] getLyric: platform=${music.platform}, source=${music.source}, songmid=${music.songmid}');

    // 1. 优先尝试自定义源
    final enabledSources = _customSourceService.enabledSources;
    if (enabledSources.isNotEmpty) {
      debugPrint('[MusicSourceService] 尝试 ${enabledSources.length} 个自定义源');
    }
    for (final source in enabledSources) {
      final lyric = await _customSourceService.getLyric(source.id, music)
          .catchError((e) { debugPrint('[MusicSourceService] 自定义源 ${source.id} 歌词失败: $e'); return null; });
      if (lyric != null && lyric.isNotEmpty) {
        debugPrint('[MusicSourceService] 自定义源 ${source.id} 返回歌词');
        return lyric;
      }
    }

    // 2. 回退到歌曲所属的内置源
    final platform = music.platform.isNotEmpty ? music.platform : music.source;
    debugPrint('[MusicSourceService] 尝试内置源 platform=$platform');
    if (platform.isNotEmpty && platform != 'custom' && platform != 'test') {
      final lyric = await _builtInSources.getLyric(platform, music);
      if (lyric != null && lyric.isNotEmpty) {
        debugPrint('[MusicSourceService] 内置源 $platform 返回歌词');
        return lyric;
      }
      debugPrint('[MusicSourceService] 内置源 $platform 返回空');
    }

    // 3. 所有内置源搜索兜底
    for (final pid in _builtInSources.allIds) {
      if (pid == platform) continue;
      final lyric = await _builtInSources.getLyric(pid, music);
      if (lyric != null && lyric.isNotEmpty) {
        debugPrint('[MusicSourceService] 兜底源 $pid 返回歌词');
        return lyric;
      }
    }

    debugPrint('[MusicSourceService] 所有源均未返回歌词');
    return null;
  }

  Future<List<MusicItem>> getSongListDetail(String platformId, String songListId, {int page = 1, int limit = 50}) async {
    // 1. 优先自定义源
    final enabledSources = _customSourceService.enabledSources;
    for (final source in enabledSources) {
      try {
        final songs = await _customSourceService.getSongListDetail(platformId, songListId);
        if (songs.isNotEmpty) return songs;
      } catch (_) {}
    }
    // 2. 内置源
    return _builtInSources.getSongListDetail(platformId, songListId, page: page, limit: limit);
  }

  void dispose() {
    _builtInSources.dispose();
  }
}
