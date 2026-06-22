import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/music_source/platform/music_platform.dart';
import '../../leaderboard/presentation/leaderboard_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _platforms = ['kw', 'kg', 'tx', 'wy', 'mg'];
  final Map<String, String> _platformNames = {
    'kw': '酷我',
    'kg': '酷狗',
    'tx': '腾讯',
    'wy': '网易',
    'mg': '咪咕',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(leaderboardCategoriesProvider);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF141828), Color(0xFF0D0F1A), Color(0xFF0A0D18)],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // Platform tabs
              TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: AppColors.amber,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: AppColors.amber,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
                tabs: _platforms.map((p) => Tab(text: _platformNames[p])).toList(),
              ),
              // Leaderboard grid
              Expanded(
                child: categoriesAsync.when(
                  loading: () => const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.amber),
                      ),
                    ),
                  ),
                  error: (error, stack) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                        const SizedBox(height: 16),
                        Text('加载失败: $error', style: const TextStyle(color: AppColors.textSecondary)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => ref.invalidate(leaderboardCategoriesProvider),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                  data: (categories) => TabBarView(
                    controller: _tabController,
                    children: _platforms.map((platform) {
                      final filtered = categories.where((c) => c.platform == platform).toList();
                      return _buildLeaderboardGrid(context, filtered, platform);
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboardGrid(BuildContext context, List<LeaderboardCategory> categories, String platform) {
    if (categories.isEmpty) {
      return const Center(
        child: Text('暂无排行榜数据', style: TextStyle(color: AppColors.textMuted)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return _buildLeaderboardCard(context, category, platform, index);
      },
    );
  }

  Widget _buildLeaderboardCard(BuildContext context, LeaderboardCategory category, String platform, int index) {
    return GestureDetector(
      onTap: () => context.push('/leaderboard/detail?id=${Uri.encodeComponent(category.id)}&name=${Uri.encodeComponent(category.name)}'),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: _getAccentColor(platform, index).withAlpha(40),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 生成独特的排行榜封面
              _LeaderboardCover(
                platform: platform,
                index: index,
                name: category.name,
              ),
              // 底部名称标签
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withAlpha(180),
                      ],
                    ),
                  ),
                  child: Text(
                    category.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getAccentColor(String platform, int index) {
    final colors = _getPlatformPalette(platform);
    return colors[index % colors.length];
  }

  List<Color> _getPlatformPalette(String platform) {
    switch (platform) {
      case 'kw':
        return const [Color(0xFF6B3FA0), Color(0xFF9B59B6), Color(0xFF8E44AD), Color(0xFF7D3C98)];
      case 'kg':
        return const [Color(0xFF1A8A8A), Color(0xFF2ECC71), Color(0xFF1ABC9C), Color(0xFF16A085)];
      case 'tx':
        return const [Color(0xFF2355C0), Color(0xFF3498DB), Color(0xFF2980B9), Color(0xFF1F6FBB)];
      case 'wy':
        return const [Color(0xFF9B3060), Color(0xFFE74C3C), Color(0xFFC0392B), Color(0xFFD35400)];
      case 'mg':
        return const [Color(0xFFC06020), Color(0xFFF39C12), Color(0xFFE67E22), Color(0xFFD68910)];
      default:
        return const [Color(0xFF3D4A5A), Color(0xFF5D6D7E)];
    }
  }
}

/// 排行榜封面生成器 - 根据平台和索引生成独特视觉
class _LeaderboardCover extends StatelessWidget {
  final String platform;
  final int index;
  final String name;

  const _LeaderboardCover({
    required this.platform,
    required this.index,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    final seed = _hashString(platform + index.toString());
    final random = Random(seed);

    final palette = _getPalette(platform);
    final baseColor = palette[index % palette.length];
    final accentColor = palette[(index + 1) % palette.length];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(
            random.nextDouble() * 2 - 1,
            random.nextDouble() * 2 - 1,
          ),
          end: Alignment(
            random.nextDouble() * 2 - 1,
            random.nextDouble() * 2 - 1,
          ),
          colors: [
            baseColor,
            accentColor,
            baseColor.withAlpha(180),
          ],
        ),
      ),
      child: Stack(
        children: [
          // 装饰图案
          ...List.generate(3, (i) => _buildDecorShape(random, i)),
          // 中心图标
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getPlatformIcon(),
                  color: Colors.white.withAlpha(220),
                  size: 40,
                  shadows: const [Shadow(blurRadius: 8, color: Colors.black26)],
                ),
                const SizedBox(height: 4),
                Text(
                  _getShortName(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withAlpha(200),
                    shadows: const [Shadow(blurRadius: 4, color: Colors.black38)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDecorShape(Random random, int i) {
    final size = 40.0 + random.nextDouble() * 80;
    final dx = random.nextDouble() * 200 - 50;
    final dy = random.nextDouble() * 200 - 50;
    final opacity = 0.05 + random.nextDouble() * 0.15;

    return Positioned(
      left: dx,
      top: dy,
      child: Transform.rotate(
        angle: random.nextDouble() * pi * 2,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha((opacity * 255).toInt()),
            shape: i % 2 == 0 ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: i % 2 == 0 ? null : BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  String _getShortName() {
    if (name.length <= 4) return name;
    return name.replaceAll('榜', '').replaceAll('排行榜', '');
  }

  List<Color> _getPalette(String platform) {
    switch (platform) {
      case 'kw':
        return const [Color(0xFF6B3FA0), Color(0xFF9B59B6), Color(0xFF8E44AD), Color(0xFF5B2C6F)];
      case 'kg':
        return const [Color(0xFF1A8A8A), Color(0xFF2ECC71), Color(0xFF1ABC9C), Color(0xFF0E6655)];
      case 'tx':
        return const [Color(0xFF2355C0), Color(0xFF3498DB), Color(0xFF2980B9), Color(0xFF1A5276)];
      case 'wy':
        return const [Color(0xFF9B3060), Color(0xFFE74C3C), Color(0xFFC0392B), Color(0xFF7B241C)];
      case 'mg':
        return const [Color(0xFFC06020), Color(0xFFF39C12), Color(0xFFE67E22), Color(0xFF935116)];
      default:
        return const [Color(0xFF3D4A5A), Color(0xFF5D6D7E)];
    }
  }

  IconData _getPlatformIcon() {
    switch (platform) {
      case 'kw':
        return Icons.music_note;
      case 'kg':
        return Icons.graphic_eq;
      case 'tx':
        return Icons.queue_music;
      case 'wy':
        return Icons.cloud;
      case 'mg':
        return Icons.radio;
      default:
        return Icons.trending_up;
    }
  }

  int _hashString(String input) {
    int hash = 0;
    for (int i = 0; i < input.length; i++) {
      hash = (hash * 31 + input.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return hash;
  }
}
