import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../models/sample_data.dart';
import '../services/audio_cache_store.dart';
import '../services/cover_cache_store.dart';
import '../services/db_service.dart';

part 'library_state.freezed.dart';

/// 책장 정렬 모드.
enum LibrarySort { recent, title }

/// 내 서재 상태.
/// [openSource] 가 null 이면 책장 화면, 값이 있으면 해당 원작의 창작물 보기 화면.
@freezed
class LibraryState with _$LibraryState {
  const factory LibraryState({
    String? openSource,
    @Default(0) int page, // 원작별 창작물 보기의 현재 페이지
    @Default(<CreativeWork>[]) List<CreativeWork> works,
    @Default(<String, String>{}) Map<String, String> covers, // 작품 id → 표지 이미지 경로
    @Default(LibrarySort.recent) LibrarySort sort,
    @Default(<String>{}) Set<String> favorites, // 즐겨찾기한 원작 제목
    @Default(<String, double>{}) Map<String, double> reading, // 원작 제목 → 읽던 스크롤 위치
  }) = _LibraryState;
}

// 로컬 DB(app_kv) 저장 키.
const _kFavoritesKey = 'lib_favorites';
const _kReadingKey = 'lib_reading';
const _kCoversKey = 'lib_covers';

class LibraryNotifier extends Notifier<LibraryState> {
  DbService get _db => ref.read(dbServiceProvider);

  /// 표지 백그라운드 재다운로드가 도는 중인지(재진입·다운로드 폭주 방지).
  bool _retryingCovers = false;

  @override
  LibraryState build() {
    // 내 서재는 **실제 창작물 History** 만 보여 준다(데모 시드 없음). 곧 로컬 DB 값으로 채운다.
    _load();
    return const LibraryState();
  }

  /// 저장해 둔 즐겨찾기·읽던 위치·표지와 로컬 DB 창작물을 불러와 상태에 반영.
  Future<void> _load() async {
    try {
      final favs =
          (_decodeList(await _db.getKv(_kFavoritesKey))).cast<String>().toSet();
      final reading = _decodeDoubleMap(await _db.getKv(_kReadingKey));
      final covers = _decodeStringMap(await _db.getKv(_kCoversKey));
      // 로드 도중 사용자가 이미 바꾼 in-session 값이 있으면 그쪽을 우선한다(덮어쓰지 않음).
      state = state.copyWith(
        favorites: {...favs, ...state.favorites},
        reading: {...reading, ...state.reading},
        covers: {...covers, ...state.covers},
      );
    } catch (_) {
      // DB 미지원 환경: 기본값 유지.
    }
    await _loadWorks();
  }

  List<dynamic> _decodeList(String? json) {
    if (json == null || json.isEmpty) return const [];
    return jsonDecode(json) as List<dynamic>;
  }

  /// 로컬 DB(works)에서 실제 창작물 목록을 불러와 상태에 반영(데모 시드 없음).
  /// 표지 오프라인 캐시 파일명이 있으면 절대 경로를 해석해 [CreativeWork.coverLocalAbsPath] 에 채운다
  /// (디스크에 받아 둔 표지를 우선 렌더 → 오프라인에서도 표시). 미다운로드면 생성 표지 URL 폴백.
  Future<void> _loadWorks() async {
    try {
      final works = await _db.getWorks();
      final store = ref.read(coverCacheStoreProvider);
      final resolved = [
        for (final w in works)
          w.copyWith(
            coverLocalAbsPath:
                await store.pathForFileName(w.creationCoverLocalPath),
          ),
      ];
      state = state.copyWith(works: resolved);
      // 로컬에 표지 파일이 아직 없는 작품(생성 직후·첫 다운로드 실패·오프라인 생성분)은
      // 원격 URL 로 백그라운드 재다운로드 → 받으면 로컬 AI 표지로 교체한다(서재 표시는 막지 않음).
      unawaited(_retryMissingCovers(resolved));
    } catch (_) {
      // DB 미지원 환경: 빈 목록 유지.
    }
  }

