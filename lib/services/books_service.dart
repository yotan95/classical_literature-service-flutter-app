import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../state/create_main_state.dart'
    show BookCover, registerServerBookCovers, registerServerBookIds;
import 'db_service.dart';

/// 원작 책 목록/상세 조회.
/// 기존 UI(kBooks/kScenes) 를 **서버 데이터로 동적 치환**하기 위한 데이터 소스.
/// base URL 은 [AppConfig] 에서만 온다(하드코딩 금지).

/// 서버 미디어 URL([coverImageUrl] 등)을 앱이 실제로 닿는 [baseUrl] 기준 절대 URL 로 보정한다.
/// - 절대 http(s) URL: scheme/host/port 를 baseUrl 의 것으로 교체(서버가 접근 불가 호스트를
///   하드코딩해 보내는 문제 보정 — 에뮬레이터 10.0.2.2, 실기기 LAN IP 등).
/// - 서버 루트 상대경로(`/images/bakssi_jeon.webp?v=1`): baseUrl 기준 절대 URL 로 변환
///   (그래야 `Image.network` 가 로드한다. 안 그러면 에셋으로 오인돼 표지가 안 뜬다).
/// - 그 외(에셋 경로 `assets/...`, 빈 값): 그대로 둔다.
String? rebaseMediaUrl(String? url, String baseUrl) {
  if (url == null || url.isEmpty) return url;
  final base = Uri.tryParse(baseUrl);
  if (base == null || base.host.isEmpty) return url;
  final u = Uri.tryParse(url);
  if (u == null) return url;
  if (u.isScheme('http') || u.isScheme('https')) {
    return u
        .replace(scheme: base.scheme, host: base.host, port: base.port)
        .toString();
  }
  if (url.startsWith('/')) return base.resolveUri(u).toString();
  return url;
}

/// 서버가 내려준 미디어 상대경로(`/images/...`, `/creation-covers/...`, `/audio/...`)를
/// [baseUrl] 기준 절대 URL 로 해석한다(이미지·오디오 공용).
/// 예: `/creation-covers/a.webp` + `http://10.0.2.2:8000`
///     → `http://10.0.2.2:8000/creation-covers/a.webp`.
/// 동작은 [rebaseMediaUrl] 과 동일(절대 URL 은 호스트 보정, 에셋/빈 값은 보존).
String? resolveMediaUrl(String? path, String baseUrl) =>
    rebaseMediaUrl(path, baseUrl);

/// "#RRGGBB" / "#AARRGGBB" → Color. 실패 시 기본 톤.
Color hexColor(String hex) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFFA07860);
}

/// `GET /books` 한 항목.
class Book {
  const Book({
    required this.bookId,
    required this.title,
    required this.emoji,
    required this.author,
    required this.era,
    required this.difficulty,
    required this.tags,
    required this.coverColor,
    required this.coverImageUrl,
    required this.shortDescription,
    required this.sceneCount,
  });

  final String bookId; // 그대로 POST /create 의 bookId 로 보낸다.
  final String title;
  final String emoji;
  final String author;
  final String era;
  final String difficulty;
  final List<String> tags;
  final String coverColor; // #RRGGBB
  final String? coverImageUrl;
  final String shortDescription;
  final int sceneCount;

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        bookId: (j['bookId'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        emoji: (j['emoji'] as String?) ?? '📖',
        author: (j['author'] as String?) ?? '',
        era: (j['era'] as String?) ?? '',
        difficulty: (j['difficulty'] as String?) ?? '',
        tags: [for (final t in (j['tags'] as List? ?? const [])) '$t'],
        coverColor: (j['coverColor'] as String?) ?? '#A07860',
        coverImageUrl: j['coverImageUrl'] as String?,
        shortDescription: (j['shortDescription'] as String?) ?? '',
        sceneCount: (j['sceneCount'] as num?)?.toInt() ?? 0,
      );

  /// SQLite books 행 → Book.
  factory Book.fromRow(Map<String, Object?> r) => Book(
        bookId: r['book_id'] as String,
        title: (r['title'] as String?) ?? '',
        emoji: (r['emoji'] as String?) ?? '📖',
        author: (r['author'] as String?) ?? '',
        era: (r['era'] as String?) ?? '',
        difficulty: (r['difficulty'] as String?) ?? '',
        tags: () {
          final raw = r['tags'] as String?;
          if (raw == null || raw.isEmpty) return const <String>[];
          final v = jsonDecode(raw);
          return v is List ? [for (final t in v) '$t'] : const <String>[];
        }(),
        coverColor: (r['cover_color'] as String?) ?? '#A07860',
        coverImageUrl: r['cover_image_url'] as String?,
        shortDescription: (r['short_description'] as String?) ?? '',
        sceneCount: (r['scene_count'] as num?)?.toInt() ?? 0,
      );

  /// Book → SQLite books 행. [sortOrder] 는 서버 목록 순서.
  Map<String, Object?> toRow(int sortOrder) => {
        'book_id': bookId,
        'title': title,
        'emoji': emoji,
        'author': author,
        'era': era,
        'difficulty': difficulty,
        'tags': jsonEncode(tags),
        'cover_color': coverColor,
        'cover_image_url': coverImageUrl,
        'short_description': shortDescription,
        'scene_count': sceneCount,
        'sort_order': sortOrder,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      };

  /// 표지 이미지 URL 호스트를 [baseUrl] 에 맞춘 사본(접근 불가 호스트 보정). 그 외 필드는 동일.
  Book rebasedCover(String baseUrl) => Book(
        bookId: bookId,
        title: title,
        emoji: emoji,
        author: author,
        era: era,
        difficulty: difficulty,
        tags: tags,
        coverColor: coverColor,
        coverImageUrl: rebaseMediaUrl(coverImageUrl, baseUrl),
        shortDescription: shortDescription,
        sceneCount: sceneCount,
      );

  /// 기존 UI 의 BookCover 로 변환(표지는 coverImageUrl, 없으면 색+이모지 폴백).
  BookCover toCover() =>
      BookCover(title, emoji, hexColor(coverColor), image: coverImageUrl);
}

/// `GET /books/{bookId}` 의 장면(칩) 한 개.
class SceneOption {
  const SceneOption({
    required this.sceneId,
    required this.order,
    required this.emoji,
    required this.title,
    required this.description,
  });

