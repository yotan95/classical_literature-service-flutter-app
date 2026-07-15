import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 창작물 표지용 사진을 갤러리에서 가져온다(Android Photo Picker / iOS PHPicker).
///
/// 갤러리가 넘겨주는 경로는 임시 캐시라 언제든 정리될 수 있으므로,
/// 고른 사진을 앱 문서 폴더(`<app-docs>/covers/`) 안으로 복사한 뒤
/// 그 영구 경로를 돌려준다. 사용자가 취소하면 null.
///
/// 반환 경로는 `assets/` 로 시작하지 않는 실제 파일 경로이므로,
/// 표지를 그릴 때 [coverIsAsset] 로 에셋/파일을 구분해 렌더링한다.
class CoverPicker {
  CoverPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// 갤러리에서 사진 한 장을 골라 앱 문서 폴더에 복사하고 그 경로를 반환.
  /// [workId] 는 파일명에 섞어 작품별로 구분한다.
  Future<String?> pickFromGallery(String workId) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080, // 표지로 충분한 해상도로 다운스케일(저장 용량 절약)
      imageQuality: 85,
    );
    if (picked == null) return null; // 사용자가 취소

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'covers'));
    if (!await dir.exists()) await dir.create(recursive: true);

    final ext = p.extension(picked.path).isEmpty ? '.jpg' : p.extension(picked.path);
    final safeId = workId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final dest = p.join(
        dir.path, '${safeId}_${DateTime.now().millisecondsSinceEpoch}$ext');

    await File(picked.path).copy(dest);
    return dest;
  }
}

/// 표지 경로가 번들 에셋인지(true) 갤러리에서 가져온 실제 파일인지(false) 구분.
bool coverIsAsset(String path) => path.startsWith('assets/');
