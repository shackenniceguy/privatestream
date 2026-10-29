import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:privatestream/models/download_task.dart';
import 'package:privatestream/models/media_item.dart';
import 'package:privatestream/services/api_service.dart';

final offlineServiceProvider = ChangeNotifierProvider<OfflineSyncService>((ref) {
  final api = ref.watch(apiServiceProvider);
  return OfflineSyncService(api);
});

class OfflineSyncService extends ChangeNotifier {
  final ApiService _apiService;
  Database? _db;
  final Map<int, CancelToken> _cancelTokens = {};
  final Map<int, DownloadTask> _tasks = {};
  bool _isOnline = true;
  StreamSubscription? _connectivitySubscription;

  OfflineSyncService(this._apiService) {
    _init();
  }

  Map<int, DownloadTask> get tasks => _tasks;
  bool get isOnline => _isOnline;

  List<DownloadTask> get downloadedItems =>
      _tasks.values.where((t) => t.status == DownloadStatus.completed).toList();

  List<DownloadTask> get activeDownloads =>
      _tasks.values.where((t) => t.status == DownloadStatus.downloading || t.status == DownloadStatus.queued).toList();

  int get totalDownloadedBytes {
    return _tasks.values
        .where((t) => t.status == DownloadStatus.completed)
        .fold(0, (sum, t) => sum + t.downloadedBytes);
  }

