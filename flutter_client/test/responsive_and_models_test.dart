import 'package:flutter_test/flutter_test.dart';
import 'package:privatestream/models/media_item.dart';
import 'package:privatestream/models/download_task.dart';

void main() {
  group('MediaItem and AspectRatio Tests', () {
    test('Correctly identifies vertical media (9:16 and 3:4)', () {
      const verticalItem1 = MediaItem(
        id: 1,
        title: 'Vertical Reel',
        mediaType: 'movie',
        fileSizeBytes: 104857600,
        durationSeconds: 120.0,
        width: 1080,
        height: 1920,
        aspectRatio: '9:16',
        aspectRatioCategory: 'vertical',
        videoCodec: 'h264',
        audioCodec: 'aac',
        audioChannels: 2,
        voteAverage: 8.5,
        genres: ['Vertical', 'Shorts'],
        subtitles: [],
      );

      expect(verticalItem1.isVertical, isTrue);
      expect(verticalItem1.aspectRatioValue, closeTo(9 / 16, 0.01));
      expect(verticalItem1.qualityBadge, equals('1080p FHD'));
      expect(verticalItem1.formattedDuration, equals('2m'));

      const horizontalItem = MediaItem(
        id: 2,
        title: 'Cinema Movie',
        mediaType: 'movie',
        fileSizeBytes: 4294967296,
        durationSeconds: 7320.0,
        width: 3840,
        height: 2160,
        aspectRatio: '16:9',
        aspectRatioCategory: 'horizontal',
        videoCodec: 'hevc',
        audioCodec: 'aac',
        audioChannels: 6,
        voteAverage: 9.1,
        genres: ['Action', 'Sci-Fi'],
        subtitles: [],
      );

      expect(horizontalItem.isVertical, isFalse);
      expect(horizontalItem.aspectRatioValue, closeTo(16 / 9, 0.01));
      expect(horizontalItem.qualityBadge, equals('4K UHD'));
      expect(horizontalItem.formattedDuration, equals('2h 2m'));
    });

    test('WatchProgressModel calculation and percentage', () {
      const progress = WatchProgressModel(
        id: 1,
        userId: 'primary_user',
        mediaId: 10,
        positionSeconds: 1800.0,
        durationSeconds: 3600.0,
        completed: false,
        updatedAt: '2026-10-29T12:00:00Z',
      );

      expect(progress.percentage, equals(0.5));
      expect(progress.formattedPosition, equals('30:00'));
    });
  });

  group('DownloadTask Tests', () {
    test('DownloadTask serialization and formatting', () {
      const task = DownloadTask(
        mediaId: 100,
        title: 'Cyberpunk 2099',
        mediaType: 'movie',
        videoUrl: 'http://127.0.0.1:8000/api/download/100',
        localVideoPath: '/storage/media/100/video.mp4',
        localPosterPath: '/storage/media/100/poster.jpg',
        subtitlesJson: '[]',
        totalBytes: 1500 * 1024 * 1024,
        downloadedBytes: 750 * 1024 * 1024,
        status: DownloadStatus.downloading,
        progress: 0.5,
        createdAt: '2026-10-29T12:00:00Z',
      );

      expect(task.progressPercent, equals(50));
      expect(task.formattedTotalSize, equals('1.46 GB'));
      expect(task.formattedDownloadedSize, equals('750.0 MB'));

      final map = task.toMap();
      final reconstructed = DownloadTask.fromMap(map);

      expect(reconstructed.mediaId, equals(task.mediaId));
      expect(reconstructed.title, equals(task.title));
      expect(reconstructed.status, equals(DownloadStatus.downloading));
      expect(reconstructed.progress, equals(0.5));
    });
  });
}

