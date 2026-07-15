import 'dart:convert';
import 'dart:ui';

import '../state/create_main_state.dart'
    show
        CreateMode,
        gServerBookCovers,
        gServerBookIdToTitle,
        kBooks,
        normalizeLevelLabel;

/// 데모용 샘플 데이터 모음.
/// 서버/SQLite 연동 전까지 결과 화면·내 서재가 사용하는 정적 데이터.
/// (디자인 프로토타입 `창작 결과물 화면.html` 의 SCRIPT/VOCAB 과 동일)

// ── 대본 한 줄 ─────────────────────────────────────────

/// 대본 한 줄. [char] 가 null 이면 내레이션.
class ScriptLine {
  const ScriptLine({
    required this.id,
    required this.scene,
    this.char,
    this.mood,
    required this.text,
  });

  final int id;
  final int scene;
  final String? char; // 화자 (null = 내레이션)
  final String? mood; // 지문 (예: '환히 웃으며')
  final String text;

  bool get isNarration => char == null;

  ScriptLine copyWith({String? text}) =>
      ScriptLine(id: id, scene: scene, char: char, mood: mood, text: text ?? this.text);

  /// JSON/맵 직렬화 (로컬 DB 저장·서버 응답 파싱 공용).
  /// 키 이름은 서버 계약(POST /generate 의 lines 항목)과 동일하게 맞춘다.
  Map<String, dynamic> toMap() => {
        'id': id,
        'scene': scene,
        'char': char,
        'mood': mood,
        'text': text,
      };

  factory ScriptLine.fromMap(Map<String, dynamic> m) => ScriptLine(
        id: (m['id'] as num).toInt(),
        scene: (m['scene'] as num?)?.toInt() ?? 1,
        char: m['char'] as String?,
        mood: m['mood'] as String?,
        text: (m['text'] as String?) ?? '',
      );

  /// 대본 줄 목록 ↔ JSON 문자열 (works 테이블의 lines 컬럼용).
  static String encodeList(List<ScriptLine> lines) =>
      jsonEncode([for (final l in lines) l.toMap()]);

  static List<ScriptLine> decodeList(String? json) {
    if (json == null || json.isEmpty) return const [];
    final list = jsonDecode(json) as List<dynamic>;
    return [for (final e in list) ScriptLine.fromMap(e as Map<String, dynamic>)];
  }
}

/// 장면 번호 → 장면 제목.
const Map<int, String> kSceneNames = {1: '봄날 마당', 2: '박씨를 받다'};

/// 쉬운말 버전 대본 (오디오극·역할 읽기 탭에서 사용).
const List<ScriptLine> kScriptEasy = [
  ScriptLine(id: 0, scene: 1, text: '봄날, 흥부네 마당에 제비 한 마리가 날아들었다. 작년에 발을 고쳐준 바로 그 제비였다.'),
  ScriptLine(id: 1, scene: 1, char: '제비', mood: '날개를 퍼덕이며', text: '흥부 님, 작년에 제 발을 고쳐주셔서 정말 감사해요. 이걸 드리고 싶었어요.'),
  ScriptLine(id: 2, scene: 1, char: '흥부', mood: '손사래 치며', text: '에고, 별말씀을요. 그냥 발을 싸매 드린 것뿐인걸요.'),
  ScriptLine(id: 3, scene: 1, char: '흥부 아내', mood: '걱정하며', text: '여보, 설마 또 박씨를 주는 건 아니겠죠? 지난번엔 요괴가 나왔잖아요.'),
  ScriptLine(id: 4, scene: 1, char: '흥부', mood: '환히 웃으며', text: '하하! 이번엔 우리가 잘 나누어 쓰면 되잖아요, 여보!'),
  ScriptLine(id: 5, scene: 2, text: '제비는 박씨 하나를 마당에 떨어뜨리고 하늘 높이 날아올랐다.'),
  ScriptLine(id: 6, scene: 2, char: '흥부 아내', mood: '신기한 듯', text: '어머, 이 박씨는 뭔가 달라요. 빛이 나는 것 같아요.'),
  ScriptLine(id: 7, scene: 2, char: '흥부', mood: '무릎 꿇으며', text: '잘 심어볼게요. 우리 아이들과 함께 가꿔 나가면 좋겠어요.'),
];

