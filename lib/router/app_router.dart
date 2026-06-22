import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/home/presentation/main_scaffold.dart';
import '../features/player/presentation/player_screen.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/playlist/presentation/playlist_screen.dart';
import '../features/playlist/presentation/playlist_detail_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/download/presentation/download_screen.dart';
import '../features/custom_source/presentation/custom_source_screen.dart';
import '../features/leaderboard/presentation/leaderboard_screen.dart';
import '../features/equalizer/presentation/equalizer_screen.dart';
import '../features/sync/presentation/sync_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainScaffold(child: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              builder: (context, state) => const SearchScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/playlist',
              builder: (context, state) => const PlaylistScreen(),
              routes: [
                GoRoute(
                  path: 'detail',
                  builder: (context, state) => const PlaylistDetailScreen(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/player',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => const MaterialPage(
        fullscreenDialog: true,
        child: PlayerScreen(),
      ),
    ),
    GoRoute(
      path: '/download',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const DownloadScreen(),
    ),
    GoRoute(
      path: '/custom-source',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CustomSourceScreen(),
    ),
    GoRoute(
      path: '/leaderboard',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const LeaderboardScreen(),
    ),
    GoRoute(
      path: '/leaderboard/detail',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final id = state.uri.queryParameters['id'] ?? '';
        final name = state.uri.queryParameters['name'] ?? '';
        return LeaderboardDetailScreenById(id: id, name: name);
      },
    ),
    GoRoute(
      path: '/equalizer',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const EqualizerScreen(),
    ),
    GoRoute(
      path: '/sync',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const SyncScreen(),
    ),
  ],
);
