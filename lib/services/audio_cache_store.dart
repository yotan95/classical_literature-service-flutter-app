import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 앱 전역 오디오극 MP3 오프라인 캐시 저장소.
final audioCacheStoreProvider =
    Provider<AudioCacheStore>((ref) => AudioCacheStore());

/// 오디오극(서버 단일 MP3)을 **오프라인 재생용으로 디스크에 캐시**하는 저장소.
///
/// 설계(사용자 결정 2026-06-25):
/// - 위치: `getApplicationSupportDirectory()/audio_cache/<creationId>.mp3`
///   (지원 폴더 → 사용자에게 안 보이고 iCloud 백업 제외, OS 가 자동으로 안 지움 →
///    재생성 가능한 캐시에 적합하면서 오프라인 재생이 안정적)
/// - 파일은 디스크에 두고, **참조(파일명)는 SQLite `works.audio_local_path` 에** 기록한다.
///   (BLOB 아님 — DB 비대화 방지)
/// - 다운로드는 첫 재생 때 서버 스트리밍과 **동시에** 백그라운드로 받는다.
///
/// 절대 경로를 하드코딩하지 않는다 — 항상 path_provider 로 폴더를 해석한 뒤
/// [p.join] 으로 조합한다. DB 에는 **파일명만** 저장하고, 재설치로 샌드박스
/// 경로가 바뀌어도 런타임에 폴더를 다시 해석해 절대 경로를 만든다.
class AudioCacheStore {
  AudioCacheStore({this.subDir = 'audio_cache'});

  /// 앱 지원 디렉터리 하위 폴더명.
  final String subDir;

  Directory? _dir;
  final Dio _dio = Dio();

  /// `audio_cache/` 디렉터리를 보장하고 반환한다(없으면 생성).
  Future<Directory> _ensureDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, subDir));
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  /// creationId 의 캐시 파일명(`<id>.mp3`). DB 에 저장하는 값.
  String fileName(String creationId) => '$creationId.mp3';

  Future<File> _fileFor(String creationId) async {
    final dir = await _ensureDir();
    return File(p.join(dir.path, fileName(creationId)));
  }

  /// 로컬에 받아 둔 MP3 의 절대 경로(없으면 null). 재생 소스 선택에 쓴다.
  Future<String?> localPath(String creationId) async {
    if (creationId.isEmpty) return null;
    final f = await _fileFor(creationId);
    return await f.exists() ? f.path : null;
  }

  /// 서버 MP3([url])를 받아 `.part` 로 저장한 뒤 **원자적 rename** 으로 확정한다.
  /// (중간에 앱이 죽어도 반쪽 파일을 완성본으로 오인하지 않는다)
  /// 성공하면 저장한 파일명([fileName]), 실패하면 null 을 반환한다.
  /// 이미 받아 둔 파일이 있으면 다시 받지 않고 파일명을 돌려준다.
  Future<String?> download(String url, String creationId) async {
    if (url.isEmpty || creationId.isEmpty) return null;
    final f = await _fileFor(creationId);
    if (await f.exists()) return fileName(creationId);
    final part = File('${f.path}.part');
    try {
      if (await part.exists()) await part.delete();
      await _dio.download(url, part.path);
      if (await f.exists()) await f.delete();
      await part.rename(f.path);
      return fileName(creationId);
    } catch (_) {
      // 실패 시 남은 임시 파일을 정리하고 null(다음 재생에서 재시도).
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      return null;
    }
  }

  /// 단건 삭제(`.mp3` + 혹시 남은 `.part`). 창작물 삭제와 함께 호출한다.
  Future<void> delete(String creationId) async {
    if (creationId.isEmpty) return;
    final f = await _fileFor(creationId);
    final part = File('${f.path}.part');
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
    try {
      if (await part.exists()) await part.delete();
    } catch (_) {}
  }

  /// 전체 삭제(데이터 초기화에서 사용).
  Future<void> clear() async {
    final dir = await _ensureDir();
    if (await dir.exists()) await dir.delete(recursive: true);
    _dir = null;
  }
}