  final String sceneId;
  final int order;
  final String emoji;
  final String title;
  final String description;

  factory SceneOption.fromJson(Map<String, dynamic> j) => SceneOption(
        sceneId: (j['sceneId'] as String?) ?? '',
        order: (j['order'] as num?)?.toInt() ?? 0,
        emoji: (j['emoji'] as String?) ?? '🎬',
        title: (j['title'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
      );
}

class BookDetail {
  const BookDetail({
    required this.bookId,
    required this.summary,
    required this.characterNames,
    required this.scenes,
  });
  final String bookId;
  final String summary; // 전체 줄거리(3문단). 화면에선 1~2줄로 잘라 표시.
  final List<String> characterNames; // 주요 인물 이름
  final List<SceneOption> scenes;

  factory BookDetail.fromJson(Map<String, dynamic> j) => BookDetail(
        bookId: (j['bookId'] as String?) ?? '',
        summary: (j['summary'] as String?) ?? '',
        characterNames: [
          for (final c in (j['characters'] as List? ?? const []))
            if (c is Map<String, dynamic> && c['name'] != null)
              '${c['name']}',
        ],
        scenes: [
          for (final s in (j['scenes'] as List? ?? const []))
            if (s is Map<String, dynamic>) SceneOption.fromJson(s),
        ],
      );
}

class BooksApi {
  BooksApi(this.config);
  final AppConfig config;
  static const Duration _timeout = Duration(seconds: 15);

  Future<List<Book>> fetchBooks() async {
    final res =
        await http.get(Uri.parse('${config.baseUrl}/books')).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('원작 목록을 불러오지 못했어요 (HTTP ${res.statusCode}).');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final b in (j['books'] as List? ?? const []))
        if (b is Map<String, dynamic>) Book.fromJson(b),
    ];
  }

  Future<BookDetail> fetchBookDetail(String bookId) async {
    final res = await http
        .get(Uri.parse('${config.baseUrl}/books/$bookId'))
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('원작 정보를 불러오지 못했어요 (HTTP ${res.statusCode}).');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return BookDetail.fromJson(j);
  }

  /// `GET /books/{bookId}/original` — 원작 원문 텍스트(원작 보기용). 없으면 빈 문자열.
  Future<String> fetchOriginalText(String bookId) async {
    final res = await http
        .get(Uri.parse('${config.baseUrl}/books/$bookId/original'))
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('원문을 불러오지 못했어요 (HTTP ${res.statusCode}).');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (j['text'] as String?) ?? '';
  }
}

final booksApiProvider = Provider<BooksApi>((ref) {
  return BooksApi(ref.watch(appConfigProvider));
});

/// 원작 목록 저장소: SQLite 캐시 + 서버 동기화(추가/변경 반영).
class BooksRepository {
  BooksRepository(this._api, this._db);
  final BooksApi _api;
  final DbService _db;

  /// SQLite 에 캐시된 목록(오프라인/즉시 표시). 표지 URL 은 현재 baseUrl 로 재작성.
  Future<List<Book>> cached() async {
    final rows = await _db.getBookRows();
    final base = _api.config.baseUrl;
    final books = [for (final r in rows) Book.fromRow(r).rebasedCover(base)];
    _register(books);
    return books;
  }

