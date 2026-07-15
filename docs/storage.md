# Local Storage — `created_data/` (app-private)

> Owned by this doc: how creations are persisted on-device and `CreationStore`. Update here when the
> storage location / format / API or permission posture changes (and append `docs/CHANGELOG.md`).

Every creation — the `/create` `result.data` **and** anything a local DB would hold — is saved as
**JSON files in an app-private folder the user cannot browse**, then read back for My Library and result
screens (offline).

## Location & permissions
- App documents/support directory via `path_provider`
  (`getApplicationDocumentsDirectory()` / `getApplicationSupportDirectory()`), under a `created_data/`
  subfolder — `<app-docs>/created_data/<creationId>.json`. This sandboxed path is **not visible** in the
  device file manager / gallery, which satisfies the "user can't explore it" requirement.
- **No runtime storage permission** is needed for the app-private sandbox on Android or iOS — so prefer
  it. Use `permission_handler` **only if** a future location needs shared/external storage (the current
  plan avoids this). If that happens, request up front and handle denial gracefully.

## Format & DB relationship
- One JSON file per creation, filename = `creationId`, holding the full result
  (`creationId`/`bookId`/`title`/`mode`/`difficulty`/`tags`/`intro`/`characters`/`scenes`…).
- The **JSON files are canonical.** The previously-planned SQLite tables
  (`creations`/`characters`/`scenes`/`lines`) are now **optional** — an index/cache over the JSON, not a
  second source of truth. Don't duplicate the data into two authorities. Stable
  `creationId`/`sceneId`/`lineId` + `order` keep the two consistent.

## `CreationStore` (`lib/services/creation_store.dart`, done)
- Owns `save` / `read` / `readAll` / `listIds` / `delete` / `clear` over `created_data/`, resolving the
  dir via `path_provider` + `p.join` (no hardcoded paths). Exposed as `creationStoreProvider`.

## 오디오극 MP3 오프라인 캐시 (`lib/services/audio_cache_store.dart`, done — 사용자 결정 2026-06-25)
오디오극(서버 단일 MP3)을 **첫 재생 때 스트리밍과 동시에 디스크에 받아 두고, 이후엔 서버 없이 오프라인 재생**한다.
- **위치:** `getApplicationSupportDirectory()/audio_cache/<creationId>.mp3` (지원 폴더 — 사용자에게 안 보이고
  iCloud 백업 제외, OS 가 자동으로 안 지움). `created_data/`(Documents)와 역할 분리.
- **파일은 디스크, 참조는 SQLite.** `works.audio_local_path`(db_service v7 신설, TEXT)에 **파일명만** 저장
  (절대경로·BLOB 아님). 런타임에 폴더를 다시 해석하므로 재설치로 샌드박스 경로가 바뀌어도 안전.
- **다운로드(읽기-스루 캐시):** `AudioCacheStore.download(url, id)` 가 `<id>.mp3.part` 로 받은 뒤 **원자적 rename**
  으로 확정(중간 종료 시 반쪽 파일 오인 방지). `audio_result_state` 는 **화면 진입 시(`_loadFromDb`)** 캐시가
  없으면 즉시 백그라운드 다운로드를 걸고(`_maybeCacheAudio`, 재생 시작에 의존 안 함 → 한 번도 못 틀어도 다음 진입부터
  오프라인), 완료되면 `db.setAudioLocalPath` 로 파일명을 기록한다. `_downloadTried` 는 `load` 마다 리셋되어 **재진입 시
  실패분을 재시도**한다. (재생 시작 시점에도 `playingStream` 으로 한 번 더 시도 — 멱등, `_downloadTried`/`_localPath` 가드.)
- **재생 소스 선택:** `_loadFromDb` 가 `audio_local_path` 의 실제 파일 존재를 확인해 있으면 `TtsPlayer.setLocalFile`
  (`DeviceFileSource`, 오프라인), 없으면 `setUrl`(서버 스트리밍). seek/timepoints 는 양쪽 동일.