/// 고전의 결 살리기 버전 대본 (대사극 대본 탭에서 사용).
const List<ScriptLine> kScriptClassical = [
  ScriptLine(id: 0, scene: 1, text: '봄볕이 완연한 흥부의 뜰에 제비 한 마리가 날아들었으니, 지난해 부러진 다리를 고쳐 주었던 바로 그 제비였더라.'),
  ScriptLine(id: 1, scene: 1, char: '제비', mood: '날개를 가다듬으며', text: '소인이 황공하옵게도 흥부 나리의 은혜를 입었사오니, 이 박씨 하나로 보답하고자 하옵니다.'),
  ScriptLine(id: 2, scene: 1, char: '흥부', mood: '손을 내저으며', text: '허허, 별것 아니었소. 다리가 성한 것이 다행이오.'),
  ScriptLine(id: 3, scene: 1, char: '흥부 아내', mood: '근심스러운 낯빛으로', text: '여보, 설마 또 박씨를 주는 것이오? 지난번에는 요물이 나와 크게 낭패를 봤잖소.'),
  ScriptLine(id: 4, scene: 1, char: '흥부', mood: '밝게 웃으며', text: '하하! 이번에는 분수에 맞게 나누어 쓰면 될 것이오, 여보!'),
  ScriptLine(id: 5, scene: 2, text: '제비는 박씨 하나를 뜰에 떨어뜨리고 하늘 높이 날아올랐다.'),
  ScriptLine(id: 6, scene: 2, char: '흥부 아내', mood: '신기한 눈빛으로', text: '어머, 이 박씨는 예사롭지 않아요. 빛이 나는 것 같소이다.'),
  ScriptLine(id: 7, scene: 2, char: '흥부', mood: '무릎 꿇으며', text: '정성껏 심어보겠소. 우리 아이들과 함께 가꿔 나가면 좋겠소.'),
];

// ── 어휘 풀이 ─────────────────────────────────────────

class VocabEntry {
  const VocabEntry({this.hanja, required this.meaning, this.note});
  final String? hanja;
  final String meaning;
  final String? note;

  /// 서버 POST /vocab 응답 → 모델. ({hanja?, meaning, note?})
  factory VocabEntry.fromMap(Map<String, dynamic> m) => VocabEntry(
        hanja: m['hanja'] as String?,
        meaning: (m['meaning'] as String?) ?? '',
        note: m['note'] as String?,
      );

  /// 로컬 DB 저장용 직렬화.
  Map<String, dynamic> toMap() => {
        if (hanja != null) 'hanja': hanja,
        'meaning': meaning,
        if (note != null) 'note': note,
      };
}

/// 어려운 단어 사전 (고전의 결 살리기 수준).
const Map<String, VocabEntry> kVocab = {
  '완연한': VocabEntry(hanja: '宛然', meaning: '봄기운이 뚜렷하고 분명하게 드러나 있는 모습이에요.'),
  '소인': VocabEntry(hanja: '小人', meaning: '신분이 낮은 사람이 자기 자신을 낮추어 이르던 말이에요.', note: '현대어로는 "저"에 해당해요.'),
  '황공하옵게도': VocabEntry(hanja: '惶恐', meaning: '두렵고 황송하게도. 은혜를 입어 몸 둘 바를 모를 때 쓰는 표현이에요.'),
  '나리': VocabEntry(meaning: '지체 높은 사람을 높여 이르던 말이에요.', note: '현대어로는 "어르신" 정도에 해당해요.'),
  '은혜': VocabEntry(hanja: '恩惠', meaning: '베풀어 준 혜택이나 고마운 도움을 말해요.'),
  '박씨': VocabEntry(meaning: '박의 씨앗이에요. 이 이야기에서는 제비가 은혜 갚음으로 가져다줘요.', note: '흥부전에서 복의 상징으로 등장해요.'),
  '보답': VocabEntry(hanja: '報答', meaning: '받은 은혜나 도움을 갚는 것을 말해요.'),
  '낭패': VocabEntry(hanja: '狼狽', meaning: '일이 뜻대로 되지 않아 어찌할 바를 모르는 딱한 상황이에요.'),
  '분수': VocabEntry(hanja: '分數', meaning: '자기 처지와 형편에 알맞은 한도를 말해요.', note: '"분수에 맞게"는 자기 형편에 걸맞게 행동한다는 뜻이에요.'),
  '요물': VocabEntry(hanja: '妖物', meaning: '요사스럽고 이상한 물건이나 존재를 가리켜요.'),
  '예사롭지': VocabEntry(meaning: '보통과 같지 않고 특별한 데가 있는 모습이에요.'),
};