  /// 서버에서 받아 SQLite 캐시를 전체 교체하고 반환(앱 실행/새로고침 시 동기화).
  /// 캐시에는 원본 URL 을 저장하고, 반환·표시용으로만 표지 URL 을 baseUrl 로 재작성한다.
  Future<List<Book>> syncFromServer() async {
    final fetched = await _api.fetchBooks();
    await _db.replaceBooks([
      for (var i = 0; i < fetched.length; i++) fetched[i].toRow(i),
    ]);
    final base = _api.config.baseUrl;
    final books = [for (final b in fetched) b.rebasedCover(base)];
    _register(books);
    return books;
  }

  /// 기존 화면(bookColor/bookEmoji/bookImage)이 쓰는 서버 표지 레지스트리 갱신.
  /// 표지(제목→BookCover) + bookId→제목(창작물 source 가 슬러그일 때 표지 매칭용) 둘 다.
  void _register(List<Book> books) {
    registerServerBookCovers(books.map((b) => b.toCover()));
    registerServerBookIds(books.map((b) => MapEntry(b.bookId, b.title)));
  }

  // 동시 선반입 중복 실행 방지(앱 실행 시 캐시 경로·동기화 후 두 번 호출될 수 있음).
  bool _prefetching = false;

  /// 원작 본문 **증분 선반입**: 아직 저장 안 된 책만 `GET /books/{id}/original` 로 받아
  /// SQLite(`book_originals`)에 저장한다(설계: 첫 실행 전체 + 이후 새 책만).
  /// 백그라운드로 호출(첫 실행/화면 진입을 막지 않음). 실패(서버 미연결·404)는 조용히
  /// 넘겨 다음 실행에 재시도한다.
  Future<void> prefetchMissingOriginals(List<Book> books) async {
    if (_prefetching) return;
    _prefetching = true;
    try {
      final stored = await _db.getOriginalBookIds();
      for (final b in books) {
        if (stored.contains(b.bookId)) continue; // 이미 저장된 책은 건너뜀(증분).
        try {
          final text = await _api.fetchOriginalText(b.bookId);
          if (text.isNotEmpty) await _db.setOriginalText(b.bookId, text);
        } catch (_) {
          // 한 권 실패가 나머지를 막지 않도록 개별 try/catch.
        }
      }
    } finally {
      _prefetching = false;
    }
  }
}

final booksRepositoryProvider = Provider<BooksRepository>((ref) {
  return BooksRepository(ref.watch(booksApiProvider), ref.read(dbServiceProvider));
});

/// 원작 목록. 빌드 시 **캐시 먼저** 보여주고 **백그라운드로 서버 동기화**(추가/변경 반영, #0).
/// 캐시가 없으면 서버에서 직접 받는다. `ref.read(booksProvider.notifier).refresh()` 로 강제 새로고침.
class BooksNotifier extends AsyncNotifier<List<Book>> {
  @override
  Future<List<Book>> build() async {
    final repo = ref.read(booksRepositoryProvider);
    final cached = await repo.cached();
    if (cached.isNotEmpty) {
      // 캐시 즉시 반환 + 백그라운드 동기화로 최신화.
      unawaited(_syncInBackground());
      // 캐시 기준으로 아직 본문 없는 책을 미리 받아 둔다(오프라인 원작보기 대비).
      unawaited(repo.prefetchMissingOriginals(cached));
      return cached;
    }
    final fresh = await repo.syncFromServer();
    // 첫 실행(캐시 없음): 책 목록 받은 직후 원작 본문도 백그라운드로 선반입.
    unawaited(repo.prefetchMissingOriginals(fresh));
    return fresh;
  }

  Future<void> _syncInBackground() async {
    try {
      final repo = ref.read(booksRepositoryProvider);
      final fresh = await repo.syncFromServer();
      state = AsyncData(fresh);
      // 동기화로 새로 추가된 책의 본문만 이어서 선반입(증분).
      unawaited(repo.prefetchMissingOriginals(fresh));
    } catch (_) {
      // 서버 미연결: 캐시 유지.
    }
  }

  /// 강제 새로고침(서버 동기화). 새로 들어온 책의 원작 본문도 증분 선반입한다.
  Future<void> refresh() async {
    final repo = ref.read(booksRepositoryProvider);
    state = await AsyncValue.guard(() async {
      final fresh = await repo.syncFromServer();
      unawaited(repo.prefetchMissingOriginals(fresh));
      return fresh;
    });
  }
}

final booksProvider =
    AsyncNotifierProvider<BooksNotifier, List<Book>>(BooksNotifier.new);

/// 제목 → 서버 Book (선택한 원작의 실제 bookId 해석용). 로드 전이면 빈 맵.
final booksByTitleProvider = Provider<Map<String, Book>>((ref) {
  final books = ref.watch(booksProvider).valueOrNull ?? const [];
  return {for (final b in books) b.title: b};
});

/// 특정 책 상세(장면별 선택 진입 시).
final bookDetailProvider =
    FutureProvider.family<BookDetail, String>((ref, bookId) async {
  return ref.watch(booksApiProvider).fetchBookDetail(bookId);
});
