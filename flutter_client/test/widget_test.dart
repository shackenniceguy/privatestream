import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:privatestream/main.dart';
import 'package:privatestream/models/media_item.dart';
import 'package:privatestream/services/api_service.dart';

class FakeApiService extends ApiService {
  @override
  Future<List<MediaItem>> fetchCatalog({
    String? genre,
    String? search,
    String? orientation,
    String? mediaType,
    int limit = 50,
    int offset = 0,
  }) async {
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTorrentJobs() async {
    return [];
  }
}

void main() {
  testWidgets('PrivateStreamApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiServiceProvider.overrideWithValue(FakeApiService()),
        ],
        child: const PrivateStreamApp(),
      ),
    );

    await tester.pump();
    expect(find.byType(PrivateStreamApp), findsOneWidget);
  });
}
