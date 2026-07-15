import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_config.dart';
import '../models/create_request.dart';
import '../models/result_adapter.dart';
import '../services/create_api.dart';
import '../services/creation_store.dart';
import '../services/db_service.dart';
import 'ai_generation_state.dart' show kAiStages;
import 'create_main_state.dart' show CreateMode;
import 'library_state.dart';

/// 창작 작업 상태.
enum CreationJobStatus { idle, running, done, error }

/// 백그라운드로 도는 창작 작업 상태.
/// 화면(AiGeneratingScreen)이 dispose 돼도 살아남아, 사용자가 기다리는 동안
/// 원작을 읽거나 다른 곳을 둘러봐도 생성이 계속되도록 한다.
class CreationJobState {
  const CreationJobState({
    this.status = CreationJobStatus.idle,
    this.displayStage = 0,
    this.resultReady = false,
    this.error,
    this.result,
    this.request,
    this.bookTitle = '',
    this.mode = CreateMode.dialogue,
    this.level = '청소년용',
  });

  final CreationJobStatus status;
  final int displayStage; // 화면에 보여줄 단계(0..3)
  final bool resultReady; // 서버 result 수신(진행률 100%)
  final String? error;
  final AdaptedCreation? result; // 완료 결과(결과 화면 이동·배너용)
  final CreateRequest? request;
  final String bookTitle; // 진행 화면 설정 카드/팁용
  final CreateMode mode;
  final String level;

  bool get isRunning => status == CreationJobStatus.running;
  bool get isDone => status == CreationJobStatus.done;
  bool get hasError => status == CreationJobStatus.error;

  CreationJobState copyWith({
    CreationJobStatus? status,
    int? displayStage,
    bool? resultReady,
    String? error,
    AdaptedCreation? result,
    CreateRequest? request,
    String? bookTitle,
    CreateMode? mode,
    String? level,
  }) =>
      CreationJobState(
        status: status ?? this.status,
        displayStage: displayStage ?? this.displayStage,
        resultReady: resultReady ?? this.resultReady,
        error: error ?? this.error,
        result: result ?? this.result,
        request: request ?? this.request,
        bookTitle: bookTitle ?? this.bookTitle,
        mode: mode ?? this.mode,
        level: level ?? this.level,
      );
}

