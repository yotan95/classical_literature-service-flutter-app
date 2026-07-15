import '../state/create_main_state.dart' show CreateMode, RangeMode;
import 'sample_data.dart' show bookSlug;

/// `POST /create` 요청 본문 모델.
/// 앱 상태(createMainProvider + 설정)를 백엔드 API 계약에 맞춰 직렬화한다.
/// 바디 필드·enum 문자열(bookId/mode/difficulty/scope/sceneIds/ideaText)은 백엔드
/// CreateRequest 와 **정확히 동일**해야 한다(백엔드에 없는 필드는 보내지 않는다).
class CreateRequest {
  const CreateRequest({
    required this.bookId,
    required this.mode,
    required this.difficulty,
    this.scope = 'full',
    this.sceneIds = const [],
    this.ideaText = '',
  });

  final String bookId; // 백엔드 슬러그(언더스코어, book.json 폴더명). 빈 값 불가.
  final String mode; // dialogue | audio
  final String difficulty; // children | korean_learner | youth | original
  final String scope; // full | scene
  final List<String> sceneIds; // scope=="scene" 일 때 ≥1
  final String ideaText;

  Map<String, dynamic> toJson() => {
        'bookId': bookId,
        'mode': mode,
        'difficulty': difficulty,
        'scope': scope,
        'sceneIds': sceneIds,
        'ideaText': ideaText,
      };

  /// 요청을 보내기 전 앱 단에서 잡는 사전 검증(백엔드 422 와 동일 규칙).
  /// 통과하면 null, 실패하면 사용자에게 보여줄 한국어 사유를 반환한다.
  String? validate() {
    if (bookId.isEmpty) return '아직 준비 중인 원작이에요. 다른 작품을 골라 주세요.';
    if (scope == 'scene' && sceneIds.isEmpty) return '장면을 한 개 이상 선택해 주세요.';
    return null;
  }
}

// ── enum 매핑 (앱 ↔ 백엔드 API) ─────────────────────────────

/// 앱 난이도(한글 라벨) → API difficulty enum.
/// kLevels 순서대로 children/korean_learner/youth/original — 백엔드 Difficulty enum 과 동일.
const Map<String, String> kDifficultyByLevel = {
  '동화책 수준': 'children',
  '읽기 도움 많이': 'children',
  '한국어 배우는 중': 'korean_learner',
  '청소년용': 'youth',
  '고전의 결 살리기': 'original',
  '원작 느낌 살리기': 'original',
};

String modeToApi(CreateMode m) => m == CreateMode.dialogue ? 'dialogue' : 'audio';

String scopeToApi(RangeMode r) => r == RangeMode.full ? 'full' : 'scene';

/// 원작 제목 → 백엔드 슬러그(book.json 폴더명). 단일 출처는 [bookSlug](sample_data).
/// 백엔드에 대응 원작이 없으면 null → CTA 가 막힌다(validate).
String? bookIdForSource(String source) => bookSlug(source);

/// 난이도 라벨 → API difficulty(미매핑 시 youth 기본).
String difficultyToApi(String level) => kDifficultyByLevel[level] ?? 'youth';
