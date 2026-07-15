# Changelog (structural)

> Append an entry for every structural change, in the same commit/change. Newest first.

- **2026-06-26 — release APK 네트워크 전면 차단 버그 수정: 메인 매니페스트에 `INTERNET` 권한 명시.**
  실기기(공기계) release 설치 시 모든 서버 기능이 "오프라인"으로 보이고 원작 본문도 못 받던 문제. 원인은
  `android/app/src/main/AndroidManifest.xml` 에 `<uses-permission android:name="android.permission.INTERNET"/>`
  가 빠져 있었던 것. Flutter 는 INTERNET 을 `debug`/`profile` 매니페스트에만 자동 주입하므로 `flutter run`
  에선 멀쩡하지만 **release 빌드(메인 매니페스트)** 엔 들어가지 않아 release APK 가 네트워크 전면 차단됨
  → 연결 프로브(`GET /books`)부터 실패 → 창작 "지금은 오프라인이에요" + 원작 캐시 선반입 실패. 서버
  (`https://api.rasponline.xyz`)·APK 의 `BASE_URL` 은 모두 정상이었다. 메인 매니페스트에 권한을 명시하고
  release APK 재빌드(`aapt dump permissions` 로 포함 확인). (이전 CHANGELOG 2026-06-23 항목이 "메인
  매니페스트에 INTERNET 추가"라고 적었으나 실제 코드엔 누락돼 있었던 것을 정정.)

- **2026-06-26 — 앱 런처 아이콘(표지) 적용 + 앱 표시 이름 '쉬운고전'.**
  사용자 제공 표지 그림(흰 배경 1024² PNG, 알파 없음)을 런처 아이콘으로 설정. `flutter_launcher_icons ^0.14.4`
  (dev_dependency + pubspec 하단 `flutter_launcher_icons:` 설정) 으로 Android/iOS/web/macOS 일괄 생성:
  `image_path`·adaptive 전경 모두 `assets/icon/app_icon.png`, 배경 `#FFFFFF`, `remove_alpha_ios`(앱스토어 규격).
  Android adaptive 는 도구 기본 16% inset 으로 원형/스쿼클 마스크 안전영역 안에 글자·인물이 들어온다. 재생성:
  `dart run flutter_launcher_icons`. 표시 이름은 Android `android:label`·iOS `CFBundleDisplayName`·web
  `manifest.json`(name/short_name)·`index.html`(title/apple title) 를 **쉬운고전** 으로 변경(패키지 id
  `classic_theater`·iOS `CFBundleName`·macOS `PRODUCT_NAME` 등 내부 식별자는 유지).
- **2026-06-26 — 창작물 표지(AI 이미지) 안 뜨던 버그 수정 + 원작 커버 placeholder·자동 교체·재시도(사용자 결정).**
  창작 직후·서재에서 표지가 단색(책 색)으로만 보이던 문제. 원인은 표지 캐시가 **서로 다른 두 시스템에 반쪽씩** 물려
  있던 것: **쓰기**(`state/creation_job.dart`)는 `MediaCache`(`creation_covers/`)로 받아 **절대경로**를
  `works.creation_cover_image_url` 에 저장했는데, **읽기**(`library_state._loadWorks`)·**삭제**(`removeWork`/`clearAll`)는
  `CoverCacheStore`(`cover_cache/`)와 `creation_cover_local_path`(파일명) 기준이라 서로 만나지 못했다. 보이던 표지도
  `coverDisplayPath` 가 절대경로로 폴백한 덕분인데, 절대경로는 재설치/세션 교체로 iOS 샌드박스 경로가 바뀌면 깨져
  (`Image.file` 실패 → `netOrAssetCover` errorBuilder → 단색) 사라졌다.
  - **다운로드 일원화:** 표지 다운로드를 `library_state._loadWorks._retryMissingCovers` 한 곳으로 모음. 창작 작업은
    작품을 **즉시 저장**(원격 URL 만 `creation_cover_image_url` 에 보존)하고 `refresh()` 만 부른다. `_loadWorks` 가
    **로컬 파일 없고 원격 URL(http) 있는 작품**을 백그라운드 `CoverCacheStore.download` → `setCoverLocalPath`(파일명) →
    재로드로 교체. 이 경로가 **생성 직후 첫 다운로드 + 실패·오프라인 생성분의 다음 실행 자동 재시도**(사용자 결정)를
    모두 담당(`_retryingCovers` 플래그로 재진입 방지, 받은 게 없으면 추가 로드 없음).
  - **placeholder = 원작 대표 커버(사용자 결정):** `CreativeWork.coverDisplayPath` 를 `coverLocalAbsPath ?? bookImage(source)`
    로 변경 — 다운로드 전·실패 시 **원작 커버**로 임시 표시하고, 받으면 로컬 AI 표지로 자동 교체. 원격 URL 은 렌더
    소스로 쓰지 않아 네트워크 깜빡임 제거. AI 표지가 아예 없는 작품(서버가 이모지만 줌)도 원작 커버로 표시(사용자 결정).
  - **부수 효과:** 옛 빌드의 절대경로만 남은 **기존 작품**도 이제 단색 대신 원작 커버로 폴백(절대경로 무시). 원격 URL 이
    유실돼 AI 표지 자동 복구는 불가(새로 만들면 정상). `MediaCache`(`media_cache.dart`)는 더 이상 쓰기 경로에서 안 쓰며
    (데이터 초기화의 `creation_covers/` 정리에만 잔존), 단위 테스트(`test/media_cache_test.dart`)는 유지. `docs/storage.md` 현행화.

- **2026-06-26 — 오디오극 진입 시 무한 assert + 재생 안 멈춤 근본 원인 수정(dispose 의 `ref` 사용).**
  '내 작품'에서 오디오극을 열면 `_lifecycleState != defunct` assert 가 **무한 반복**되고, 뒤로가기로 나가도
  **재생이 계속**되며 로그에 `Cannot use "ref" after the widget was disposed` 가 떴다. 원인은
  `audio_result_screen.dispose()` 안의 `ref.read(audioResultProvider.notifier)` 였다.
  - flutter_riverpod 2.6.1 `ConsumerStatefulElement.unmount()` 는 `super.unmount()`(→ Element 를 defunct 로
    만들고 `State.dispose()` 호출)를 **먼저** 실행한 뒤에야 `dependency.close()`(구독 해제)를 한다.
  - 따라서 `dispose()` 에서 `ref.read` 를 부르면 `_assertNotDisposed()`(`context.mounted==false`)가 예외를 던지고,
    그 예외가 `unmount()` 를 중단 → **구독이 영영 안 닫힘(누수)**. 그러면 `stopAndPersist()` 도 호출 안 돼
    재생이 안 멈추고, 재생 중인 포지션 스트림이 매 틱 `state` 를 바꿔 누수된 defunct Element 에
    `markNeedsBuild` 를 무한 호출했다.
  - **수정:** `_AudioResultScreenState` 가 `initState` 에서 `_audio = ref.read(audioResultProvider.notifier)` 로
    notifier 인스턴스를 캐시(전역 provider 라 안정적) → `dispose`/`didChangeAppLifecycleState`/`build` 가 위젯 ref
    대신 `_audio` 로 호출. postFrame `load` 와 dialogue_result_screen 의 postFrame `load` 에 `if(!mounted) return`
    가드 추가(프레임 전 이탈 시 ref-after-disposed 방지). dispose 는 계속 `updateState:false`.

- **2026-06-26 — 원작 읽기 화면 dispose 중 provider 수정 assert 수정.** 원작 읽기 도중 화면 전환
  (예: 오디오극 생성으로 이동) 시 `original_read_screen.dispose()` 가 `_save()`→`LibraryNotifier.setReading()`
  로 `state = copyWith(reading:…)` 를 호출, 트리 finalize(lockState) 중 provider 를 수정해 Riverpod
  `_debugCanModifyProviders` assert 가 터졌다(`audio_result_screen` 의 dispose 버그와 동일 계열). →
  dispose 에서는 offset/source 를 복사해 `scheduleMicrotask` 로 잠금 해제 후 저장하도록 변경. 디바운스
  타이머 경로(`_save`)는 finalize 밖이라 그대로 둠.

- **2026-06-26 — 오디오극 뒤로가기 크래시 수정 + 2회차 mp3/스트리밍 전환 수정.** 두 가지 버그를 잡았다.
  - **뒤로가기 시 assert 크래시(`_lifecycleState != defunct`).** `audio_result_screen.dispose()` 가
    `stopAndPersist()` 안에서 `state = copyWith(playing:false)` 로 provider state 를 바꿨는데, dispose 시점엔
    이 provider 를 `watch` 하던 Element 가 이미 defunct 라 자기 자신에 `markNeedsBuild` 가 호출돼 터졌다.
    → `stopAndPersist({bool updateState = true})` 로 바꿔 **dispose 경로에선 `updateState:false`** (정지·위치저장만,
    state 변경 없음). 라이프사이클(paused) 콜백은 위젯이 살아 있어 기존대로 `true`(재생버튼 즉시 끔).
  - **2회차(히스토리 재진입) 다운로드 mp3 미사용.** `_loadFromDb` 가 로컬/스트리밍을 **DB `audio_local_path`
    플래그**로 골랐는데, 1회차 백그라운드 다운로드가 끝나기 전에 다른 작품으로 넘어가면 완료 콜백의
    `state.workId != id` 가드에 막혀 **파일은 디스크에 있는데 DB 플래그는 미기록**이 돼 스트리밍으로 폴백했다.
    → (1) `_loadFromDb` 가 플래그 대신 **실제 디스크 파일 존재**(`AudioCacheStore.localPath`)로 소스를 결정
    (`.part`→`.mp3` 원자적 rename 이라 파일 있으면 완본). (2) `_maybeCacheAudio` 완료 콜백이 `setAudioLocalPath(id,…)`
    를 작품 전환과 무관하게 먼저 기록(메모리 `_localPath` 갱신만 현재 작품일 때). 상세는 `docs/screens.md`(오디오극) 참조.

- **2026-06-26 — 원작 본문 오프라인 캐시(선반입 + 로컬 우선 읽기).** 원작보기가 화면을 열 때마다
  `GET /books/{id}/original` 을 매번 요청하고 본문을 메모리에만 두던 것을, **앱 실행 시 선반입 + SQLite 저장 +
  로컬 우선 읽기**로 바꿨다(사용자 결정 2026-06-26: 백그라운드 선반입 + 새 책만 증분).
  - **db_service v8 → v9:** 별도 테이블 `book_originals(book_id PK, text, fetched_at)` 신설(`_createBookOriginals`
    + onCreate/onUpgrade 연결). `books` 는 동기화 시 `replaceBooks` 로 전체 교체되므로 본문을 거기 두지 않고
    분리 테이블에 보존. 접근자 `getOriginalText`/`setOriginalText`/`getOriginalBookIds` 추가.
  - **`BooksRepository.prefetchMissingOriginals(books)`:** `getOriginalBookIds()` 에 없는 책만(증분) `fetchOriginalText`
    로 받아 `setOriginalText` 저장. `_prefetching` 플래그로 중복 실행 방지, 책별 try/catch 로 부분 실패 격리.
  - **`BooksNotifier` 연결:** `build`(캐시 반환 직후/첫 실행 동기화 직후), `_syncInBackground`(새 책 반영), `refresh`
    각 경로에서 `unawaited(prefetchMissingOriginals(...))` — 첫 실행·화면 진입을 막지 않는 백그라운드 선반입.
  - **`original_read_screen._load`:** `dbServiceProvider.getOriginalText` 우선(오프라인·즉시) → 없으면 그 자리에서
    `fetchOriginalText` 표시 + `setOriginalText` 저장(폴백 겸 선반입 보완). 상세는 `docs/storage.md`(원작 본문 캐시).
  - **주의(미해결, 별개 과제):** 배포 서버 `api.rasponline.xyz` 에 `/books/{id}/original` 라우트가 아직 없어 404 —
    캐시가 채워지려면 백엔드(`service-data-pipeline`, 라우트+`data/original/*.txt` 보유) 재배포가 필요(로컬에선 200 확인).

- **2026-06-26 — 브랜치 머지 충돌 해소(컴파일 오류 수정).** 다른 브랜치 머지 후 "호출부는 새 브랜치, 정의부는 기존
  브랜치"로 짝이 안 맞아 생긴 오류 2건 수정. (1) `audio_result_screen` `_AudioLineTile` 이 인물별 색을 쓰도록 바뀌었으나
  (`colors?[line.char]`) 머지 때 생성자 `colors` 파라미터+전달이 누락 → `_LineTile`(dialogue) 과 동일하게
  `final Map<String, ({Color bg, Color fg})>? colors` 필드 추가 + `_lineList` 에서 `colors:` 전달. (2)
  `ai_generating_screen` 이 표지 캐시 후 `CreativeWork.copyWith(creationCoverImageUrl: …)` 로 덮어쓰는데, 수기 작성
  `CreativeWork.copyWith`(sample_data) 에 해당 파라미터가 없었음 → `creationCoverImageUrl` 파라미터 추가(`?? this.…`).
- **2026-06-26 — 오디오극 스트리밍 seek 멈춤/크래시 수정 + 캐시 선반입.** 캐시 미완성(스트리밍) 구간에서
  네트워크 seek 이 응답을 못 받으면 audioplayers 기본 30초까지 UI 가 멈추고 줄 탭 경로에서 미처리 `TimeoutException`
  (크래시)으로 번지던 문제를 수정.
  - **`TtsPlayer`(`lib/services/tts_player.dart`):** `seekMs`/`skip` 의 실제 seek 을 `_seek` 로 모아 **8초 자체 타임아웃**
    (`TtsPlayer.seekTimeout`) 적용 — 초과 시 빠르게 `TimeoutException`(전파).
  - **`AudioResultNotifier`(`lib/state/audio_result_state.dart`):** (1) `_loadFromDb` 가 캐시 없을 때 **화면 진입 즉시**
    `_maybeCacheAudio()` 를 호출 — 재생 시작에 의존하던 다운로드 트리거를 앞당겨, "재생 전 seek 이 막혀 재생이 시작 못 해
    캐시가 영영 안 채워지던" 자기모순 루프를 끊음(재진입 시 `_downloadTried` 리셋으로 실패분 재시도). (2) `seekToFraction`
    은 위치를 이미 반영하므로 seek 실패를 조용히 무시(`try/catch`, 드래그마다 스낵바 방지).
  - **`audio_result_screen.dart`:** 줄 탭 재생을 `_AudioLineTile.onPlayFrom` 콜백으로 받아 `_safePlay(() => n.playFrom)` 경유
    — 액션 메뉴/재생 버튼과 동일하게 실패 시 크래시 대신 안내 스낵바. 효과: 서버 정상이면 스트리밍·로컬 모두 정상 재생,
    서버 불량이면 30초 멈춤·크래시 대신 ≤8초 내 스낵바. 상세는 `docs/storage.md`(오디오 캐시).
- **2026-06-26 — 오디오극 뒤로가기 시 재생 멈춤(경쟁 조건 수정).** 미디어 알림/잠금화면 제어는 미도입 상태 확인
  (audioplayers 단독; 추가하려면 `audio_service`/`just_audio_background` + 플랫폼 백그라운드 설정 필요 = 별도 과제).
  뒤로가기 정지(`dispose`→`stopAndPersist`: pause+위치저장)와 이어듣기(`lastPositionMs` 복원)는 이미 있었으나, 비동기
  재생 시퀀스(`togglePlay`/`playFrom`/`playLineOnly`)가 느린 스트리밍 `_loadSource`/seek 을 `await` 하는 동안 화면을
  떠나면, `stopAndPersist` 의 `pause()` 가 "아직 재생 전"이라 무효였다가 뒤늦게 `resume()` 이 실행돼 **화면 이탈 후에도
  재생**되던 버그가 있었음. `AudioResultNotifier._playEpoch` 토큰 추가 — 각 재생 메서드가 시작 시 토큰을 캡처하고
  `resume()` 직전 재확인, `stopAndPersist`(및 새 재생)가 토큰을 올려 **stale 한 resume 을 취소**. `docs/screens.md`(오디오극
  재생 라이프사이클) 참고.
- **2026-06-26 — 백그라운드/화면 잠금 시 오디오극 일시정지.** 미디어 알림/백그라운드 재생을 지원하지 않으므로 화면이
  안 보일 때 계속 재생하지 않도록, `_AudioResultScreenState` 에 `WidgetsBindingObserver` 를 추가
  (`initState`/`dispose` 에서 add/remove). `didChangeAppLifecycleState` 가 `paused`/`hidden` 에서
  `AudioResultNotifier.stopAndPersist()`(pause + 위치저장 + in-flight resume 취소) 호출 — `inactive` 는 알림센터·앱 전환
  미리보기 등 일시적 상황이라 제외. 포그라운드 복귀 후 재생을 누르면 멈춘 위치에서 이어짐(플레이어가 위치 유지).
- **2026-06-25 (c) — 서버 호스트 단일 출처화(`AppConfig` 로 통합) + 배포 서버 기본값.**
  중복이던 `ApiConfig`(Dio 클라이언트 전용 baseUrl/timeout/apiKey)를 제거하고, `ApiClient` 가 `AppConfig.baseUrl`
  을 주입받도록 통합. 이제 서버 호스트는 `AppConfig` 한 곳·env var `BASE_URL` 하나로만 관리된다.
  - **`ApiClient`(`lib/services/api_client.dart`):** 생성자를 `ApiClient({String baseUrl, Dio? dio})` 로 변경,
    `_defaultDio(baseUrl)` 가 주입값 사용. 타임아웃(10s/60s)은 내부 상수로 이동. 미사용 `X-API-Key` 헤더 제거
    (backend.md: "No auth headers"). `apiClientProvider` 가 `appConfigProvider` 를 watch → base URL 변경 시 재생성.
  - **`lib/services/api_config.dart` 삭제** — `ApiConfig` 는 어디서도 안 쓰임(host 중복 + 미사용 apiKey/`API_BASE_URL`).
  - **기본 서버 주소 = `https://api.rasponline.xyz`:** `AppConfig.kDefaultBaseUrl` 값 유지 + 낡은 주석(로컬 기본이라
    적혀 있던 것) 정정. `docs/backend.md` Config 섹션을 배포 기본값/단일 출처 기준으로 현행화.

- **2026-06-25 (b) — 창작물 표지(AI 이미지) 오프라인 캐시 + docs 현행화(merge 로 어긋난 문서를 현재 코드 기준 정정).**
  오디오 MP3 캐시와 동일 패턴. 기존 UI·위젯은 표지 경로 선택만 바꿈(렌더 위젯 무재작성, 사용자 결정: 지원 폴더 +
  생성 직후 다운로드 + SQLite 에 파일명).
  - **신규 `CoverCacheStore`(`lib/services/cover_cache_store.dart`):** `getApplicationSupportDirectory()/cover_cache/`
    하위에 `<creationId>.<ext>`(URL 에서 추출, 미상 `.img`) 저장. `download`(=.part 로 받고 **원자적 rename**)·
    `pathForFileName`·`delete`(`<id>.*`+`.part`)·`clear`. `dio` 사용(새 패키지 없음). `coverCacheStoreProvider` 노출.
  - **db_service v7 → v8:** `works` 에 `creation_cover_local_path TEXT` 컬럼 신설(파일명만, BLOB 아님) + 마이그레이션.
    `setCoverLocalPath(id, name)` 추가. `CreativeWork` 에 `creationCoverLocalPath`(저장) + `coverLocalAbsPath`(일시,
    DB 미저장) 필드와 `coverDisplayPath`(로컬 우선 → URL) getter, `toRow`/`fromRow`/`copyWith` 반영.
  - **다운로드 시점(생성 직후 1회, `ai_generating_screen`):** `/create` 결과 저장 직후 `_cacheCover` 를 비동기로 띄워
    표지를 받고 DB 에 파일명 기록 → 서재 새로고침. 결과 화면 이동은 막지 않는다.
  - **렌더(`library_screen`):** 썸네일/큰 표지 모두 `work.creationCoverImageUrl` → `work.coverDisplayPath` 로 교체
    (오프라인 캐시 우선). `library_state._loadWorks` 가 파일 존재 확인 후 `coverLocalAbsPath` 를 채운다.
  - **CRUD 삭제 동기화(`library_state`):** `removeWork` → `CoverCacheStore.delete(id)`, `clearAll`/데이터 초기화 →
    `CoverCacheStore.clear()`(오디오와 나란히).
  - **사전(어휘) 정책 확정 — 번들 방식 유지:** 단어 탭 시 서버를 부르지 않고 `/create` 결과의 `vocab` 로컬 맵을 본다.
    미사용 `ApiClient.vocab()`(POST /vocab) 제거.
  - **docs 현행화:** `backend.md` §result.data 에 `vocab`/`creationCoverImageUrl`/`creationCoverEmoji`/`audio` 명시 +
    vocab 번들 정책 기술. `storage.md` 에 표지 캐시 섹션 추가. 서비스 목록/의존성 오기(cached_network_image,
    dictionary_service stub 등)를 현재 파일 기준으로 정정.

- **2026-06-25 — 오디오극 MP3 오프라인 캐시(첫 재생 스트리밍 + 동시 다운로드 → 이후 오프라인 재생).**
  기존 UI·위젯 무수정, 서비스/상태 계층만 변경(사용자 결정: 지원 폴더 + 파일은 디스크/경로만 SQLite + 첫 재생 시 다운로드).
  - **신규 `AudioCacheStore`(`lib/services/audio_cache_store.dart`):** `getApplicationSupportDirectory()/audio_cache/`
    하위에 `<creationId>.mp3` 저장. `download`(=.part 로 받고 **원자적 rename**)·`localPath`·`delete`(.mp3+.part)·
    `clear`. `dio` 사용(기존 의존성, 새 패키지 없음). `audioCacheStoreProvider` 노출.
  - **db_service v6 → v7:** `works` 에 `audio_local_path TEXT` 컬럼 신설(파일명만, BLOB 아님) + 마이그레이션.
    `WorkContent.audioLocalPath` 필드, `setAudioLocalPath(id, name)` 추가. `_contentColumns`/`getWorkContent` 반영.
  - **`TtsPlayer.setLocalFile(path)`:** `DeviceFileSource` 로 로컬 파일 재생(오프라인). 내부 소스 키(`url:`/`file:`)로
    동일 소스 재로드 생략. 기존 `setUrl`(스트리밍)은 유지.
  - **`audio_result_state`:** `_loadFromDb` 가 로컬 캐시 존재 시 `setLocalFile`(오프라인), 없으면 `setUrl`(스트리밍).
    재생이 실제 시작되면(`playingStream`) `_maybeCacheAudio` 가 첫 1회 백그라운드 다운로드 → 완료 시 DB 에 파일명 기록.
    `togglePlay`/`seekToFraction`/`playFrom`/`playLineOnly` 는 통합 `_loadSource`/`_hasSource` 사용.
  - **CRUD 삭제 동기화(`library_state`):** `removeWork` → `AudioCacheStore.delete(id)`, `clearAll`/데이터 초기화 →
    `AudioCacheStore.clear()`. 창작물과 MP3 가 함께 생성·삭제된다.

- **2026-06-24 (c) — 책 데이터 SQLite 캐시 + 원작 보기 원문 엔드포인트 + 내 서재 실데이터.**
  - **SQLite books 캐시 (db_service v4):** 새 `books` 테이블(`book_id` PK + title/emoji/author/era/
    difficulty/tags/cover_color/cover_image_url/short_description/scene_count/sort_order/fetched_at).
    `replaceBooks`(전체 교체)·`getBookRows`. `books_service` 에 `BooksRepository`(cached/syncFromServer)
    + `booksProvider` 를 **AsyncNotifier(캐시 먼저 → 백그라운드 서버 동기화)** 로 교체 → 앱 실행 시
    `GET /books` 로 추가/변경 반영(#0), 오프라인은 캐시 표시.
  - **기존 화면에 서버 표지 주입(무수정):** `create_main_state` 에 `gServerBookCovers` 레지스트리 +
    `registerServerBookCovers`. `sample_data` 의 `bookColor/bookEmoji/bookImage` 가 레지스트리를 먼저
    조회 → 내 서재/원작/원작보기 표지·색·이모지가 서버값으로(코드 수정 없이). 책 동기화 시 채워짐.
  - **내 서재 = 실제 창작물 History:** `library_state` 데모 시드(`kSampleWorks`) 제거, `works` 는 DB
    실데이터만. `allOriginals(..., bookTitles)` 가 서버 원작 제목을 받음(+창작물 있는 비서버 원작 보존).
    `library_screen._openWork` 가 `workId` 전달 → 저장된 창작물(대사극/오디오극)을 실데이터로 재오픈
    (1-1, #2). 최근 창작물은 updated_at DESC.
  - **원작 보기 원문 (1-2):** 백엔드(`classic_literature_fastAPi`)에 **`GET /books/{id}/original`** 추가
    (`data_loader.load_original_text` → `data/original/<slug>.txt`, slug=bookId). Flutter
    `original_read_screen` 이 제목→bookId 해석 후 `BooksApi.fetchOriginalText` 로 원문 표시(에셋 의존 제거).

- **2026-06-24 — FastAPI wired into the EXISTING UI (adapter approach) + 창작물 History.** 기존 화면을
  그대로 두고 데이터 소스만 서버로 바꿨다(화면 재작성 없음).
  - **Baseline fix:** `yohan` 병합으로 깨졌던 `BookCover.image` 필드와 result-state `load(workId:…)` 를
    복구해 컴파일 가능 상태로(원본 UI = `yohan_TTS1`). `pubspec` 의 삭제된 `assets/data/*` 참조 제거.
  - **Books/Scenes (신규 `services/books_service.dart`):** `GET /books`→`booksProvider` 가 기존
    `create_main_screen` 의 책 목록을 채움(`Book.toCover()`→BookCover; 표지는 coverImageUrl 네트워크,
    없으면 색+이모지). `GET /books/{id}`→`bookDetailProvider` 가 장면 칩을 채움. CTA 는 서버 `bookId` 와
    선택 장면의 `sceneId` 를 그대로 전송.
  - **Result→기존 화면 (신규 `models/result_adapter.dart`):** `/create` result.data 를 기존
    `ScriptLine`/`WorkContent`(+`audioUrl`/`timepoints`)로 매핑. `ai_generating_screen` 이 결과를
    디바이스 JSON(`created_data/`)과 **정규화 SQLite**(`db_service`, v3: `audio_url`/`timepoints` 컬럼
    추가) 양쪽에 저장한 뒤 `workId` 로 기존 결과 화면을 열어 실데이터 로드 → **내 서재가 창작물 History**.
  - **Audio (단일 MP3):** `tts_player.dart` 를 줄별 `/tts` 합성 → **단일 MP3(`audio.audioUrl`) 스트리밍+
    seek** 로 교체(audioplayers `UrlSource`). 기존 오디오 UI 유지: 재생/일시정지·여기부터(seek)·이 줄만
    듣기(seek+종료)·positionStream→현재 문장 하이라이트·배속.
  - **Config:** `AppConfig` 를 `--dart-define`(`BASE_URL`/`USE_MOCK`) 주입식으로, **`useMock` 기본
    false(실서버)**. 서버 계약 확인: `GET /books`·`/books/{id}`·`/create`(sceneIds/scope/ideaText) 일치.

- **2026-06-23 (b) — Backend URL/mock via `--dart-define` + cleartext config.** `AppConfig.baseUrl` and
  `AppConfig.useMock` now read `String/bool.fromEnvironment('BASE_URL'/'USE_MOCK', …)` so the
  test↔Raspberry-Pi environment is switched at run time, not by editing code. **`useMock` default
  flipped `true`→`false`** (real server by default). Added `http` cleartext allowances scoped to
  local/private networks: iOS `Info.plist` `NSAllowsLocalNetworking`; Android
  `res/xml/network_security_config.xml` (referenced from `AndroidManifest.xml`, lists localhost /
  10.0.2.2 etc. — real LAN/Pi IPs to be added there) + `INTERNET` permission in the main manifest.
  Docs: `docs/backend.md` Config/Status updated. No public-internet cleartext opened.
- **2026-06-23 — Docs split for token efficiency.** The single project guide doc was split into
  `docs/architecture.md`, `docs/backend.md`, `docs/storage.md`, `docs/screens.md`, and this
  `docs/CHANGELOG.md`. Removed duplicated statements (the sync rule, `created_data/`, the book mismatch,
  the SSE stages were each repeated across sections). Content/decisions unchanged — reorganized only.
- **2026-06-22 (b) — Create flow + storage wired (mockable).** Added `lib/core/app_config.dart`
  (`AppConfig.baseUrl` default `http://localhost:8000`, `AppConfig.useMock` default `true`;
  `appConfigProvider`), `lib/models/create_request.dart` (`CreateRequest` + enum maps + `validate()`,
  incl. `kBookIdBySource`), `lib/services/create_api.dart` (`CreateApi` streaming `CreateEvent`, real SSE
  or canned), `lib/services/creation_store.dart` (`CreationStore` over `created_data/`). Create button →
  `/create`; `ai_generating_screen` runs the SSE stages and saves `result.data` to `created_data/`;
  settings data-reset clears it. Added deps `http ^1.5.0`, `path_provider ^2.1.5` + `path ^1.9.0`,
  `shared_preferences ^2.2.0`. Result screens still render `sample_data.dart` (typed `creation_result.dart`
  + rendering = next); My Library still reads sample data (listing from `created_data/` = next). Book
  mismatch handled by a title→slug map (심청전·춘향전·해와 달 unmapped → Create blocked).
- **2026-06-22 (a) — UI/UX spec pass.** (0) `created_data/` app-private JSON store (no runtime
  permission; SQLite demoted to optional index). (1) Onboarding shows once (shared_prefs flag) and drops
  the name step; `onboarding_state` loses `nickname`. `settings_state` removes the `profile` sub-view;
  data-reset relocated to the settings root bottom. (2) Initial tab = Library (내 서재). (3) Library 원작
  section = 2×5 grid, horizontal paging when >10. (4) Tapping an 원작 book opens with 원본 보기 first.
  (5) `create_main_screen` removes the top-right alarm icon; the Create button does `POST /create` then
  drives the generating animation by SSE stages (`analysis→structure→writing→finalize`).
- **2026-06-20 — Backend integration documented.** Mapped the FastAPI endpoints (`/health`, `/books`,
  `/books/{bookId}`, `/create` SSE) and the result schema onto the create flow / result screens per the
  backend's API spec. Flagged the book-list mismatch (sample `kBooks` vs the 6 server slugs). Noted SSE progress
  (`analysis → structure → writing → finalize`) drives `ai_generating_screen` and that word explanations
  (`kVocab`) are not part of the API result. Added the docs sync rule.
- **2026-06-19 — Doc realigned to the actual codebase.** All previously "designed, pending" screens are
  implemented; added `AppShell` tab navigation (`navigation.dart`), `models/sample_data.dart`, the
  audio/dialogue/library/onboarding/create_main states, `app_bottom_nav_bar.dart` + `result_shared.dart`,
  global `AppScrollBehavior`. App entry is `ClassicTheaterApp` (pubspec name `classic_theater`).
