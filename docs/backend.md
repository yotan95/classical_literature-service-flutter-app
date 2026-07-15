# Backend Integration — 창작하기 API (FastAPI)

> Owned by this doc: how the app talks to the FastAPI backend — endpoints, `/create`
> request·SSE·result schema, enum maps, the create flow, and the models/services that implement it.
> The **authoritative contract is the backend's `API.md`**; keep enum strings identical to it. Update
> this doc when the flutter-side wiring changes (and append `docs/CHANGELOG.md`).

창작하기 is **not** generated on-device. A separate FastAPI backend (repo `classic_literature_fastAPI`)
loads the original literature, builds a prompt (original + options), calls the
Claude API, and refines the output into mode-specific JSON. The app's job: **collect options → call
`/create` → render → store as JSON in `created_data/`** (see `docs/storage.md`).

## Status — create flow wired (2026-06-22)
- The Create button builds a `CreateRequest`; `ai_generating_screen` consumes the `/create` SSE via
  `CreateApi`, advances the stage animation, and on `result` saves to `created_data/` then pushes the
  result screen.
- **`AppConfig.useMock` now defaults to `false`** (hits the real backend). Pass
  `--dart-define=USE_MOCK=true` to run the flow end-to-end **without a server** (canned SSE → a minimal
  result). See "Config" below for `--dart-define` env switching.
- **Pending:** result screens still render `sample_data.dart`; mapping the backend `result.data` into
  them (and typing it via `creation_result.dart`) is the next step.

## Config (`lib/core/app_config.dart`)
- `AppConfig`, exposed via `appConfigProvider`, is the **only** place the host/switches live; services
  and widgets read it, never literals. The Dio client (`ApiClient`, used by 줄 단위 AI 수정 `rewriteLine`)
  also takes its base URL from here via `apiClientProvider` — there is **no separate `ApiConfig`** anymore
  (host 단일 출처, env var 도 `BASE_URL` 하나).