- **스트리밍 구간 seek 내성:** 네트워크 스트림 seek 은 응답이 없으면 audioplayers 기본 **30초**까지 UI 가 멈추고
  미처리 `TimeoutException` 으로 번질 수 있어, `TtsPlayer.seekMs`/`skip` 에 **8초 자체 타임아웃**(`TtsPlayer.seekTimeout`)을
  건다. 명시적 재생(`togglePlay`/`playFrom`/`playLineOnly` — 줄 탭 포함 모두 `_safePlay` 경유)은 실패 시 안내 스낵바,
  시크바 드래그(`seekToFraction`)·로드 중 복원 seek 은 위치를 이미 반영했으므로 조용히 무시. 로컬 파일 seek 은 즉시 끝나므로
  이 타임아웃은 실질적으로 스트리밍 구간에서만 의미가 있다.
- **CRUD 삭제 동기화:** `library_state.removeWork` → `AudioCacheStore.delete(id)`(`.mp3`+`.part`),
  `clearAll`/데이터 초기화 → `AudioCacheStore.clear()`(폴더 통째). 대사극·다운로드 실패·오프라인 첫 재생은
  기존 스트리밍 동작으로 자연 폴백(캐시는 다음 재생에서 재시도).

## 창작물 표지(AI 이미지) 오프라인 캐시 (`lib/services/cover_cache_store.dart`, done — 사용자 결정 2026-06-25)
서버가 GPT 이미지로 만들어 `result.data.creationCoverImageUrl` 로 내려주는 **창작물 대표 표지**를
**생성 직후 디스크에 받아 두고, 이후엔 서버 없이 오프라인에서 표시**한다. 오디오 MP3 캐시와 동일 패턴.
- **위치:** `getApplicationSupportDirectory()/cover_cache/<creationId>.<ext>` (지원 폴더 — 사용자에게 안 보이고
  iCloud 백업 제외, OS 자동 삭제 안 함). 확장자는 URL 에서 추출(webp/png/jpg, 미상은 `.img`) — `Image.file` 은
  확장자와 무관하게 내용(magic bytes)으로 디코딩하므로 확장자는 표시용일 뿐이다.
- **파일은 디스크, 참조는 SQLite.** `works.creation_cover_local_path`(db_service v8 신설, TEXT)에 **파일명만** 저장
  (절대경로·BLOB 아님). 런타임에 폴더를 다시 해석하므로 재설치로 샌드박스 경로가 바뀌어도 안전.
- **다운로드·재시도(일원화 — `library_state._loadWorks`):** 표지 다운로드는 한 곳에서만 한다. 창작 작업
  (`state/creation_job.dart`)은 작품을 **곧바로 저장**(원격 URL 은 `creation_cover_image_url` 에 보존, 파일명 미기록)하고
  `refresh()` 만 부른다. `_loadWorks` 는 작품을 로드한 뒤 **로컬 파일이 없고 원격 URL(http)이 있는 작품**을
  `_retryMissingCovers` 로 백그라운드 `CoverCacheStore.download(url, id)`(`<id>.<ext>.part` → **원자적 rename**)한다.
  받으면 `db.setCoverLocalPath(id, name)` 로 **파일명**을 기록하고 다시 로드해 화면을 갱신한다(원작 커버 → AI 표지 교체).
  이 경로가 **생성 직후 첫 다운로드 + 실패·오프라인 생성분의 다음 실행 자동 재시도**를 모두 담당한다(`_retryingCovers`
  플래그로 재진입/폭주 방지, 받은 게 없으면 추가 로드 없음). DB 에 **절대경로**를 저장하던 옛 `MediaCache` 경로는
  재설치/세션 교체 시 깨져 이 설계로 교체했다.
