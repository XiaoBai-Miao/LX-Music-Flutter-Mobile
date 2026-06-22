import '../../../features/player/domain/music_item.dart';
import 'music_platform.dart';
import 'kw_source.dart';
import 'kg_source.dart';
import 'tx_source.dart';
import 'wy_source.dart';
import 'mg_source.dart';

class BuiltInSourceManager {
  final Map<String, MusicPlatform> _platforms = {};

  BuiltInSourceManager() {
    _register(KwSource());
    _register(KgSource());
    _register(TxSource());
    _register(WySource());
    _register(MgSource());
  }

  void _register(MusicPlatform platform) {
    _platforms[platform.id] = platform;
  }

  MusicPlatform? get(String id) => _platforms[id];

  List<MusicPlatform> get all => _platforms.values.toList();

  List<String> get allIds => _platforms.keys.toList();

  Future<List<MusicItem>> search(String platformId, String keyword, {int page = 1, int limit = 20}) async {
    final platform = _platforms[platformId];
    if (platform == null) return [];
    return platform.search(keyword, page: page, limit: limit);
  }

  Future<String?> getMusicUrl(String platformId, MusicItem music, {String quality = '128k'}) async {
    final platform = _platforms[platformId];
    if (platform == null) return null;
    return platform.getMusicUrl(music, quality: quality);
  }

  Future<String?> getLyric(String platformId, MusicItem music) async {
    final platform = _platforms[platformId];
    if (platform == null) return null;
    return platform.getLyric(music);
  }

  Future<List<LeaderboardCategory>> getLeaderboardCategories(String platformId) async {
    final platform = _platforms[platformId];
    if (platform == null) return [];
    return platform.getLeaderboardCategories();
  }

  Future<List<MusicItem>> getLeaderboardSongs(String platformId, String leaderboardId, {int page = 1, int limit = 100}) async {
    final platform = _platforms[platformId];
    if (platform == null) return [];
    return platform.getLeaderboardSongs(leaderboardId, page: page, limit: limit);
  }

  // 获取所有平台的排行榜分类
  Future<List<LeaderboardCategory>> getAllLeaderboardCategories() async {
    final categories = <LeaderboardCategory>[];
    for (final platform in _platforms.values) {
      final cats = await platform.getLeaderboardCategories();
      categories.addAll(cats);
    }
    return categories;
  }

  Future<List<MusicItem>> searchSongLists(String platformId, String keyword, {int page = 1, int limit = 20}) async {
    final platform = _platforms[platformId];
    if (platform == null) return [];
    return platform.searchSongLists(keyword, page: page, limit: limit);
  }

  Future<List<MusicItem>> getSongListDetail(String platformId, String songListId, {int page = 1, int limit = 50}) async {
    final platform = _platforms[platformId];
    if (platform == null) return [];
    return platform.getSongListDetail(songListId, page: page, limit: limit);
  }

  void dispose() {
    for (final platform in _platforms.values) {
      if (platform is KwSource) platform.dispose();
      if (platform is KgSource) platform.dispose();
      if (platform is TxSource) platform.dispose();
      if (platform is WySource) platform.dispose();
      if (platform is MgSource) platform.dispose();
    }
  }
}
