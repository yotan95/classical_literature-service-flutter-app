import 'package:flutter/material.dart';

/// 쉬운 고전 창작 극장 — 디자인 토큰
/// 포인트 컬러는 세이지 그린 #3D8A65 로 고정.
class AppColors {
  AppColors._();

  // 포인트 / 강조
  static const Color sage = Color(0xFF3D8A65); // accent
  static const Color src = Color(0xFFA07860); // 원작 소스색

  // 배경
  static const Color canvas = Color(0xFFDDDCDA); // 바깥 캔버스
  static const Color surface = Color(0xFFFFFFFF); // 화면 본문
  static const Color surfaceAlt = Color(0xFFFAFAF8); // 콘텐츠 영역
  static const Color shelfPlank = Color(0xFFEDEBE6);
  static const Color shelfBg = Color(0xFFF7F2E7); // 내 서재 책장 배경(크림)
  static const Color shelfWood = Color(0xFFE3D4B8); // 내 서재 책장 선반(우드)

  // 텍스트
  static const Color ink = Color(0xFF1C1A17); // 기본
  static const Color textSub = Color(0xFF888888);
  static const Color textMuted = Color(0xFF999999);
  static const Color textFaint = Color(0xFFBBBBBB);

  // 선
  static const Color border = Color(0xFFEBEBEB);
  static const Color divider = Color(0xFFF0F0F0);

  // 위험(삭제 등 되돌릴 수 없는 동작)
  static const Color danger = Color(0xFFD0584A);

  // 경고
  static const Color warnBg = Color(0xFFFFF8E5);
  static const Color warnBorder = Color(0xFFF0D870);
  static const Color warnText = Color(0xFFA08010);

  // 하이라이트(표시하기)
  static const Color highlight = Color(0xFFFFF176);

  /// 인물 색 팔레트 (대사극·오디오극 공통). 서버가 내려준 인물에 순서대로 배정한다.
  static const List<({Color bg, Color fg})> _characterFallback = [
    (bg: Color(0xFFFEF3E0), fg: Color(0xFFA0620A)),
    (bg: Color(0xFFEBF3FF), fg: Color(0xFF2855A0)),
    (bg: Color(0xFFF3EBFF), fg: Color(0xFF7A45B8)),
    (bg: Color(0xFFE6F5EC), fg: Color(0xFF2E7D4F)),
    (bg: Color(0xFFFCE8EC), fg: Color(0xFFB03A52)),
    (bg: Color(0xFFFFF6E0), fg: Color(0xFF9A7B10)),
    (bg: Color(0xFFE9F0F5), fg: Color(0xFF3A6080)),
  ];

  /// 인물 이름 → 색. 이름 해시로 폴백 팔레트에서 안정적으로 한 색을 고른다
  /// (같은 이름은 항상 같은 색). 단일 인물 폴백용 — 한 작품의 인물들에게
  /// "서로 다른" 색을 보장하려면 [characterColors] 로 작품 단위 맵을 만들어 쓸 것.
  static ({Color bg, Color fg}) characterColor(String name) {
    if (name.isEmpty) {
      return (bg: const Color(0xFFF0F0F0), fg: const Color(0xFF666666));
    }
    final idx =
        name.codeUnits.fold<int>(0, (a, c) => a + c) % _characterFallback.length;
    return _characterFallback[idx];
  }

  /// 한 작품에 등장하는 인물들에게 "서로 겹치지 않는" 색을 배정한 맵을 만든다.
  /// [orderedNames] 는 등장 순서(중복·null·내레이션 빈 이름 허용 — 알아서 걸러냄).
  /// 팔레트에서 색을 순서대로 배정하므로, 인물이 팔레트 수보다 많을 때만 색이 순환된다.
  static Map<String, ({Color bg, Color fg})> characterColors(
      Iterable<String?> orderedNames) {
    final result = <String, ({Color bg, Color fg})>{};
    for (final raw in orderedNames) {
      final name = (raw ?? '').trim();
      if (name.isEmpty || result.containsKey(name)) continue;
      result[name] =
          _characterFallback[result.length % _characterFallback.length];
    }
    return result;
  }

  /// React 의 `ac + '0C'` 같은 hex-alpha 보조용.
  /// 예) AppColors.alpha(AppColors.sage, 0x0C)
  static Color alpha(Color base, int alpha) =>
      base.withAlpha(alpha.clamp(0, 255));
}