// ── 오디오극 웨이브폼 ──────────────────────────────────

/// 웨이브폼 막대 높이 샘플 (디자인 프로토타입과 동일).
const List<int> kWaveHeights = [
  3, 5, 8, 10, 7, 9, 12, 8, 5, 10, 14, 9, 7, 11, 10, 8, 5, 9, 13, 10,
  7, 9, 8, 11, 13, 9, 7, 5, 8, 11, 13, 9, 7, 8, 10, 12, 9, 7, 5, 6,
];

// ── 원작별 보조 데이터 ─────────────────────────────────

/// 원작 키 정규화. 창작물 결과(`result.data`)는 제목 없이 `bookId`(슬러그)만 줘서
/// `work.source` 가 슬러그로 저장될 수 있다. 슬러그면 서버 레지스트리로 제목을 찾아 돌려준다
/// (이미 제목이거나 미지의 값이면 그대로). 표지/색/이모지 레지스트리는 모두 제목으로 키가 잡힌다.
String _bookKey(String source) => gServerBookCovers.containsKey(source)
    ? source
    : (gServerBookIdToTitle[source] ?? source);

/// bookId(슬러그) 또는 제목을 서재/표지가 쓰는 원작 제목 키로 정규화한다(외부용).
/// 창작물 어댑터가 `source` 를 제목으로 통일해 저장하도록 쓴다.
String resolveBookKey(String source) => _bookKey(source);

/// 원작 제목(또는 bookId) → 표지 색. 서버 레지스트리 우선, 없으면 kBooks, 그래도 없으면 src 톤.
Color bookColor(String title) {
  final key = _bookKey(title);
  final s = gServerBookCovers[key];
  if (s != null) return s.color;
  for (final b in kBooks) {
    if (b.title == key) return b.color;
  }
  return const Color(0xFFA07860);
}

/// 원작 제목(또는 bookId) → 표지 이모지. 서버 레지스트리 우선.
String bookEmoji(String title) {
  final key = _bookKey(title);
  final s = gServerBookCovers[key];
  if (s != null && s.icon.isNotEmpty) return s.icon;
  for (final b in kBooks) {
    if (b.title == key) return b.icon;
  }
  return '📖';
}

/// 표지 에셋이 있는 원작 슬러그. 파일명은 `assets/images/<슬러그>.webp` 로 슬러그와 1:1.
/// (백엔드 bookId·[_kBookSlug] 값과 동일.)
const Set<String> _kCoverSlugs = {
  'hongbu_jeon',
  'bakssi_jeon',
  'kongjwi_patjwi_jeon',
  'heosaeng_jeon',
  'hong_gildong_jeon',
  'tokki_jeon',
};

/// 원작 제목/슬러그(또는 work.source) → 백엔드 슬러그. 표지 에셋을 슬러그로 찾기 위한 정규화.
/// 서버 레지스트리(동기화 시) 우선, 없으면 앱 표시명 정적 매핑([_kBookSlug])으로 폴백.
String? _coverSlugFor(String source) {
  // 이미 슬러그면 그대로 사용.
  if (gServerBookIdToTitle.containsKey(source) ||
      _kBookSlug.containsValue(source)) {
    return source;
  }
  // 서버 제목(흥부전·콩쥐팥쥐전 등) → 슬러그(슬러그→제목 레지스트리 역인덱스).
  for (final e in gServerBookIdToTitle.entries) {
    if (e.value == source) return e.key;
  }
  // 앱 표시명(흥부와 놀부 등) → 슬러그(서버 미동기화 폴백).
  return _kBookSlug[source];
}

