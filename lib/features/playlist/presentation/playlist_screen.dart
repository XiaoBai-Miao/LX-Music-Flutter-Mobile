import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/playlist.dart';
import 'playlist_provider.dart';
import '../../player/presentation/player_provider.dart';

enum PlaylistSortMode { recent, name, songCount }

class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({super.key});

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  String _searchQuery = '';
  PlaylistSortMode _sortMode = PlaylistSortMode.recent;

  List<Playlist> _filterAndSort(List<Playlist> playlists) {
    var filtered = playlists.where((p) => p.id != 'favorites').toList();

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((p) =>
        p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        (p.description ?? '').toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }

    switch (_sortMode) {
      case PlaylistSortMode.name:
        filtered.sort((a, b) => a.name.compareTo(b.name));
      case PlaylistSortMode.songCount:
        filtered.sort((a, b) => b.songCount.compareTo(a.songCount));
      case PlaylistSortMode.recent:
        break;
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistsProvider);
    final playlistService = ref.watch(playlistServiceProvider);
    final favorites = playlistService.favorites;
    final playerService = ref.watch(playerServiceProvider);
    final filteredPlaylists = _filterAndSort(playlists);

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
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.amberDim,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.music_note, color: AppColors.amber, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('我的歌单', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.add, color: AppColors.textPrimary, size: 24),
              onPressed: () => _showCreateDialog(context, ref),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            // Search in library
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              child: TextField(
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: '在库中搜索',
                  hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            // Favorites card
            _buildFavoritesCard(context, ref, favorites, playerService),
            const SizedBox(height: 24),
            // Section header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('歌单 (${filteredPlaylists.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                IconButton(
                  icon: const Icon(Icons.sort, color: AppColors.textMuted, size: 20),
                  onPressed: () => _showSortMenu(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (filteredPlaylists.isEmpty && _searchQuery.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('未找到匹配的歌单', style: TextStyle(color: AppColors.textMuted))),
              )
            else
              ...filteredPlaylists.map((playlist) => _buildPlaylistItem(context, ref, playlist)),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoritesCard(BuildContext context, WidgetRef ref, Playlist? favorites, dynamic playerService) {
    final songCount = favorites?.songCount ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4338CA), Color(0xFF818CF8)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.favorite, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('我喜欢的音乐', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('$songCount 首歌曲', style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 13)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              if (favorites != null && favorites.songs.isNotEmpty) {
                playerService.playPlaylist(favorites.songs);
              }
            },
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(40),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 30),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistItem(BuildContext context, WidgetRef ref, Playlist playlist) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          ref.read(currentPlaylistProvider.notifier).state = playlist;
          Navigator.pushNamed(context, '/playlist/detail');
        },
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary.withAlpha(100),
                    Theme.of(context).colorScheme.primary.withAlpha(40),
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  playlist.name.substring(0, 1),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(playlist.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('${playlist.songCount} 首歌曲 · ${playlist.description ?? "私人"}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, color: AppColors.textMuted, size: 20),
              onPressed: () => _showPlaylistMoreMenu(context, ref, playlist),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('创建歌单', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: '歌单名称',
                hintStyle: TextStyle(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: '描述（可选）',
                hintStyle: TextStyle(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: AppColors.textMuted))),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                ref.read(createPlaylistProvider)(nameController.text, description: descController.text.isEmpty ? null : descController.text);
                Navigator.pop(context);
              }
            },
            child: const Text('创建', style: TextStyle(color: AppColors.amber)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, Playlist playlist) {
    final nameController = TextEditingController(text: playlist.name);
    final descController = TextEditingController(text: playlist.description ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('编辑歌单', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: '歌单名称',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: '描述（可选）',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: AppColors.textMuted))),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                ref.read(playlistServiceProvider).updatePlaylist(
                  id: playlist.id,
                  name: nameController.text,
                  description: descController.text.isEmpty ? null : descController.text,
                );
                setState(() {});
                Navigator.pop(ctx);
              }
            },
            child: const Text('保存', style: TextStyle(color: AppColors.amber)),
          ),
        ],
      ),
    );
  }

  void _showSortMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 32, height: 4, margin: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(2))),
            const Padding(padding: EdgeInsets.all(16), child: Text('排序方式', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600))),
            _sortOption(context, PlaylistSortMode.recent, Icons.access_time, '最近添加'),
            _sortOption(context, PlaylistSortMode.name, Icons.sort_by_alpha, '名称排序'),
            _sortOption(context, PlaylistSortMode.songCount, Icons.music_note, '歌曲数量'),
          ],
        ),
      ),
    );
  }

  Widget _sortOption(BuildContext context, PlaylistSortMode mode, IconData icon, String label) {
    final isSelected = _sortMode == mode;
    return ListTile(
      leading: Icon(icon, color: isSelected ? AppColors.amber : AppColors.textPrimary),
      title: Text(label, style: TextStyle(color: isSelected ? AppColors.amber : AppColors.textPrimary, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
      trailing: isSelected ? const Icon(Icons.check, color: AppColors.amber, size: 20) : null,
      onTap: () {
        setState(() => _sortMode = mode);
        Navigator.pop(context);
      },
    );
  }

  void _showPlaylistMoreMenu(BuildContext context, WidgetRef ref, Playlist playlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 32, height: 4, margin: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(2))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(playlist.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600))),
            const Divider(color: AppColors.border, height: 1),
            if (playlist.id != 'recent')
              ListTile(
                leading: const Icon(Icons.edit, color: AppColors.textPrimary),
                title: const Text('编辑歌单', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () { Navigator.pop(context); _showEditDialog(context, ref, playlist); },
              ),
            if (playlist.id != 'favorites' && playlist.id != 'recent')
              ListTile(
                leading: const Icon(Icons.delete, color: AppColors.error),
                title: const Text('删除歌单', style: TextStyle(color: AppColors.error)),
                onTap: () {
                  ref.read(playlistServiceProvider).deletePlaylist(playlist.id);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}
