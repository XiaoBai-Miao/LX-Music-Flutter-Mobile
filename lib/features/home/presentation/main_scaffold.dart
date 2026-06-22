import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../player/presentation/widgets/mini_player.dart';

class MainScaffold extends StatelessWidget {
  final Widget child;

  const MainScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: child),
          const MiniPlayer(),
          _buildBottomNav(context),
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);
    return Container(
      height: 83,
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: AppColors.bg.withAlpha(242),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _navItem(context, 0, selectedIndex, Icons.home_outlined, Icons.home, '首页', '/'),
          _navItem(context, 1, selectedIndex, Icons.search, Icons.search, '搜索', '/search'),
          _navItem(context, 2, selectedIndex, Icons.library_music_outlined, Icons.library_music, '歌单', '/playlist'),
          _navItem(context, 3, selectedIndex, Icons.settings_outlined, Icons.settings, '设置', '/settings'),
        ],
      ),
    );
  }

  Widget _navItem(BuildContext context, int index, int selectedIndex, IconData icon, IconData activeIcon, String label, String path) {
    final isSelected = index == selectedIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () => context.go(path),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              size: 21,
              color: isSelected ? AppColors.amber : AppColors.textMuted,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.4,
                color: isSelected ? AppColors.amber : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/search')) return 1;
    if (location.startsWith('/playlist')) return 2;
    if (location.startsWith('/settings')) return 3;
    return 0;
  }
}
