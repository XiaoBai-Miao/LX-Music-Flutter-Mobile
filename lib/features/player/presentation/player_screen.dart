import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/music_item.dart';
import '../domain/player_service.dart';
import 'player_provider.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../playlist/presentation/playlist_picker.dart';
import '../../download/presentation/download_provider.dart';
import '../../lyric/presentation/lyric_view.dart';
import '../../lyric/presentation/lyric_provider.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerService = ref.watch(playerServiceProvider);
    final currentMusic = ref.watch(currentMusicProvider);
    final playbackState = ref.watch(playbackStateProvider).value;
    final position = ref.watch(playerPositionProvider);
    final playMode = ref.watch(playModeProvider);

    // 监听全局播放器消息（PlayerScreen 内部也可以监听以确保及时弹出）
    ref.listen<String?>(playerMessageProvider, (previous, next) {
      if (next != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        ref.read(playerMessageProvider.notifier).state = null;
      }
    });

    if (currentMusic == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.music_note, size: 64, color: AppColors.textMuted),
              SizedBox(height: 16),
              Text('暂无播放内容', style: TextStyle(color: AppColors.textMuted)),
            ],
          ),
        ),
      );
    }

    final isPlaying = playbackState?.playing ?? false;
    final duration = ref.watch(durationProvider).value ?? currentMusic.duration;
    final isFavorite = ref.watch(isSongFavoriteProvider(currentMusic.id));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF141828), Color(0xFF0D0F1A), Color(0xFF0A0D18)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context, currentMusic),
              const SizedBox(height: 16),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) => setState(() => _currentPage = index),
                  children: [
                    _buildArtwork(currentMusic.artwork),
                    const LyricView(isFullScreen: true),
                  ],
                ),
              ),
              _buildSongInfo(currentMusic, isFavorite),
              _buildCurrentLyricLine(),
              _buildProgressSection(playerService, position, duration),
              _buildControls(playerService, isPlaying, playMode),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, MusicItem music) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary, size: 20),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_currentPage == 0 ? '正在播放' : '歌词', style: const TextStyle(color: AppColors.textMuted, fontSize: 12, letterSpacing: 2)),
              const SizedBox(height: 6),
              _buildPageIndicator(),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
            onPressed: () => _showMoreMenu(context, music),
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(2, (index) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: _currentPage == index ? 12 : 6,
          height: 4,
          decoration: BoxDecoration(
            color: _currentPage == index ? AppColors.amber : AppColors.textMuted.withAlpha(100),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildArtwork(String? artwork) {
    return Center(
      child: Container(
        width: 300,
        height: 300,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(80),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: artwork != null && artwork.isNotEmpty
              ? Image.network(artwork, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultArtwork())
              : _defaultArtwork(),
        ),
      ),
    );
  }

  Widget _defaultArtwork() {
    return Container(
      color: AppColors.surfaceVariant,
      child: const Icon(Icons.music_note, color: AppColors.textMuted, size: 80),
    );
  }

  Widget _buildSongInfo(MusicItem music, bool isFavorite) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  music.name,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  music.singer,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download, color: AppColors.textSecondary, size: 24),
            onPressed: () {
              ref.read(downloadSongProvider)(music);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已添加到下载队列'), duration: Duration(seconds: 1)),
              );
            },
          ),
          IconButton(
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite ? AppColors.amber : AppColors.textSecondary,
              size: 28,
            ),
            onPressed: () => ref.read(toggleFavoriteProvider)(music),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentLyricLine() {
    final lyrics = ref.watch(currentLyricProvider);
    final currentLineIndex = ref.watch(currentLineIndexProvider);

    if (lyrics.isEmpty || currentLineIndex < 0 || currentLineIndex >= lyrics.lines.length) {
      return const SizedBox.shrink();
    }

    final line = lyrics.lines[currentLineIndex];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            line.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.amber,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (line.translation != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                line.translation!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressSection(PlayerService playerService, Duration position, Duration duration) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: AppColors.amber,
              inactiveTrackColor: AppColors.border,
              thumbColor: AppColors.amber,
            ),
            child: Slider(
              value: position.inMilliseconds.toDouble().clamp(0, duration.inMilliseconds.toDouble()),
              max: duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1,
              onChanged: (val) {
                playerService.seek(Duration(milliseconds: val.toInt()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(position), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                Text(_formatDuration(duration), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(PlayerService playerService, bool isPlaying, PlayMode playMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(
              _getPlayModeIcon(playMode),
              color: AppColors.textMuted,
              size: 22,
            ),
            onPressed: () {
              final nextMode = _getNextPlayMode(playMode);
              ref.read(playModeProvider.notifier).state = nextMode;
              _applyPlayMode(playerService, nextMode);
            },
          ),
          IconButton(
            icon: const Icon(Icons.skip_previous, color: AppColors.textPrimary, size: 32),
            onPressed: playerService.previous,
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.amber,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.amber.withAlpha(60),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: AppColors.black,
                size: 34,
              ),
              onPressed: playerService.togglePlay,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.skip_next, color: AppColors.textPrimary, size: 32),
            onPressed: playerService.next,
          ),
          IconButton(
            icon: const Icon(Icons.queue_music, color: AppColors.textMuted, size: 22),
            onPressed: () => _showPlaylist(context),
          ),
        ],
      ),
    );
  }

  PlayMode _getNextPlayMode(PlayMode current) {
    switch (current) {
      case PlayMode.repeatOne: return PlayMode.sequential;
      case PlayMode.sequential: return PlayMode.shuffle;
      case PlayMode.shuffle: return PlayMode.repeatOne;
    }
  }

  IconData _getPlayModeIcon(PlayMode mode) {
    switch (mode) {
      case PlayMode.repeatOne: return Icons.repeat_one;
      case PlayMode.sequential: return Icons.trending_flat;
      case PlayMode.shuffle: return Icons.shuffle;
    }
  }

  void _applyPlayMode(PlayerService playerService, PlayMode mode) {
    switch (mode) {
      case PlayMode.repeatOne:
        playerService.setRepeatMode(AudioServiceRepeatMode.one);
        playerService.setShuffleMode(false);
        break;
      case PlayMode.sequential:
        playerService.setRepeatMode(AudioServiceRepeatMode.none);
        playerService.setShuffleMode(false);
        break;
      case PlayMode.shuffle:
        playerService.setRepeatMode(AudioServiceRepeatMode.none);
        playerService.setShuffleMode(true);
        break;
    }
  }

  void _showPlaylist(BuildContext context) {
    final playerService = ref.read(playerServiceProvider);
    final queue = playerService.queue;
    final currentIndex = playerService.currentIndex;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 32, height: 4, margin: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.queue_music, color: AppColors.amber, size: 20),
                  const SizedBox(width: 8),
                  Text('播放列表 (${queue.length})', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            if (queue.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('播放列表为空', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: queue.length,
                  itemBuilder: (context, index) {
                    final item = queue[index];
                    final isPlaying = index == currentIndex;
                    
                    return ListTile(
                      leading: isPlaying
                          ? const Icon(Icons.play_arrow, color: AppColors.amber)
                          : Text('${index + 1}', style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
                      title: Text(
                        item.title,
                        style: TextStyle(
                          color: isPlaying ? AppColors.amber : AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: isPlaying ? FontWeight.w600 : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        item.artist ?? '',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        playerService.setQueue(queue.map((e) => MusicItem.fromJson(e.extras ?? {})).toList(), startIndex: index);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }



  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showMoreMenu(BuildContext context, MusicItem music) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 32, height: 4, margin: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.music_note, color: AppColors.textMuted)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(music.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis), Text(music.singer, style: const TextStyle(color: AppColors.textMuted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)])),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            ListTile(leading: const Icon(Icons.favorite_border, color: AppColors.textPrimary), title: const Text('收藏', style: TextStyle(color: AppColors.textPrimary)), onTap: () { Navigator.pop(context); ref.read(toggleFavoriteProvider)(music); }),
            ListTile(leading: const Icon(Icons.playlist_add, color: AppColors.textPrimary), title: const Text('添加到歌单', style: TextStyle(color: AppColors.textPrimary)), onTap: () { Navigator.pop(context); showPlaylistPicker(context: context, ref: ref, song: music); }),
            ListTile(leading: const Icon(Icons.download, color: AppColors.textPrimary), title: const Text('下载', style: TextStyle(color: AppColors.textPrimary)), onTap: () { Navigator.pop(context); ref.read(downloadSongProvider)(music); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加到下载队列'), duration: Duration(seconds: 1))); }),
          ],
        ),
      ),
    );
  }
}