- **렌더 소스 선택(placeholder = 원작 커버):** `_loadWorks` 가 `creation_cover_local_path` 의 실제 파일을 확인해 절대경로를
  `CreativeWork.coverLocalAbsPath`(DB 미저장 일시값)에 채운다. `CreativeWork.coverDisplayPath` = **다운로드된 AI 표지
  (`coverLocalAbsPath`) → 없으면 원작 대표 커버(`bookImage(source)`)**. 원격 URL 자체는 렌더 소스로 쓰지 않아(다운로드
  전에는 원작 커버, 받은 뒤 로컬 파일로 교체) 네트워크 깜빡임이 없고, 옛 빌드의 깨진 절대경로도 원작 커버로 자연
  폴백한다. 원작 커버도 없는 미지의 책만 이모지/책색으로 폴백. `netOrAssetCover` 가 경로 형태로
  `Image.file`/`Image.asset` 를 분기한다.
- **CRUD 삭제 동기화:** `library_state.removeWork` → `CoverCacheStore.delete(id)`(`<id>.*`+`.part`),
  `clearAll`/데이터 초기화 → `CoverCacheStore.clear()`(폴더 통째). 다운로드 실패·미다운로드는 원작 커버 폴백.

## 원작 본문 오프라인 캐시 (`book_originals` 테이블, done — 사용자 결정 2026-06-26)
원작보기(`GET /books/{id}/original`)의 본문을 **앱 실행 시 선반입**해 두고, 화면에선 **로컬 우선**으로 읽는다
(매번 네트워크 요청하던 것을 제거). 미디어와 달리 텍스트라 디스크 파일이 아닌 **SQLite 행에 본문 자체를 저장**한다.
- **저장 위치:** 별도 테이블 `book_originals(book_id PK, text, fetched_at)`(db_service v9 신설). `books` 테이블은
  동기화 때 `replaceBooks` 로 **전체 교체**되므로, 거기에 본문을 두면 매 동기화마다 날아간다 → **분리 테이블로 보존**.
  접근: `getOriginalText(bookId)`(없으면 null) · `setOriginalText(bookId, text)` · `getOriginalBookIds()`(저장된 집합).
- **선반입 시점·증분(사용자 결정 = 백그라운드 + 새 책만):** `BooksRepository.prefetchMissingOriginals(books)` 가
  `getOriginalBookIds()` 에 **없는 책만** `fetchOriginalText` 로 받아 저장. `BooksNotifier` 가 (1) 캐시 즉시 반환 직후,
  (2) 백그라운드 `syncFromServer` 완료 후(새로 추가된 책 반영), (3) 수동 `refresh()` 후에 `unawaited` 로 호출 —
  첫 실행/화면 진입을 막지 않는다. `_prefetching` 플래그로 중복 실행 방지. 실패(서버 미연결·404)는 책별 try/catch 로
  조용히 넘겨 다음 실행에 재시도.
- **읽기(폴백):** `original_read_screen._load` 가 `getOriginalText` 우선 → 있으면 즉시 표시(오프라인). 아직 없으면
  (선반입 전/실패) 그 자리에서 `fetchOriginalText` → 표시 + `setOriginalText` 저장(선반입 보완). 둘 다 실패면 "원작 내용은
  준비 중이에요." (서버에 `/original` 라우트가 배포돼 있어야 채워진다 — 배포 누락 시 모두 404).
- **CRUD:** 서버 파생 캐시(books 와 동격)라 `clearAll`/데이터 초기화에서 별도로 비우지 않는다(다음 실행에 재선반입).

## Status (2026-06-26)
- **오프라인 미디어 캐시 완료:** 오디오극 MP3(`audio_cache/`, v7) + 창작물 표지 이미지(`cover_cache/`, v8) 모두
  디스크 캐시 + SQLite 파일명 참조 + CRUD 삭제 동기화로 오프라인 동작.
- **원작 본문 캐시 완료:** `book_originals`(v9) 에 본문 저장 — 앱 실행 시 미저장분만 백그라운드 선반입(증분),
  원작보기는 로컬 우선·미저장 시 네트워크 폴백.

## Status (2026-06-22)
- **Write side wired:** `ai_generating_screen` saves the `/create` `result.data` on success; the
  settings data-reset calls `CreationStore.clear()`.
- **Read side pending:** `library_state` / result screens still read `sample_data.dart`; listing My
  Library from `created_data/` is the next step.