  /// 로컬 표지 파일이 없는 작품을 원격 URL 로 백그라운드 다운로드해 AI 표지로 교체한다.
  /// 생성 직후(다운로드 전)·첫 다운로드 실패·오프라인 생성분이 이후 온라인에서 자동 복구되도록 한다.
  /// 받은 게 하나라도 있으면 다시 로드해 화면(URL → 로컬 파일)을 갱신한다.
  /// 옛 빌드가 남긴 절대경로만 있는 작품은 URL 이 http 가 아니라 다운로드 대상에서 제외한다.
  Future<void> _retryMissingCovers(List<CreativeWork> works) async {
    if (_retryingCovers) return;
    final pending = [
      for (final w in works)
        if (w.coverLocalAbsPath == null &&
            (w.creationCoverImageUrl?.startsWith('http') ?? false))
          w,
    ];
    if (pending.isEmpty) return;
    _retryingCovers = true;
    final store = ref.read(coverCacheStoreProvider);
    var anyDownloaded = false;
    try {
      for (final w in pending) {
        final name = await store.download(w.creationCoverImageUrl!, w.id);
        if (name != null) {
          await _db.setCoverLocalPath(w.id, name);
          anyDownloaded = true;
        }
      }
    } catch (_) {
      // 네트워크/DB 오류는 무시(다음 로드에서 재시도).
    } finally {
      _retryingCovers = false;
    }
    // 받은 표지를 반영(이번에 받은 작품은 로컬 파일이 생겨 다음 로드의 재시도 대상에서 빠진다).
    if (anyDownloaded) await _loadWorks();
  }

  Map<String, double> _decodeDoubleMap(String? json) {
    if (json == null) return {};
    final m = jsonDecode(json) as Map<String, dynamic>;
    return {for (final e in m.entries) e.key: (e.value as num).toDouble()};
  }

  Map<String, String> _decodeStringMap(String? json) {
    if (json == null) return {};
    final m = jsonDecode(json) as Map<String, dynamic>;
    return {for (final e in m.entries) e.key: e.value as String};
  }

  void openBook(String source) => state = state.copyWith(openSource: source, page: 0);

  void closeBook() => state = state.copyWith(openSource: null, page: 0);

  void setPage(int i) => state = state.copyWith(page: i);

  /// 작품 표지 이미지를 지정(대표 이미지 변경).
  void setCover(String id, String imagePath) {
    state = state.copyWith(covers: {...state.covers, id: imagePath});
    _db.setKv(_kCoversKey, jsonEncode(state.covers)).catchError((_) {});
  }

  /// 책장 정렬 모드 변경.
  void setSort(LibrarySort s) => state = state.copyWith(sort: s);

  /// 원작 즐겨찾기 토글.
  void toggleFavorite(String source) {
    final next = {...state.favorites};
    if (!next.add(source)) next.remove(source);
    state = state.copyWith(favorites: next);
    _db.setKv(_kFavoritesKey, jsonEncode(next.toList())).catchError((_) {});
  }

  /// 원작 읽던 스크롤 위치 저장.
  void setReading(String source, double offset) {
    state = state.copyWith(reading: {...state.reading, source: offset});
    _db.setKv(_kReadingKey, jsonEncode(state.reading)).catchError((_) {});
  }

  /// 새 창작물을 로컬 DB 에 저장하고 서재 목록 맨 앞에 추가한다.
  /// (생성 흐름에서 /generate 결과를 저장할 때 사용)
  Future<void> addWork(CreativeWork work, WorkContent content) async {
    try {
      await _db.insertWork(work, content);
    } catch (_) {
      // DB 미지원 환경: 메모리 상태에만 반영한다.
    }
    final others = state.works.where((w) => w.id != work.id);
    state = state.copyWith(works: [work, ...others]);
  }

  /// 데이터 초기화: 모든 창작물·저장값을 비우고 책장 화면으로 되돌린다.
  void clearAll() {
    state = const LibraryState();
    _db.removeKv(_kFavoritesKey).catchError((_) {});
    _db.removeKv(_kReadingKey).catchError((_) {});
    _db.removeKv(_kCoversKey).catchError((_) {});
    _db.clearAll().catchError((_) {});
    // 창작물과 함께 받아 둔 오프라인 캐시(MP3·표지 이미지)도 전부 비운다.
    ref.read(audioCacheStoreProvider).clear().catchError((_) {});
    ref.read(coverCacheStoreProvider).clear().catchError((_) {});
  }