/// 원작 제목(또는 bookId) → 표지 이미지. 번들 에셋(assets/images/<슬러그>.webp) 우선,
/// 없으면 서버 coverImageUrl, 그래도 없으면 kBooks 폴백. 모두 없으면 null.
String? bookImage(String title) {
  final slug = _coverSlugFor(title);
  if (slug != null && _kCoverSlugs.contains(slug)) {
    return 'assets/images/$slug.webp'; // 원작 커버는 번들 에셋 우선
  }
  final key = _bookKey(title);
  final s = gServerBookCovers[key];
  if (s != null) return s.image;
  for (final b in kBooks) {
    if (b.title == key) return b.image;
  }
  return null;
}

/// 원작 제목 → 원작 본문 txt 파일명 (assets/data/0_original/ 내부).
const Map<String, String> _kOriginalFile = {
  '흥부와 놀부': 'heungbu-nolbu.txt',
  '박씨전': 'bakssi-jeon.txt',
  '콩쥐팥쥐': 'Kongjwi-Patjwi-jeon.txt',
  '허생전': 'heosaeng-jeon.txt',
  '홍길동전': 'hong-gildong-jeon.txt',
  '토끼전': 'tokki-jeon.txt',
};

/// 원작 제목 → 백엔드 책 슬러그(언더스코어). GET /books/{id}/original 등 서버 호출용.
/// 백엔드 app/data/<슬러그>/ 폴더명과 정확히 일치해야 한다(하이픈 아님).
const Map<String, String> _kBookSlug = {
  '흥부와 놀부': 'hongbu_jeon',
  '박씨전': 'bakssi_jeon',
  '콩쥐팥쥐': 'kongjwi_patjwi_jeon',
  '허생전': 'heosaeng_jeon',
  '홍길동전': 'hong_gildong_jeon',
  '토끼전': 'tokki_jeon',
};

/// 원작 제목 → 백엔드 슬러그. 백엔드에 없는 원작은 null.
String? bookSlug(String title) => _kBookSlug[title];

/// 원작 제목 → 본문 텍스트 에셋 경로. 없으면 null.
String? bookText(String title) {
  final file = _kOriginalFile[title];
  return file == null ? null : 'assets/data/0_original/$file';
}

/// 생성 중 화면에 보여줄 작업 제목(원작별 샘플).
const Map<String, String> kWorkingTitles = {
  '흥부와 놀부': '흥부의 두 번째 박',
  '콩쥐팥쥐': '콩쥐의 새로운 친구',
  '허생전': '허생의 새로운 장사',
  '홍길동전': '홍길동의 새 약속',
  '토끼전': '토끼가 용궁에서 한 약속',
  '해와 달': '오누이의 새 아침',
};

/// 생성 중 화면 하단 '잠깐 읽어봐요' 원작 소개.
const Map<String, String> kBookTips = {
  '흥부와 놀부': '흥부와 놀부는 조선 시대를 대표하는 구비 설화예요. 착한 동생 흥부가 다친 제비를 도와주고 복을 받는 이야기로, 나눔과 욕심에 대한 교훈을 담고 있어요.',
  '콩쥐팥쥐': '콩쥐팥쥐는 착한 콩쥐가 어려움을 이겨내고 행복을 찾는 설화예요. 동물 친구들의 도움과 꽃신 한 짝이 만들어내는 따뜻한 이야기가 담겨 있어요.',
  '심청전': '심청전은 아버지의 눈을 뜨게 하려고 인당수에 몸을 던진 심청의 이야기예요. 효와 희생, 그리고 기적 같은 재회가 감동을 줘요.',
  '춘향전': '춘향전은 신분을 뛰어넘은 춘향과 몽룡의 사랑 이야기예요. 인물들의 생생한 대사가 풍부해서 대사극으로 만들기 좋아요.',
  '토끼전': '토끼전은 꾀 많은 토끼가 용궁에서 지혜로 위기를 벗어나는 우화예요. 재치 있는 대화가 많아 오디오극으로 듣기 좋아요.',
};

/// 원작 주요 인물 (원작 페이지에 표시).
const Map<String, List<String>> kBookCharacters = {
  '흥부와 놀부': ['흥부', '놀부', '제비', '흥부 아내'],
  '박씨전': ['박씨 부인', '이시백', '시아버지'],
  '콩쥐팥쥐': ['콩쥐', '팥쥐', '팥쥐 엄마', '원님'],
  '허생전': ['허생', '허생 아내', '변씨'],
  '홍길동전': ['홍길동', '홍 판서', '활빈당'],
  '토끼전': ['토끼', '자라', '용왕'],
};

