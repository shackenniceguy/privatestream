class SubtitleModel {
  final int id;
  final int mediaId;
  final String language;
  final String title;
  final String vttUrl;
  final bool isDefault;

  const SubtitleModel({
    required this.id,
    required this.mediaId,
    required this.language,
    required this.title,
    required this.vttUrl,
    required this.isDefault,
  });

  factory SubtitleModel.fromJson(Map<String, dynamic> json) {
    return SubtitleModel(
      id: json['id'] as int? ?? 0,
      mediaId: json['media_id'] as int? ?? 0,
      language: json['language'] as String? ?? 'und',
      title: json['title'] as String? ?? 'Subtitles',
      vttUrl: json['vtt_url'] as String? ?? '',
      isDefault: json['is_default'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'media_id': mediaId,
      'language': language,
      'title': title,
      'vtt_url': vttUrl,
      'is_default': isDefault,
    };
  }
}

class WatchProgressModel {
  final int id;
  final String userId;
  final int mediaId;
  final double positionSeconds;
  final double durationSeconds;
  final bool completed;
  final String updatedAt;

  const WatchProgressModel({
    required this.id,
    required this.userId,
    required this.mediaId,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.completed,
    required this.updatedAt,
  });

  double get percentage {
    if (durationSeconds <= 0) return 0.0;
    final p = positionSeconds / durationSeconds;
    return p.clamp(0.0, 1.0);
  }

  String get formattedPosition {
    final int total = positionSeconds.toInt();
    final int hours = total ~/ 3600;
    final int minutes = (total % 3600) ~/ 60;
    final int seconds = total % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  factory WatchProgressModel.fromJson(Map<String, dynamic> json) {
    return WatchProgressModel(
      id: json['id'] as int? ?? 0,
      userId: json['user_id'] as String? ?? 'primary_user',
      mediaId: json['media_id'] as int? ?? 0,
      positionSeconds: (json['position_seconds'] as num?)?.toDouble() ?? 0.0,
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble() ?? 0.0,
      completed: json['completed'] as bool? ?? false,
      updatedAt: json['updated_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'media_id': mediaId,
      'position_seconds': positionSeconds,
      'duration_seconds': durationSeconds,
      'completed': completed,
      'updated_at': updatedAt,
    };
  }
}

class MediaItem {
  final int id;
  final String title;
  final String? originalTitle;
  final String? overview;
  final String mediaType;
  final int? year;
  final int? season;
  final int? episode;
  final int fileSizeBytes;
  final double durationSeconds;
  final int width;
  final int height;
  final String aspectRatio;
  final String aspectRatioCategory;
  final String videoCodec;
  final String audioCodec;
  final int audioChannels;
  final String? posterUrl;
  final String? backdropUrl;
  final int? tmdbId;
  final double voteAverage;
  final List<String> genres;
  final List<SubtitleModel> subtitles;
  final WatchProgressModel? watchProgress;
  final String? createdAt;

  const MediaItem({
    required this.id,
    required this.title,
    this.originalTitle,
    this.overview,
    required this.mediaType,
    this.year,
    this.season,
    this.episode,
    required this.fileSizeBytes,
    required this.durationSeconds,
    required this.width,
    required this.height,
    required this.aspectRatio,
    required this.aspectRatioCategory,
    required this.videoCodec,
    required this.audioCodec,
    required this.audioChannels,
    this.posterUrl,
    this.backdropUrl,
    this.tmdbId,
    required this.voteAverage,
    required this.genres,
    required this.subtitles,
    this.watchProgress,
    this.createdAt,
  });

  bool get isVertical =>
      aspectRatioCategory == 'vertical' ||
      aspectRatio == '9:16' ||
      aspectRatio == '3:4' ||
      (height > width && width > 0);

  double get aspectRatioValue {
    if (aspectRatio.contains(':')) {
      final parts = aspectRatio.split(':');
      final num? w = num.tryParse(parts[0]);
      final num? h = num.tryParse(parts[1]);
      if (w != null && h != null && h > 0) {
        return w / h;
      }
    }
    if (height > 0 && width > 0) {
      return width / height;
    }
    return 16 / 9;
  }

  String get formattedDuration {
    if (durationSeconds <= 0) return '';
    final int total = durationSeconds.toInt();
    final int hours = total ~/ 3600;
    final int minutes = (total % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String get qualityBadge {
    if (width >= 3840 || height >= 2160) return '4K UHD';
    if (width >= 1920 || height >= 1080) return '1080p FHD';
    if (width >= 1280 || height >= 720) return '720p HD';
    return 'SD';
  }

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final subsRaw = json['subtitles'] as List<dynamic>? ?? [];
    final subtitles = subsRaw.map((s) => SubtitleModel.fromJson(s as Map<String, dynamic>)).toList();

    WatchProgressModel? progress;
    if (json['watch_progress'] != null && json['watch_progress'] is Map<String, dynamic>) {
      progress = WatchProgressModel.fromJson(json['watch_progress'] as Map<String, dynamic>);
    }

    final genresRaw = json['genres'];
    List<String> parsedGenres = [];
    if (genresRaw is List) {
      parsedGenres = genresRaw.map((e) => e.toString()).toList();
    } else if (genresRaw is String && genresRaw.isNotEmpty) {
      parsedGenres = genresRaw.split(',').map((e) => e.trim()).toList();
    }

    return MediaItem(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? 'Untitled',
      originalTitle: json['original_title'] as String?,
      overview: json['overview'] as String?,
      mediaType: json['media_type'] as String? ?? 'movie',
      year: json['year'] as int?,
      season: json['season'] as int?,
      episode: json['episode'] as int?,
      fileSizeBytes: json['file_size_bytes'] as int? ?? 0,
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble() ?? 0.0,
      width: json['width'] as int? ?? 1920,
      height: json['height'] as int? ?? 1080,
      aspectRatio: json['aspect_ratio'] as String? ?? '16:9',
      aspectRatioCategory: json['aspect_ratio_category'] as String? ?? 'horizontal',
      videoCodec: json['video_codec'] as String? ?? 'h264',
      audioCodec: json['audio_codec'] as String? ?? 'aac',
      audioChannels: json['audio_channels'] as int? ?? 2,
      posterUrl: json['poster_url'] as String?,
      backdropUrl: json['backdrop_url'] as String?,
      tmdbId: json['tmdb_id'] as int?,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      genres: parsedGenres,
      subtitles: subtitles,
      watchProgress: progress,
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'original_title': originalTitle,
      'overview': overview,
      'media_type': mediaType,
      'year': year,
      'season': season,
      'episode': episode,
      'file_size_bytes': fileSizeBytes,
      'duration_seconds': durationSeconds,
      'width': width,
      'height': height,
      'aspect_ratio': aspectRatio,
      'aspect_ratio_category': aspectRatioCategory,
      'video_codec': videoCodec,
      'audio_codec': audioCodec,
      'audio_channels': audioChannels,
      'poster_url': posterUrl,
      'backdrop_url': backdropUrl,
      'tmdb_id': tmdbId,
      'vote_average': voteAverage,
      'genres': genres,
      'subtitles': subtitles.map((s) => s.toJson()).toList(),
      'watch_progress': watchProgress?.toJson(),
      'created_at': createdAt,
    };
  }
}
