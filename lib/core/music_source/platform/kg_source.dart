import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../features/player/domain/music_item.dart';
import 'music_platform.dart';
import 'source_utils.dart';

class KgSource extends MusicPlatform {
  @override
  String get id => 'kg';

  @override
  String get name => '酷狗音乐';

  late final Dio _dio;

  KgSource() {
    _dio = createDio();
  }

  @override
  Future<List<MusicItem>> search(String keyword, {int page = 1, int limit = 20}) async {
    try {
      final response = await _dio.get(
        'https://songsearch.kugou.com/song_search_v2',
        queryParameters: {
          'keyword': keyword,
          'page': page.toString(),
          'pagesize': limit.toString(),
          'userid': '0',
          'clientver': '',
          'platform': 'WebFilter',
          'filter': '2',
          'iscorrection': '1',
          'privilege_filter': '0',
          'area_code': '1',
        },
      ).timeout(const Duration(seconds: 10));

      final data = response.data;
      if (data == null) return [];

      // 使用 compute 在后台线程处理解析逻辑，避免 UI 卡顿
      final results = await compute(_parseSearchResult, data);
      return results;
    } catch (e) {
      return [];
    }
  }

  static List<MusicItem> _parseSearchResult(dynamic data) {
    dynamic body = data;
    if (body is String) {
      try {
        body = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        return [];
      }
    }
    if (body is! Map) return [];

    if (body['error_code'] != 0) return [];

    final resultData = body['data'];
    if (resultData is! Map) return [];

    final lists = resultData['lists'] as List<dynamic>?;
    if (lists == null || lists.isEmpty) return [];

    return _staticHandleResult(lists);
  }

  static List<MusicItem> _staticHandleResult(List<dynamic> rawData) {
    final ids = <String>{};
    final list = <MusicItem>[];

    for (final item in rawData) {
      final map = item as Map<String, dynamic>;
      final key = '${map['Audioid']}${map['FileHash']}';
      if (ids.contains(key)) continue;
      ids.add(key);

      final parsed = _staticFilterData(map);
      if (parsed != null) list.add(parsed);

      final grp = map['Grp'] as List<dynamic>?;
      if (grp != null) {
        for (final child in grp) {
          final childMap = child as Map<String, dynamic>;
          final childKey = '${childMap['Audioid']}${childMap['FileHash']}';
          if (ids.contains(childKey)) continue;
          ids.add(childKey);
          final childParsed = _staticFilterData(childMap);
          if (childParsed != null) list.add(childParsed);
        }
      }
    }
    return list;
  }

  static MusicItem? _staticFilterData(Map<String, dynamic> raw) {
    // 支持搜索 API（大写字段）和排行榜 API（小写字段）
    final fileHash = raw['FileHash'] as String? ?? raw['hash'] as String? ?? '';
    if (fileHash.isEmpty) return null;

    final singers = raw['Singers'] as List<dynamic>? ?? raw['authors'] as List<dynamic>? ?? [];
    final duration = int.tryParse(raw['Duration']?.toString() ?? raw['duration']?.toString() ?? '0') ?? 0;

    // 排行榜 API 的 singers 格式: [{author_name: 'xxx'}]
    String singerName;
    if (singers.isNotEmpty && singers.first is Map) {
      final firstSinger = singers.first as Map;
      if (firstSinger.containsKey('author_name')) {
        singerName = singers.map((s) => (s as Map)['author_name']?.toString() ?? '').where((s) => s.isNotEmpty).join('、');
      } else {
        singerName = _staticFormatSingerName(singers, nameKey: 'name');
      }
    } else {
      singerName = _staticFormatSingerName(singers, nameKey: 'name');
    }

    return MusicItem(
      id: fileHash,
      name: (raw['SongName'] as String? ?? raw['songname'] as String? ?? '').trim(),
      singer: singerName.isEmpty ? '未知歌手' : singerName,
      source: 'kg',
      platform: 'kg',
      artwork: fileHash.isNotEmpty ? 'http://imge.kugou.com/1024/1024/$fileHash.jpg' : '',
      url: '',
      songmid: raw['Audioid']?.toString() ?? raw['audio_id']?.toString() ?? '',
      hash: fileHash,
      duration: Duration(seconds: duration),
      album: (raw['AlbumName'] as String? ?? raw['remark'] as String? ?? '').trim(),
    );
  }

