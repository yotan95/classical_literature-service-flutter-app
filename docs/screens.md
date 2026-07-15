# Screens — fragments & behavior

> Owned by this doc: per-screen roles and UI/behavior specs. Update here when a screen's behavior
> changes (and append `docs/CHANGELOG.md`). Navigation/structure is in `docs/architecture.md`; the
> create-flow contract is in `docs/backend.md`.

## Screens (all in `lib/fragments/`)
| File | Widget | Role |
|---|---|---|
| `onboarding_screen.dart` | `OnboardingScreen` | intro, shown once (no name step) → AppShell |
| `app_shell.dart` | `AppShell` | tab host (IndexedStack + bottom nav); initial tab = Library |
| `create_main_screen.dart` | `CreateMainScreen` | pick classic/mode/level/range/idea → POST /create (no alarm icon) |
| `ai_generating_screen.dart` | `AiGeneratingScreen` | /create SSE progress (analysis→structure→writing→finalize) → result |
| `dialogue_result_screen.dart` | `DialogueResultScreen` | 대사극 result (3 tabs) |
| `audio_result_screen.dart` | `AudioResultScreen` | 오디오극 result (player) |
| `library_screen.dart` | `LibraryScreen` | 내 서재 (first screen): 원작 2×5 paged grid + shelf |
| `settings_screen.dart` | `SettingsScreen` | 설정 (no profile sub-view; data-reset pinned at bottom) |

Result screens accept optional `title`/`source`/`level` from My Library; when null they load default
sample data. Create path → `ai_generating_screen` consumes the SSE then pushes the result screen by
`mode`; the My Library path reads stored `created_data/` (see `docs/storage.md`). Mapping `result.data`
into the result screens is still pending (see `docs/backend.md`).

## Behavior specs
- **`library_screen` — 원작 (originals) section:** lay the books out as a **2-row × 5-column grid**
  (10 per page). When more than 10 exist, the section **pages horizontally (slide right)** rather than
  growing vertically — e.g. a `PageView` of 2×5 `GridView` pages (or horizontal pager). Book art/data
  are placeholders for now; source the list from `/books` when wired.
- **`library_screen` — tapping an 원작 book:** open its detail with **원본 보기 (view original) as the
  default, always-present first view**; the remaining views (created works for that source, etc.) behave
  as before. Original text comes from backend/original data (see `/books/{bookId}`), not vocab.
- **`create_main_screen`:** **no alarm/notification icon** (top-right removed). The **창작물 만들기
  (Create) button** sends the selected values (`bookId`/`mode`/`difficulty`/`scope`/`sceneIds`/`ideaText`/
  `ideaTags`) to **`POST /create`** and drives the generating animation by SSE stage (see
  `docs/backend.md`).
- **`settings_screen` / `settings_state`:** **no standalone profile sub-view** (`_profileView` and the
  `profile` value in the `SettingsView` enum removed). Its **data-reset (초기화) sits at the very bottom
  of the settings root** and calls `CreationStore.clear()`. Onboarding sets no nickname; nickname (if
  still editable) lives only in its own settings sub-view.
- **`dialogue_result_screen` / `audio_result_screen`:** render per `docs/backend.md` `result.data`
  (대본 / 역할 읽기 by `speaker` / 원작 정보; audio plays `lines` in `order` with per-line `tts`).
  Currently still backed by `sample_data.dart` until the result mapping lands.
- **오디오극 재생 라이프사이클(`audio_result_screen` + `AudioResultNotifier`):** 미디어 알림/잠금화면 제어는
  **없음**(audioplayers 단독, `audio_service`/`just_audio_background` 미도입). **뒤로가기 = 정지+위치저장:** 화면
  `dispose` → `stopAndPersist(updateState:false)`(pause + `works.lastPositionMs` 저장; **state 변경 없음** — dispose
  시점엔 watch 중인 Element 가 defunct 라 state 를 바꾸면 `markNeedsBuild` assert 가 터진다. 라이프사이클 콜백은
  위젯이 살아 있어 `updateState:true`(기본)로 재생버튼을 즉시 끔). **⚠️ dispose 에서 위젯 `ref` 금지:** dispose 시점엔
  `ref` 가 무효(`Cannot use ref after disposed`)이고 그 예외가 `unmount` 를 끊어 구독 누수 → 재생이 안 멈추고 무한
  `markNeedsBuild` 가 된다. `initState` 에서 `_audio = ref.read(...notifier)` 로 캐시해 dispose/라이프사이클에서 이걸로
  호출한다(전역 provider 라 인스턴스 안정적). **백그라운드/화면 잠금 = 일시정지:** State 가
  `WidgetsBindingObserver` 로 `didChangeAppLifecycleState` 를 받아 `paused`/`hidden` 에서 `stopAndPersist` 호출
  (`inactive` 는 알림센터·앱 전환 미리보기 등 일시적 상황이라 제외). 비동기 재생 시퀀스(`togglePlay`/`playFrom`/
  `playLineOnly`)는 `_playEpoch` 토큰으로 가드 — 느린 스트리밍 로드/seek 도중 화면을 떠나거나 백그라운드로 가면
  `stopAndPersist` 가 토큰을 올려 **뒤늦은 `resume()` 을 취소**(화면 이탈/백그라운드 후 재생되던 버그 차단).
  **이어듣기:** 재진입 시 `_loadFromDb` 가 `lastPositionMs` → `_restorePosMs` 로 복원해 시크바/현재 줄을 맞추고,
  재생을 누르면 그 지점부터 이어 재생(백그라운드 일시정지 후 포그라운드 복귀 시엔 플레이어가 위치를 유지하므로 재생만 누르면 이어짐).
  **재생 소스(1회차 vs 재진입):** 1회차(생성 직후)는 **서버 URL 스트리밍 + 백그라운드 mp3 다운로드**(`_maybeCacheAudio`,
  `audio_cache/<id>.mp3`)를 동시에 한다. 재진입 시 `_loadFromDb` 는 **DB 플래그가 아니라 실제 디스크 파일 존재**
  (`AudioCacheStore.localPath`)로 소스를 고른다 — **받아 둔 mp3 있으면 로컬 파일, 없으면 스트리밍**(다운로드는
  `.part`→`.mp3` 원자적 rename 이라 파일이 있으면 완본). 다운로드 완료 콜백은 작품 전환과 무관하게 그 작품 행에
  `setAudioLocalPath` 를 먼저 기록해 DB·디스크 불일치를 막는다.
