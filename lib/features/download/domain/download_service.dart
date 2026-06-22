import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/network/music_source_service.dart';
import '../../../core/storage/storage_service.dart';
import '../domain/download_task.dart';
import '../../player/domain/music_item.dart';

class DownloadService {
  final Dio _dio = Dio();
  final List<DownloadTask> _tasks = [];
  final StreamController<List<DownloadTask>> _tasksController =
      StreamController<List<DownloadTask>>.broadcast();

  String? _downloadDir;
  int _maxConcurrent = 3;
  int _currentDownloading = 0;
  MusicSourceService? _musicSourceService;
  StorageService? _storage;
  bool _initialized = false;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  Stream<List<DownloadTask>> get tasksStream => _tasksController.stream;
  int get maxCacheSizeMB => 2048;

  DownloadService();

  void setMusicSourceService(MusicSourceService service) {
    _musicSourceService = service;
  }

  Future<void> init() async {
    if (_initialized) return;
    _storage = await StorageService.instance;
    _loadFromStorage();
    await _initDownloadDir();
    _initialized = true;
  }

  void _loadFromStorage() {
    final saved = _storage!.getJsonList('download_tasks');
    if (saved.isEmpty) return;
    _tasks.clear();
    for (final json in saved) {
      _tasks.add(DownloadTask.fromJson(json as Map<String, dynamic>));
    }
    _tasksController.add(_tasks);
  }

  Future<void> _saveToStorage() async {
    _storage ??= await StorageService.instance;
    final data = _tasks.map((t) => t.toJson()).toList();
    await _storage!.setJsonList('download_tasks', data);
  }

