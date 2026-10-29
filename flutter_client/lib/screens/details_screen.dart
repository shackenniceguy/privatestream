import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:privatestream/core/theme.dart';
import 'package:privatestream/models/media_item.dart';
import 'package:privatestream/models/download_task.dart';
import 'package:privatestream/screens/player_screen.dart';
import 'package:privatestream/services/api_service.dart';
import 'package:privatestream/services/offline_sync_service.dart';

class DetailsScreen extends ConsumerWidget {
  final MediaItem media;

  const DetailsScreen({super.key, required this.media});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offlineService = ref.watch(offlineServiceProvider);
    final apiService = ref.watch(apiServiceProvider);
    final task = offlineService.tasks[media.id];
    final isDownloaded = task?.status == DownloadStatus.completed;
    final isDownloading = task?.status == DownloadStatus.downloading;

    final progressSeconds = media.watchProgress?.positionSeconds ?? 0.0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          // 1. Cinematic Backdrop Sliver App Bar
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: AppTheme.background,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (media.backdropUrl != null)
                    CachedNetworkImage(
                      imageUrl: media.backdropUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, _) => Container(color: AppTheme.surface),
                      errorWidget: (context, _, __) => Container(color: AppTheme.surface),
                    )
                  else
                    Container(color: AppTheme.surface),

                  // Ambient Gradient Overlay
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0x990B0C10),
                          AppTheme.background,
                        ],
                        stops: [0.3, 0.7, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Main Content & Metadata Badges
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    media.title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 26,
                      letterSpacing: 0.5,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Metadata Badges Row (Rating, Year, Duration, Resolution, Aspect Ratio)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // TMDB Rating
                      if (media.voteAverage > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.starGold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.starGold.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: AppTheme.starGold, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                media.voteAverage.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: AppTheme.starGold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Year
                      if (media.year != null)
                        Text(
                          media.year.toString(),
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                        ),

                      // Duration
                      if (media.formattedDuration.isNotEmpty)
                        Text(
                          '•  ${media.formattedDuration}',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        ),

                      // Resolution Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppTheme.surfaceBorder),
                        ),
                        child: Text(
                          media.qualityBadge,
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),

                      // Native Aspect Ratio Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: media.isVertical ? AppTheme.cyberCyan.withValues(alpha: 0.15) : AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: media.isVertical ? AppTheme.cyberCyan : AppTheme.surfaceBorder,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              media.isVertical ? Icons.stay_current_portrait : Icons.aspect_ratio,
                              color: media.isVertical ? AppTheme.cyberCyan : AppTheme.textSecondary,
                              size: 13,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${media.aspectRatio} (${media.aspectRatioCategory})',
                              style: TextStyle(
                                color: media.isVertical ? AppTheme.cyberCyan : AppTheme.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Action Buttons: Play/Resume & Smart Offline Download
                  Row(
                    children: [
                      // Play / Resume Button
                      Expanded(
                        flex: 3,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.netflixRed,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 6,
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 26),
                          label: Text(
                            progressSeconds > 0 ? 'Resume Playback' : 'Play Video',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          onPressed: () {
                            final sourceUrl = isDownloaded
                                ? 'file://${task!.localVideoPath}'
                                : apiService.getStreamUrl(media.id);

                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PlayerScreen(
                                  media: media,
                                  playbackSourceUrl: sourceUrl,
                                  isOffline: isDownloaded,
                                  initialPositionSeconds: progressSeconds,
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Download for Offline Button
                      Expanded(
                        flex: 2,
                        child: _buildDownloadButton(context, ref, task, isDownloaded, isDownloading),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Overview Description
                  const Text(
                    'Storyline',
                    style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    media.overview != null && media.overview!.isNotEmpty
                        ? media.overview!
                        : 'No detailed overview provided for this title.',
                    style: const TextStyle(color: AppTheme.textSecondary, height: 1.5, fontSize: 14),
                  ),

                  const SizedBox(height: 24),

                  // Genres
                  if (media.genres.isNotEmpty) ...[
                    const Text(
                      'Genres',
                      style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: media.genres.map((g) {
                        return Chip(
                          label: Text(g),
                          backgroundColor: AppTheme.surfaceLight,
                          labelStyle: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                          side: const BorderSide(color: AppTheme.surfaceBorder),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Audio Codec & Subtitles Available
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.surfaceBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.audiotrack_rounded, color: AppTheme.cyberCyan, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              'Audio: ${media.audioCodec.toUpperCase()} (${media.audioChannels} channels)',
                              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.subtitles_rounded, color: AppTheme.neonPurple, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              media.subtitles.isNotEmpty
                                  ? 'Subtitles: ${media.subtitles.map((s) => s.language.toUpperCase()).join(', ')} (.vtt)'
                                  : 'Subtitles: Embedded in stream',
                              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadButton(
    BuildContext context,
    WidgetRef ref,
    DownloadTask? task,
    bool isDownloaded,
    bool isDownloading,
  ) {
    final offlineService = ref.read(offlineServiceProvider);

    if (isDownloaded) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: AppTheme.accentGreen),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: const Icon(Icons.check_circle_rounded, color: AppTheme.accentGreen, size: 20),
        label: const Text(
          'Downloaded',
          style: TextStyle(color: AppTheme.accentGreen, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        onPressed: () {
          // Confirm deletion sheet
          showModalBottomSheet(
            context: context,
            backgroundColor: AppTheme.surface,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (ctx) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Manage Offline Download',
                      style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                      title: const Text('Delete from Device Storage', style: TextStyle(color: Colors.redAccent)),
                      onTap: () {
                        offlineService.deleteDownload(media.id);
                        Navigator.of(ctx).pop();
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    }

    if (isDownloading) {
      final pct = task?.progressPercent ?? 0;
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: AppTheme.cyberCyan),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            value: task?.progress,
            strokeWidth: 2.5,
            color: AppTheme.cyberCyan,
          ),
        ),
        label: Text(
          '$pct%',
          style: const TextStyle(color: AppTheme.cyberCyan, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        onPressed: () {
          offlineService.pauseDownload(media.id);
        },
      );
    }

    // Default: Not downloaded yet
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: const BorderSide(color: AppTheme.surfaceBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: const Icon(Icons.download_rounded, color: AppTheme.textPrimary, size: 20),
      label: const Text(
        'Download',
        style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
      ),
      onPressed: () {
        offlineService.startDownload(media);
      },
    );
  }
}
