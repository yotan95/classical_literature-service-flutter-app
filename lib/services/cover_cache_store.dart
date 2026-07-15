import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 앱 전역 창작물 표지(AI 생성 대표 이미지) 오프라인 캐시 저장소.
final coverCacheStoreProvider =
    Provider<CoverCacheStore>((ref) => CoverCacheStore());

/// 창작물 대표 이미지(서버가 GPT 이미지로 만들어 `creationCoverImageUrl` 로 내려주는 표지)를
/// **오프라인 표시용으로 디스크에 캐시**하는 저장소. [AudioCacheStore] 와 동일한 설계다.
///
/// 설계(사용자 결정 2026-06-25):
/// - 위치: `getApplicationSupportDirectory()/cover_cache/<creationId>.<ext>`
///   (지원 폴더 → 사용자에게 안 보이고 iCloud 백업 제외, OS 가 자동으로 안 지움 →
///    재생성 가능한 캐시에 적합하면서 오프라인 표시가 안정적)
/// - 파일은 디스크에 두고, **참조(파일명)는 SQLite `works.creation_cover_local_path` 에** 기록한다.
///   (BLOB 아님 — DB 비대화 방지)
/// - 다운로드는 **생성 직후 저장 시점**에 한 번 받는다(한 번도 안 열어봐도 오프라인에서 표지가 보임).
///
/// 절대 경로를 하드코딩하지 않는다 — 항상 path_provider 로 폴더를 해석한 뒤
/// [p.join] 으로 조합한다. DB 에는 **파일명만** 저장하고, 재설치로 샌드박스
/// 경로가 바뀌어도 런타임에 폴더를 다시 해석해 절대 경로를 만든다.
///
/// 확장자는 URL 에서 추출하되, 실제 디코딩은 파일 내용(magic bytes)으로 하므로
/// 확장자는 표시용일 뿐이다(`Image.file` 은 확장자와 무관하게 webp/png/jpg 를 디코딩).
class CoverCacheStore {
  CoverCacheStore({this.subDir = 'cover_cache'});

  /// 앱 지원 디렉터리 하위 폴더명.
  final String subDir;

  Directory? _dir;
  final Dio _dio = Dio();

  /// 캐시로 받아 둘 수 있는 이미지 확장자(그 외 URL 은 `.img` 로 보관).
  static const Set<String> _imageExts = {
    '.webp', '.png', '.jpg', '.jpeg', '.gif',
  };

  /// `cover_cache/` 디렉터리를 보장하고 반환한다(없으면 생성).
  Future<Directory> _ensureDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, subDir));
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  /// URL 경로에서 이미지 확장자를 뽑는다(알 수 없으면 `.img`).
  String _extFromUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final ext = p.extension(path).toLowerCase();
    return _imageExts.contains(ext) ? ext : '.img';
  }

  /// creationId + url 의 캐시 파일명(`<id><ext>`). DB 에 저장하는 값.
  String fileName(String creationId, String url) =>
      '$creationId${_extFromUrl(url)}';

  /// DB 에 저장된 파일명([fileName])으로 캐시 파일의 절대 경로를 해석한다.
  /// 파일이 실제로 존재할 때만 경로를 반환(없으면 null → 원격 URL 폴백).
  Future<String?> pathForFileName(String? fileName) async {
    if (fileName == null || fileName.isEmpty) return null;
    final dir = await _ensureDir();
    final f = File(p.join(dir.path, fileName));
    return await f.exists() ? f.path : null;
  }

  /// 서버 표지([url])를 받아 `.part` 로 저장한 뒤 **원자적 rename** 으로 확정한다.
  /// (중간에 앱이 죽어도 반쪽 파일을 완성본으로 오인하지 않는다)
  /// 성공하면 저장한 파일명([fileName]), 실패하면 null 을 반환한다.
  /// 이미 받아 둔 파일이 있으면 다시 받지 않고 파일명을 돌려준다.
  /// http(s) URL 이 아니면(에셋·로컬 파일 경로) 받지 않고 null.
  Future<String?> download(String url, String creationId) async {
    if (url.isEmpty || creationId.isEmpty || !url.startsWith('http')) return null;
    final name = fileName(creationId, url);
    final dir = await _ensureDir();
    final f = File(p.join(dir.path, name));
    if (await f.exists()) return name;
    final part = File('${f.path}.part');
    try {
      if (await part.exists()) await part.delete();
      await _dio.download(url, part.path);
      if (await f.exists()) await f.delete();
      await part.rename(f.path);
      return name;
    } catch (_) {
      // 실패 시 남은 임시 파일을 정리하고 null(다음 시도에서 재시도).
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      return null;
    }
  }

  /// 단건 삭제(확장자가 다를 수 있어 `<id>.*` 와 남은 `.part` 를 모두 제거).
  /// 창작물 삭제와 함께 호출한다.
  Future<void> delete(String creationId) async {
    if (creationId.isEmpty) return;
    final dir = await _ensureDir();
    if (!await dir.exists()) return;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final base = p.basename(e.path);
      if (base == creationId || base.startsWith('$creationId.')) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  }

  /// 전체 삭제(데이터 초기화에서 사용).
  Future<void> clear() async {
    final dir = await _ensureDir();
    if (await dir.exists()) await dir.delete(recursive: true);
    _dir = null;
  }
}