  Future<void> _initDownloadDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    _downloadDir = '${appDir.path}/downloads';
    await Directory(_downloadDir!).create(recursive: true);
  }

  // 添加下载任务
  Future<void> addTask(MusicItem music, {String? quality}) async {
    // 检查是否已存在
    if (_tasks.any((t) => t.musicId == music.id && t.status != DownloadStatus.failed)) {
      return;
    }

    // 确保下载目录已初始化
    if (_downloadDir == null) {
      await _initDownloadDir();
    }

    final task = DownloadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      musicId: music.id,
      name: music.name,
      singer: music.singer,
      url: music.url,
      createdAt: DateTime.now(),
      quality: quality,
      // 保存完整的元数据
      platform: music.platform,
      source: music.source,
      songmid: music.songmid,
      hash: music.hash,
      album: music.album,
      artwork: music.artwork,
      duration: music.duration.inSeconds,
    );

    _tasks.add(task);
    _tasksController.add(_tasks);
    await _saveToStorage();

    // 自动开始下载
    _startDownload(task, music: music, quality: quality);
  }

  // 批量添加下载任务
  Future<void> addTasks(List<MusicItem> songs, {String? quality}) async {
    for (final song in songs) {
      await addTask(song, quality: quality);
    }
  }

  // 开始下载
  Future<void> _startDownload(DownloadTask task, {MusicItem? music, String? quality}) async {
    if (_currentDownloading >= _maxConcurrent) {
      return;
    }

    // 确保下载目录已初始化
    if (_downloadDir == null) {
      await _initDownloadDir();
    }

    _currentDownloading++;
    _updateTask(task.id, status: DownloadStatus.downloading);

    try {
      // 获取下载链接：优先用 task.url，否则通过 MusicSourceService 获取
      String? downloadUrl = task.url;
      if ((downloadUrl == null || downloadUrl.isEmpty) && _musicSourceService != null && music != null) {
        downloadUrl = await _musicSourceService!.getPlayUrl(music, quality: quality ?? '128k');
      }

      if (downloadUrl == null || downloadUrl.isEmpty) {
        _updateTask(task.id, status: DownloadStatus.failed, errorMsg: '无法获取下载链接');
        return;
      }

      final fileName = '${task.musicId}.mp3';
      final savePath = '$_downloadDir/$fileName';

      await _dio.download(
        downloadUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            _updateTask(task.id, progress: progress);
          }
        },
      );

      _updateTask(
        task.id,
        status: DownloadStatus.completed,
        progress: 1.0,
        savePath: savePath,
        completedAt: DateTime.now(),
      );

      // 下载完成后获取文件大小
      final file = File(savePath);
      if (await file.exists()) {
        final size = await file.length();
        _updateTask(task.id, fileSize: size);
      }
    } catch (e) {
      _updateTask(task.id, status: DownloadStatus.failed, errorMsg: e.toString());
    } finally {
      _currentDownloading--;
      _processQueue();
    }
  }

  // 处理下载队列
  void _processQueue() {
    final pendingTasks = _tasks
        .where((t) => t.status == DownloadStatus.pending)
        .take(_maxConcurrent - _currentDownloading)
        .toList();

    for (final task in pendingTasks) {
      _startDownload(task);
    }
  }

  // 暂停下载
  void pauseTask(String taskId) {
    _updateTask(taskId, status: DownloadStatus.paused);
  }

  // 恢复下载
  void resumeTask(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    if (task.status == DownloadStatus.paused) {
      _updateTask(taskId, status: DownloadStatus.pending);
      _processQueue();
    }
  }

  // 取消下载
  void cancelTask(String taskId) {
    _tasks.removeWhere((t) => t.id == taskId);
    _tasksController.add(_tasks);
    _saveToStorage();
  }

  // 重试下载
  void retryTask(String taskId) {
    _updateTask(taskId, status: DownloadStatus.pending, progress: 0.0);
    _processQueue();
  }

  // 删除已下载文件
  Future<void> deleteDownloaded(String taskId) async {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    if (task.savePath != null) {
      final file = File(task.savePath!);
      if (await file.exists()) {
        await file.delete();
      }
    }
    _tasks.removeWhere((t) => t.id == taskId);
    _tasksController.add(_tasks);
    await _saveToStorage();
  }

  // 更新任务状态
  void _updateTask(String taskId, {
    DownloadStatus? status,
    double? progress,
    int? speed,
    String? errorMsg,
    String? savePath,
    DateTime? completedAt,
    int? fileSize,
  }) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index < 0) return;

    final task = _tasks[index];
    _tasks[index] = task.copyWith(
      status: status,
      progress: progress,
      speed: speed,
      errorMsg: errorMsg,
      savePath: savePath,
      completedAt: completedAt,
      fileSize: fileSize,
    );
    _tasksController.add(_tasks);
    _saveToStorage();
  }

  // 获取已下载歌曲
  Future<List<DownloadTask>> getDownloadedTasks() async {
    return _tasks.where((t) => t.status == DownloadStatus.completed).toList();
  }

  // 检查歌曲是否已下载
  bool isDownloaded(String musicId) {
    return _tasks.any((t) => t.musicId == musicId && t.status == DownloadStatus.completed);
  }

  // 获取已下载文件路径
  String? getDownloadPath(String musicId) {
    try {
      final task = _tasks.firstWhere(
        (t) => t.musicId == musicId && t.status == DownloadStatus.completed,
      );
      return task.savePath;
    } catch (_) {
      return null;
    }
  }

  // 获取缓存大小
  Future<int> getCacheSize() async {
    int totalSize = 0;
    for (final task in _tasks) {
      if (task.savePath != null) {
        final file = File(task.savePath!);
        if (await file.exists()) {
          totalSize += await file.length();
        }
      }
    }
    return totalSize;
  }

  // 清理缓存
  Future<void> clearCache() async {
    for (final task in _tasks.where((t) => t.status == DownloadStatus.completed)) {
      if (task.savePath != null) {
        final file = File(task.savePath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }
    _tasks.clear();
    _tasksController.add(_tasks);
    await _saveToStorage();
  }

  // 按 LRU 策略清理缓存
  Future<void> clearCacheWithLRU({required int maxBytes}) async {
    final completedTasks = _tasks
        .where((t) => t.status == DownloadStatus.completed)
        .toList()
      ..sort((a, b) => (a.completedAt ?? a.createdAt).compareTo(b.completedAt ?? b.createdAt));

    int currentSize = await getCacheSize();

    for (final task in completedTasks) {
      if (currentSize <= maxBytes) break;

      if (task.savePath != null) {
        final file = File(task.savePath!);
        if (await file.exists()) {
          final fileSize = await file.length();
          await file.delete();
          currentSize -= fileSize;
          _tasks.remove(task);
        }
      }
    }
    _tasksController.add(_tasks);
    await _saveToStorage();
  }

  void dispose() {
    _dio.close();
    _tasksController.close();
  }
}