- Both switches are injected via **`--dart-define`** (don't edit code per environment):
  - `AppConfig.baseUrl` — `String.fromEnvironment('BASE_URL', default 'https://api.rasponline.xyz')`.
    **Never hardcode the host/IP.** 기본값은 배포 서버 — 로컬 개발 서버로 붙으려면 아래처럼 override 한다:

    | Flutter runs on | `BASE_URL` |
    |---|---|
    | Deploy (default, 미주입 시) | `https://api.rasponline.xyz` |
    | iOS sim / macOS / Chrome + 로컬 서버 | `http://localhost:8000` |
    | Android emulator + 로컬 서버 | `http://10.0.2.2:8000` (`localhost` = the emulator itself) |
    | Real device (same WiFi) + 로컬 서버 | `http://<Mac LAN IP>:8000` (`ipconfig getifaddr en0`) |
  - `AppConfig.useMock` — `bool.fromEnvironment('USE_MOCK', default false)`. **Default is now `false`**
    (real server). Pass `--dart-define=USE_MOCK=true` to replay canned SSE without a server.
- Run examples:
  ```bash
  flutter run --dart-define=BASE_URL=http://10.0.2.2:8000      # Android emulator → local FastAPI
  flutter run --dart-define=BASE_URL=http://192.168.0.50:8000  # Raspberry Pi
  flutter run --dart-define=USE_MOCK=true                      # UI-only, no server
  ```
- **Cleartext (`http`) is allowed for local/private networks only**, not the public internet:
  - iOS — `ios/Runner/Info.plist`: `NSAppTransportSecurity → NSAllowsLocalNetworking` (covers
    localhost / 192.168.x / 10.x automatically).
  - Android — `android/app/src/main/res/xml/network_security_config.xml` (referenced from
    `AndroidManifest.xml`): cleartext permitted only for listed domains (localhost, 127.0.0.1,
    10.0.2.2, 10.0.3.2). **Add the real Mac LAN IP / Raspberry Pi IP there** for real-device/deploy
    builds — Android can't auto-allow a private range the way iOS does. `INTERNET` permission is in the
    main manifest (release builds need it too).
- No auth headers; bodies are `application/json`. 클라이언트는 `X-API-Key` 등 인증 헤더를 보내지 않는다
  (과거 `ApiConfig.apiKey` 는 미사용이라 호스트 통합 시 제거). 서버는 `ANTHROPIC_API_KEY` 를 자기 `.env`
  에서 읽으며, 없으면 `/create` 가 진행 중 `error` 이벤트를 흘린다.

## Endpoints (see `API.md`)
| Method | Path | Use in app | Response |
|---|---|---|---|
| GET | `/health` | connectivity / ready check | `{status, model}` |
| GET | `/books` | book list for the 창작하기 picker | `{ books: [...] }` |
| GET | `/books/{bookId}` | scenes/characters for scene-selection | `BookDetail` |
| POST | `/create` | run creation + stream progress | **SSE** (`text/event-stream`) |

## Books & the slug mapping (2026-06-23: catalog-driven)
원작 목록은 **`assets/data/book_list.json` 단일 출처**다. `BookCatalog`(`lib/services/book_catalog.dart`)
가 `main()` 에서 1회 로드해 동기 조회한다. 6권: 허생전 · 흥부전 · 홍길동전 · 박씨전 · 콩쥐팥쥐전 ·
토끼전. 책을 추가/수정하는 규칙은 **`docs/data_authoring.md`** 참조(코드 수정 불필요).
- `BookMeta` 는 `bookId`(에셋 폴더, 언더스코어)와 `apiBookId`(백엔드 슬러그, 하이픈)를 **둘 다** 가진다.
  `/create` 는 `apiBookId` 를, 원문 로드(원본 보기)는 `bookId` 폴더를 쓴다.
- ⚠️ 슬러그가 폴더명과 줄기까지 다를 수 있다(`hongbu_jeon` ↔ `heungbu-nolbu`) → `book_list.json` 의
  `apiBookId` 필드로 명시. `BookCatalog.byTitle/byAssetId/byApiId/byAnyId` 로 상호 변환.
- ⚠️ `hong-gildong-jeon` 등 구조화 JSON 이 비면 `scenes`/`characters` 가 비어 올 수 있다.

## `POST /create` — request (← `createMainProvider`)
```jsonc
{
  "bookId": "heungbu-nolbu",     // apiBookId (← BookCatalog.byTitle(...).apiBookId)
  "mode": "dialogue",            // dialogue | audio                (← CreateMode)
  "difficulty": "youth",         // children | korean_learner | youth | original  (← settings level)
  "scope": "full",               // full | scene                    (← RangeMode)
  "sceneSelection": {            // scope="scene" 일 때만. full 이면 생략(null)
    "title": "…",
    "chapters": [ { "label": "…", "startSegmentId": "seg_001" } ],
    "segments": [ { "id": "seg_001", "order": 1, "speaker": "narrator", "type": "narration", "text": "…" } ]
  },
  "ideaText": "결말을 더 따뜻하게",  // free text (optional)
  "ideaTags": ["change_ending"]  // change_ending | add_character | funnier | other (optional, multi)
}
```
- **API명세서(2026-06-23) 반영**: 과거의 `sceneIds: []` 는 폐기. `scope="scene"` 이면
  `sceneSelection.segments`(≥1, 선택 챕터의 원문 segments)를 보낸다. `CreateRequest.sceneSelection`
  은 `OriginalLoader.buildSceneSelection(assetBookId, chapterIndex)` 가 `script.json` 에서 만든다.
- enum 문자열은 `modeToApi`/`scopeToApi`/`kDifficultyByLevel`/`kIdeaTagByChip` 로 매핑. `bookId` 는
  `bookIdForSource(title)` = `BookCatalog.byTitle(title).apiBookId`.
- 잘못된 enum, 또는 `scope="scene"` 인데 `sceneSelection.segments` 비었으면 **422 (스트리밍 전)** —
  `CreateRequest.validate()` 가 사전 차단한다. `difficulty` 가 LLM 문체/어휘 수준을 결정.

## `POST /create` — SSE progress → `ai_generating_screen`
Lines arrive as `data: <JSON>\n\n`. Stages map to the generating animation:
`analysis` 원작 분석 → `structure` 구조화 → `writing` 대사 집필 → `finalize` 마무리.
```jsonc
{ "type": "progress", "stage": "analysis", "status": "running" }
{ "type": "progress", "stage": "analysis", "status": "done" }
// … structure / writing / finalize (each running → done) …
{ "type": "result", "data": { /* below */ } }
{ "type": "error",  "message": "…" }   // on failure (e.g. server has no ANTHROPIC_API_KEY)
```
Advance the visible stage on each `progress`; on `error`, show `message` and stop — do **not** navigate
to a result screen.

## `POST /create` — `result.data`
```jsonc
{
  "creationId": "uuid", "bookId": "heosaeng-jeon", "title": "…",
  "mode": "dialogue", "difficulty": "youth",
  "tags": ["…"],            // chips at top of the result UI
  "intro": "…",             // 'A quick read' info-box text
  "characters": [ { "characterId": "heosaeng", "name": "허생", "voiceProfile": "young_hero_male" } ],
  "scenes": [ {
    "sceneId": "scene-1", "order": 1, "title": "…",
    "lines": [ {
      "lineId": "scene-1-l1", "order": 1,
      "speaker": "heosaeng",        // one of characters[].characterId
      "speakerName": "허생",
      "direction": null,            // 지문/감정 (null if none)
      "text": "…",
      "voiceProfile": "young_hero_male",                     // audio mode only (null for dialogue)
      "tts": { "rate": 1.0, "pitch": 1.0, "lang": "ko-KR" }  // audio mode only (fixed for now)
    } ]
  } ],
  // ── 아래 필드는 모두 optional. 없으면 앱이 폴백한다(이모지 표지 / 밑줄 없음 / 스트리밍·대사극). ──
  "creationCoverImageUrl": "/creation-covers/uuid.webp",  // GPT 이미지 표지(상대경로). baseUrl 로 절대화
  "creationCoverEmoji": "🎭",                              // 표지 이미지가 없을 때의 폴백 이모지
  "vocab": {                       // 어려운 단어 사전(본문 표기 그대로가 key) — 본문과 함께 번들로 내려준다
    "홍문관부제학": { "hanja": "弘文館副提學", "meaning": "…", "note": "…" }
  },
  "audio": {                       // audio mode only — 단일 MP3 + 줄별 타임포인트
    "audioUrl": "/audio/uuid.mp3", // 상대경로. baseUrl 로 절대화 후 cover 와 같은 방식으로 오프라인 캐시
    "timepoints": [ { "lineId": "scene-1-l1", "startMs": 0, "endMs": 1800 } ]
  }
}
```
- `dialogue_result_screen`: `scenes[].lines[]` = **대본**; **역할 읽기** = lines filtered by `speaker`
  (no separate field); **원작 정보** = `intro` / `tags` / source meta.
- `audio_result_screen`: play `lines` in `order`; audio mode adds per-line `voiceProfile` + `tts`. The
  0.8x/1.0x/1.2x speed UI is a **global** app-side rate; the server gives per-line defaults only.
- **어휘 풀이(vocab)는 단어 탭 시 호출하지 않는다.** `/create` 결과의 `vocab` 사전이 본문과 함께 와서
  SQLite(`works.vocab`)에 저장되고, 단어를 누르면 그 로컬 맵에서 즉시 보여 준다(오프라인). 별도 `POST /vocab`
  엔드포인트는 쓰지 않는다(과거 `ApiClient.vocab()` 는 제거됨).
- **표지/오디오 미디어는 상대경로**(`/creation-covers/…`, `/audio/…`)로 내려주면 앱이 `baseUrl` 로 절대화한 뒤
  디스크에 받아 둔다(`cover_cache/`·`audio_cache/`, 오프라인). 자세한 캐시 동작은 `docs/storage.md`.
- Backend guarantees: no duplicate ids, no missing `order`, every `speaker` ∈ `characters[]`.
- `voiceProfile` vocabulary varies per book (e.g. `young_hero_male` vs `pure_gentle`) and isn't a
  reliable gender/age signal — Flutter maps it to TTS voices. Backend may later add `gender`/`ageGroup`
  (not in the response yet); update this section when it does.

## Models & services
- **`lib/models/create_request.dart`** (done) — `CreateRequest` (→ `/create` body) + the enum maps
  (`kBookIdBySource`, `kDifficultyByLevel`, `kIdeaTagByChip`, `modeToApi`/`scopeToApi`) kept identical
  to `API.md`, plus `validate()`.
- **`lib/services/create_api.dart`** (done) — `CreateApi` streams `CreateEvent`
  (`CreateProgress` / `CreateResult` / `CreateError`); real SSE via `http`, or canned events when
  `AppConfig.useMock`. `createApiProvider` injects the current `AppConfig`.
- **`lib/models/creation_result.dart`** (**planned**) — typed `CreationResult` / `CreationCharacter` /
  `CreationScene` / `CreationLine`. The store currently keeps the result as a **raw JSON `Map`**
  (decision: structure + raw store first); typing it + rendering it in the result screens is next.
