import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../presentation/lyric_provider.dart';
import '../../player/presentation/player_provider.dart';
import '../../player/domain/music_item.dart';

class LyricView extends ConsumerStatefulWidget {
  final bool isFullScreen;

  const LyricView({super.key, this.isFullScreen = false});

  @override
  ConsumerState<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends ConsumerState<LyricView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  int _lastHighlightIndex = -1;
  bool _isUserScrolling = false;
  bool _scrollListenerAttached = false;

  void _attachScrollListener() {
    if (_scrollListenerAttached || !_scrollController.hasClients) return;
    _scrollListenerAttached = true;

    _scrollController.position.isScrollingNotifier.addListener(() {
      if (_scrollController.position.isScrollingNotifier.value) {
        _isUserScrolling = true;
      } else {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _isUserScrolling = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _getKey(int index) {
    return _lineKeys.putIfAbsent(index, () => GlobalKey());
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = ref.watch(currentLyricProvider);
    final currentLineIndex = ref.watch(currentLineIndexProvider);
    final currentMusic = ref.watch(currentMusicProvider);

    if (lyrics.isEmpty) {
      return _buildEmptyState(currentMusic);
    }

    if (currentLineIndex != _lastHighlightIndex && currentLineIndex >= 0 && !_isUserScrolling) {
      _lastHighlightIndex = currentLineIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _attachScrollListener();
        _scrollToLine(currentLineIndex);
      });
    }

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: const [0.0, 0.1, 0.9, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.symmetric(
          vertical: widget.isFullScreen ? 150 : 80,
        ),
        itemCount: lyrics.lines.length,
        itemBuilder: (context, index) {
          final line = lyrics.lines[index];
          final isCurrent = index == currentLineIndex;

          return GestureDetector(
            key: _getKey(index),
            onTap: () {
              final playerService = ref.read(playerServiceProvider);
              playerService.seek(line.time);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              padding: EdgeInsets.symmetric(
                vertical: widget.isFullScreen ? 12 : 8,
                horizontal: 24,
              ),
              child: Column(
                children: [
                  Text(
                    line.text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isCurrent
                          ? (widget.isFullScreen ? AppColors.textPrimary : AppColors.amber)
                          : (widget.isFullScreen ? AppColors.textPrimary.withAlpha(80) : AppColors.textMuted),
                      fontSize: isCurrent
                          ? (widget.isFullScreen ? 20 : 16)
                          : (widget.isFullScreen ? 16 : 14),
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (line.translation != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      line.translation!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isCurrent
                            ? AppColors.textSecondary
                            : AppColors.textMuted.withAlpha(60),
                        fontSize: isCurrent
                            ? (widget.isFullScreen ? 14 : 12)
                            : (widget.isFullScreen ? 12 : 11),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(MusicItem? currentMusic) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.music_note, size: 34, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            const Text(
              '暂无歌词',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              currentMusic != null ? '${currentMusic.name} - ${currentMusic.singer}' : '该歌曲暂时没有可用的歌词文件',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => _searchLyric(currentMusic),
              child: _buildOutlineButton('搜索歌词'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutlineButton(String text) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderActive),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  void _scrollToLine(int index) {
    if (!_scrollController.hasClients) return;
    final key = _lineKeys[index];
    if (key?.currentContext == null) return;

    try {
      final RenderBox box = key!.currentContext!.findRenderObject() as RenderBox;
      final RenderBox scrollBox = _scrollController.position.context.storageContext.findRenderObject() as RenderBox;

      final offset = box.localToGlobal(Offset.zero, ancestor: scrollBox);
      final targetScroll = _scrollController.offset + offset.dy - (scrollBox.size.height / 2) + (box.size.height / 2);

      _scrollController.animateTo(
        targetScroll.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } catch (_) {
      // 忽略滚动异常
    }
  }

  Future<void> _searchLyric(MusicItem? music) async {
    if (music == null) return;
    await ref.read(currentLyricProvider.notifier).loadLyric(music);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在搜索歌词...'), duration: Duration(seconds: 1)),
      );
    }
  }
}
