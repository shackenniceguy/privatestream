import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:privatestream/core/theme.dart';
import 'package:privatestream/models/download_task.dart';
import 'package:privatestream/screens/player_screen.dart';
import 'package:privatestream/services/api_service.dart';
import 'package:privatestream/services/offline_sync_service.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;

  const DownloadsScreen({super.key, this.initialTabIndex = 0});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  WebSocketChannel? _wsChannel;
  List<Map<String, dynamic>> _cloudTorrents = [];
  bool _isLoadingTorrents = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTabIndex);
    _fetchCloudTorrents();
    _connectTorrentWebSocket();
  }

  void _connectTorrentWebSocket() {
    try {
      final apiService = ref.read(apiServiceProvider);
      final wsUrl = '${apiService.baseUrl.replaceFirst('http', 'ws')}/ws/torrents';
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _wsChannel?.stream.listen(
        (message) {
          if (mounted && message is String) {
            try {
              final List<dynamic> list = jsonDecode(message) as List<dynamic>;
              setState(() {
                _cloudTorrents = list.map((e) => e as Map<String, dynamic>).toList();
              });
            } catch (_) {}
          }
        },
        onError: (_) {},
        onDone: () {},
      );
    } catch (_) {}
  }

  Future<void> _fetchCloudTorrents() async {
    setState(() => _isLoadingTorrents = true);
    try {
      final list = await ref.read(apiServiceProvider).fetchTorrentJobs();
      if (mounted) setState(() => _cloudTorrents = list);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingTorrents = false);
    }
  }

  void _showAddTorrentSheet() {
    final magnetController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Ingest New Torrent',
                    style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textMuted),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Directly stages download to server local SSD before Anti-Ban sequential upload to Google Drive.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: magnetController,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Paste magnet:?xt=... link here',
                  prefixIcon: Icon(Icons.link_rounded, color: AppTheme.cyberCyan),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.cyberCyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.cloud_upload_rounded),
                  label: const Text('Start Staged Ingestion', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    final magnet = magnetController.text.trim();
                    if (magnet.isNotEmpty) {
                      Navigator.of(ctx).pop();
                      try {
                        await ref.read(apiServiceProvider).addTorrentMagnet(magnet);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Torrent added! Staging to server SSD...'),
                            backgroundColor: AppTheme.accentGreen,
                          ),
                        );
                        _fetchCloudTorrents();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to add torrent: $e'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _wsChannel?.sink.close();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Downloads & Ingestion'),
        actions: [
          IconButton(
            tooltip: 'Add Torrent Magnet',
            icon: const Icon(Icons.add_link_rounded, color: AppTheme.cyberCyan),
            onPressed: _showAddTorrentSheet,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.cyberCyan,
          labelColor: AppTheme.cyberCyan,
          unselectedLabelColor: AppTheme.textMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.download_for_offline), text: 'On-Device (Offline)'),
            Tab(icon: Icon(Icons.cloud_download), text: 'Cloud Torrents Queue'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOfflineTab(context),
          _buildCloudTorrentsTab(context),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Tab 1: On-Device Offline Downloads
  // --------------------------------------------------------------------------

  Widget _buildOfflineTab(BuildContext context) {
    final offlineService = ref.watch(offlineServiceProvider);
    final tasks = offlineService.tasks.values.toList();

    return Column(
      children: [
        // Storage Usage Header Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          color: AppTheme.surface,
          child: Row(
            children: [
              const Icon(Icons.disc_full_rounded, color: AppTheme.cyberCyan, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Local Storage Usage',
                      style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${offlineService.formattedTotalStorageUsed} used by PrivateStream Offline Media',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (!offlineService.isOnline)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Offline Mode', style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),

        const Divider(height: 1, color: AppTheme.surfaceBorder),

        Expanded(
          child: tasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download_for_offline_outlined, color: AppTheme.textMuted.withValues(alpha: 0.5), size: 64),
                      const SizedBox(height: 16),
                      const Text(
                        'No Offline Media Saved',
                        style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Browse the catalog and tap "Download" to watch without internet.',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: tasks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, idx) {
                    final t = tasks[idx];
                    return _buildOfflineTaskCard(context, t, offlineService);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildOfflineTaskCard(BuildContext context, DownloadTask task, OfflineSyncService service) {
    final isCompleted = task.status == DownloadStatus.completed;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted ? AppTheme.surfaceBorder : AppTheme.cyberCyan.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isCompleted ? Icons.play_circle_fill_rounded : Icons.downloading_rounded,
                  color: isCompleted ? AppTheme.accentGreen : AppTheme.cyberCyan,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isCompleted
                          ? '${task.formattedTotalSize} • Ready to watch offline'
                          : '${task.formattedDownloadedSize} / ${task.formattedTotalSize} (${task.progressPercent}%)',
                      style: TextStyle(
                        color: isCompleted ? AppTheme.accentGreen : AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCompleted)
                IconButton(
                  tooltip: 'Play Offline',
                  icon: const Icon(Icons.play_arrow_rounded, color: AppTheme.accentGreen, size: 28),
                  onPressed: () async {
                    final cachedMedia = await service.getCachedMediaItem(task.mediaId);
                    if (cachedMedia != null && context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PlayerScreen(
                            media: cachedMedia,
                            playbackSourceUrl: 'file://${task.localVideoPath}',
                            isOffline: true,
                          ),
                        ),
                      );
                    }
                  },
                )
              else if (task.status == DownloadStatus.downloading)
                IconButton(
                  tooltip: 'Pause',
                  icon: const Icon(Icons.pause_circle_outline_rounded, color: AppTheme.cyberCyan),
                  onPressed: () => service.pauseDownload(task.mediaId),
                )
              else
                IconButton(
                  tooltip: 'Resume',
                  icon: const Icon(Icons.play_circle_outline_rounded, color: AppTheme.cyberCyan),
                  onPressed: () => service.resumeDownload(task.mediaId),
                ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                onPressed: () => service.deleteDownload(task.mediaId),
              ),
            ],
          ),
          if (!isCompleted) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress,
                backgroundColor: AppTheme.surfaceLight,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.cyberCyan),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Tab 2: Cloud Torrents Queue
  // --------------------------------------------------------------------------

  Widget _buildCloudTorrentsTab(BuildContext context) {
    if (_isLoadingTorrents && _cloudTorrents.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.cyberCyan));
    }

    if (_cloudTorrents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_done_outlined, color: AppTheme.textMuted.withValues(alpha: 0.5), size: 64),
            const SizedBox(height: 16),
            const Text(
              'No Active Cloud Torrents',
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the link icon in the top right or message the Telegram Bot\nto ingest torrents directly into your Private Cloud.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchCloudTorrents,
      color: AppTheme.cyberCyan,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _cloudTorrents.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, idx) {
          final t = _cloudTorrents[idx];
          return _buildCloudTorrentCard(context, t);
        },
      ),
    );
  }

  Widget _buildCloudTorrentCard(BuildContext context, Map<String, dynamic> item) {
    final name = item['name'] as String? ?? 'Torrent';
    final state = item['state'] as String? ?? 'downloading';
    final progress = (item['progress'] as num?)?.toDouble() ?? 0.0;
    final dSpeed = (item['download_speed'] as num?)?.toInt() ?? 0;
    final eta = (item['eta_seconds'] as num?)?.toInt() ?? 0;
    final hash = item['hash'] as String? ?? '';

    final speedStr = dSpeed > 0 ? '${(dSpeed / (1024 * 1024)).toStringAsFixed(1)} MB/s' : '0 KB/s';
    final progressPct = (progress * 100).toInt().clamp(0, 100);

    String etaStr = 'Calculating...';
    if (eta > 0) {
      final min = eta ~/ 60;
      final sec = eta % 60;
      etaStr = '${min}m ${sec}s';
    }

    Color stateColor = AppTheme.cyberCyan;
    if (state == 'completed') stateColor = AppTheme.accentGreen;
    if (state == 'post_processing' || state == 'uploading') stateColor = AppTheme.neonPurple;
    if (state == 'error') stateColor = Colors.redAccent;

    return Container(
      padding: const EdgeInsets.all(14),
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
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: stateColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  state.toUpperCase(),
                  style: TextStyle(color: stateColor, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 20),
                onPressed: () async {
                  await ref.read(apiServiceProvider).deleteTorrent(hash);
                  _fetchCloudTorrents();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Speed: $speedStr',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              Text(
                'ETA: $etaStr',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              Text(
                '$progressPct%',
                style: TextStyle(color: stateColor, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppTheme.surfaceLight,
              valueColor: AlwaysStoppedAnimation<Color>(stateColor),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}
