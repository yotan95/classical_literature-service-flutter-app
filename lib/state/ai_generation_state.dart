import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'ai_generation_state.freezed.dart';

/// 생성 단계 메타데이터(불변).
class AiStage {
  const AiStage(this.progress, this.message, this.emoji, {this.warn = false});
  final int progress;
  final String message;
  final String emoji;
  final bool warn;
}

/// 화면에 보여줄 4단계. 인덱스는 `/create` SSE 의 stage 순서
/// (analysis → structure → writing → finalize)와 1:1 대응한다.
const List<AiStage> kAiStages = [
  AiStage(18, '원작을 꼼꼼히 읽고 있어요...', '📖'),
  AiStage(38, '인물과 장면을 구성하고 있어요...', '🧩'),
  AiStage(62, '대사를 한 줄씩 써 내려가고 있어요...', '📜'),
  AiStage(90, '거의 다 됐어요! ✨ 마무리하고 있어요', '🎭', warn: true),
];

const List<String> kStepLabels = ['원작 읽기', '구성', '대사 쓰기', '마무리'];

/// 생성 화면 상태. SSE 이벤트(create_api)에 의해 외부에서 갱신된다.
@freezed
class AiGenerationState with _$AiGenerationState {
  const AiGenerationState._();

  const factory AiGenerationState({
    @Default(0) int stage, // 현재 단계 인덱스(0..3)
    @Default(false) bool done, // result 수신 완료
    String? error, // error 이벤트 메시지(있으면 실패)
  }) = _AiGenerationState;

  AiStage get current => kAiStages[stage.clamp(0, kAiStages.length - 1)];
  bool get isLastStage => stage >= kAiStages.length - 1;
  bool get hasError => error != null;
}

/// 생성 진행 상태 노티파이어.
/// 단계 진행/완료/오류는 `/create` 스트림을 듣는 화면이 호출한다(고정 타이머 아님).
class AiGenerationNotifier extends Notifier<AiGenerationState> {
  @override
  AiGenerationState build() => const AiGenerationState();

  /// 새 생성 시작 — 처음 단계부터.
  void reset() => state = const AiGenerationState();

  /// SSE progress 이벤트로 현재 단계를 갱신(범위 클램프).
  void setStage(int s) {
    if (state.hasError) return;
    state = state.copyWith(stage: s.clamp(0, kAiStages.length - 1));
  }

  /// result 수신 — 완료 표시(마지막 단계로 고정).
  void markDone() =>
      state = state.copyWith(done: true, stage: kAiStages.length - 1);

  /// error 수신 — 실패 메시지 표시(진행 중단).
  void setError(String message) => state = state.copyWith(error: message);
}

final aiGenerationProvider =
    NotifierProvider<AiGenerationNotifier, AiGenerationState>(
        AiGenerationNotifier.new);

/// 생성 흐름 결과.
/// [workId] 가 있으면 로컬 DB 에 저장된 새 창작물 id(결과 화면이 이걸로 로드),
/// null 이면 서버 호출 실패로 샘플 대본을 보여 주는 폴백 상태.
typedef GenerationOutcome = ({String? workId, bool fallback});

/// 생성 중 화면 → 결과 화면으로 결과를 전달하는 전역 상태.
final lastGenerationProvider = StateProvider<GenerationOutcome?>((ref) => null);
