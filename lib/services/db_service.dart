import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/sample_data.dart';

/// 창작물 1건의 본문 묶음(메타데이터 [CreativeWork] 와 분리).
/// 결과 화면이 작품을 열 때 필요한 모든 콘텐츠를 담는다.
class WorkContent {
  const WorkContent({
    this.lines = const [],
    this.scenes = const {},
    this.vocab = const {},
    this.highlighted = const {},
    this.audioSpeed = 1.0,
    this.lastPositionMs = 0,
    this.audioUrl,
    this.timepoints = const {},
    this.audioLocalPath,
  });

  final List<ScriptLine> lines; // 대본 줄 N개
  final Map<int, String> scenes; // 장면 번호 → 제목
  final Map<String, VocabEntry> vocab; // 단어 → 풀이
  final Set<int> highlighted; // 표시(하이라이트)한 줄 id
  final double audioSpeed; // 오디오극 마지막 배속
  final int lastPositionMs; // 오디오극 마지막 재생 위치(ms)
  // 오디오극(서버 단일 MP3) — 대사극이면 null/빈값.
  final String? audioUrl; // result.audio.audioUrl (단일 MP3)
  final Map<int, (int start, int end)> timepoints; // ScriptLine.id → (startMs,endMs)
  // 오프라인 캐시: 디스크에 받아 둔 MP3 파일명(절대경로 아님). 없으면 아직 미다운로드.
  // 실제 파일은 AudioCacheStore(앱 지원 폴더/audio_cache)에 두고 여기엔 파일명만 보관.
  final String? audioLocalPath;

  WorkContent copyWith({
    Set<int>? highlighted,
    double? audioSpeed,
    int? lastPositionMs,
    String? audioLocalPath,
  }) =>
      WorkContent(
        lines: lines,
        scenes: scenes,
        vocab: vocab,
        highlighted: highlighted ?? this.highlighted,
        audioSpeed: audioSpeed ?? this.audioSpeed,
        lastPositionMs: lastPositionMs ?? this.lastPositionMs,
        audioUrl: audioUrl,
        timepoints: timepoints,
        audioLocalPath: audioLocalPath ?? this.audioLocalPath,
      );
}

/// 로컬 SQLite 저장소.
/// 사용자 데이터(창작물·서재 설정·앱 설정)는 전부 휴대폰 샌드박스 DB 에만 저장한다.
/// (서버로 보내 저장하지 않음 — 오프라인 우선)
///
/// 구조:
///   works   : 창작물 1건 = 1행. 대본 줄·장면·어휘·표시·오디오 상태를 함께 보관.
///   app_kv  : 앱 전역 키–값(즐겨찾기·읽던 위치·표지·설정값). 값은 JSON 문자열.
class DbService {
  DbService();

  static const _dbName = 'classic_theater.db';
  static const _dbVersion = 9;

  /// 과거 seedIfEmpty 로 심어진 데모 창작물 id(이제 시드 안 함 → 기존 DB 에서 제거 대상).
  static const _demoWorkIds = [
    'w1', 'w2', 'w3', 'w4', 'w5', 'w6', 'w7', 'w8',
  ];
  static const _works = 'works';
  static const _kv = 'app_kv';
  static const _books = 'books'; // GET /books 캐시(원작 목록)
  static const _bookOriginals =
      'book_originals'; // GET /books/{id}/original 본문 캐시(책당 1행)

  Database? _db;