// ── 내 서재 샘플 창작물 ────────────────────────────────

/// 사용자가 만든 창작물 (로컬 저장 가정).
class CreativeWork {
  const CreativeWork({
    required this.id,
    required this.title,
    required this.source,
    required this.mode,
    required this.level,
    required this.desc,
    required this.updatedAt,
    this.creationCoverImageUrl,
    this.creationCoverEmoji,
    this.creationCoverLocalPath,
    this.coverLocalAbsPath,
  });

  final String id;
  final String title;
  final String source; // 원작 제목
  final CreateMode mode;
  final String level;
  final String desc; // 짧은 설명
  final DateTime updatedAt;

  /// 창작물 대표 이미지(서버 URL 또는 앱 문서 폴더에 캐시한 로컬 파일 경로).
  /// 원작 표지(`source.coverImageUrl`)와 별개다 — 창작물 카드/서재/결과 화면 썸네일 전용.
  final String? creationCoverImageUrl;

  /// 창작물 대표 이미지가 없을 때 쓰는 대표 이모티콘(`data.creationCoverEmoji`).
  final String? creationCoverEmoji;

  /// 오프라인 캐시: 디스크(cover_cache)에 받아 둔 표지 이미지 **파일명**(절대경로 아님).
  /// 없으면 아직 미다운로드. 실제 파일은 [CoverCacheStore] 가 앱 지원 폴더에 두고
  /// 여기엔 파일명만 보관한다(SQLite `works.creation_cover_local_path`).
  final String? creationCoverLocalPath;

  /// 런타임에 [creationCoverLocalPath] 를 해석한 캐시 파일 **절대 경로**(있을 때만).
  /// DB 에 저장하지 않는 일시 값 — 서재 로드 시 채운다. [coverDisplayPath] 가 이걸 우선한다.
  final String? coverLocalAbsPath;

  /// 창작물 썸네일에 쓸 대표 이모지. 이미지가 없을 때의 폴백.
  /// 우선순위: [creationCoverEmoji] → 기본 '🎭' (원작 이모지로 폴백하지 않는다).
  String get coverEmoji => (creationCoverEmoji?.isNotEmpty ?? false)
      ? creationCoverEmoji!
      : '🎭';

  /// 표지로 그릴 경로(우선순위):
  /// ① 다운로드된 AI 표지(오프라인 캐시 절대경로) → ② 서버 생성 표지 URL
  /// ([creationCoverImageUrl]) → ③ null → 호출부가 이모지/책색으로 폴백.
  ///
  /// 원작 대표 커버([bookImage])는 원작 페이지나 사용자가 직접 고른 표지에서만 쓴다.
  /// 창작물 썸네일이 원작 표지로 되돌아가면 `creationCoverImageUrl` 과
  /// `source.coverImageUrl` 의 책임 경계가 다시 섞인다.
  /// (`Image.network` ↔ `Image.asset` ↔ `Image.file` 분기는 netOrAssetCover 가 경로 형태로 판단)
  String? get coverDisplayPath => coverLocalAbsPath ?? creationCoverImageUrl;

  CreativeWork copyWith({
    String? title,
    String? desc,
    DateTime? updatedAt,
    String? creationCoverImageUrl,
    String? creationCoverLocalPath,
    String? coverLocalAbsPath,
  }) =>
      CreativeWork(
        id: id,
        title: title ?? this.title,
        source: source,
        mode: mode,
        level: level,
        desc: desc ?? this.desc,
        updatedAt: updatedAt ?? this.updatedAt,
        creationCoverImageUrl:
            creationCoverImageUrl ?? this.creationCoverImageUrl,
        creationCoverEmoji: creationCoverEmoji,
        creationCoverLocalPath:
            creationCoverLocalPath ?? this.creationCoverLocalPath,
        coverLocalAbsPath: coverLocalAbsPath ?? this.coverLocalAbsPath,
      );

  /// 로컬 DB(works 테이블) 행 ↔ 모델.
  /// mode 는 enum 이름(name)으로, updatedAt 은 epoch millis 로 저장한다.
  Map<String, Object?> toRow() => {
        'id': id,
        'title': title,
        'source': source,
        'mode': mode.name,
        'level': level,
        'description': desc,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'creation_cover_image_url': creationCoverImageUrl,
        'creation_cover_emoji': creationCoverEmoji,
        'creation_cover_local_path': creationCoverLocalPath,
      };

