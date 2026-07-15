import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_keys.dart';
import '../models/create_request.dart';
import '../models/sample_data.dart';
import '../theme/app_colors.dart';
import '../state/ai_generation_state.dart';
import '../state/create_main_state.dart';
import '../state/creation_job.dart';
import '../state/navigation.dart';
import 'audio_result_screen.dart';
import 'dialogue_result_screen.dart';
import 'original_read_screen.dart';

/// 완료된 창작 결과 화면을 연다(진행 화면의 '보러가기' · 완료 배너 공용).
/// 결과를 한 번 소비하면 작업 상태를 비워(idle) 중복 처리를 막는다.
void openCreationResult(WidgetRef ref) {
  appMessengerKey.currentState?.hideCurrentSnackBar(); // 완료 알림 스낵바가 떠 있으면 먼저 닫는다.
  final st = ref.read(creationJobProvider);
  final a = st.result;
  final nav = appNavigatorKey.currentState;
  if (a == null || nav == null) return; // 이미 결과를 본 뒤(소비됨)면 스낵바만 닫고 종료.
  ref.read(creationJobProvider.notifier).clear();
  nav.popUntil((r) => r.isFirst); // 진행/원작 읽기 화면을 모두 닫고
  nav.push(MaterialPageRoute<void>( // 결과 화면을 앱 셸 위에 올린다.
    builder: (_) => a.work.mode == CreateMode.dialogue
        ? DialogueResultScreen(
            workId: a.work.id,
            title: a.work.title,
            source: a.work.source,
            level: a.work.level)
        : AudioResultScreen(
            workId: a.work.id,
            title: a.work.title,
            source: a.work.source,
            level: a.work.level),
  ));
}

/// AI 생성 중 화면. 실제 생성은 [creationJobProvider] 가 백그라운드로 진행하며,
/// 이 화면은 진행 상태를 "관찰"만 한다(화면을 떠나도 생성은 계속됨).
/// 기다리는 동안 원작 읽기 · 둘러보기(백그라운드로 두기)를 제공하고,
/// 완료되면 '보러가기'로 결과 화면을 연다.
/// 특정 단계를 고정 표시하려면 [fixedStage] 지정(데모/디자인 확인용, 작업 미시작).
class AiGeneratingScreen extends ConsumerStatefulWidget {
  const AiGeneratingScreen({super.key, this.request, this.fixedStage});

  /// 창작 요청. 있으면 진입 시 작업을 시작한다(배너로 재진입 시엔 null=관찰 전용).
  final CreateRequest? request;
  final int? fixedStage;

  @override
  ConsumerState<AiGeneratingScreen> createState() => _AiGeneratingScreenState();
}

