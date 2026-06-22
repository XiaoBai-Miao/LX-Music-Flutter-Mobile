import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../player_provider.dart';
import '../../../lyric/presentation/lyric_provider.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final position = ref.watch(positionProvider);
    final duration = ref.watch(durationProvider);
    final playerService = ref.watch(playerServiceProvider);
    final lyrics = ref.watch(currentLyricProvider);
    final currentLineIndex = ref.watch(currentLineIndexProvider);

    if (currentMusic == null) {
      return const SizedBox.shrink();
    }

    final positionValue = position;
    final durationValue = duration.value ?? Duration.zero;
    final isPlayingValue = isPlaying.value ?? false;
    final progress = durationValue.inMilliseconds > 0
        ? positionValue.inMilliseconds / durationValue.inMilliseconds
        : 0.0;

    // 获取当前歌词行文本
    String subtitleText = currentMusic.singer;
    if (lyrics.isNotEmpty && currentLineIndex >= 0 && currentLineIndex < lyrics.lines.length) {
      subtitleText = lyrics.lines[currentLineIndex].text;
    }

    return GestureDetector(
      onTap: () => context.push('/player'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xDA191E37),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderActive),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Positioned(
                bottom: 0,
                left: 14,
                right: 14,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(1),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.amber,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: currentMusic.artwork != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                currentMusic.artwork!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(Icons.music_note, color: AppColors.textMuted);
                                },
                              ),
                            )
                          : const Icon(Icons.music_note, color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentMusic.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitleText,
                            style: TextStyle(
                              fontSize: 11,
                              color: lyrics.isNotEmpty && currentLineIndex >= 0
                                  ? AppColors.amber.withAlpha(200)
                                  : AppColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.skip_previous, size: 20, color: AppColors.textSecondary),
                      onPressed: () => playerService.previous(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    ),
                    GestureDetector(
                      onTap: () => playerService.togglePlay(),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: AppColors.amber,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPlayingValue ? Icons.pause : Icons.play_arrow,
                          size: 18,
                          color: AppColors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.skip_next, size: 20, color: AppColors.textSecondary),
                      onPressed: () => playerService.next(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
