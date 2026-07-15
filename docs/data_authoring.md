# 정적 데이터 작성 가이드 — `assets/data`

> 앱의 **원작 카탈로그**와 **원문(원본 보기/원문 기반 결과 화면)** 은 모두 `assets/data` 의
> 정적 JSON 에서 온다. 이 문서는 **새 원작을 추가하거나 기존 데이터를 고칠 때의 형식과 절차**를
> 정의한다. 여기 규칙만 지키면 코드를 고치지 않고도 책이 자동으로 늘어난다.
>
> 관련 코드: `lib/services/book_catalog.dart`(목록), `lib/services/original_loader.dart`(원문→화면),
> `lib/models/book_meta.dart`, `lib/models/creation_result.dart`. Last updated: 2026-06-23.

---

## 1. 폴더 구조

```
assets/data/
  book_list.json                 # 원작 카탈로그(목록/메타) — 단일 출처
  <bookId>/                      # 원작 1권 (폴더명 = bookId, 언더스코어)
    meta.json                    # 작품 메타 + 인물 소개
    script.json                  # 전체 스크립트(원문 전체)
    script_summary.json          # 핵심 장면 압축본
    voice_profiles.json          # 화자별 음성 프로필(TTS)
```

- `<bookId>` 는 **언더스코어** 슬러그(`hongbu_jeon`). 폴더명 = 파일들의 `bookId` 와 동일해야 한다.
- 예: `assets/data/hongbu_jeon/script.json`

---

## 2. 새 원작 추가 절차 (체크리스트)

1. `assets/data/<bookId>/` 폴더를 만들고 4개 JSON(`meta`, `script`, `script_summary`,
   `voice_profiles`)을 넣는다. (§4 형식)
2. `assets/data/book_list.json` 의 `books` 배열에 항목 1개를 추가한다. (§3)
   - **`apiBookId` 를 반드시 적는다** — 백엔드 `/create` 슬러그는 폴더명과 다를 수 있다(예: 폴더
     `hongbu_jeon` ↔ API `heungbu-nolbu`).
3. `pubspec.yaml` 의 `flutter > assets` 에 폴더를 등록한다. (Flutter 는 하위 폴더를 자동 포함하지
   않으므로 **반드시** 줄을 추가)
   ```yaml
   flutter:
     assets:
       - assets/data/book_list.json
       - assets/data/<bookId>/
   ```
4. `flutter pub get` 후 앱을 재시작한다. 창작/내 서재/원본 보기에 새 책이 자동으로 나타난다.

> 코드 수정은 필요 없다. 목록은 `book_list.json`, 원문은 폴더의 JSON 에서 런타임 로드된다.

---

## 3. `book_list.json` 항목 스키마

```jsonc
{
  "bookId": "hongbu_jeon",          // (필수) 에셋 폴더명(언더스코어)
  "apiBookId": "heungbu-nolbu",     // (필수) 백엔드 /create 슬러그(하이픈). 폴더명과 달라도 됨
  "title": "흥부전",                  // (필수) 화면에 보일 한글 제목
  "emoji": "🐦",                      // (권장) 표지 이모지. 없으면 📖
  "coverColor": "#E8A838",           // (권장) 표지 색 "#RRGGBB". 없으면 기본 소스색
  "author": "작자 미상",              // (선택) 원본 보기 부제에 표시
  "era": "조선 후기",                 // (선택)
  "tags": ["권선징악", "형제"],        // (선택) 결과 화면 '원작 정보' 칩
  "difficulty": "초급",               // (선택) 원본 난이도 라벨(표시용)
  "shortDescription": "착한 흥부와 …"  // (선택) 원본 보기 소개 / 결과 '한눈에 보기'
}
```

- 백엔드 슬러그는 언더스코어로 폴더명과 동일하다(`bakssi_jeon`, `hongbu_jeon` …). `apiBookId` 를
  생략하면 폴더명을 그대로 슬러그로 쓰며, 폴더명과 다른 슬러그가 필요할 때만 `apiBookId` 를 명시한다.
- `title` 은 앱 전역의 식별 키다(내 서재 그룹핑, `kSampleWorks.source` 등). 카탈로그와 다른 제목을
  코드에 하드코딩하지 말 것.

---

## 4. 원작 폴더 JSON 스키마

### 4-1. `meta.json`
```jsonc
{
  "bookId": "hongbu_jeon",
  "title": "흥부전",
  "author": "작자 미상", "era": "조선 후기", "genre": "판소리계 소설",
  "difficulty": "초급", "tags": ["권선징악", "형제"],
  "coverColor": "#E8A838",
  "shortDescription": "…",
  "characters": [
    { "name": "흥부", "role": "주인공", "description": "마음씨 착한 동생…" }
  ]
}
```
> 현재 앱의 인물/색은 **script + voice_profiles 기준**으로 만든다(§5). `meta.characters` 의 이름엔
> 공백이 있을 수 있으나(`흥부 아내`), script/voice 의 화자 키는 무공백(`흥부아내`)일 수 있다 —
> **이름 표기는 voice_profiles 의 `displayName` 을 정본으로** 쓴다.

