import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 앱 전역 창작물 저장소(created_data).
final creationStoreProvider = Provider<CreationStore>((ref) => CreationStore());

/// 창작 결과(및 로컬 데이터)를 **사용자가 탐색 불가능한 앱 전용 폴더**에
/// JSON 파일로 저장/조회하는 저장소.
///
/// - 위치: `<app-docs>/created_data/<creationId>.json` (path_provider 로 해석, 샌드박스 → 권한 불필요)
/// - 형식: 창작 1건 = JSON 파일 1개(파일명 = creationId)
/// - JSON 파일이 1차(정본) 저장소. SQLite 는 선택적 인덱스(미구현).
///
/// 절대 경로를 하드코딩하지 않는다 — 항상 path_provider 로 해석 후 [p.join] 으로 조합한다.
class CreationStore {
  CreationStore({this.subDir = 'created_data'});

  /// 앱 문서 디렉터리 하위 폴더명.
  final String subDir;

  Directory? _dir;

  /// `created_data/` 디렉터리를 보장하고 반환한다(없으면 생성).
  Future<Directory> _ensureDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, subDir));
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  File _fileFor(Directory dir, String creationId) =>
      File(p.join(dir.path, '$creationId.json'));

  /// 창작 결과 1건 저장. [data] 는 `/create` 의 `result.data` 형태의 JSON Map.
  /// 오프라인 표시를 위해 캐시된 로컬 미디어 경로가 반영될 수 있다.
  /// `creationId` 가 없으면 저장하지 않고 false 를 반환한다.
  Future<bool> save(Map<String, dynamic> data) async {
    final id = data['creationId'];
    if (id is! String || id.isEmpty) return false;
    final dir = await _ensureDir();
    await _fileFor(dir, id).writeAsString(jsonEncode(data));
    return true;
  }

  /// creationId 로 1건 조회(없으면 null).
  Future<Map<String, dynamic>?> read(String creationId) async {
    final dir = await _ensureDir();
    final f = _fileFor(dir, creationId);
    if (!await f.exists()) return null;
    final raw = await f.readAsString();
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// 저장된 모든 창작 결과를 읽어 반환한다(파싱 실패 파일은 건너뜀).
  Future<List<Map<String, dynamic>>> readAll() async {
    final dir = await _ensureDir();
    final out = <Map<String, dynamic>>[];
    await for (final e in dir.list()) {
      if (e is! File || p.extension(e.path) != '.json') continue;
      try {
        final decoded = jsonDecode(await e.readAsString());
        if (decoded is Map<String, dynamic>) out.add(decoded);
      } catch (_) {
        // 손상된 파일은 무시한다.
      }
    }
    return out;
  }

  /// 저장된 creationId 목록.
  Future<List<String>> listIds() async {
    final dir = await _ensureDir();
    final ids = <String>[];
    await for (final e in dir.list()) {
      if (e is File && p.extension(e.path) == '.json') {
        ids.add(p.basenameWithoutExtension(e.path));
      }
    }
    return ids;
  }

  /// 1건 삭제(존재 여부 반환).
  Future<bool> delete(String creationId) async {
    final dir = await _ensureDir();
    final f = _fileFor(dir, creationId);
    if (!await f.exists()) return false;
    await f.delete();
    return true;
  }

  /// 전체 삭제(데이터 초기화에서 사용).
  Future<void> clear() async {
    final dir = await _ensureDir();
    if (await dir.exists()) await dir.delete(recursive: true);
    _dir = null;
  }
}