class _AiGeneratingScreenState extends ConsumerState<AiGeneratingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
        ..repeat();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2300))
        ..repeat();
  late final AnimationController _float =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
        ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    // request 가 있으면(=CTA 진입) 백그라운드 작업을 시작한다.
    // 배너로 재진입(request==null)하거나 데모(fixedStage)면 시작하지 않고 관찰만 한다.
    if (widget.fixedStage == null && widget.request != null) {
      final cm = ref.read(createMainProvider);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(creationJobProvider.notifier).start(
              request: widget.request!,
              bookTitle: cm.book,
              mode: cm.mode,
              level: cm.level,
            );
        // 작업이 선택값을 가져간 뒤, 창작 폼을 기본값으로 초기화한다.
        // (이 화면 표시는 job 상태를 쓰므로 영향 없음 — 창작 탭으로 돌아가면 새 폼)
        ref.read(createMainProvider.notifier).reset();
        ref.read(createScrollTopProvider.notifier).requestTop();
        ref.read(createBookScrollStartProvider.notifier).requestStart();
      });
    }
  }

  @override
  void dispose() {
    // 작업은 프로바이더가 소유하므로 화면을 떠나도 멈추지 않는다(애니메이션만 정리).
    _spin.dispose();
    _pulse.dispose();
    _float.dispose();
    super.dispose();
  }

  /// 둘러보기: 작업은 멈추지 않고 앱 셸로 돌아간다. 돌아갈 때 창작 폼을 초기화해
  /// 창작 탭이 새 폼(기본 읽기 수준·첫 원작·빈 입력)으로 보이게 한다.
  void _browseAway() {
    ref.read(createMainProvider.notifier).reset();
    ref.read(createScrollTopProvider.notifier).requestTop();
    ref.read(createBookScrollStartProvider.notifier).requestStart();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(creationJobProvider);
    final cm = ref.watch(createMainProvider);
    final demo = widget.fixedStage != null;

    // 생성 화면에서 기다리는 동안 완성되면 버튼 없이 바로 결과 화면으로 넘어간다.
    // (둘러보기로 빠져나가 이 화면이 dispose 된 경우엔 발화하지 않고 셸 배너/알림이 안내)
    ref.listen<CreationJobState>(creationJobProvider, (prev, next) {
      if (demo) return;
      final justDone = prev?.status != CreationJobStatus.done &&
          next.status == CreationJobStatus.done &&
          next.result != null;
      if (!justDone) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openCreationResult(ref);
      });
    });

    // 오류 발생 시 전용 화면(결과로 이동하지 않음).
    if (!demo && job.hasError) {
      return _errorScreen(job.error ?? '생성 중 문제가 발생했어요.');
    }

    // 표시 정보: 데모면 현재 선택값, 아니면 작업 상태에서.
    final book = demo ? cm.book : (job.bookTitle.isEmpty ? cm.book : job.bookTitle);
    final mode = demo ? cm.mode : job.mode;
    final level = demo ? cm.level : job.level;

    final stage = widget.fixedStage ?? job.displayStage;
    final s = kAiStages[stage.clamp(0, kAiStages.length - 1)];
    final done = !demo && job.isDone;
    final progress = (done || (!demo && job.resultReady)) ? 100 : s.progress;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _navBar(),
            _progressBar(progress),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _settingsCard(book, mode, level),
                    _stepper(stage),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                      child: Text(
                        done ? '작품이 완성됐어요! 🎉' : s.message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              (done || s.warn) ? FontWeight.w600 : FontWeight.w400,
                          color: (done || s.warn)
                              ? const Color(0xFF555555)
                              : AppColors.textSub,
                        ),
                      ),
                    ),
                    _floatingIcon(done ? '🎉' : s.emoji),
                    _tipCard(book),
                    if (done)
                      _viewResultButton()
                    else ...[
                      if (!demo) _waitActions(book),
                      if (!demo) _appCloseHint(),
                      if (s.warn) _cancelWarn(),
                      _cancelButton(muted: s.warn),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 생성 실패 화면.
  Widget _errorScreen(String message) => Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Column(
            children: [
              _navBar(),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('😢', style: TextStyle(fontSize: 44)),
                        const SizedBox(height: 14),
                        const Text('만들기에 실패했어요',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink)),
                        const SizedBox(height: 8),
                        Text(message,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 13,
                                height: 1.6,
                                color: AppColors.textSub)),
                        const SizedBox(height: 22),
                        // 같은 요청으로 다시 생성(연결 끊김 후 복구용).
                        GestureDetector(
                          onTap: () =>
                              ref.read(creationJobProvider.notifier).retry(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.sage,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Text('다시 시도',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () {
                            ref.read(creationJobProvider.notifier).clear();
                            Navigator.of(context).maybePop();
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Text('돌아가기',
                                style: TextStyle(
                                    fontSize: 13, color: AppColors.textSub)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _navBar() => Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text('만드는 중...',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
            ),
            // 둘러보기: 작업을 멈추지 않고 앱 셸로 돌아간다(완료되면 알림).
            GestureDetector(
              onTap: _browseAway,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text('둘러보기',
                    style: TextStyle(fontSize: 13, color: AppColors.sage)),
              ),
            ),
          ],
        ),
      );

  Widget _progressBar(int progress) => Container(
        height: 3,
        color: const Color(0xFFF0F0F0),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: progress / 100,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.sage,
              borderRadius: BorderRadius.only(
                  topRight: Radius.circular(1.5), bottomRight: Radius.circular(1.5)),
            ),
          ),
        ),
      );

  Widget _settingsCard(String book, CreateMode mode, String level) => Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.alpha(AppColors.sage, 0x0E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.alpha(AppColors.sage, 0x22)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.alpha(AppColors.src, 0x25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('📖', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kWorkingTitles[book] ?? '새 작품',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 3),
                  Row(children: [
                    _chip(book, AppColors.alpha(bookColor(book), 0x22),
                        bookColor(book)),
                    const SizedBox(width: 5),
                    _chip(mode == CreateMode.dialogue ? '대사극' : '오디오극',
                        AppColors.alpha(AppColors.sage, 0x20), AppColors.sage),
                    const SizedBox(width: 5),
                    _chip(levelDisplayLabel(level), const Color(0xFFEFEFEF),
                        const Color(0xFF777777)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _chip(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: fg)),
      );

  Widget _stepper(int active) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < kStepLabels.length; i++) ...[
              Expanded(child: _stepItem(i, active)),
              if (i < kStepLabels.length - 1)
                Container(
                  margin: const EdgeInsets.only(top: 11),
                  width: 18,
                  height: 1.5,
                  color: i < active ? AppColors.sage : const Color(0xFFE8E8E8),
                ),
            ],
          ],
        ),
      );

  Widget _stepItem(int i, int active) {
    final done = i < active;
    final isAct = i == active;
    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done
                ? AppColors.sage
                : isAct
                    ? const Color(0xFFFFFFFF)
                    : const Color(0xFFF0F0F0),
            shape: BoxShape.circle,
            border: isAct
                ? Border.all(color: AppColors.sage, width: 2)
                : done
                    ? null
                    : Border.all(color: const Color(0xFFE4E4E4), width: 2),
            boxShadow: isAct
                ? [
                    BoxShadow(
                        color: AppColors.alpha(AppColors.sage, 0x45),
                        blurRadius: 10,
                        offset: const Offset(0, 2))
                  ]
                : null,
          ),
          child: done
              ? const Icon(Icons.check, size: 13, color: Color(0xFFFFFFFF))
              : isAct
                  ? RotationTransition(
                      turns: _spin,
                      child: const SizedBox(
                        width: 11,
                        height: 11,
                        child: CustomPaint(painter: _ArcSpinnerPainter()),
                      ),
                    )
                  : Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: Color(0xFFCCCCCC), shape: BoxShape.circle)),
        ),
        const SizedBox(height: 4),
        Text(
          kStepLabels[i],
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9,
            height: 1.3,
            fontWeight: isAct ? FontWeight.w700 : FontWeight.w400,
            color: isAct
                ? AppColors.sage
                : done
                    ? const Color(0xFF888888)
                    : AppColors.textFaint,
          ),
        ),
      ],
    );
  }

  Widget _floatingIcon(String emoji) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
        child: SizedBox(
          width: 130,
          height: 118,
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulse, _float]),
            builder: (context, _) {
              final p = _pulse.value;
              final ring = (p < 0.5 ? p : 1 - p) * 2; // 0..1..0
              final dy = (_float.value - 0.5) * 16; // -8..8
              return Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: 0.30 + 0.30 * ring,
                    child: Transform.scale(
                      scale: 1 + 0.14 * ring,
                      child: _ring(86, 2),
                    ),
                  ),
                  Opacity(
                    opacity: 0.15 + 0.20 * ring,
                    child: Transform.scale(
                      scale: 1 + 0.11 * ring,
                      child: _ring(112, 1.5),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(0, dy),
                    child: Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.sage,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.alpha(AppColors.sage, 0x66),
                              blurRadius: 32,
                              offset: const Offset(0, 10)),
                        ],
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 30)),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );

  Widget _ring(double size, double w) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.sage, width: w),
        ),
      );

  Widget _tipCard(String book) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.alpha(AppColors.sage, 0x0C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.alpha(AppColors.sage, 0x20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('원작 노트',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppColors.sage)),
            const SizedBox(height: 6),
            Text(
              kBookTips[book] ?? '고른 원작에서 새로운 이야기를 엮고 있어요.',
              style: const TextStyle(
                  fontSize: 12, height: 1.75, color: Color(0xFF555555)),
            ),
          ],
        ),
      );

  /// 기다리는 동안 할 수 있는 일: 원작 읽기 / 둘러보기(백그라운드로 두기).
  Widget _waitActions(String book) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: _outlinedAction('📖  원작 읽기', () {
                Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => OriginalReadScreen(source: book)));
              }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _outlinedAction('🔎  둘러보기', _browseAway),
            ),
          ],
        ),
      );

  /// 앱을 끄면 서버 연결(SSE)이 끊겨 만들기가 중단된다는 사전 안내.
  Widget _appCloseHint() => const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('📴', style: TextStyle(fontSize: 12)),
            SizedBox(width: 6),
            Flexible(
              child: Text('앱을 끄면 창작이 중단돼요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSub)),
            ),
          ],
        ),
      );

  Widget _outlinedAction(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.alpha(AppColors.sage, 0x0C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.alpha(AppColors.sage, 0x40), width: 1.5),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.sage)),
        ),
      );

  /// 완료 시: 결과 화면으로 이동.
  Widget _viewResultButton() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: GestureDetector(
          onTap: () => openCreationResult(ref),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.sage,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: AppColors.alpha(AppColors.sage, 0x55),
                    blurRadius: 24,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: const Text('완성작 보기 →',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      );

  Widget _cancelWarn() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.warnBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.warnBorder),
          ),
          child: Row(children: const [
            Text('⚠️', style: TextStyle(fontSize: 14)),
            SizedBox(width: 8),
            Text('지금 그만두면 만들던 작품이 사라져요',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.warnText)),
          ]),
        ),
      );

  Widget _cancelButton({required bool muted}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: GestureDetector(
          onTap: () {
            ref.read(creationJobProvider.notifier).cancel();
            Navigator.of(context).maybePop();
          },
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border, width: 1.5),
            ),
            child: Text('그만두기',
                style: TextStyle(
                    fontSize: 14,
                    color: muted ? const Color(0xFFD0D0D0) : AppColors.textFaint)),
          ),
        ),
      );
}

/// 위쪽이 트인 호(arc) 스피너. (Material 의존 없이 직접 그림)
class _ArcSpinnerPainter extends CustomPainter {
  const _ArcSpinnerPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.sage
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    canvas.drawArc(rect.deflate(1), -math.pi / 2, math.pi * 1.5, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