  /// 창작물 삭제. 해당 원작의 마지막 창작물이면 책장으로 돌아간다.
  void removeWork(String id) {
    final removed = state.works.where((w) => w.id == id).firstOrNull;
    final next = state.works.where((w) => w.id != id).toList();
    final sourceLeft =
        removed != null && next.any((w) => w.source == removed.source);
    state = state.copyWith(
      works: next,
      openSource: sourceLeft ? state.openSource : null,
      page: 0,
    );
    _db.deleteWork(id).catchError((_) {});
    // 창작물 삭제 시 받아 둔 오프라인 캐시 파일도 함께 제거(CRUD).
    // - MP3(.mp3/.part), 표지 이미지(<id>.*/.part)
    ref.read(audioCacheStoreProvider).delete(id).catchError((_) {});
    ref.read(coverCacheStoreProvider).delete(id).catchError((_) {});
  }

  /// 창작물 제목 수정. 빈 입력은 무시.
  void renameWork(String id, String title) {
    if (title.trim().isEmpty) return;
    final trimmed = title.trim();
    state = state.copyWith(works: [
      for (final w in state.works)
        w.id == id ? w.copyWith(title: trimmed, updatedAt: DateTime.now()) : w,
    ]);
    _db.updateTitle(id, trimmed).catchError((_) {});
  }

  /// DB 의 변경(결과 화면에서의 제목·줄 편집 등)을 서재에 다시 반영한다.
  Future<void> refresh() => _loadWorks();
}

final libraryProvider =
    NotifierProvider<LibraryNotifier, LibraryState>(LibraryNotifier.new);

/// 원작별로 묶고, 가장 최근 수정일 기준으로 정렬한 책 목록(기획서 7-1).
List<(String source, List<CreativeWork> works)> groupBySource(
    List<CreativeWork> works) {
  final map = <String, List<CreativeWork>>{};
  for (final w in works) {
    map.putIfAbsent(w.source, () => []).add(w);
  }
  final groups = [
    for (final e in map.entries)
      (
        e.key,
        e.value..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      ),
  ];
  groups.sort((a, b) => b.$2.first.updatedAt.compareTo(a.$2.first.updatedAt));
  return groups;
}

/// 모든 원작([bookTitles] = 서버 GET /books 제목들)을 [sort] 규칙으로 정렬해
/// (제목, 창작물목록) 으로 반환. 창작물이 없는 원작도 빈 목록과 함께 포함된다(0편 표시용).
/// 서버 목록엔 없지만 창작물이 있는 원작도 포함한다(과거 창작물 보존).
/// - 최신순: 창작물이 있는 원작을 최근 수정 순으로, 없는 원작은 뒤쪽에 가나다순.
/// - 가나다순: 창작물 유무와 무관하게 제목순.
List<(String source, List<CreativeWork> works)> allOriginals(
    List<CreativeWork> works, LibrarySort sort, List<String> bookTitles,
    [Set<String> favorites = const {}]) {
  final map = <String, List<CreativeWork>>{};
  for (final w in works) {
    map.putIfAbsent(w.source, () => []).add(w);
  }
  for (final list in map.values) {
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }
  final titles = <String>[...bookTitles];
  for (final k in map.keys) {
    if (!titles.contains(k)) titles.add(k);
  }
  final result = [
    for (final t in titles) (t, map[t] ?? <CreativeWork>[]),
  ];
  int base(
      (String, List<CreativeWork>) a, (String, List<CreativeWork>) b) {
    if (sort == LibrarySort.title) return a.$1.compareTo(b.$1);
    final aHas = a.$2.isNotEmpty, bHas = b.$2.isNotEmpty;
    if (aHas && bHas) {
      return b.$2.first.updatedAt.compareTo(a.$2.first.updatedAt);
    }
    if (aHas != bHas) return aHas ? -1 : 1; // 창작물 있는 원작 먼저
    return a.$1.compareTo(b.$1); // 둘 다 없으면 가나다순
  }

  result.sort((a, b) {
    // 즐겨찾기한 원작을 항상 앞쪽에.
    final af = favorites.contains(a.$1), bf = favorites.contains(b.$1);
    if (af != bf) return af ? -1 : 1;
    return base(a, b);
  });
  return result;
}