  static String _staticFormatSingerName(List<dynamic> singers, {String nameKey = 'name'}) {
    if (singers.isEmpty) return '未知歌手';
    return singers.map((s) => (s as Map)[nameKey]?.toString() ?? '').where((s) => s.isNotEmpty).join('、');
  }

  List<MusicItem> _handleResult(List<dynamic> rawData) {
    return _staticHandleResult(rawData);
  }

  MusicItem? _filterData(Map<String, dynamic> raw) {
    return _staticFilterData(raw);
  }

  @override
  Future<String?> getMusicUrl(MusicItem music, {String quality = '128k'}) async {
    final hash = music.hash ?? music.songmid ?? music.id;
    if (hash.isEmpty) return null;

    // 方案1: 酷狗 CDN v2 接口
    try {
      final key = md5String('${hash}kgcloudv2');
      final urlDio = createDioForService();

      final response = await urlDio.get(
        'http://trackercdn.kugou.com/i/v2/',
        queryParameters: {
          'key': key,
          'behavior': 'play',
          'pid': '2',
          'cmd': '25',
          'version': '9108',
          'hash': hash,
        },
      );

      final body = response.data;
      if (body is Map) {
        final url = body['url'];
        if (url is String && url.isNotEmpty) return url;
        final data = body['data'];
        if (data is List && data.isNotEmpty && data[0] is Map) {
          return data[0]['url'] as String?;
        }
      }
    } catch (e) {
      debugPrint('[KG] trackercdn v2 接口失败: $e');
    }

    // 方案2: 酷狗 H5 接口
    try {
      final urlDio = createDioForService(headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36',
        'Referer': 'https://www.kugou.com/',
      });

      final response = await urlDio.get(
        'https://wwwapi.kugou.com/yy/index.php',
        queryParameters: {
          'r': 'play/getdata',
          'hash': hash,
          'dfid': '2SSV0c1eL1Na0W0W0c0c0c0c',
          'mid': '2SSV0c1eL1Na0W0W0c0c0c0c',
          'platid': '4',
          'album_id': music.album,
        },
      );

      final body = response.data;
      if (body is Map && body['status'] == 1) {
        final playUrl = body['data']?['play_url'] as String?;
        if (playUrl != null && playUrl.isNotEmpty) return playUrl;
      }
    } catch (e) {
      debugPrint('[KG] H5 接口失败: $e');
    }

