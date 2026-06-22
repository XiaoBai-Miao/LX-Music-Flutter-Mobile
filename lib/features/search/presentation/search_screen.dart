import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../player/presentation/player_provider.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../playlist/presentation/playlist_picker.dart';
import '../../download/presentation/download_provider.dart';
import 'search_provider.dart';
import 'song_list_detail_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100) {
      _loadMore();
    }
  }

  void _loadMore() {
    final searchState = ref.read(searchStateProvider);
    if (searchState.isLoading || !searchState.hasMore) return;
    final query = _searchController.text;
    if (query.isNotEmpty) {
      ref.read(searchStateProvider.notifier).search(query, isLoadMore: true);
    }
  }

  void _onSearch(String query) {
    if (query.trim().isNotEmpty) {
      ref.read(searchQueryProvider.notifier).state = query.trim();
      ref.read(searchStateProvider.notifier).search(query.trim());
      ref.read(searchHistoryProvider.notifier).add(query.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchStateProvider);
    final selectedSourceId = ref.watch(selectedSourceIdProvider);
    final allSources = ref.watch(allSearchSourcesProvider);
    final searchHistory = ref.watch(searchHistoryProvider);

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
          title: Container(
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: '搜索音乐/歌手...',
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                border: InputBorder.none,
                prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.textMuted, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(searchQueryProvider.notifier).state = '';
                          ref.read(searchStateProvider.notifier).reset();
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onSubmitted: _onSearch,
            ),
          ),
        ),
        body: Column(
          children: [
            // Source + type tabs
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ...allSources.map((source) => _buildTabItem(
                            text: source.name,
                            isSelected: source.id == selectedSourceId,
                            onTap: () {
                              ref.read(selectedSourceIdProvider.notifier).state = source.id;
                              if (_searchController.text.isNotEmpty) _onSearch(_searchController.text);
                            },
                          )),
                        ],
                      ),
                    ),
                  ),

                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            Expanded(child: _buildMainContent(searchState, searchHistory)),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(SearchState searchState, List<String> searchHistory) {
    if (searchState.items.isEmpty && _searchController.text.isEmpty && !searchState.isLoading) {
      return _buildHistory(searchHistory);
    }
    if (searchState.isLoading && searchState.items.isEmpty) {
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(AppColors.amber))));
    }
    if (searchState.error != null && searchState.items.isEmpty) {
      return Center(child: Text('搜索出错: ${searchState.error}', style: const TextStyle(color: AppColors.error)));
    }
    return _buildResultList(searchState);
  }

  Widget _buildTabItem({required String text, required bool isSelected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppColors.amber : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? AppColors.amber : AppColors.textMuted,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildResultList(SearchState searchState) {
    final results = searchState.items;
    if (results.isEmpty && !searchState.isLoading) {
      return const Center(child: Text('无结果', style: TextStyle(color: AppColors.textMuted)));
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: results.length + (searchState.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == results.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: searchState.isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(AppColors.amber)))
                  : const Text('滑动加载更多', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ),
          );
        }
        final item = results[index];
        final isSonglist = !item.isPlayable;

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
              if (isSonglist) {
                Navigator.push(context, MaterialPageRoute(builder: (context) => SongListDetailScreen(songList: item)));
              } else {
                final playableItems = results.where((i) => i.isPlayable).toList();
                final pIndex = playableItems.indexOf(item);
                ref.read(playerServiceProvider).setQueue(playableItems, startIndex: pIndex >= 0 ? pIndex : 0);
              }
            },
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(isSonglist ? 8 : 4),
                  child: (item.artwork != null && item.artwork!.isNotEmpty)
                      ? Image.network(item.artwork!, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholderIcon(isSonglist))
                      : _placeholderIcon(isSonglist),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                        isSonglist ? '${item.singer}${item.album.isNotEmpty ? ' · ${item.album}' : ''}' : '${item.singer} · ${item.album}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isSonglist)
                  const Icon(Icons.chevron_right, color: AppColors.textMuted)
                else
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: AppColors.textMuted, size: 20),
                    onPressed: () => _showSongOptions(item),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _placeholderIcon([bool isSonglist = false]) {
    return Container(
      width: 50,
      height: 50,
      color: AppColors.surfaceVariant,
      child: Icon(isSonglist ? Icons.playlist_play : Icons.music_note, color: AppColors.textMuted, size: 20),
    );
  }

  Widget _buildHistory(List<String> history) {
    final hotSearch = ref.watch(hotSearchProvider);
    final hotWords = hotSearch.value ?? [];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 搜索历史
          if (history.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('搜索历史', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 14)),
                  GestureDetector(
                    onTap: () => ref.read(searchHistoryProvider.notifier).clear(),
                    child: const Text('清空', style: TextStyle(color: AppColors.amber, fontSize: 12)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: history.map((h) => InkWell(
                  onTap: () {
                    _searchController.text = h;
                    _onSearch(h);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(h, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
                  ),
                )).toList(),
              ),
            ),
            const SizedBox(height: 24),
          ],
          // 热搜榜
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.local_fire_department, color: AppColors.amber, size: 18),
                const SizedBox(width: 6),
                const Text('热搜榜', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
          ),
          if (hotWords.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('加载中...', style: TextStyle(color: AppColors.textMuted, fontSize: 13)))
          else
            ...hotWords.asMap().entries.map((entry) => InkWell(
              onTap: () {
                _searchController.text = entry.value;
                _onSearch(entry.value);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${entry.key + 1}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: entry.key < 3 ? AppColors.amber : AppColors.textMuted,
                          fontSize: 14,
                          fontWeight: entry.key < 3 ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(entry.value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
            )),
        ],
      ),
    );
  }

  void _showSongOptions(dynamic song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(2)),
            margin: const EdgeInsets.only(top: 12),
          ),
          ListTile(
            leading: const Icon(Icons.play_arrow, color: AppColors.textPrimary),
            title: const Text('立即播放', style: TextStyle(color: AppColors.textPrimary)),
            onTap: () {
              Navigator.pop(context);
              final results = ref.read(searchStateProvider).items;
              final playableItems = results.where((i) => i.isPlayable).toList();
              final pIndex = playableItems.indexOf(song);
              ref.read(playerServiceProvider).setQueue(playableItems, startIndex: pIndex >= 0 ? pIndex : 0);
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add, color: AppColors.textPrimary),
            title: const Text('添加到歌单', style: TextStyle(color: AppColors.textPrimary)),
            onTap: () { Navigator.pop(context); showPlaylistPicker(context: context, ref: ref, song: song); },
          ),
          ListTile(
            leading: const Icon(Icons.favorite_border, color: AppColors.textPrimary),
            title: const Text('收藏', style: TextStyle(color: AppColors.textPrimary)),
            onTap: () { ref.read(toggleFavoriteProvider)(song); Navigator.pop(context); },
          ),
          ListTile(
            leading: const Icon(Icons.download, color: AppColors.textPrimary),
            title: const Text('下载', style: TextStyle(color: AppColors.textPrimary)),
            onTap: () { ref.read(downloadSongProvider)(song); Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加到下载队列'), duration: Duration(seconds: 1))); },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
