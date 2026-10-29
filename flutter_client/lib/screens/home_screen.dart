import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:privatestream/core/theme.dart';
import 'package:privatestream/core/responsive_shell.dart';
import 'package:privatestream/models/media_item.dart';
import 'package:privatestream/screens/details_screen.dart';
import 'package:privatestream/screens/player_screen.dart';
import 'package:privatestream/services/api_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<MediaItem> _allMedia = [];
  bool _isLoading = false;
  String _selectedGenre = 'All';

  final List<String> _genreFilters = ['All', 'Action', 'Sci-Fi', 'Drama', 'Comedy', 'Vertical 9:16'];

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    setState(() => _isLoading = true);
    try {
      final items = await ref.read(apiServiceProvider).fetchCatalog();
      if (mounted) setState(() => _allMedia = items);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<MediaItem> get _filteredItems {
    var list = _allMedia;
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((m) => m.title.toLowerCase().contains(query)).toList();
    }
    if (_selectedGenre == 'Vertical 9:16') {
      list = list.where((m) => m.isVertical).toList();
    } else if (_selectedGenre != 'All') {
      list = list.where((m) => m.genres.any((g) => g.toLowerCase() == _selectedGenre.toLowerCase())).toList();
    }
    return list;
  }

  List<MediaItem> get _continueWatchingItems {
    return _allMedia.where((m) => m.watchProgress != null && !m.watchProgress!.completed && m.watchProgress!.positionSeconds > 0).toList();
  }

  List<MediaItem> get _verticalItems {
    return _allMedia.where((m) => m.isVertical).toList();
  }

  List<MediaItem> get _movies {
    return _allMedia.where((m) => m.mediaType == 'movie' && !m.isVertical).toList();
  }

  List<MediaItem> get _series {
    return _allMedia.where((m) => m.mediaType == 'series').toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heroItem = _allMedia.isNotEmpty ? _allMedia.first : null;
    final isSearching = _searchController.text.trim().isNotEmpty || _selectedGenre != 'All';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: _loadCatalog,
        color: AppTheme.cyberCyan,
        child: CustomScrollView(
          slivers: [
            // Top App Bar with Search Box
            SliverAppBar(
              floating: true,
              pinned: false,
              backgroundColor: AppTheme.background,
              title: const Text('PrivateStream', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search movies, series, 4K, 9:16 vertical...',
                      prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.cyberCyan, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: AppTheme.textMuted, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),

            // Genre Filter Chips Bar
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  itemCount: _genreFilters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final g = _genreFilters[idx];
                    final isSelected = _selectedGenre == g;
                    return ChoiceChip(
                      label: Text(g),
                      selected: isSelected,
                      selectedColor: AppTheme.cyberCyan,
                      backgroundColor: AppTheme.surfaceLight,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.black : AppTheme.textSecondary,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      side: BorderSide(color: isSelected ? AppTheme.cyberCyan : AppTheme.surfaceBorder),
                      onSelected: (val) {
                        setState(() => _selectedGenre = g);
                      },
                    );
                  },
                ),
              ),
            ),

            // Search Results Grid Mode
            if (_isLoading && _allMedia.isEmpty) ...[
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.cyberCyan),
                ),
              ),
            ] else if (isSearching) ...[
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: _buildSearchGrid(context),
              ),
            ] else ...[
              // Hero Banner (Featured Media)
              if (heroItem != null)
                SliverToBoxAdapter(
                  child: _buildHeroBanner(context, heroItem),
                ),

              // Continue Watching Row
              if (_continueWatchingItems.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader('Continue Watching', Icons.history_rounded),
                ),
                SliverToBoxAdapter(
                  child: _buildContinueWatchingRow(context),
                ),
              ],

              // Vertical / Mobile-First Videos Row (9:16 / 3:4)
              if (_verticalItems.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader('Vertical & Mobile-First (9:16)', Icons.stay_current_portrait_rounded),
                ),
                SliverToBoxAdapter(
                  child: _buildMediaRow(context, _verticalItems, isVertical: true),
                ),
              ],

              // Movies Row
              if (_movies.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader('Movies', Icons.movie_filter_rounded),
                ),
                SliverToBoxAdapter(
                  child: _buildMediaRow(context, _movies),
                ),
              ],

              // TV Series Row
              if (_series.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader('TV Series', Icons.tv_rounded),
                ),
                SliverToBoxAdapter(
                  child: _buildMediaRow(context, _series),
                ),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 60)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.cyberCyan, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 18,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBanner(BuildContext context, MediaItem item) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;
    final bannerHeight = isDesktop ? 420.0 : 280.0;

    return Container(
      height: bannerHeight,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (item.backdropUrl != null || item.posterUrl != null)
              CachedNetworkImage(
                imageUrl: item.backdropUrl ?? item.posterUrl!,
                fit: BoxFit.cover,
                placeholder: (context, _) => Container(color: AppTheme.surface),
                errorWidget: (context, _, __) => Container(color: AppTheme.surface),
              )
            else
              Container(color: AppTheme.surface),

            // Gradient Tint
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xAA0B0C10), AppTheme.background],
                  stops: [0.2, 0.7, 1.0],
                ),
              ),
            ),

            // Content Overlay
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.netflixRed,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('FEATURED', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
                      ),
                      const SizedBox(width: 8),
                      Text(item.qualityBadge, style: const TextStyle(color: AppTheme.cyberCyan, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                        label: const Text('Play', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          final streamUrl = ref.read(apiServiceProvider).getStreamUrl(item.id);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PlayerScreen(media: item, playbackSourceUrl: streamUrl),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        icon: const Icon(Icons.info_outline_rounded, color: Colors.white),
                        label: const Text('Details'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => DetailsScreen(media: item)),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueWatchingRow(BuildContext context) {
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _continueWatchingItems.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, idx) {
          final item = _continueWatchingItems[idx];
          final progressPct = item.watchProgress?.percentage ?? 0.0;

          return InkWell(
            onTap: () {
              final streamUrl = ref.read(apiServiceProvider).getStreamUrl(item.id);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlayerScreen(
                    media: item,
                    playbackSourceUrl: streamUrl,
                    initialPositionSeconds: item.watchProgress?.positionSeconds ?? 0.0,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 240,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.surfaceBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                          child: CachedNetworkImage(
                            imageUrl: item.backdropUrl ?? item.posterUrl ?? '',
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(color: AppTheme.surfaceLight),
                          ),
                        ),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white70),
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                          ),
                        ),
                      ],
                    ),
                  ),
                  LinearProgressIndicator(
                    value: progressPct,
                    backgroundColor: AppTheme.surfaceLight,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.netflixRed),
                    minHeight: 4,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      item.title,
                      style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMediaRow(BuildContext context, List<MediaItem> items, {bool isVertical = false}) {
    final double cardWidth = isVertical ? 120 : 130;
    final double cardHeight = isVertical ? 220 : 200;

    return SizedBox(
      height: cardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, idx) {
          final item = items[idx];
          return _buildMediaCard(context, item, width: cardWidth, isVertical: isVertical);
        },
      ),
    );
  }

  Widget _buildMediaCard(BuildContext context, MediaItem item, {required double width, bool isVertical = false}) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DetailsScreen(media: item)),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: item.posterUrl ?? item.backdropUrl ?? '',
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppTheme.surfaceLight),
                      errorWidget: (_, __, ___) => Container(
                        color: AppTheme.surfaceLight,
                        child: const Icon(Icons.movie, color: AppTheme.textMuted),
                      ),
                    ),
                    if (isVertical)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppTheme.cyberCyan, width: 0.8),
                          ),
                          child: const Text('9:16', style: TextStyle(color: AppTheme.cyberCyan, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchGrid(BuildContext context) {
    final columns = ResponsiveLayout.getGridColumnCount(context);
    final items = _filteredItems;

    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.search_off_rounded, color: AppTheme.textMuted.withValues(alpha: 0.5), size: 48),
                const SizedBox(height: 12),
                const Text('No titles matched your search query', style: TextStyle(color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ),
      );
    }

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, idx) {
          final item = items[idx];
          return _buildMediaCard(context, item, width: 140, isVertical: item.isVertical);
        },
        childCount: items.length,
      ),
    );
  }
}