  /// 지연 오픈. 앱 샌드박스(getDatabasesPath)에만 파일을 둔다(외부 저장소 금지).
  Future<Database> get _database async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getDatabasesPath();
    final path = p.join(dir, _dbName);
    final db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, _) async {
        await _createWorks(db);
        await _createKv(db);
        await _createBooks(db);
        await _createBookOriginals(db);
      },
      onUpgrade: (db, oldV, newV) async {
        // v1 → v2: works 에 컬럼 추가 + app_kv 신설.
        if (oldV < 2) {
          await db.execute(
              "ALTER TABLE $_works ADD COLUMN scenes TEXT NOT NULL DEFAULT ''");
          await db.execute(
              "ALTER TABLE $_works ADD COLUMN vocab TEXT NOT NULL DEFAULT ''");
          await db.execute(
              "ALTER TABLE $_works ADD COLUMN highlighted TEXT NOT NULL DEFAULT ''");
          await db.execute(
              "ALTER TABLE $_works ADD COLUMN audio_speed REAL NOT NULL DEFAULT 1.0");
          await db.execute(
              "ALTER TABLE $_works ADD COLUMN last_position INTEGER NOT NULL DEFAULT 0");
          await _createKv(db);
        }
        // v2 → v3: 서버 단일 MP3 오디오극 — audio_url + timepoints 보관.
        if (oldV < 3) {
          await db.execute(
              "ALTER TABLE $_works ADD COLUMN audio_url TEXT NOT NULL DEFAULT ''");
          await db.execute(
              "ALTER TABLE $_works ADD COLUMN timepoints TEXT NOT NULL DEFAULT ''");
        }
        // v3 → v4: GET /books 캐시 테이블 신설.
        if (oldV < 4) {
          await _createBooks(db);
        }
        // v4 → v5: 과거에 심어진 데모 창작물 제거(이제 내 서재는 실제 창작물만).
        if (oldV < 5) {
          await db.delete(
            _works,
            where: 'id IN (${List.filled(_demoWorkIds.length, '?').join(',')})',
            whereArgs: _demoWorkIds,
          );
        }
        // v5 → v6: 창작물 대표 이미지/이모지 분리 저장(원작 표지와 무관).
        // 기존 행은 창작물 대표 이미지가 없으므로 image=null, emoji 는 기본 🎭 로 채운다.
        if (oldV < 6) {
          await db.execute(
              "ALTER TABLE $_works ADD COLUMN creation_cover_image_url TEXT");
          await db.execute(
              "ALTER TABLE $_works ADD COLUMN creation_cover_emoji TEXT");
          await db.update(_works, {'creation_cover_emoji': '🎭'},
              where: 'creation_cover_emoji IS NULL');
        }
        // v6 → v7: 오디오극 MP3 오프라인 캐시 — 디스크 파일명 보관 컬럼 신설.
        // (실제 MP3 는 AudioCacheStore 가 디스크에 두고 여기엔 파일명만 저장)
        if (oldV < 7) {
          await db.execute(
              "ALTER TABLE $_works ADD COLUMN audio_local_path TEXT");
        }
        // v7 → v8: 창작물 표지(AI 이미지) 오프라인 캐시 — 디스크 파일명 보관 컬럼 신설.
        // (실제 이미지는 CoverCacheStore 가 디스크에 두고 여기엔 파일명만 저장)
        if (oldV < 8) {
          await db.execute(
              "ALTER TABLE $_works ADD COLUMN creation_cover_local_path TEXT");
        }
        // v8 → v9: 원작 본문(GET /books/{id}/original) 오프라인 캐시 테이블 신설.
        // (books 는 동기화 시 전체 교체되므로 본문은 살아남도록 별도 테이블에 둔다)
        if (oldV < 9) {
          await _createBookOriginals(db);
        }
      },
    );
    _db = db;
    return db;
  }

  Future<void> _createWorks(Database db) => db.execute('''
        CREATE TABLE $_works (
          id            TEXT PRIMARY KEY,
          title         TEXT NOT NULL,
          source        TEXT NOT NULL,
          mode          TEXT NOT NULL,
          level         TEXT NOT NULL,
          description   TEXT NOT NULL DEFAULT '',
          updated_at    INTEGER NOT NULL,
          lines         TEXT NOT NULL DEFAULT '',
          scenes        TEXT NOT NULL DEFAULT '',
          vocab         TEXT NOT NULL DEFAULT '',
          highlighted   TEXT NOT NULL DEFAULT '',
          audio_speed   REAL NOT NULL DEFAULT 1.0,
          last_position INTEGER NOT NULL DEFAULT 0,
          audio_url     TEXT NOT NULL DEFAULT '',
          timepoints    TEXT NOT NULL DEFAULT '',
          creation_cover_image_url TEXT,
          creation_cover_emoji     TEXT,
          audio_local_path TEXT,
          creation_cover_local_path TEXT
        )
      ''');

  Future<void> _createKv(Database db) => db.execute('''
        CREATE TABLE $_kv (
          k TEXT PRIMARY KEY,
          v TEXT NOT NULL
        )
      ''');

  /// 원작 목록 캐시(GET /books). 실행 시 서버와 동기화(전체 교체)해 추가/변경을 반영.
  Future<void> _createBooks(Database db) => db.execute('''
        CREATE TABLE $_books (
          book_id           TEXT PRIMARY KEY,
          title             TEXT NOT NULL,
          emoji             TEXT NOT NULL DEFAULT '',
          author            TEXT NOT NULL DEFAULT '',
          era               TEXT NOT NULL DEFAULT '',
          difficulty        TEXT NOT NULL DEFAULT '',
          tags              TEXT NOT NULL DEFAULT '[]',
          cover_color       TEXT NOT NULL DEFAULT '',
          cover_image_url   TEXT,
          short_description TEXT NOT NULL DEFAULT '',
          scene_count       INTEGER NOT NULL DEFAULT 0,
          sort_order        INTEGER NOT NULL DEFAULT 0,
          fetched_at        INTEGER NOT NULL DEFAULT 0
        )
      ''');

  /// 원작 본문 캐시(GET /books/{id}/original). books 와 분리해 동기화 전체 교체에도 보존.
  Future<void> _createBookOriginals(Database db) => db.execute('''
        CREATE TABLE $_bookOriginals (
          book_id    TEXT PRIMARY KEY,
          text       TEXT NOT NULL DEFAULT '',
          fetched_at INTEGER NOT NULL DEFAULT 0
        )
      ''');

  // ── 원작 목록 캐시 ───────────────────────────────────────

  /// 서버 책 목록으로 캐시를 **전체 교체**(추가/삭제/변경 반영). [rows] 는 books 컬럼 맵.
  Future<void> replaceBooks(List<Map<String, Object?>> rows) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete(_books);
      final batch = txn.batch();
      for (final r in rows) {
        batch.insert(_books, r, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  /// 캐시된 원작 목록 행(sort_order 순).
  Future<List<Map<String, Object?>>> getBookRows() async {
    final db = await _database;
    return db.query(_books, orderBy: 'sort_order ASC');
  }

  // ── 원작 본문 캐시 ───────────────────────────────────────

  /// 저장된 원작 본문. 없으면 null(미저장), 빈 행이면 ''.
  Future<String?> getOriginalText(String bookId) async {
    final db = await _database;
    final rows = await db.query(_bookOriginals,
        columns: ['text'], where: 'book_id = ?', whereArgs: [bookId], limit: 1);
    if (rows.isEmpty) return null;
    return (rows.first['text'] as String?) ?? '';
  }

  /// 원작 본문 저장(있으면 교체). 선반입·폴백 양쪽에서 사용.
  Future<void> setOriginalText(String bookId, String text) async {
    final db = await _database;
    await db.insert(
      _bookOriginals,
      {
        'book_id': bookId,
        'text': text,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 이미 본문이 저장된 book_id 집합(증분 선반입에서 "받을 책" 판별용).
  Future<Set<String>> getOriginalBookIds() async {
    final db = await _database;
    final rows = await db.query(_bookOriginals, columns: ['book_id']);
    return {for (final r in rows) r['book_id'] as String};
  }

  // ── 직렬화 헬퍼 ─────────────────────────────────────────

  static String _encScenes(Map<int, String> m) =>
      jsonEncode({for (final e in m.entries) '${e.key}': e.value});

  static Map<int, String> _decScenes(String? json) {
    if (json == null || json.isEmpty) return const {};
    final m = jsonDecode(json) as Map<String, dynamic>;
    return {
      for (final e in m.entries)
        if (int.tryParse(e.key) != null) int.parse(e.key): '${e.value}'
    };
  }

  static String _encVocab(Map<String, VocabEntry> m) =>
      jsonEncode({for (final e in m.entries) e.key: e.value.toMap()});

  static Map<String, VocabEntry> _decVocab(String? json) {
    if (json == null || json.isEmpty) return const {};
    final m = jsonDecode(json) as Map<String, dynamic>;
    return {
      for (final e in m.entries)
        e.key: VocabEntry.fromMap((e.value as Map).cast<String, dynamic>())
    };
  }

  static String _encInts(Set<int> s) => jsonEncode(s.toList());

  static Set<int> _decInts(String? json) {
    if (json == null || json.isEmpty) return <int>{};
    final list = jsonDecode(json) as List<dynamic>;
    return {for (final e in list) (e as num).toInt()};
  }

  // 오디오 timepoints: { "<lineId>": [startMs, endMs] } 형태로 직렬화.
  static String _encTimepoints(Map<int, (int, int)> m) => jsonEncode(
      {for (final e in m.entries) '${e.key}': [e.value.$1, e.value.$2]});

  static Map<int, (int, int)> _decTimepoints(String? json) {
    if (json == null || json.isEmpty) return const {};
    final m = jsonDecode(json) as Map<String, dynamic>;
    return {
      for (final e in m.entries)
        if (int.tryParse(e.key) != null)
          int.parse(e.key): (
            ((e.value as List)[0] as num).toInt(),
            ((e.value as List)[1] as num).toInt(),
          ),
    };
  }

  Map<String, Object?> _contentColumns(WorkContent c) => {
        'lines': ScriptLine.encodeList(c.lines),
        'scenes': _encScenes(c.scenes),
        'vocab': _encVocab(c.vocab),
        'highlighted': _encInts(c.highlighted),
        'audio_speed': c.audioSpeed,
        'last_position': c.lastPositionMs,
        'audio_url': c.audioUrl ?? '',
        'timepoints': _encTimepoints(c.timepoints),
        'audio_local_path': c.audioLocalPath,
      };

  // ── 창작물 저장/조회 ─────────────────────────────────────

  /// 창작물 1건 + 본문을 저장(이미 있으면 덮어쓰기).
  Future<void> insertWork(CreativeWork work, WorkContent content) async {
    final db = await _database;
    await db.insert(
      _works,
      {...work.toRow(), ..._contentColumns(content)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 전체 창작물 목록(최근 수정 순). 본문은 포함하지 않는다(서재 표시용).
  Future<List<CreativeWork>> getWorks() async {
    final db = await _database;
    final rows = await db.query(_works, orderBy: 'updated_at DESC');
    return [for (final r in rows) CreativeWork.fromRow(r)];
  }

  /// 단건 메타데이터. 없으면 null.
  Future<CreativeWork?> getWork(String id) async {
    final db = await _database;
    final rows =
        await db.query(_works, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return CreativeWork.fromRow(rows.first);
  }

  /// 단건 본문(대본·장면·어휘·표시·오디오 상태). 없으면 null.
  Future<WorkContent?> getWorkContent(String id) async {
    final db = await _database;
    final rows =
        await db.query(_works, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return WorkContent(
      lines: ScriptLine.decodeList(r['lines'] as String?),
      scenes: _decScenes(r['scenes'] as String?),
      vocab: _decVocab(r['vocab'] as String?),
      highlighted: _decInts(r['highlighted'] as String?),
      audioSpeed: (r['audio_speed'] as num?)?.toDouble() ?? 1.0,
      lastPositionMs: (r['last_position'] as num?)?.toInt() ?? 0,
      audioUrl: (r['audio_url'] as String?)?.isEmpty ?? true
          ? null
          : r['audio_url'] as String,
      timepoints: _decTimepoints(r['timepoints'] as String?),
      audioLocalPath: (r['audio_local_path'] as String?)?.isEmpty ?? true
          ? null
          : r['audio_local_path'] as String,
    );
  }

  // ── 수정 ────────────────────────────────────────────────

  /// 제목 수정(+ 수정 시각 갱신).
  Future<void> updateTitle(String id, String title) => _update(id, {
        'title': title,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

  /// 대본 줄 전체 교체(+ 수정 시각 갱신).
  Future<void> updateLines(String id, List<ScriptLine> lines) => _update(id, {
        'lines': ScriptLine.encodeList(lines),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

  /// 표시(하이라이트)한 줄 갱신.
  Future<void> updateHighlighted(String id, Set<int> ids) =>
      _update(id, {'highlighted': _encInts(ids)});

  /// 오디오극 배속·마지막 재생 위치 갱신(전달된 값만).
  Future<void> updateAudio(String id, {double? speed, int? positionMs}) =>
      _update(id, {
        if (speed != null) 'audio_speed': speed,
        if (positionMs != null) 'last_position': positionMs,
      });

  /// 오프라인 MP3 캐시 파일명 기록/해제(다운로드 완료 시 파일명, 삭제 시 null).
  Future<void> setAudioLocalPath(String id, String? fileName) =>
      _update(id, {'audio_local_path': fileName});

  /// 오프라인 표지 이미지 캐시 파일명 기록/해제(다운로드 완료 시 파일명, 삭제 시 null).
  Future<void> setCoverLocalPath(String id, String? fileName) =>
      _update(id, {'creation_cover_local_path': fileName});

  Future<void> _update(String id, Map<String, Object?> values) async {
    if (values.isEmpty) return;
    final db = await _database;
    await db.update(_works, values, where: 'id = ?', whereArgs: [id]);
  }

  // ── 삭제 ────────────────────────────────────────────────

  /// 창작물 1건 삭제.
  Future<void> deleteWork(String id) async {
    final db = await _database;
    await db.delete(_works, where: 'id = ?', whereArgs: [id]);
  }

  /// 전체 창작물 삭제(서재 초기화). app_kv 는 [removeKv] 로 따로 비운다.
  Future<void> clearAll() async {
    final db = await _database;
    await db.delete(_works);
  }

  /// 첫 실행 등 비어 있을 때 데모 샘플을 한 번 채운다.
  Future<void> seedIfEmpty(List<CreativeWork> works,
      {WorkContent Function(CreativeWork)? contentOf}) async {
    final db = await _database;
    final count =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $_works'));
    if ((count ?? 0) > 0) return;
    final batch = db.batch();
    for (final w in works) {
      batch.insert(
        _works,
        {
          ...w.toRow(),
          ..._contentColumns(contentOf?.call(w) ?? const WorkContent()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // ── 앱 전역 키–값(app_kv) ────────────────────────────────

  /// 키로 JSON 문자열 값 읽기. 없으면 null.
  Future<String?> getKv(String key) async {
    final db = await _database;
    final rows =
        await db.query(_kv, where: 'k = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['v'] as String?;
  }

  /// 키에 JSON 문자열 값 저장(덮어쓰기).
  Future<void> setKv(String key, String value) async {
    final db = await _database;
    await db.insert(_kv, {'k': key, 'v': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 키 삭제.
  Future<void> removeKv(String key) async {
    final db = await _database;
    await db.delete(_kv, where: 'k = ?', whereArgs: [key]);
  }

  // ── 온보딩 완료 플래그 ───────────────────────────────────
  static const _kOnboarded = 'onboarding_done';

  /// 온보딩을 이미 마쳤는지(최초 실행·초기화 후에는 false).
  Future<bool> isOnboarded() async => (await getKv(_kOnboarded)) == '1';

  /// 온보딩 완료 여부 저장(초기화 시 false 로 지운다).
  Future<void> setOnboarded(bool done) =>
      done ? setKv(_kOnboarded, '1') : removeKv(_kOnboarded);
}

/// 앱 전역에서 공유하는 DB 서비스 인스턴스.
final dbServiceProvider = Provider<DbService>((ref) => DbService());
