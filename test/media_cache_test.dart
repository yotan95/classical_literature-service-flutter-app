import 'dart:io';

import 'package:classic_theater/services/media_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

void main() {
  test('cacheCreationCover stores a remote image in the app documents folder',
      () async {
    final temp = await Directory.systemTemp.createTemp('media_cache_test_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final cache = MediaCache(
      docsDir: () async => temp,
      get: (_) async => http.Response.bytes(
        [1, 2, 3],
        200,
        headers: {'content-type': 'image/webp'},
      ),
    );

    final path = await cache.cacheCreationCover(
      creationId: 'cre:1/2',
      url: 'https://example.com/cover',
    );

    expect(path, isNotNull);
    expect(path!.startsWith('http'), isFalse);
    expect(p.basename(path), 'cre_1_2.webp');
    expect(await File(path).readAsBytes(), [1, 2, 3]);
  });

  test('cacheCreationCover keeps the original path when it is already local',
      () async {
    final cache = MediaCache(
      docsDir: () async => Directory.systemTemp,
      get: (_) => throw StateError('remote fetch should not run'),
    );

    final path = await cache.cacheCreationCover(
      creationId: 'cre-1',
      url: r'C:\app\cover.webp',
    );

    expect(path, r'C:\app\cover.webp');
  });
}
