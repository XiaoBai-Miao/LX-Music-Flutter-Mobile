import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/playlist.dart';
import '../../player/domain/music_item.dart';
import 'playlist_provider.dart';
import '../../player/presentation/player_provider.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  const PlaylistDetailScreen({super.key});

  @override
  ConsumerState<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  bool _isEditing = false;
  final List<MusicItem> _reorderedSongs = [];

  @override
  Widget build(BuildContext context) {
    final playlist = ref.watch(currentPlaylistProvider);
    final playerService = ref.watch(playerServiceProvider);

    if (playlist == null) {
      return Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF141828), Color(0xFF0D0F1A), Color(0xFF0A0D18)])),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: const Text('歌单', style: TextStyle(color: AppColors.textPrimary))),
          body: const Center(child: Text('歌单不存在', style: TextStyle(color: AppColors.textMuted))),
        ),
      );
    }

    if (_reorderedSongs.isEmpty && playlist.songs.isNotEmpty) {
      _reorderedSongs.addAll(playlist.songs);
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF141828), Color(0xFF0D0F1A), Color(0xFF0A0D18)]),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(_isEditing ? Icons.close : Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () {
              if (_isEditing) {
                setState(() { _isEditing = false; _reorderedSongs.clear(); _reorderedSongs.addAll(playlist.songs); });
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(
            _isEditing ? '编辑歌单' : playlist.name,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 18),
          ),
          actions: [
            if (_isEditing)
              TextButton(
                onPressed: () {
                  ref.read(playlistServiceProvider).updatePlaylist(id: playlist.id, songs: _reorderedSongs);
                  setState(() => _isEditing = false);
                },
                child: const Text('保存', style: TextStyle(color: AppColors.amber)),
              )
            else
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
                onSelected: (value) {
                  switch (value) {
                    case 'play_all':
                      if (playlist.songs.isNotEmpty) {
                        playerService.setQueue(playlist.songs, startIndex: 0);
                      }
                    case 'edit':
                      _showEditDialog(context, ref, playlist);
                    case 'sort_name':
                      ref.read(playlistServiceProvider).sortSongsByName(playlist.id);
                    case 'sort_artist':
                      ref.read(playlistServiceProvider).sortSongsByArtist(playlist.id);
                    case 'sort_duration':
                      ref.read(playlistServiceProvider).sortSongsByDuration(playlist.id);
                    case 'reorder':
                      setState(() => _isEditing = true);
                    case 'delete':
                      _showDeleteDialog(context, ref, playlist);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'play_all', child: Text('播放全部', style: TextStyle(color: AppColors.textPrimary))),
                  const PopupMenuItem(value: 'edit', child: Text('编辑歌单', style: TextStyle(color: AppColors.textPrimary))),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'sort_name', child: Text('按名称排序', style: TextStyle(color: AppColors.textPrimary))),
                  const PopupMenuItem(value: 'sort_artist', child: Text('按歌手排序', style: TextStyle(color: AppColors.textPrimary))),
                  const PopupMenuItem(value: 'sort_duration', child: Text('按时长排序', style: TextStyle(color: AppColors.textPrimary))),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'reorder', child: Text('手动排序', style: TextStyle(color: AppColors.textPrimary))),
                  const PopupMenuItem(value: 'delete', child: Text('删除歌单', style: TextStyle(color: AppColors.error))),
                ],
              ),
          ],
        ),
        body: Column(
          children: [
            // Playlist header
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [Theme.of(context).colorScheme.primary.withAlpha(80), Theme.of(context).colorScheme.primary.withAlpha(30)],
                      ),
                    ),
                    child: Center(
                      child: Text(playlist.name.substring(0, 1), style: const TextStyle(color: AppColors.textPrimary, fontSize: 40, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(playlist.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                        if (playlist.description != null) ...[
                          const SizedBox(height: 4),
                          Text(playlist.description!, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                        ],
                        const SizedBox(height: 6),
                        Text('${playlist.songCount} 首歌曲', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            Expanded(
              child: _isEditing
                  ? _buildEditableList(ref, playlist)
                  : _buildNormalList(ref, playerService, playlist),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableList(WidgetRef ref, Playlist playlist) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _reorderedSongs.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (oldIndex < newIndex) newIndex -= 1;
          final item = _reorderedSongs.removeAt(oldIndex);
          _reorderedSongs.insert(newIndex, item);
        });
      },
      itemBuilder: (context, index) {
        final song = _reorderedSongs[index];
        return Container(
          key: ValueKey(song.id),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Row(
            children: [
              Icon(Icons.drag_handle, color: AppColors.textMuted, size: 20),
              const SizedBox(width: 12),
              SizedBox(width: 20, child: Text('${index + 1}', style: const TextStyle(color: AppColors.textMuted, fontSize: 13))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(song.singer, style: const TextStyle(color: AppColors.textMuted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNormalList(WidgetRef ref, dynamic playerService, Playlist playlist) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: playlist.songs.length,
      itemBuilder: (context, index) {
        final song = playlist.songs[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              playerService.setQueue(playlist.songs, startIndex: index);
            },
            child: Row(
              children: [
                SizedBox(width: 20, child: Text('${index + 1}', style: const TextStyle(color: AppColors.textMuted, fontSize: 13))),
                const SizedBox(width: 12),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: song.artwork != null
                        ? Image.network(song.artwork!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholderIcon())
                        : _placeholderIcon(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(song.singer, style: const TextStyle(color: AppColors.textMuted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Text(_formatDuration(song.duration), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: AppColors.textMuted, size: 18),
                  onSelected: (value) {
                    if (value == 'remove') {
                      ref.read(playlistServiceProvider).removeSongFromPlaylist(playlist.id, song.id);
                    } else if (value == 'play') {
                      playerService.setQueue(playlist.songs, startIndex: index);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'play', child: Text('播放', style: TextStyle(color: AppColors.textPrimary))),
                    const PopupMenuItem(value: 'remove', child: Text('移除', style: TextStyle(color: AppColors.error))),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _placeholderIcon() {
    return Container(
      color: AppColors.surfaceVariant,
      child: const Icon(Icons.music_note, color: AppColors.textMuted, size: 20),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, Playlist playlist) {
    final nameController = TextEditingController(text: playlist.name);
    final descController = TextEditingController(text: playlist.description);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('编辑歌单', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameController, style: const TextStyle(color: AppColors.textPrimary), decoration: InputDecoration(hintText: '歌单名称', hintStyle: TextStyle(color: AppColors.textMuted), filled: true, fillColor: AppColors.surfaceVariant, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none))),
          const SizedBox(height: 8),
          TextField(controller: descController, style: const TextStyle(color: AppColors.textPrimary), decoration: InputDecoration(hintText: '描述', hintStyle: TextStyle(color: AppColors.textMuted), filled: true, fillColor: AppColors.surfaceVariant, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: AppColors.textMuted))),
          TextButton(onPressed: () { ref.read(playlistServiceProvider).updatePlaylist(id: playlist.id, name: nameController.text, description: descController.text); Navigator.pop(context); }, child: const Text('保存', style: TextStyle(color: AppColors.amber))),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref, Playlist playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除歌单', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('确定要删除歌单"${playlist.name}"吗？', style: const TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: AppColors.textMuted))),
          TextButton(onPressed: () { ref.read(playlistServiceProvider).deletePlaylist(playlist.id); Navigator.pop(context); Navigator.pop(context); }, child: const Text('删除', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
  }
}
