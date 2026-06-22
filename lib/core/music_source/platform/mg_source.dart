import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../features/player/domain/music_item.dart';
import 'music_platform.dart';
import 'source_utils.dart';

const _signatureMd5 = '6cdc72a439cef99a3418d2a78aa28c73';
const _deviceId = '963B7AA0D21511ED807EE5846EC87D20';

class MgSource extends MusicPlatform {
  @override
  String get id => 'mg';

  @override
  String get name => '咪咕音乐';

  late final Dio _dio;

  MgSource() {
    _dio = createDio();
    _dio.options.headers.addAll({
      'Referer': 'https://music.migu.cn/',
      'User-Agent': 'Mozilla/5.0 (Linux; U; Android 11.0.0; zh-cn; MI 11 Build/OPR1.170623.032) AppleWebKit/534.30 (KHTML, like Gecko) Version/4.0 Mobile Safari/534.30',
    });
  }

  Map<String, String> _createSignature(String str) {
    final time = DateTime.now().millisecondsSinceEpoch.toString();
    final signStr = '$str$_signatureMd5${'yyapp2d16148780a1dcc7408e06336b98cfd50'}$_deviceId$time';
    final sign = md5String(signStr);
    return {'sign': sign, 'deviceId': _deviceId, 'timestamp': time};
  }

  @override
  Future<List<MusicItem>> search(String keyword, {int page = 1, int limit = 20}) async {
    try {
      final sigData = _createSignature(keyword);

      final response = await _dio.get(
        'https://jadeite.migu.cn/music_search/v3/search/searchAll',
        queryParameters: {
          'isCorrect': '0',
          'isCopyright': '1',
          'searchSwitch': '{"song":1,"album":0,"singer":0,"tagSong":1,"mvSong":0,"bestShow":1,"songlist":0,"lyricSong":0}',
          'pageSize': limit.toString(),
          'text': keyword,
          'pageNo': page.toString(),
          'sort': '0',
          'sid': 'USS',
        },
        options: Options(headers: {
          'uiVersion': 'A_music_3.6.1',
          'deviceId': sigData['deviceId'],
          'timestamp': sigData['timestamp'],
          'sign': sigData['sign'],
          'channel': '0146921',
        }),
      ).timeout(const Duration(seconds: 10));

      final body = response.data;
      if (body == null) return [];

      final results = await compute(_parseSearchResult, body);
      return results;
    } catch (e) {
      return [];
    }
  }

  static List<MusicItem> _parseSearchResult(dynamic body) {
    if (body is! Map || body['code'] != '000000') return [];

    final songResultData = body['songResultData'] as Map?;
    if (songResultData == null) return [];

    final resultList = songResultData['resultList'] as List<dynamic>?;
    if (resultList == null || resultList.isEmpty) return [];

    return _staticFilterData(resultList);
  }

  static List<MusicItem> _staticFilterData(List<dynamic> rawData) {
    final ids = <String>{};
    final list = <MusicItem>[];

    for (final outer in rawData) {
      if (outer is! List) continue;
      for (final item in outer) {
        final map = item as Map<String, dynamic>;
        final copyrightId = map['copyrightId'] as String? ?? '';
        final songId = map['songId'] as String? ?? '';

        if (songId.isEmpty || copyrightId.isEmpty || ids.contains(copyrightId)) continue;
        ids.add(copyrightId);

        final duration = int.tryParse(map['duration']?.toString() ?? '0') ?? 0;
        final singerList = map['singerList'] as List<dynamic>? ?? [];
        final img = map['img3'] as String? ?? map['img2'] as String? ?? map['img1'] as String? ?? '';
        final lrcUrl = map['lrcUrl'] as String? ?? '';
        final mrcUrl = map['mrcurl'] as String? ?? '';

        list.add(MusicItem(
          id: songId,
          name: (map['name'] as String? ?? '').trim(),
          singer: _staticFormatSingerName(singerList, nameKey: 'name'),
          source: 'mg',
          platform: 'mg',
          artwork: img.isNotEmpty ? (img.startsWith('http') ? img : 'http://d.musicapp.migu.cn$img') : '',
          url: '',
          songmid: songId,
          duration: Duration(seconds: duration),
          album: (map['album'] as String? ?? '').trim(),
          lyricsUrl: mrcUrl.isNotEmpty ? mrcUrl : lrcUrl,
        ));
      }
    }
    return list;
  }

  static String _staticFormatSingerName(List<dynamic> singers, {String nameKey = 'name'}) {
    if (singers.isEmpty) return '未知歌手';
    return singers.map((s) => (s as Map)[nameKey]?.toString() ?? '').where((s) => s.isNotEmpty).join('、');
  }

