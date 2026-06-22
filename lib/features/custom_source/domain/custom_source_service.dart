import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/custom_source.dart';
import '../domain/custom_source_engine.dart';
import '../../player/domain/music_item.dart';

class CustomSourceService {
  static const String _storageKey = 'custom_sources';
  final List<CustomSource> _sources = [];
  final Map<String, CustomSourceEngine> _engines = {};
  final Dio _dio = Dio();
  SharedPreferences? _prefs;

  List<CustomSource> get sources => List.unmodifiable(_sources);
  List<CustomSource> get enabledSources => _sources.where((s) => s.isEnabled).toList();

  // 初始化
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadSources();
  }

  // 加载自定义源
  Future<void> _loadSources() async {
    final jsonStr = _prefs?.getString(_storageKey);
    if (jsonStr != null) {
      final List<dynamic> jsonList = json.decode(jsonStr);
      _sources.clear();
      _sources.addAll(jsonList.map((j) => CustomSource.fromJson(j)));
    }
  }

  // 保存自定义源
  Future<void> _saveSources() async {
    final jsonList = _sources.map((s) => s.toJson()).toList();
    await _prefs?.setString(_storageKey, json.encode(jsonList));
  }

  // 添加自定义源
  Future<void> addSource(CustomSource source) async {
    _sources.add(source);
    await _saveSources();
  }

  // 更新自定义源
  Future<void> updateSource(CustomSource source) async {
    final index = _sources.indexWhere((s) => s.id == source.id);
    if (index >= 0) {
      _sources[index] = source.copyWith(updatedAt: DateTime.now());
      await _saveSources();
      // 清除旧引擎
      _engines[source.id]?.dispose();
      _engines.remove(source.id);
    }
  }

  // 删除自定义源
  Future<void> deleteSource(String id) async {
    _sources.removeWhere((s) => s.id == id);
    await _saveSources();
    _engines[id]?.dispose();
    _engines.remove(id);
  }

  // 切换启用状态 (唯一启用)
  Future<void> toggleSource(String id) async {
    final index = _sources.indexWhere((s) => s.id == id);
    if (index >= 0) {
      final bool willEnable = !_sources[index].isEnabled;
      
      for (int i = 0; i < _sources.length; i++) {
        if (i == index) {
          _sources[i] = _sources[i].copyWith(
            isEnabled: willEnable,
            updatedAt: DateTime.now(),
          );
        } else if (willEnable) {
          // 如果某一个源被启用，则关闭其他所有源
          _sources[i] = _sources[i].copyWith(isEnabled: false);
        }
      }
      await _saveSources();
    }
  }

  // 获取或创建引擎
  CustomSourceEngine _getEngine(String sourceId) {
    if (!_engines.containsKey(sourceId)) {
      _engines[sourceId] = CustomSourceEngine();
    }
    return _engines[sourceId]!;
  }

  // 获取指定源的事件流
  Stream<Map<String, dynamic>> getEventStream(String sourceId) {
    return _getEngine(sourceId).eventStream;
  }

  // 使用自定义源搜索
  Future<List<MusicItem>> searchWithSource(
    String sourceId,
    String keyword, {
    String source = 'kw', // 平台标识，如 kw, kg, wy
    int page = 1,
    int limit = 20,
    String type = 'music',
  }) async {
    final customSource = _sources.firstWhere(
      (s) => s.id == sourceId,
      orElse: () => throw Exception('源不存在'),
    );

    if (!customSource.isEnabled) return [];

    try {
      final engine = _getEngine(sourceId);
      await engine.loadSource(customSource);
      return await engine.search(keyword, source: source, page: page, limit: limit, type: type);
    } catch (e) {
      return [];
    }
  }

  // 获取播放链接
  Future<String?> getMusicUrl(String sourceId, MusicItem music) async {
    try {
      final customSource = _sources.firstWhere(
        (s) => s.id == sourceId,
        orElse: () => throw Exception('源不存在'),
      );
      if (!customSource.isEnabled) return null;

      final engine = _getEngine(sourceId);
      await engine.loadSource(customSource); // 确保脚本已加载
      return await engine.getMusicUrl(music);
    } catch (e) {
      return null;
    }
  }

  // 获取歌词
  Future<String?> getLyric(String sourceId, MusicItem music) async {
    try {
      final customSource = _sources.firstWhere(
        (s) => s.id == sourceId,
        orElse: () => throw Exception('源不存在'),
      );
      if (!customSource.isEnabled) return null;

      final engine = _getEngine(sourceId);
      await engine.loadSource(customSource); // 确保脚本已加载
      return await engine.getLyric(music);
    } catch (e) {
      return null;
    }
  }

  // 获取歌单详情
  Future<List<MusicItem>> getSongListDetail(String sourceId, String id, {int page = 1}) async {
    try {
      final engine = _getEngine(sourceId);
      return await engine.getSongListDetail(id, page: page);
    } catch (e) {
      return [];
    }
  }

  // 导入自定义源（JSON 字符串）
  Future<bool> importSource(String jsonStr) async {
    try {
      final json = jsonDecode(jsonStr);
      final source = CustomSource.fromJson(json);
      
      if (_sources.any((s) => s.id == source.id)) {
        await updateSource(source);
      } else {
        await addSource(source);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  // 导入 LX Music 格式的脚本
  Future<bool> importLxMusicScript(String script) async {
    try {
      // 从脚本中提取元数据
      final nameMatch = RegExp(r'@name\s+(.+)').firstMatch(script);
      final descMatch = RegExp(r'@description\s+(.+)').firstMatch(script);
      final versionMatch = RegExp(r'@version\s+(.+)').firstMatch(script);
      final authorMatch = RegExp(r'@author\s+(.+)').firstMatch(script);

      final name = nameMatch?.group(1)?.trim() ?? '未命名音源';
      final description = descMatch?.group(1)?.trim() ?? '';
      final version = versionMatch?.group(1)?.trim() ?? '1.0.0';
      final author = authorMatch?.group(1)?.trim() ?? '未知';

      // 检查是否已存在同名且同作者的源，如果是则更新
      final existingIndex = _sources.indexWhere((s) => s.name == name && s.author == author);
      
      final source = CustomSource(
        id: existingIndex >= 0 ? _sources[existingIndex].id : DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        description: description,
        version: version,
        author: author,
        script: script,
        createdAt: existingIndex >= 0 ? _sources[existingIndex].createdAt : DateTime.now(),
        updatedAt: DateTime.now(),
        isEnabled: existingIndex >= 0 ? _sources[existingIndex].isEnabled : false,
      );

      if (existingIndex >= 0) {
        _sources[existingIndex] = source;
        // 清除旧引擎
        _engines[source.id]?.dispose();
        _engines.remove(source.id);
      } else {
        _sources.add(source);
      }
      await _saveSources();
      return true;
    } catch (e) {
      return false;
    }
  }

  // 从网络导入脚本
  Future<bool> importSourceFromUrl(String url) async {
    try {
      final response = await _dio.get(url, options: Options(responseType: ResponseType.plain));
      final script = response.data.toString();
      if (validateScript(script)) {
        return await importLxMusicScript(script);
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // 导出自定义源
  String exportSource(String id) {
    final source = _sources.firstWhere((s) => s.id == id);
    return json.encode(source.toJson());
  }

  // 导出所有自定义源
  String exportAllSources() {
    final jsonList = _sources.map((s) => s.toJson()).toList();
    return json.encode(jsonList);
  }

  // 验证脚本格式
  bool validateScript(String script) {
    // 检查是否是 LX Music 格式
    if (script.contains('globalThis.lx') || script.contains('EVENT_NAMES')) {
      return true;
    }
    // 检查是否是简单格式
    return script.contains('search') || script.contains('getMusicUrl');
  }

  // 检查是否是 LX Music 格式脚本
  bool isLxMusicScript(String script) {
    return script.contains('globalThis.lx') || 
           script.contains('EVENT_NAMES') ||
           script.contains('on(EVENT_NAMES.request');
  }

  void dispose() {
    for (final engine in _engines.values) {
      engine.dispose();
    }
    _engines.clear();
  }
}
