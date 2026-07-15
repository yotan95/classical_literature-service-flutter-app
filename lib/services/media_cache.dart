import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final mediaCacheProvider = Provider<MediaCache>((ref) => MediaCache());

/// 서버가 내려준 창작물 미디어를 앱 문서 폴더에 보관한다.
///
/// 현재는 AI 창작물 대표 이미지만 저장한다. 저장된 경로는 `Image.file` 로
/// 그대로 렌더링할 수 있는 실제 파일 경로다.
class MediaCache {
  MediaCache({
    this.subDir = 'creation_covers',
    Future<http.Response> Function(Uri uri)? get,
    Future<Directory> Function()? docsDir,
  })  : _get = get ?? http.get,
        _docsDir = docsDir ?? getApplicationDocumentsDirectory;

  final String subDir;
  final Future<http.Response> Function(Uri uri) _get;
  final Future<Directory> Function() _docsDir;

  Directory? _dir;

  Future<Directory> _ensureDir() async {
    if (_dir != null) return _dir!;
    final docs = await _docsDir();
    final dir = Directory(p.join(docs.path, subDir));
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  /// [url] 이 원격 이미지면 내려받아 로컬 파일 경로를 반환한다.
  ///
  /// 이미 로컬 파일/에셋 경로이거나 다운로드에 실패하면 원래 값을 반환해
  /// 생성 완료 흐름을 막지 않는다.
  Future<String?> cacheCreationCover({
    required String creationId,
    required String? url,
  }) async {
    if (url == null || url.isEmpty) return url;

    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return url;
    }

    try {
      final response = await _get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          response.bodyBytes.isEmpty) {
        return url;
      }

      final dir = await _ensureDir();
      final ext = _extensionFor(uri, response.headers['content-type']);
      final safeId = creationId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final dest = File(p.join(dir.path, '$safeId$ext'));
      final tmp = File(p.join(dir.path, '$safeId.tmp'));

      await tmp.writeAsBytes(response.bodyBytes, flush: true);
      if (await dest.exists()) await dest.delete();
      await tmp.rename(dest.path);
      return dest.path;
    } catch (_) {
      return url;
    }
  }

  /// 데이터 초기화 시 내려받은 AI 대표 이미지도 같이 비운다.
  Future<void> clear() async {
    final dir = await _ensureDir();
    if (await dir.exists()) await dir.delete(recursive: true);
    _dir = null;
  }

  String _extensionFor(Uri uri, String? contentType) {
    final uriExt = p.extension(uri.path).toLowerCase();
    if (RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(uriExt)) return uriExt;

    final type = (contentType ?? '').split(';').first.trim().toLowerCase();
    return switch (type) {
      'image/webp' => '.webp',
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/avif' => '.avif',
      'image/bmp' => '.bmp',
      _ => '.img',
    };
  }
}