  factory CreativeWork.fromRow(Map<String, Object?> r) => CreativeWork(
        id: r['id'] as String,
        title: (r['title'] as String?) ?? '',
        source: (r['source'] as String?) ?? '',
        mode: createModeFromName(r['mode'] as String?),
        level: normalizeLevelLabel((r['level'] as String?) ?? ''),
        desc: (r['description'] as String?) ?? '',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            (r['updated_at'] as num?)?.toInt() ?? 0),
        creationCoverImageUrl: r['creation_cover_image_url'] as String?,
        creationCoverEmoji: r['creation_cover_emoji'] as String?,
        creationCoverLocalPath: r['creation_cover_local_path'] as String?,
      );
}

/// 문자열 → CreateMode (저장값/서버값 파싱). 알 수 없으면 대사극.
CreateMode createModeFromName(String? name) {
  switch (name) {
    case 'audio':
      return CreateMode.audio;
    case 'dialogue':
    default:
      return CreateMode.dialogue;
  }
}

/// 내 서재 데모 데이터. (DateTime 은 const 불가 → final)
final List<CreativeWork> kSampleWorks = [
  CreativeWork(
    id: 'w1',
    title: '흥부의 두 번째 박',
    source: '흥부와 놀부',
    mode: CreateMode.dialogue,
    level: '청소년용',
    desc: '제비가 다시 찾아와 건넨 두 번째 박씨. 이번에는 가족이 함께 나누는 법을 배워요.',
    updatedAt: DateTime(2026, 6, 10),
  ),
  CreativeWork(
    id: 'w2',
    title: '제비의 보은',
    source: '흥부와 놀부',
    mode: CreateMode.audio,
    level: '동화책 수준',
    desc: '제비의 눈으로 다시 본 흥부네 이야기를 목소리로 들어요.',
    updatedAt: DateTime(2026, 6, 8),
  ),
  CreativeWork(
    id: 'w3',
    title: '놀부의 반성문',
    source: '흥부와 놀부',
    mode: CreateMode.dialogue,
    level: '고전의 결 살리기',
    desc: '벌을 받은 놀부가 동생에게 쓴 편지에서 시작되는 화해의 장면.',
    updatedAt: DateTime(2026, 5, 30),
  ),
  CreativeWork(
    id: 'w4',
    title: '박씨 부인의 비밀',
    source: '박씨전',
    mode: CreateMode.dialogue,
    level: '청소년용',
    desc: '허물을 벗기 전 박씨 부인이 남편에게 건넨 진심 어린 한마디.',
    updatedAt: DateTime(2026, 6, 14),
  ),
  CreativeWork(
    id: 'w5',
    title: '콩쥐의 새로운 친구',
    source: '콩쥐팥쥐',
    mode: CreateMode.dialogue,
    level: '청소년용',
    desc: '혼자 울지 않기로 한 콩쥐가 친구를 부르며 달라지는 이야기.',
    updatedAt: DateTime(2026, 6, 5),
  ),
  CreativeWork(
    id: 'w6',
    title: '허생의 새로운 장사',
    source: '허생전',
    mode: CreateMode.audio,
    level: '청소년용',
    desc: '빈 섬에서 돌아온 허생이 들려주는 또 하나의 장사 이야기.',
    updatedAt: DateTime(2026, 6, 12),
  ),
  CreativeWork(
    id: 'w7',
    title: '홍길동의 새 약속',
    source: '홍길동전',
    mode: CreateMode.dialogue,
    level: '고전의 결 살리기',
    desc: '율도국의 왕이 된 홍길동이 백성에게 건네는 새로운 약속.',
    updatedAt: DateTime(2026, 6, 16),
  ),
  CreativeWork(
    id: 'w8',
    title: '토끼가 용궁에서 한 약속',
    source: '토끼전',
    mode: CreateMode.audio,
    level: '동화책 수준',
    desc: '용왕에게 다른 해결책을 제안한 토끼의 기지 넘치는 하루.',
    updatedAt: DateTime(2026, 6, 2),
  ),
];

/// '2026.06.10' 형식 날짜 문자열. (intl 미사용)
String formatDate(DateTime d) =>
    '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
