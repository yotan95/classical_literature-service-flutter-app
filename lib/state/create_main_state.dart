import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'settings_state.dart' show settingsProvider;

part 'create_main_state.freezed.dart';

enum CreateMode { dialogue, audio } // 대사극 / 오디오극
enum RangeMode { full, scene } // 전체 줄거리 / 장면별 선택

@freezed
class CreateMainState with _$CreateMainState {
  const factory CreateMainState({
    @Default('흥부와 놀부') String book,
    // 사용자가 원작을 직접 고른 적이 있는지. false 이면 화면의 원작 목록 첫 항목을
    // 기본 선택으로 따라간다(서버 목록/즐겨찾기 정렬에 맞춰 자동 갱신).
    @Default(false) bool bookTouched,
    @Default(CreateMode.dialogue) CreateMode mode,
    @Default('청소년용') String level,
    @Default(RangeMode.full) RangeMode rangeMode,
    @Default(0) int selScene,
    @Default('') String idea, // 추가 아이디어 입력값
  }) = _CreateMainState;
}

class CreateMainNotifier extends Notifier<CreateMainState> {
  @override
  CreateMainState build() {
    // 설정의 '기본 읽기 수준'을 창작 난이도 초기값으로 사용하고,
    // 이후 설정이 바뀌면 난이도만 따라 바꾼다(다른 선택은 유지).
    ref.listen(settingsProvider.select((s) => s.level), (prev, next) {
      state = state.copyWith(level: normalizeLevelLabel(next));
    });
    return CreateMainState(
        level: normalizeLevelLabel(ref.read(settingsProvider).level));
  }

  // 사용자가 원작을 직접 선택. 이후로는 목록 첫 항목 자동 추종을 끈다.
  void setBook(String b) =>
      state = state.copyWith(book: b, selScene: 0, bookTouched: true);

  /// 사용자가 아직 원작을 직접 고르지 않았을 때, 화면 목록의 첫 항목을 기본 선택으로 맞춘다.
  /// (touched 로 표시하지 않아, 목록이 늦게 로딩되거나 정렬이 바뀌어도 계속 첫 항목을 따라간다.)
  void defaultBook(String b) {
    if (state.bookTouched || state.book == b) return;
    state = state.copyWith(book: b, selScene: 0);
  }

  void setMode(CreateMode m) => state = state.copyWith(mode: m);
  void setLevel(String l) => state = state.copyWith(level: normalizeLevelLabel(l));
  void setRangeMode(RangeMode r) => state = state.copyWith(rangeMode: r);
  void setScene(int i) => state = state.copyWith(selScene: i);
  void setIdea(String s) => state = state.copyWith(idea: s);

  /// 폼을 기본값으로 되돌린다(둘러보기·창작 시작 직후 호출).
  /// 난이도는 설정의 '기본 읽기 수준'으로, 원작은 bookTouched=false 로 비워 화면 목록의
  /// 첫 항목을 자동 선택하게 하고, 모드·범위·아이디어 입력도 모두 초기 상태로 비운다.
  void reset() {
    state = CreateMainState(
        level: normalizeLevelLabel(ref.read(settingsProvider).level));
  }
}

final createMainProvider =
    NotifierProvider<CreateMainNotifier, CreateMainState>(CreateMainNotifier.new);

// ── 오늘의 추천 ─────────────────────────────────────────
/// 추천 배너용 무작위 선택(원작 + 모드). 앱 세션 동안 한 번만 뽑아 고정한다
/// (매 빌드마다 다시 섞이면 안 됨). [bookPick] 은 0~1 값으로, 표시 시점의
/// 책 목록 길이에 곱해 인덱스로 쓴다 → 서버 목록이 늦게 로딩돼도 자연히 적응한다.
class Recommendation {
  const Recommendation(this.bookPick, this.mode);
  final double bookPick;
  final CreateMode mode;
}

final recommendationProvider = Provider<Recommendation>((ref) {
  final r = Random();
  return Recommendation(r.nextDouble(), kModes[r.nextInt(kModes.length)].$1);
});

// ── 데이터 ─────────────────────────────────────────────

/// 책 표지 (제목, 이모지, 고정 색).
/// [image] 가 있으면 이모지 대신 표지 이미지(에셋)를 사용한다.
class BookCover {
  const BookCover(this.title, this.icon, this.color, {this.image});
  final String title;
  final String icon;
  final Color color;
  final String? image; // 표지 이미지(에셋 경로 또는 서버 URL). 없으면 색+이모지 폴백.
}

