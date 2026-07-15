import 'package:classic_theater/models/sample_data.dart';
import 'package:classic_theater/state/create_main_state.dart' show CreateMode;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coverDisplayPath prefers the generated cover over the source cover',
      () {
    final work = CreativeWork(
      id: 'work-1',
      title: 'Generated Work',
      source: '흥부와 놀부',
      mode: CreateMode.dialogue,
      level: '청소년용',
      desc: '',
      updatedAt: DateTime(2026, 6, 26),
      creationCoverImageUrl: 'https://example.com/creation.webp',
    );

    expect(bookImage(work.source), isNotNull);
    expect(work.coverDisplayPath, 'https://example.com/creation.webp');
  });

  test('coverDisplayPath still prefers the local generated cover cache', () {
    final work = CreativeWork(
      id: 'work-2',
      title: 'Cached Work',
      source: '흥부와 놀부',
      mode: CreateMode.dialogue,
      level: '청소년용',
      desc: '',
      updatedAt: DateTime(2026, 6, 26),
      creationCoverImageUrl: 'https://example.com/creation.webp',
      coverLocalAbsPath: r'C:\cache\work-2.webp',
    );

    expect(work.coverDisplayPath, r'C:\cache\work-2.webp');
  });
}
