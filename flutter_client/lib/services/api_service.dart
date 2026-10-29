import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:privatestream/models/media_item.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

class ApiService {
  late final Dio _dio;
  String _baseUrl = 'http://127.0.0.1:8000';

  ApiService({String? baseUrl}) {
    if (baseUrl != null && baseUrl.isNotEmpty) {
      _baseUrl = baseUrl;
    }
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Accept': 'application/json',
        },
      ),
    );
  }

  String get baseUrl => _baseUrl;

  void updateBaseUrl(String newUrl) {
    _baseUrl = newUrl;
    _dio.options.baseUrl = newUrl;
  }

  String getStreamUrl(int mediaId, {bool remux = false, int audioTrack = 0, double startTime = 0.0}) {
    final query = remux ? '?remux=1&audio_track=$audioTrack&start_time=$startTime' : '';
    return '$_baseUrl/api/stream/$mediaId$query';
  }

  String getDownloadUrl(int mediaId) {
    return '$_baseUrl/api/download/$mediaId';
  }

  String getSubtitleUrl(String relativeUrl) {
    if (relativeUrl.startsWith('http')) return relativeUrl;
    return '$_baseUrl$relativeUrl';
  }

  Future<List<MediaItem>> fetchCatalog({
    String? genre,
    String? search,
    String? orientation,
    String? mediaType,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'limit': limit,
        'offset': offset,
      };
      if (genre != null && genre.isNotEmpty) queryParams['genre'] = genre;
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (orientation != null && orientation.isNotEmpty) {
        queryParams['aspect_ratio_category'] = orientation;
      }
      if (mediaType != null && mediaType.isNotEmpty) {
        queryParams['media_type'] = mediaType;
      }

      final response = await _dio.get('/api/catalog', queryParameters: queryParams);
      if (response.statusCode == 200) {
        final List<dynamic> items = response.data['items'] as List<dynamic>? ?? [];
        return items.map((e) => MediaItem.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<MediaItem> fetchMediaDetails(int mediaId) async {
    final response = await _dio.get('/api/media/$mediaId');
    return MediaItem.fromJson(response.data as Map<String, dynamic>);
  }

  Future<bool> syncWatchProgress(List<WatchProgressModel> updates) async {
    if (updates.isEmpty) return true;
    try {
      final payload = {
        'user_id': 'primary_user',
        'updates': updates.map((u) => u.toJson()).toList(),
      };
      final res = await _dio.post('/api/progress/sync', data: payload);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchTorrentJobs() async {
    final response = await _dio.get('/api/torrents/list');
    if (response.statusCode == 200) {
      final List<dynamic> list = response.data as List<dynamic>? ?? [];
      return list.map((e) => e as Map<String, dynamic>).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> addTorrentMagnet(String magnetUrl) async {
    final formData = FormData.fromMap({
      'magnet_url': magnetUrl,
    });
    final response = await _dio.post('/api/torrents/add', data: formData);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> addTorrentFile(List<int> fileBytes, String filename) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(fileBytes, filename: filename),
    });
    final response = await _dio.post('/api/torrents/add', data: formData);
    return response.data as Map<String, dynamic>;
  }

  Future<bool> deleteTorrent(String hash) async {
    final response = await _dio.delete('/api/torrents/$hash');
    return response.statusCode == 200;
  }
}