// 서버(GET /books) 미연결 시 폴백 목록. 실제 백엔드 6권과 동일하게 유지한다.
// 표지는 bookImage(title)가 슬러그(assets/images/<슬러그>.webp)로 해석한다.
const List<BookCover> kBooks = [
  BookCover('허생전', '📜', Color(0xFF7A8A6A)),
  BookCover('흥부와 놀부', '🐦', Color(0xFFA07860)),
  BookCover('홍길동전', '🗡️', Color(0xFF9A6A6A)),
  BookCover('박씨전', '🌷', Color(0xFF8A5B72)),
  BookCover('콩쥐팥쥐', '🌸', Color(0xFF6A7A9A)),
  BookCover('토끼전', '🐰', Color(0xFFC89450)),
];

/// 서버(GET /books)에서 받은 원작 표지 레지스트리(제목→BookCover). 책 동기화 시 채워진다.
/// `bookColor/bookEmoji/bookImage`(sample_data) 가 이 값을 먼저 보고, 없으면 kBooks 로 폴백한다.
/// → 기존 화면 코드를 고치지 않고 서버 표지/색/이모지를 반영한다.
final Map<String, BookCover> gServerBookCovers = {};

/// 서버 표지 목록으로 레지스트리를 갱신(전체 교체).
void registerServerBookCovers(Iterable<BookCover> covers) {
  gServerBookCovers
    ..clear()
    ..addEntries(covers.map((c) => MapEntry(c.title, c)));
}

/// 서버 bookId(슬러그) → 원작 제목. 책 동기화 시 채워진다.
/// 창작물 결과(`result.data`)는 제목 없이 `bookId` 만 주므로 source 가 슬러그로 저장될 수 있다.
/// 이 맵이 슬러그를, 제목으로 키가 잡힌 표지/색/이모지 레지스트리에 잇는 다리다.
final Map<String, String> gServerBookIdToTitle = {};

/// 서버 책 목록으로 bookId→제목 레지스트리를 갱신(전체 교체).
void registerServerBookIds(Iterable<MapEntry<String, String>> idTitles) {
  gServerBookIdToTitle
    ..clear()
    ..addEntries(idTitles);
}

/// 창작 모드 (이모지, 이름, 설명).
const List<(CreateMode, String, String, String)> kModes = [
  (CreateMode.dialogue, '🎭', '대사극', '인물이 말하는 짧은 극'),
  (CreateMode.audio, '🎙', '오디오극', '들으면서 감상하는 이야기'),
];

/// 난이도 (이모지, 라벨). 라벨의 \n 은 줄바꿈.
const List<(String, String)> kLevels = [
  ('📖', '동화책\n수준'),
  ('🌿', '한국어\n배우는 중'),
  ('⭐', '청소년용'),
  ('🏮', '고전의 결\n살리기'),
];

const String kLegacyEasyLevel = '읽기 도움 많이';
const String kEasyStorybookLevel = '동화책 수준';
const String kLegacyOriginalLevel = '원작 느낌 살리기';
const String kClassicTextureLevel = '고전의 결 살리기';

String normalizeLevelLabel(String level) => switch (level) {
      kLegacyEasyLevel => kEasyStorybookLevel,
      kLegacyOriginalLevel => kClassicTextureLevel,
      _ => level,
    };

String levelApiLabel(String level) => switch (normalizeLevelLabel(level)) {
      kEasyStorybookLevel => kLegacyEasyLevel,
      kClassicTextureLevel => kLegacyOriginalLevel,
      _ => level,
    };

/// 저장된 난이도 값(공백 버전, 예: '한국어 배우는 중')을 칩/카드 표시용 라벨로 바꾼다.
/// [wrap] 이 true(글씨가 아주 클 때)일 때만 디자인상 줄바꿈 라벨(예: '한국어\n배우는 중')로
/// 되돌리고, 평소(false)에는 한 줄(공백 버전)을 그대로 보여 준다.
String levelDisplayLabel(String level, {bool wrap = false}) {
  final normalized = normalizeLevelLabel(level);
  if (!wrap) return normalized;
  for (final l in kLevels) {
    if (l.$2.replaceAll('\n', ' ') == normalized) return l.$2;
  }
  return normalized;
}

const List<String> kIdeaChips = ['결말 바꾸기', '새 인물 넣기', '더 웃기게', '더 감동적으로'];

/// 장면 (이모지, 제목, 설명).
class Scene {
  const Scene(this.icon, this.title, this.desc);
  final String icon;
  final String title;
  final String desc;
}