### 4-2. `script.json` (전체 원문) / `script_summary.json` (요약)
```jsonc
{
  "bookId": "hongbu_jeon",
  "title": "흥부전 대화극",
  "totalDurationMs": 1156160,
  "speedOptions": [0.8, 1.0, 1.2],
  "defaultSpeed": 1.0,
  "seekStepMs": 10000,
  "chapters": [
    { "label": "심술쟁이 놀부와 착한 흥부", "startSegmentId": "seg_001" }
  ],
  "segments": [
    {
      "id": "seg_001",            // (필수) 고유 id
      "order": 1,                 // (필수) 재생/정렬 순서
      "speaker": "narrator",      // (필수) 'narrator' = 내레이션, 그 외 = 인물 화자 키
      "type": "narration",        // narration | dialogue
      "text": "형제는 오륜의 하나요…", // (필수) 본문
      "pauseAfterMs": 500,        // (선택) 재생용
      "estimatedDurationMs": 8560 // (선택) 재생용
    }
  ]
}
```
- 두 파일은 **동일 스키마**다. 앱에서 `script.json` = 전체, `script_summary.json` = 요약으로 쓴다.
- `chapters[].startSegmentId` 는 `segments[].id` 중 하나여야 한다. 챕터가 곧 **장면**으로 매핑된다
  (어떤 챕터의 시작 id 부터 다음 챕터 시작 직전까지가 한 장면).
- `segments[].id` 는 파일 내 **유일**, `order` 는 **반드시** 존재.

### 4-3. `voice_profiles.json`
```jsonc
{
  "bookId": "hongbu_jeon",
  "voices": {
    "narrator": { "voiceId": "ko-KR-default", "displayName": "내레이터",
                  "locale": "ko-KR", "rate": 0.95, "pitch": 1.0, "volume": 1.0, "gender": "neutral" },
    "흥부":     { "voiceId": "male_ko_01", "displayName": "흥부",
                  "locale": "ko-KR", "rate": 0.97, "pitch": 1.0, "volume": 1.0, "gender": "male" }
  }
}
```
- **`script.json` 에 등장하는 모든 `speaker` 는 `voices` 에 키가 있어야 한다**(`narrator` 포함).
- 오디오극 TTS 는 줄별로 `rate`(배속 기준), `pitch`(0.5~2.0), `locale`(lang)을 적용한다.
  `voiceId`/`gender` 는 향후 음성 매핑용 메타로 둔다(현재 flutter_tts 는 locale+rate+pitch 사용).

---

## 5. 앱이 데이터를 쓰는 방식 (요약)

| 화면/기능 | 사용 파일 | 비고 |
|---|---|---|
| 원작 목록(창작/서재/원본보기) | `book_list.json` | `BookCatalog` 가 1회 로드, 동기 조회 |
| 원본 보기 소개 + 장면 목록 | `book_list.json` + `script.json.chapters` | 챕터 = 장면 |
| 원본 보기 → 대사극/오디오극 버튼 | `script.json`(+`voice_profiles.json`) | 백엔드 호출 없이 원문 전체를 결과 화면으로 렌더 |
| 장면별 창작(`scope=scene`) | `script.json.chapters/segments` | 선택 챕터 segments 를 `/create` 의 `sceneSelection` 으로 전송 |
| 오디오극 음성 | `voice_profiles.json` | 줄별 rate/pitch/locale → flutter_tts |

- 원문 → 화면 변환은 `OriginalLoader.loadOriginal()` 이 `script.json`+`voice_profiles.json` 을
  `CreationResult`(결과 화면 공통 모델)로 만든다. 인물 = narrator 제외 화자 등장순.

---

## 6. 자주 하는 실수

- ❌ `pubspec.yaml` 에 폴더 등록을 빠뜨림 → 런타임에 에셋 로드 실패(원문이 안 열림).
- ❌ `apiBookId` 누락/오타 → 창작(`/create`)이 404/422.
- ❌ `script.json` 의 `speaker` 가 `voice_profiles` 에 없음 → 오디오극에서 그 줄이 기본 음성으로 재생.
- ❌ `chapters[].startSegmentId` 가 실제 `segments` 에 없음 → 해당 장면이 비거나 어긋남.
- ❌ `book_list.json` 의 `title` 과 코드/샘플의 제목 불일치 → 내 서재 그룹/원문 연동이 끊김.
