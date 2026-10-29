enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
}

class DownloadTask {
  final int mediaId;
  final String title;
  final String mediaType;
  final String videoUrl;
  final String localVideoPath;
  final String localPosterPath;
  final String subtitlesJson;
  final int totalBytes;
  final int downloadedBytes;
  final DownloadStatus status;
  final double progress;
  final String? errorMessage;
  final String createdAt;

  const DownloadTask({
    required this.mediaId,
    required this.title,
    required this.mediaType,
    required this.videoUrl,
    required this.localVideoPath,
    required this.localPosterPath,
    required this.subtitlesJson,
    required this.totalBytes,
    required this.downloadedBytes,
    required this.status,
    required this.progress,
    this.errorMessage,
    required this.createdAt,
  });

  DownloadTask copyWith({
    int? mediaId,
    String? title,
    String? mediaType,
    String? videoUrl,
    String? localVideoPath,
    String? localPosterPath,
    String? subtitlesJson,
    int? totalBytes,
    int? downloadedBytes,
    DownloadStatus? status,
    double? progress,
    String? errorMessage,
    String? createdAt,
  }) {
    return DownloadTask(
      mediaId: mediaId ?? this.mediaId,
      title: title ?? this.title,
      mediaType: mediaType ?? this.mediaType,
      videoUrl: videoUrl ?? this.videoUrl,
      localVideoPath: localVideoPath ?? this.localVideoPath,
      localPosterPath: localPosterPath ?? this.localPosterPath,
      subtitlesJson: subtitlesJson ?? this.subtitlesJson,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String get formattedTotalSize {
    if (totalBytes <= 0) return 'Unknown size';
    final mb = totalBytes / (1024 * 1024);
    if (mb > 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  String get formattedDownloadedSize {
    final mb = downloadedBytes / (1024 * 1024);
    if (mb > 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  int get progressPercent => (progress * 100).toInt().clamp(0, 100);

  Map<String, dynamic> toMap() {
    return {
      'media_id': mediaId,
      'title': title,
      'media_type': mediaType,
      'video_url': videoUrl,
      'local_video_path': localVideoPath,
      'local_poster_path': localPosterPath,
      'subtitles_json': subtitlesJson,
      'total_bytes': totalBytes,
      'downloaded_bytes': downloadedBytes,
      'status': status.name,
      'progress': progress,
      'error_message': errorMessage,
      'created_at': createdAt,
    };
  }

  factory DownloadTask.fromMap(Map<String, dynamic> map) {
    return DownloadTask(
      mediaId: map['media_id'] as int? ?? 0,
      title: map['title'] as String? ?? 'Untitled',
      mediaType: map['media_type'] as String? ?? 'movie',
      videoUrl: map['video_url'] as String? ?? '',
      localVideoPath: map['local_video_path'] as String? ?? '',
      localPosterPath: map['local_poster_path'] as String? ?? '',
      subtitlesJson: map['subtitles_json'] as String? ?? '[]',
      totalBytes: map['total_bytes'] as int? ?? 0,
      downloadedBytes: map['downloaded_bytes'] as int? ?? 0,
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => DownloadStatus.queued,
      ),
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      errorMessage: map['error_message'] as String?,
      createdAt: map['created_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }
}