const Map<String, List<Scene>> kScenes = {
  '허생전': [
    Scene('📚', '가난한 선비', '허생이 글만 읽고 지내며 집안 살림이 어려워져요'),
    Scene('💰', '만 냥을 빌리다', '허생이 변씨에게 큰돈을 빌려 장사를 시작해요'),
    Scene('🍎', '시장을 흔든 장사', '허생이 물건을 사들이고 팔아 큰 이익을 남겨요'),
    Scene('🏝️', '빈 섬의 새 삶', '허생이 사람들과 섬으로 가 새로운 마을을 만들어요'),
    Scene('⚔️', '나라를 향한 꾸짖음', '허생이 권력자에게 현실을 바로 보라고 일깨워요'),
  ],
  '흥부와 놀부': [
    Scene('🏠', '형제의 갈림', '놀부가 흥부네 식구를 집에서 내쫓아요'),
    Scene('🐦', '제비 구하기', '흥부가 다친 제비 다리를 정성껏 고쳐줘요'),
    Scene('🎁', '흥부의 박', '제비가 물어온 박씨에서 보물이 쏟아져요'),
    Scene('😤', '놀부의 욕심', '놀부가 일부러 제비 다리를 부러뜨려요'),
    Scene('🤝', '형제의 화해', '벌을 받은 놀부가 반성하고 화해해요'),
  ],
  '홍길동전': [
    Scene('🌙', '서자로 태어난 길동', '홍길동이 아버지를 아버지라 부르지 못해 괴로워해요'),
    Scene('🗡️', '집을 떠나다', '길동이 집을 나와 세상에서 자기 길을 찾기 시작해요'),
    Scene('🔥', '활빈당의 의적', '길동이 활빈당과 함께 가난한 사람들을 도와요'),
    Scene('👑', '임금 앞에 서다', '길동이 조정과 맞서며 자신의 뜻을 밝혀요'),
    Scene('🏞️', '율도국을 세우다', '길동이 새로운 나라를 세워 백성과 함께 살아가요'),
  ],
  '박씨전': [
    Scene('🌷', '낯선 새색시', '박씨 부인이 못생겼다는 이유로 차가운 시선을 받아요'),
    Scene('🪞', '허물을 벗다', '박씨 부인이 허물을 벗고 본래의 모습을 드러내요'),
    Scene('🧠', '숨은 지혜', '박씨 부인이 뛰어난 지혜와 도술로 집안을 지켜요'),
    Scene('⚔️', '전쟁의 위기', '나라가 전쟁에 휘말리고 박씨 부인이 위험을 알아차려요'),
    Scene('🏮', '충렬의 이름', '박씨 부인의 활약이 인정받고 충절이 기려져요'),
  ],
  '콩쥐팥쥐': [
    Scene('🌾', '불가능한 숙제', '콩쥐가 팥쥐 엄마에게 어려운 일을 받아요'),
    Scene('🐄', '신기한 도움', '동물들이 나타나 콩쥐 일을 도와줘요'),
    Scene('👘', '잔치에 가는 날', '예쁜 옷을 입은 콩쥐가 잔치에 나가요'),
    Scene('👞', '꽃신 한 짝', '서두르다 꽃신 한 짝을 두고 와요'),
    Scene('🌺', '행복한 결말', '원님이 콩쥐를 찾아 함께 살아가요'),
  ],
  '심청전': [
    Scene('🌊', '아버지의 눈', '심청이 아버지 눈을 뜨게 하려 결심해요'),
    Scene('⛵', '인당수로', '심청이 제물이 되어 바다에 뛰어들어요'),
    Scene('🌸', '연꽃에서 부활', '심청이 연꽃 속에서 다시 살아나요'),
    Scene('👑', '왕후가 되다', '임금이 심청을 왕후로 맞아들여요'),
    Scene('👁️', '눈 뜨는 아버지', '심봉사가 딸을 만나 눈을 뜨게 돼요'),
  ],
  '춘향전': [
    Scene('🎋', '첫 만남', '이몽룡과 춘향이 그네 아래에서 만나요'),
    Scene('🌙', '사랑의 맹세', '두 사람이 사랑을 약속하고 함께해요'),
    Scene('😢', '이별의 날', '이몽룡이 한양으로 떠나 춘향은 홀로 남아요'),
    Scene('⛓️', '변사또의 위협', '새 사또가 춘향에게 수청을 강요해요'),
    Scene('🎉', '암행어사 출두', '어사가 된 몽룡이 춘향을 구해내요'),
  ],
  '토끼전': [
    Scene('🐢', '거북이의 초대', '자라가 토끼를 용궁으로 꾀어 데려가요'),
    Scene('🏰', '용궁 도착', '토끼가 용왕 앞에 끌려가요'),
    Scene('🧠', '토끼의 꾀', '토끼가 간을 땅에 두고 왔다고 속여요'),
    Scene('🌊', '탈출 성공', '토끼가 용궁에서 빠져나와 육지로 돌아와요'),
  ],
  '해와 달': [
    Scene('🐯', '호랑이의 위협', '호랑이가 떡을 빼앗으며 엄마를 잡아먹어요'),
    Scene('🚪', '문 열어 주세요', '호랑이가 엄마 목소리를 흉내 내요'),
    Scene('🌳', '나무 위로 도망', '오누이가 나무 위로 올라가 도움을 빌어요'),
    Scene('🌞', '해와 달이 되다', '하늘이 내린 동아줄로 올라가 해와 달이 돼요'),
  ],
};