  String get formattedTotalStorageUsed {
    final mb = totalDownloadedBytes / (1024 * 1024);
    if (mb > 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _init() async {
    await _initDatabase();
    await _loadTasksFromDb();
    _initConnectivityListener();
  }

  Future<void> _initDatabase() async {
    final docsDir = await getApplicationSupportDirectory();
    final dbPath = p.join(docsDir.path, 'privatestream_offline.db');

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE offline_downloads (
            media_id INTEGER PRIMARY KEY,
            title TEXT,
            media_type TEXT,
            video_url TEXT,
            local_video_path TEXT,
            local_poster_path TEXT,
            subtitles_json TEXT,
            total_bytes INTEGER,
            downloaded_bytes INTEGER,
            status TEXT,
            progress REAL,
            error_message TEXT,
            created_at TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE watch_progress_queue (
            media_id INTEGER PRIMARY KEY,
            user_id TEXT,
            position_seconds REAL,
            duration_seconds REAL,
            completed INTEGER,
            updated_at TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE cached_media (
            media_id INTEGER PRIMARY KEY,
            media_json TEXT
          )
        ''');
      },
    );
  }

  Future<void> _loadTasksFromDb() async {
    if (_db == null) return;
    final rows = await _db!.query('offline_downloads');
    _tasks.clear();
    for (final r in rows) {
      final task = DownloadTask.fromMap(r);
      _tasks[task.mediaId] = task;
    }
    notifyListeners();
  }

  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) async {
      final isConnected = results.any((r) => r != ConnectivityResult.none);
      final wasOffline = !_isOnline;
      _isOnline = isConnected;
      notifyListeners();

      if (isConnected && wasOffline) {
        // Automatically sync queued watch progress when connection is restored
        await syncPendingProgressQueue();
      }
    });
  }

  // --------------------------------------------------------------------------
  // Download Management: Start, Resume, Pause, Cancel, Delete
  // --------------------------------------------------------------------------

  Future<void> startDownload(MediaItem media) async {
    if (_tasks.containsKey(media.id) && _tasks[media.id]!.status == DownloadStatus.downloading) {
      return;
    }

    final supportDir = await getApplicationSupportDirectory();
    final mediaDir = Directory(p.join(supportDir.path, 'media', media.id.toString()));
    if (!mediaDir.existsSync()) {
      mediaDir.createSync(recursive: true);
    }

    final localVideoPath = p.join(mediaDir.path, 'video.mp4');
    final localPosterPath = p.join(mediaDir.path, 'poster.jpg');

    // Cache Media metadata JSON locally
    await _db?.insert(
      'cached_media',
      {'media_id': media.id, 'media_json': jsonEncode(media.toJson())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Download poster image asynchronously
    if (media.posterUrl != null && media.posterUrl!.isNotEmpty) {
      _downloadFileLocally(media.posterUrl!, localPosterPath);
    }

    // Download Subtitle .vtt files locally
    final List<Map<String, dynamic>> localSubtitles = [];
    for (final sub in media.subtitles) {
      final vttLocalPath = p.join(mediaDir.path, 'sub_${sub.id}_${sub.language}.vtt');
      final remoteVttUrl = _apiService.getSubtitleUrl(sub.vttUrl);
      await _downloadFileLocally(remoteVttUrl, vttLocalPath);
      localSubtitles.add({
        'id': sub.id,
        'language': sub.language,
        'title': sub.title,
        'local_path': vttLocalPath,
      });
    }

    final task = DownloadTask(
      mediaId: media.id,
      title: media.title,
      mediaType: media.mediaType,
      videoUrl: _apiService.getDownloadUrl(media.id),
      localVideoPath: localVideoPath,
      localPosterPath: localPosterPath,
      subtitlesJson: jsonEncode(localSubtitles),
      totalBytes: media.fileSizeBytes,
      downloadedBytes: 0,
      status: DownloadStatus.downloading,
      progress: 0.0,
      createdAt: DateTime.now().toIso8601String(),
    );

    _tasks[media.id] = task;
    await _db?.insert('offline_downloads', task.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();

    _executeDownload(media.id);
  }

  Future<void> pauseDownload(int mediaId) async {
    final task = _tasks[mediaId];
    if (task == null) return;

    if (_cancelTokens.containsKey(mediaId)) {
      _cancelTokens[mediaId]!.cancel('Paused by user');
      _cancelTokens.remove(mediaId);
    }

    final updated = task.copyWith(status: DownloadStatus.paused);
    _tasks[mediaId] = updated;
    await _db?.update(
      'offline_downloads',
      updated.toMap(),
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
    notifyListeners();
  }

  Future<void> resumeDownload(int mediaId) async {
    final task = _tasks[mediaId];
    if (task == null) return;

    final updated = task.copyWith(status: DownloadStatus.downloading);
    _tasks[mediaId] = updated;
    await _db?.update(
      'offline_downloads',
      updated.toMap(),
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
    notifyListeners();

    _executeDownload(mediaId);
  }

  Future<void> deleteDownload(int mediaId) async {
    if (_cancelTokens.containsKey(mediaId)) {
      _cancelTokens[mediaId]!.cancel('Deleted by user');
      _cancelTokens.remove(mediaId);
    }

    final task = _tasks[mediaId];
    if (task != null) {
      final file = File(task.localVideoPath);
      if (file.existsSync()) {
        try {
          file.parent.deleteSync(recursive: true);
        } catch (_) {}
      }
    }

    _tasks.remove(mediaId);
    await _db?.delete('offline_downloads', where: 'media_id = ?', whereArgs: [mediaId]);
    await _db?.delete('cached_media', where: 'media_id = ?', whereArgs: [mediaId]);
    notifyListeners();
  }

  Future<void> _executeDownload(int mediaId) async {
    final task = _tasks[mediaId];
    if (task == null) return;

    final cancelToken = CancelToken();
    _cancelTokens[mediaId] = cancelToken;

    final videoFile = File(task.localVideoPath);
    int downloadedBytes = 0;
    if (videoFile.existsSync()) {
      downloadedBytes = videoFile.lengthSync();
    }

    final dio = Dio();
    try {
      final response = await dio.get<ResponseBody>(
        task.videoUrl,
        options: Options(
          responseType: ResponseType.stream,
          headers: downloadedBytes > 0 ? {'Range': 'bytes=$downloadedBytes-'} : null,
        ),
        cancelToken: cancelToken,
      );

      final totalHeader = response.headers.value('content-length');
      int totalLength = task.totalBytes;
      if (totalHeader != null) {
        totalLength = downloadedBytes + int.parse(totalHeader);
      }

      final fileAccess = videoFile.openSync(mode: downloadedBytes > 0 ? FileMode.append : FileMode.write);
      final stream = response.data!.stream;

      await for (final chunk in stream) {
        if (cancelToken.isCancelled) {
          break;
        }
        fileAccess.writeFromSync(chunk);
        downloadedBytes += chunk.length;

        final currentProgress = totalLength > 0 ? (downloadedBytes / totalLength).clamp(0.0, 1.0) : 0.0;
        final updated = task.copyWith(
          downloadedBytes: downloadedBytes,
          totalBytes: totalLength,
          progress: currentProgress,
          status: DownloadStatus.downloading,
        );
        _tasks[mediaId] = updated;
        notifyListeners();
      }

      fileAccess.closeSync();

      if (!cancelToken.isCancelled) {
        final completedTask = task.copyWith(
          downloadedBytes: downloadedBytes,
          totalBytes: totalLength,
          progress: 1.0,
          status: DownloadStatus.completed,
        );
        _tasks[mediaId] = completedTask;
        await _db?.update('offline_downloads', completedTask.toMap(), where: 'media_id = ?', whereArgs: [mediaId]);
        notifyListeners();
      }
    } catch (e) {
      if (!cancelToken.isCancelled) {
        final failedTask = task.copyWith(
          status: DownloadStatus.failed,
          errorMessage: e.toString(),
        );
        _tasks[mediaId] = failedTask;
        await _db?.update('offline_downloads', failedTask.toMap(), where: 'media_id = ?', whereArgs: [mediaId]);
        notifyListeners();
      }
    } finally {
      _cancelTokens.remove(mediaId);
    }
  }

  Future<void> _downloadFileLocally(String remoteUrl, String localPath) async {
    try {
      final dio = Dio();
      await dio.download(remoteUrl, localPath);
    } catch (_) {}
  }

  // --------------------------------------------------------------------------
  // Offline Progress Queuing & Auto-Sync
  // --------------------------------------------------------------------------

  Future<void> recordWatchProgress({
    required int mediaId,
    required double positionSeconds,
    required double durationSeconds,
    required bool completed,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    final progressItem = WatchProgressModel(
      id: 0,
      userId: 'primary_user',
      mediaId: mediaId,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      completed: completed,
      updatedAt: nowIso,
    );

    // Save to offline queue
    await _db?.insert(
      'watch_progress_queue',
      {
        'media_id': mediaId,
        'user_id': 'primary_user',
        'position_seconds': positionSeconds,
        'duration_seconds': durationSeconds,
        'completed': completed ? 1 : 0,
        'updated_at': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // If online, immediately push to server
    if (_isOnline) {
      final success = await _apiService.syncWatchProgress([progressItem]);
      if (success) {
        await _db?.delete('watch_progress_queue', where: 'media_id = ?', whereArgs: [mediaId]);
      }
    }
  }

  Future<void> syncPendingProgressQueue() async {
    if (_db == null || !_isOnline) return;

    final rows = await _db!.query('watch_progress_queue');
    if (rows.isEmpty) return;

    final List<WatchProgressModel> updates = rows.map((r) {
      return WatchProgressModel(
        id: 0,
        userId: r['user_id'] as String? ?? 'primary_user',
        mediaId: r['media_id'] as int? ?? 0,
        positionSeconds: (r['position_seconds'] as num?)?.toDouble() ?? 0.0,
        durationSeconds: (r['duration_seconds'] as num?)?.toDouble() ?? 0.0,
        completed: (r['completed'] as int? ?? 0) == 1,
        updatedAt: r['updated_at'] as String? ?? DateTime.now().toIso8601String(),
      );
    }).toList();

    final success = await _apiService.syncWatchProgress(updates);
    if (success) {
      await _db!.delete('watch_progress_queue');
      debugPrint('[OfflineSyncService] Synced ${updates.length} queued progress events.');
    }
  }

  Future<MediaItem?> getCachedMediaItem(int mediaId) async {
    if (_db == null) return null;
    final rows = await _db!.query(
      'cached_media',
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
    if (rows.isNotEmpty) {
      final jsonStr = rows.first['media_json'] as String;
      return MediaItem.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    }
    return null;
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
