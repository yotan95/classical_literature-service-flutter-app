# Architecture — structure, navigation, state

> Owned by this doc: the directory tree, app entry/handoff, navigation, and Riverpod providers.
> Update here when any of those change (and append `docs/CHANGELOG.md`). Backend / storage / screens
> have their own docs.

## Directory tree
```
lib/
├─ main.dart                 # Entry: ClassicTheaterApp (M3 theme, AppScrollBehavior, home = Onboarding-once | AppShell)
├─ core/
│  └─ app_config.dart        # AppConfig (baseUrl, useMock) + appConfigProvider     → docs/backend.md
├─ fragments/                # screen widgets (roles/behavior → docs/screens.md)
│  ├─ app_shell.dart            # IndexedStack of 3 tabs + AppBottomNavBar (initial tab = Library)
│  ├─ onboarding_screen.dart    # intro, shown once; no name step → AppShell
│  ├─ create_main_screen.dart   # 창작하기: pick book/mode/level/range/idea → POST /create (no alarm icon)
│  ├─ ai_generating_screen.dart # /create SSE stages → save to created_data/ → push result
│  ├─ dialogue_result_screen.dart # 대사극: 대본 / 역할 읽기 / 원작 정보 + vocab sheet
│  ├─ audio_result_screen.dart  # 오디오극: waveform player + line highlight
│  ├─ library_screen.dart       # 내 서재 (first screen): 원작 2×5 paged grid + shelf
│  └─ settings_screen.dart      # 설정: SettingsView sub-views; data-reset pinned at bottom
├─ models/
│  ├─ sample_data.dart       # static demo: ScriptLine, VocabEntry, CreativeWork, kScriptEasy/Classical,
│  │                         #   kVocab, kSampleWorks, kWorkingTitles, kBookTips, bookColor/Emoji, formatDate
│  └─ create_request.dart    # CreateRequest + enum maps + validate()               → docs/backend.md
├─ services/
│  ├─ create_api.dart        # CreateApi: streams CreateEvent (SSE or mock)         → docs/backend.md
│  └─ creation_store.dart    # CreationStore: created_data/ JSON CRUD               → docs/storage.md
├─ state/                    # Freezed state + Riverpod providers (+ generated *.freezed.dart)
│  ├─ navigation.dart           # selectedTabProvider (default = Library), createScrollTopProvider (no Freezed)
│  ├─ onboarding_state.dart     # onboardingProvider (no nickname; purpose/level only)
│  ├─ create_main_state.dart    # createMainProvider + CreateMode/RangeMode + kBooks/kModes/kLevels/kIdeaChips/kScenes
│  ├─ ai_generation_state.dart  # aiGenerationProvider
│  ├─ dialogue_result_state.dart# dialogueResultProvider
│  ├─ audio_result_state.dart   # audioResultProvider
│  ├─ library_state.dart        # libraryProvider (+ groupBySource)
│  └─ settings_state.dart       # settingsProvider + SettingsView enum (no profile; reset at root bottom)
├─ theme/app_colors.dart     # color tokens (single source; sage #3D8A65 fixed)
└─ widgets/
   ├─ app_bottom_nav_bar.dart   # AppBottomNavBar (real bottom tab bar used by AppShell)
   ├─ result_shared.dart        # CharBadge, TagChip, ResultNavBar, ResultTitleSection, LineActionMenu
   └─ phone_shell.dart          # preview-only chrome (PhoneShell, AppBottomTabBar) + NavBackButton
```
Runtime data lives outside the repo at `<app-docs>/created_data/` (app-private; see `docs/storage.md`).
Planned folders/data: `data/` or `assets/data/` (classic JSON bundles); `sqflite` index over the JSON store.

## App entry & navigation
- `main()` → `ProviderScope` → `ClassicTheaterApp` (`main.dart`).
- **Onboarding once:** if the `shared_preferences` "onboarding seen" flag is unset, `home =
  OnboardingScreen`; on finish (flag set) it replaces with `AppShell`. Every later launch goes straight
  to `AppShell` — onboarding never shows again. Onboarding has **no name-input step** and sets no
  nickname (short intro + purpose/level only).
- `AppShell` (`fragments/app_shell.dart`) = `IndexedStack` of the 3 main tabs + `AppBottomNavBar`,
  driven by `selectedTabProvider`, using the real device status bar (not the preview phone shell).
  Tab 0 `CreateMainScreen` 창작하기 / 1 `LibraryScreen` 내 서재 / 2 `SettingsScreen` 설정.
  **Initial index = Library (내 서재)** — only the default index changes; nav-bar order is unchanged.
- `AiGeneratingScreen` and the result screens are pushed via `Navigator` on top of the shell (not tabs).

## State (Riverpod)
All in `lib/state/`; mostly `@freezed` state + `NotifierProvider` (`navigation.dart` holds two plain
`int` notifiers).

- `selectedTabProvider` — current main tab (0 create / 1 library / 2 settings); **default = Library (1)**.
- `createScrollTopProvider` — tick signal to scroll 창작하기 to top when its tab is re-tapped.
- `onboardingProvider` — purpose/level only (**no `nickname` field**).
- `settingsProvider` — `SettingsView` enum **without `profile`**; the data-reset action sits at the
  settings root bottom and calls `CreationStore.clear()` (see `docs/storage.md`).
- `createMainProvider`, `aiGenerationProvider`, `dialogueResultProvider`, `audioResultProvider`,
  `libraryProvider`.
- **Cross-provider:** `createMainProvider` watches `settingsProvider.select((s) => s.level)` so the
  default reading level (→ `/create` `difficulty`) follows Settings.