/// 창작 작업 러너. SSE 구독·단계 페이싱·저장을 모두 여기서 소유한다(화면과 분리).
class CreationJobNotifier extends Notifier<CreationJobState>
    with WidgetsBindingObserver {
  StreamSubscription<CreateEvent>? _sub;
  Timer? _pacer;
  int _serverStage = 0;
  bool _serverDone = false;
  int _displayStage = 0;
  DateTime _stageEnteredAt = DateTime.now();
  AdaptedCreation? _adapted;

  /// 단계별 최소 노출 시간(ms). 분석·구성은 충분히 보여주고, 대사 쓰기는 짧게만 보장.
  static const List<int> _minStageDwellMs = [6000, 6000, 1500, 800];

  @override
  CreationJobState build() {
    // 앱이 백그라운드로 가거나 종료되는 순간을 감지하려고 생명주기를 구독한다.
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _sub?.cancel();
      _pacer?.cancel();
    });
    return const CreationJobState();
  }

  /// 앱이 백그라운드로 전환되거나 종료되면 서버 SSE 연결이 끊겨 생성이 중단된다.
  /// 결과를 아직 못 받은 진행 중 작업은 '중단됨'으로 바꿔, 돌아왔을 때 명확히 안내하고
  /// 다시 시도할 수 있게 한다. (이미 결과를 받았으면 사실상 완료이므로 건드리지 않는다)
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    final closing = lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.detached;
    if (closing && state.isRunning && !_serverDone) {
      _sub?.cancel();
      _pacer?.cancel();
      state = state.copyWith(
        status: CreationJobStatus.error,
        error: '앱을 닫는 동안 만들기가 중단됐어요. 다시 시도해 주세요.',
      );
    }
  }

  /// 새 창작 시작. [request] 로 `/create` SSE 를 구독하고 단계를 페이싱한다.
  /// [bookTitle]/[mode]/[level] 은 진행 화면·완료 배너 표시용.
  void start({
    required CreateRequest request,
    required String bookTitle,
    required CreateMode mode,
    required String level,
  }) {
    _sub?.cancel();
    _pacer?.cancel();
    _serverStage = 0;
    _serverDone = false;
    _displayStage = 0;
    _adapted = null;
    _stageEnteredAt = DateTime.now();
    state = CreationJobState(
      status: CreationJobStatus.running,
      displayStage: 0,
      request: request,
      bookTitle: bookTitle,
      mode: mode,
      level: level,
    );
    _startPacer();
    _sub = ref.read(createApiProvider).create(request).listen((ev) async {
      switch (ev) {
        case CreateProgress(:final stageIndex):
          if (stageIndex > _serverStage) _serverStage = stageIndex;
        case CreateResult(:final data):
          final adapted =
              adaptCreation(data, baseUrl: ref.read(appConfigProvider).baseUrl);
          _adapted = adapted;
          // 표지 다운로드를 기다리지 않고 작품을 곧바로 저장·표시한다. 서재는 먼저
          // creationCoverImageUrl 을 네트워크 이미지로 그리고, refresh 가 부르는
          // library_state._loadWorks 가 표지를 백그라운드 다운로드한 뒤
          // 로컬 AI 표지로 자동 교체한다(다운로드·재시도 경로 일원화).
          // created_data JSON 에는 서버가 준 원본(원격/상대 URL)을 그대로 저장한다(이식성).
          await ref.read(creationStoreProvider).save(data);
          try {
            await ref
                .read(dbServiceProvider)
                .insertWork(adapted.work, adapted.content);
            await ref.read(libraryProvider.notifier).refresh();
          } catch (_) {
            // DB 미지원 환경에서도 결과 표시는 계속.
          }
          _serverDone = true;
          _serverStage = kAiStages.length - 1;
          if (state.isRunning) state = state.copyWith(resultReady: true);
        case CreateError(:final message):
          // 결과를 이미 받아 저장했거나(_serverDone) 이미 중단 처리됐으면(!isRunning)
          // 뒤늦은 오류는 무시한다.
          if (!_serverDone && state.isRunning) {
            _pacer?.cancel();
            state =
                state.copyWith(status: CreationJobStatus.error, error: message);
          }
      }
    }, onError: (Object e) {
      // 결과 수신 후의 연결 종료(앱 백그라운드 전환 등)나 이미 중단 처리된 경우는 그대로 둔다.
      // (앱 종료로 인한 중단은 didChangeAppLifecycleState 가 더 명확한 메시지로 먼저 처리)
      if (_serverDone || !state.isRunning) return;
      _pacer?.cancel();
      state = state.copyWith(
          status: CreationJobStatus.error,
          error: '생성 중 문제가 발생했어요. 잠시 후 다시 시도해 주세요.');
    });
  }

  /// 표시 단계를 최소 노출 시간만큼 머문 뒤 다음으로 올리고, result 까지 받았으면 완료 처리.
  void _startPacer() {
    _pacer?.cancel();
    _pacer = Timer.periodic(const Duration(milliseconds: 120), (t) {
      if (state.status != CreationJobStatus.running) {
        t.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(_stageEnteredAt).inMilliseconds;
      final minDwell =
          _minStageDwellMs[_displayStage.clamp(0, _minStageDwellMs.length - 1)];

      if (_displayStage < _serverStage && elapsed >= minDwell) {
        _displayStage++;
        _stageEnteredAt = DateTime.now();
        state = state.copyWith(displayStage: _displayStage);
        return;
      }

      if (_serverDone &&
          _displayStage >= kAiStages.length - 1 &&
          elapsed >= minDwell) {
        t.cancel();
        state = state.copyWith(
          status: CreationJobStatus.done,
          displayStage: kAiStages.length - 1,
          resultReady: true,
          result: _adapted,
        );
      }
    });
  }

  /// 사용자 취소(생성 중단) — 진행 화면의 '취소'.
  void cancel() {
    _sub?.cancel();
    _pacer?.cancel();
    state = const CreationJobState();
  }

  /// 연결 끊김 등으로 실패한 뒤, 마지막 요청 그대로 생성을 다시 시도한다.
  /// (서버는 진행 중 작업을 보존하지 않으므로 처음부터 다시 생성한다)
  void retry() {
    final req = state.request;
    if (req == null) return;
    start(
      request: req,
      bookTitle: state.bookTitle,
      mode: state.mode,
      level: state.level,
    );
  }

  /// 결과 확인/배너 처리 후 idle 로 되돌린다(완료 상태 재발화 방지).
  void clear() {
    _sub?.cancel();
    _pacer?.cancel();
    state = const CreationJobState();
  }
}

/// 앱 전역에서 살아남는 창작 작업 프로바이더(화면 dispose 와 무관).
final creationJobProvider =
    NotifierProvider<CreationJobNotifier, CreationJobState>(
        CreationJobNotifier.new);