    return null;
  }

  @override
  Future<String?> getLyric(MusicItem music) async {
    try {
      final hash = music.hash ?? music.songmid ?? music.id;
      if (hash.isEmpty) return null;

      final lyricDio = createDioForService(headers: {
        'KG-RC': '1',
        'KG-THash': 'expand_search_manager.cpp:852736169:451',
        'User-Agent': 'KuGou2012-9020-ExpandSearchManager',
      });

      final searchResp = await lyricDio.get(
        'http://lyrics.kugou.com/search',
        queryParameters: {
          'ver': '1',
          'man': 'yes',
          'client': 'pc',
          'keyword': '${music.name} ${music.singer}',
          'hash': hash,
          'timelength': music.duration.inMilliseconds.toString(),
        },
      );

      final searchBody = searchResp.data;
      if (searchBody is! Map) return null;

      final candidates = searchBody['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return null;

      final first = candidates[0] as Map;
      final id = first['id'];
      final accessKey = first['accesskey'];

      final dlResp = await lyricDio.get(
        'http://lyrics.kugou.com/download',
        queryParameters: {
          'ver': '1',
          'client': 'pc',
          'id': id.toString(),
          'accesskey': accessKey,
          'fmt': 'lrc',
          'charset': 'utf8',
        },
      );

      final dlBody = dlResp.data;
      if (dlBody is! Map) return null;

      final content = dlBody['content'] as String?;
      if (content == null || content.isEmpty) return null;

      return utf8.decode(base64Decode(content));
    } catch (e) {
      return null;
    }
  }

  @override
  MusicItem parseItem(Map<String, dynamic> raw, String source) {
    return _filterData(raw) ?? MusicItem(id: '', name: '', singer: '', source: 'kg', platform: 'kg');
  }

  @override
  Future<List<LeaderboardCategory>> getLeaderboardCategories() async {
    return const [
      LeaderboardCategory(id: 'kg:8888', name: 'TOP500', platform: 'kg'),
      LeaderboardCategory(id: 'kg:6666', name: '飙升榜', platform: 'kg'),
      LeaderboardCategory(id: 'kg:23784', name: '网络红歌榜', platform: 'kg'),
      LeaderboardCategory(id: 'kg:24971', name: 'DJ热歌榜', platform: 'kg'),
      LeaderboardCategory(id: 'kg:31308', name: '内地榜', platform: 'kg'),
      LeaderboardCategory(id: 'kg:33160', name: '电音榜', platform: 'kg'),
      LeaderboardCategory(id: 'kg:31310', name: '欧美榜', platform: 'kg'),
      LeaderboardCategory(id: 'kg:33165', name: '粤语金曲榜', platform: 'kg'),
    ];
  }

  @override
  Future<List<MusicItem>> getLeaderboardSongs(String leaderboardId, {int page = 1, int limit = 100}) async {
    try {
      final parts = leaderboardId.split(':');
      final bangid = parts.length == 2 ? parts[1] : leaderboardId;

      debugPrint('[KG] getLeaderboardSongs: bangid=$bangid');

      final response = await _dio.get(
        'http://mobilecdnbj.kugou.com/api/v3/rank/song',
        queryParameters: {
          'version': '9108',
          'ranktype': '1',
          'plat': '0',
          'pagesize': limit.toString(),
          'area_code': '1',
          'page': page.toString(),
          'rankid': bangid,
          'with_res_tag': '0',
          'show_portrait_mv': '1',
        },
      );

      final body = response.data;
      debugPrint('[KG] getLeaderboardSongs response: ${body.runtimeType}');
      
      Map<String, dynamic> bodyMap;
      if (body is Map) {
        bodyMap = body.map((k, v) => MapEntry(k.toString(), v));
      } else if (body is String) {
        try {
          bodyMap = (jsonDecode(body) as Map).map((k, v) => MapEntry(k.toString(), v));
        } catch (e) {
          debugPrint('[KG] getLeaderboardSongs: jsonDecode failed: $e');
          return [];
        }
      } else {
        debugPrint('[KG] getLeaderboardSongs: unexpected type');
        return [];
      }
      
      if (bodyMap['errcode'] != 0) {
        debugPrint('[KG] getLeaderboardSongs: errcode=${bodyMap['errcode']}');
        return [];
      }

      final info = bodyMap['data']?['info'] as List<dynamic>?;
      if (info == null) {
        debugPrint('[KG] getLeaderboardSongs: no info in response');
        return [];
      }

      debugPrint('[KG] getLeaderboardSongs: ${info.length} songs');

      return info.map((item) => _filterData(item as Map<String, dynamic>) ?? MusicItem(id: '', name: '', singer: '', source: 'kg', platform: 'kg')).toList();
    } catch (e) {
      debugPrint('[KG] getLeaderboardSongs error: $e');
      return [];
    }
  }

  void dispose() {
    _dio.close();
  }
}