  List<MusicItem> _filterData(List<dynamic> rawData) {
    return _staticFilterData(rawData);
  }

  @override
  Future<String?> getMusicUrl(MusicItem music, {String quality = '128k'}) async {
    // 桌面版使用 copyrightId 获取播放链接
    final copyrightId = music.meta?['copyrightId'] as String? ?? music.songmid ?? music.id;
    if (copyrightId.isEmpty) return null;

    // 方案1: migu.cn v3 接口
    try {
      final urlDio = createDioForService(headers: {
        'Referer': 'https://music.migu.cn/',
        'Origin': 'https://music.migu.cn',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36',
      });

      final response = await urlDio.get(
        'https://music.migu.cn/v3/api/music/audioPlayer/getPlayInfo',
        queryParameters: {'copyrightId': copyrightId},
      );

      final body = response.data;
      if (body is! Map) return null;

      final data = body['data'] as Map?;
      if (data == null) return null;

      final playUrl = data['playUrl'] as String?;
      if (playUrl != null && playUrl.isNotEmpty) return playUrl;

      final url = data['url'] as String?;
      if (url != null && url.isNotEmpty) return url;
    } catch (e) {
      debugPrint('[MG] v3 接口失败: $e');
    }

    // 方案2: migu.cn v1 resourceinfo 接口
    try {
      final urlDio = createDioForService(headers: {
        'Referer': 'https://music.migu.cn/',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36',
      });

      final response = await urlDio.post(
        'https://c.musicapp.migu.cn/MIGUM2.0/v1.0/content/resourceinfo.do',
        data: 'resourceType=2&copyrightId=$copyrightId',
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final body = response.data;
      if (body is Map && body['code'] == '000000') {
        final resourceList = body['data']?['resourceList'] as List?;
        if (resourceList != null && resourceList.isNotEmpty) {
          for (final res in resourceList) {
            if (res is! Map) continue;
            final playUrl = res['playUrl'] as String?;
            if (playUrl != null && playUrl.isNotEmpty) {
              return playUrl.replaceAll(r'\/', '/');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[MG] resourceinfo 接口失败: $e');
    }

    return null;
  }

  @override
  Future<String?> getLyric(MusicItem music) async {
    try {
      final lyricUrl = music.lyricsUrl;
      if (lyricUrl == null || lyricUrl.isEmpty) return null;

      final lyricDio = createDioForService(headers: {
        'Referer': 'https://app.c.nf.migu.cn/',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 5.1.1; Nexus 6 Build/LYZ28E) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.115 Mobile Safari/537.36',
        'channel': '0146921',
      });

      final response = await lyricDio.get(lyricUrl);
      final body = response.data;
      if (body is! String || body.isEmpty) return null;

      return body;
    } catch (e) {
      return null;
    }
  }

  @override
  MusicItem parseItem(Map<String, dynamic> raw, String source) {
    final list = _filterData([raw]);
    return list.isNotEmpty ? list.first : MusicItem(id: '', name: '', singer: '', source: 'mg', platform: 'mg');
  }

  @override
  Future<List<LeaderboardCategory>> getLeaderboardCategories() async {
    return const [
      LeaderboardCategory(id: 'mg:27553319', name: '新歌榜', platform: 'mg'),
      LeaderboardCategory(id: 'mg:27186466', name: '热歌榜', platform: 'mg'),
      LeaderboardCategory(id: 'mg:27553408', name: '原创榜', platform: 'mg'),
      LeaderboardCategory(id: 'mg:75959118', name: '音乐风向榜', platform: 'mg'),
      LeaderboardCategory(id: 'mg:76557036', name: '彩铃分贝榜', platform: 'mg'),
      LeaderboardCategory(id: 'mg:76557745', name: '会员臻爱榜', platform: 'mg'),
      LeaderboardCategory(id: 'mg:23189800', name: '港台榜', platform: 'mg'),
      LeaderboardCategory(id: 'mg:23189399', name: '内地榜', platform: 'mg'),
      LeaderboardCategory(id: 'mg:19190036', name: '欧美榜', platform: 'mg'),
      LeaderboardCategory(id: 'mg:83176390', name: '国风金曲榜', platform: 'mg'),
    ];
  }

  @override
  Future<List<MusicItem>> getLeaderboardSongs(String leaderboardId, {int page = 1, int limit = 100}) async {
    try {
      final parts = leaderboardId.split(':');
      final columnId = parts.length == 2 ? parts[1] : leaderboardId;

      debugPrint('[MG] getLeaderboardSongs: columnId=$columnId');

      // 桌面版 leaderboard.js: getUrl(id, page)
      // https://app.c.nf.migu.cn/MIGUM2.0/v1.0/content/querycontentbyId.do?columnId=${id}&needAll=0
      final response = await _dio.get(
        'https://app.c.nf.migu.cn/MIGUM2.0/v1.0/content/querycontentbyId.do',
        queryParameters: {
          'columnId': columnId,
          'needAll': '0',
        },
        options: Options(headers: {
          'Referer': 'https://app.c.nf.migu.cn/',
          'User-Agent': 'Mozilla/5.0 (Linux; Android 5.1.1; Nexus 6 Build/LYZ28E) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.115 Mobile Safari/537.36',
          'channel': '0146921',
        }),
      );

      final body = response.data;
      debugPrint('[MG] getLeaderboardSongs response: ${body.runtimeType}');
      
      Map<String, dynamic> bodyMap;
      if (body is Map) {
        bodyMap = body.map((k, v) => MapEntry(k.toString(), v));
      } else if (body is String) {
        try {
          bodyMap = (jsonDecode(body) as Map).map((k, v) => MapEntry(k.toString(), v));
        } catch (e) {
          debugPrint('[MG] getLeaderboardSongs: jsonDecode failed: $e');
          return [];
        }
      } else {
        debugPrint('[MG] getLeaderboardSongs: unexpected type');
        return [];
      }
      
      if (bodyMap['code'] != '000000') {
        debugPrint('[MG] getLeaderboardSongs: code=${bodyMap['code']}');
        return [];
      }

      // 桌面版: body.columnInfo.contents.map(m => m.objectInfo)
      // 然后 filterMusicInfoList 处理
      final contents = bodyMap['columnInfo']?['contents'] as List<dynamic>?;
      if (contents == null) {
        debugPrint('[MG] getLeaderboardSongs: no contents');
        return [];
      }

      debugPrint('[MG] getLeaderboardSongs: ${contents.length} items');
      if (contents.isNotEmpty) {
        debugPrint('[MG] First content keys: ${(contents[0] as Map).keys}');
        final objectInfo = (contents[0] as Map)['objectInfo'];
        if (objectInfo != null) {
          debugPrint('[MG] First objectInfo keys: ${(objectInfo as Map).keys}');
          debugPrint('[MG] First objectInfo: $objectInfo');
        }
      }

      // 桌面版: contents.map(m => m.objectInfo) -> filterMusicInfoList
      return contents
          .map((item) => _parseLeaderboardItem(item as Map<String, dynamic>))
          .whereType<MusicItem>()
          .toList();
    } catch (e) {
      debugPrint('[MG] getLeaderboardSongs error: $e');
      return [];
    }
  }

  /// 桌面版 leaderboard: filterMusicInfoList(body.columnInfo.contents.map(m => m.objectInfo))
  /// 对应 musicInfo.js filterMusicInfoList
  MusicItem? _parseLeaderboardItem(Map<String, dynamic> item) {
    final objectInfo = item['objectInfo'] as Map<String, dynamic>? ?? item;
    
    final songId = objectInfo['songId']?.toString() ?? '';
    if (songId.isEmpty) return null;

    // 桌面版: formatSingerName(item.artists, 'name')
    final artists = objectInfo['artists'] as List<dynamic>? ?? [];
    final singerName = artists
        .map((a) => (a as Map)['name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .join('、');

    // 桌面版: item.albumImgs?.length ? item.albumImgs[0].img : null
    final albumImgs = objectInfo['albumImgs'] as List<dynamic>?;
    final artwork = (albumImgs != null && albumImgs.isNotEmpty)
        ? (albumImgs[0] as Map)['img']?.toString() ?? ''
        : '';

    // 桌面版: intervalTest = /(\d\d:\d\d)$/.test(item.length)
    final length = objectInfo['length']?.toString() ?? '';
    final durationMatch = RegExp(r'(\d\d:\d\d)$').firstMatch(length);
    final duration = durationMatch != null ? parseDuration(durationMatch.group(1)) : 0;

    return MusicItem(
      id: songId,
      name: (objectInfo['songName'] as String? ?? '').trim(),
      singer: singerName.isEmpty ? '未知歌手' : singerName,
      album: (objectInfo['album'] as String? ?? '').trim(),
      duration: Duration(seconds: duration),
      source: 'mg',
      platform: 'mg',
      songmid: songId,
      artwork: artwork,
      meta: {
        'copyrightId': objectInfo['copyrightId']?.toString() ?? songId,
      },
    );
  }

  void dispose() {
    _dio.close();
  }
}
