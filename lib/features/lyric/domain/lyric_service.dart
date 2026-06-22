import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'lyric.dart';
import '../data/lyric_parser.dart';
import '../../player/domain/music_item.dart';
import '../../../core/network/music_source_service.dart';

class LyricService {
  final Dio _dio = Dio();
  final MusicSourceService? _musicSourceService;
  final Map<String, Lyrics> _cache = {}; // 歌词缓存

  LyricService([this._musicSourceService]);

  // 获取歌词
  Future<Lyrics> fetchLyric(MusicItem music) async {
    debugPrint('[LyricService] fetchLyric: ${music.name}, platform=${music.platform}, songmid=${music.songmid}, source=${music.source}');

    // 0. 检查缓存
    if (_cache.containsKey(music.id)) {
      debugPrint('[LyricService] 命中缓存');
      return _cache[music.id]!;
    }

    // 1. 如果有内置的 lyricsUrl (通常是已经解析好的)
    if (music.lyricsUrl != null && music.lyricsUrl!.isNotEmpty) {
      try {
        debugPrint('[LyricService] 尝试从 lyricsUrl 获取: ${music.lyricsUrl}');
        final response = await _dio.get(music.lyricsUrl!);
        if (response.statusCode == 200 && response.data is String) {
          final lyrics = _parseLyricString(response.data);
          debugPrint('[LyricService] lyricsUrl 获取成功, ${lyrics.lines.length} 行');
          _cache[music.id] = lyrics;
          return lyrics;
        }
      } catch (e) {
        debugPrint('[LyricService] lyricsUrl 获取失败: $e');
      }
    }

    // 2. 尝试从音乐源服务获取
    if (_musicSourceService != null) {
      try {
        debugPrint('[LyricService] 尝试从 MusicSourceService 获取歌词');
        final lyricStr = await _musicSourceService.getLyric(music);
        if (lyricStr != null && lyricStr.isNotEmpty) {
          final lyrics = _parseLyricString(lyricStr);
          debugPrint('[LyricService] MusicSourceService 获取成功, ${lyrics.lines.length} 行');
          _cache[music.id] = lyrics;
          return lyrics;
        } else {
          debugPrint('[LyricService] MusicSourceService 返回空');
        }
      } catch (e) {
        debugPrint('[LyricService] MusicSourceService 获取失败: $e');
      }
    }

    debugPrint('[LyricService] 所有途径均失败，返回空歌词');
    return Lyrics.empty();
  }

  // 清除缓存
  void clearCache() {
    _cache.clear();
  }

  // 内部辅助方法：智能解析歌词字符串
  Lyrics _parseLyricString(String lyricStr) {
    // LRCX 格式：有 [mm:ss.xx] 行时间标签 + <offset,duration> 逐字标签 → 走 LRC 解析
    // QRC 格式：行时间标签后紧跟 <mm:ss.xxx> 逐字标签（无逗号）
    // 判断依据：是否有标准 LRC 行时间标签 [mm:ss.xx]
    final hasLrcTimeTag = RegExp(r'\[\d{2}:\d{2}[\.\d]*\]').hasMatch(lyricStr);
    if (hasLrcTimeTag) {
      return LyricParser.parseLrc(lyricStr);
    }
    // 纯 QRC（无标准 LRC 时间标签）
    return LyricParser.parseQrc(lyricStr);
  }

  // 解析 LRC 字符串
  Lyrics parseLrc(String lrc) {
    return LyricParser.parseLrc(lrc);
  }

  // 解析 QRC 字符串
  Lyrics parseQrc(String qrc) {
    return LyricParser.parseQrc(qrc);
  }

  void dispose() {
    _dio.close();
  }
}
