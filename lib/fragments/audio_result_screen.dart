import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sample_data.dart';
import '../state/audio_result_state.dart';
import '../state/library_state.dart' show libraryProvider;
import '../theme/app_colors.dart';
import '../widgets/result_shared.dart';

/// 오디오극 결과 화면.
/// 상단 오디오 플레이어(웨이브폼·배속) + 대사 목록(현재 줄 하이라이트).
/// 대사 줄을 탭하면 `여기부터 듣기 / 이 줄만 듣기 / AI로 수정` 3가지 액션만 제공한다(기획서 5-3).
class AudioResultScreen extends ConsumerStatefulWidget {
  const AudioResultScreen(
      {super.key, this.workId, this.title, this.source, this.level});

  /// 로컬 DB 창작물 id. 있으면 DB 에서 제목·대본을 로드한다(null 이면 샘플).
  final String? workId;

  /// 내 서재에서 열 때 넘겨받는 창작물 정보 (null 이면 기본 샘플).
  final String? title;
  final String? source;
  final String? level;

  @override
  ConsumerState<AudioResultScreen> createState() => _AudioResultScreenState();
}

class _AudioResultScreenState extends ConsumerState<AudioResultScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// 재생 중 이퀄라이저 막대 애니메이션.
  late final AnimationController _eq =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat();

  /// 오디오 노티파이어 인스턴스를 initState 에서 잡아 둔다.
  /// dispose 시점엔 위젯 ref 가 이미 무효(defunct)라 `ref.read` 가
  /// 'Cannot use ref after disposed' 예외를 던지는데, 그 예외가 unmount 를 중단시켜
  /// provider 구독이 안 닫히면(누수) 재생이 안 멈추고 포지션 스트림이 defunct Element 에
  /// markNeedsBuild 를 무한 호출한다. 전역 provider 라 notifier 인스턴스는 안정적이므로
  /// 미리 캐시해 두고 dispose/라이프사이클에서 ref 없이 직접 호출한다.
  late final AudioResultNotifier _audio;

  @override
  void initState() {
    super.initState();
    // 앱 라이프사이클 감지(백그라운드 전환·화면 잠금 시 재생 일시정지).
    WidgetsBinding.instance.addObserver(this);
    _audio = ref.read(audioResultProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return; // 프레임 전에 화면을 떠났으면 로드 생략
      _audio.load(
          workId: widget.workId,
          title: widget.title,
          source: widget.source,
          level: widget.level);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 뒤로 가기 등 화면을 떠날 때: 재생 중지 + 현재 위치 저장(다음에 그 시점부터).
    // audioResultProvider 는 전역이라 화면 pop 으로 자동 dispose 되지 않으므로 직접 멈춘다.
    // ⚠️ 여기서 ref.read 를 쓰면 안 된다(위 _audio 주석 참고) — 캐시해 둔 _audio 로 호출.
    // updateState:false — 이 시점 Element 는 defunct 라 state 를 바꾸면 markNeedsBuild assert.
    _audio.stopAndPersist(updateState: false);
    _eq.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // 앱이 백그라운드로 가거나 화면이 잠기면(paused/hidden) 재생을 멈추고 위치를 저장한다.
    // 미디어 알림/백그라운드 재생을 지원하지 않으므로 화면이 안 보일 때 계속 재생하지 않는다.
    // (inactive 는 알림센터·앱 전환 미리보기 등 일시적 상황이라 제외 — 잠금/백그라운드는 paused 로 도달)
    if (!mounted) return;
    if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden) {
      _audio.stopAndPersist();
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(audioResultProvider);
    final n = _audio;

    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      body: SafeArea(
        child: Column(
          children: [
            ResultNavBar(onMore: _showMoreMenu),
            ResultTitleSection(
              title: st.title,
              source: st.source,
              sourceColor: bookColor(st.source),
              mode: '오디오극',
              level: st.level,
              onEditTitle: () => _showTitleEdit(st.title, n),
            ),
            // 재생바는 상단에 고정 — 대사 목록을 스크롤해도 항상 보인다.
            _PlayerCard(
                st: st,
                n: n,
                eq: _eq,
                onPlayPause: () => _safePlay(n.togglePlay)),
            const SizedBox(height: 8),
            Expanded(
              // 줄 액션 메뉴(여기부터 듣기 등)가 열려 있을 때 다른 빈 곳을 누르면 닫는다.
              // translucent + onTap 이라, 줄·메뉴 버튼 탭은 각자의 제스처가
              // 먼저 가져가고(닫힘 처리 안 함) 빈 곳 탭만 여기서 처리된다.
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: st.selectedLine != null ? n.closeMenu : null,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _lineList(st, n),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 대사 목록 ──
  Widget _lineList(AudioResultState st, AudioResultNotifier n) {
    // 작품 단위로 인물마다 겹치지 않는 색을 미리 배정한다.
    final colors = AppColors.characterColors(st.lines.map((l) => l.char));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in st.lines) ...[
          // 장면 헤더 (해당 장면의 첫 줄 앞에 표시)
          if (st.lines.indexOf(line) ==
              st.lines.indexWhere((l) => l.scene == line.scene))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Text(
                '장면 ${line.scene} · ${st.scenes[line.scene] ?? ''}',
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: AppColors.textMuted),
              ),
            ),
          _AudioLineTile(
              line: line,
              st: st,
              n: n,
              colors: colors,
              // 줄 탭 재생도 _safePlay 로 감싼다 — 스트리밍 seek 실패 시
              // 미처리 예외(크래시) 대신 안내 스낵바가 뜨도록.
              onPlayFrom: (id) => _safePlay(() => n.playFrom(id))),
          if (st.selectedLine == line.id)
            LineActionMenu(actions: [
              ('▶', '여기부터 듣기', AppColors.ink,
                  () => _safePlay(() => n.playFrom(line.id))),
              ('🔁', '이 줄만 듣기', AppColors.ink,
                  () => _safePlay(() => n.playLineOnly(line.id))),
            ]),
        ],
      ],
    );
  }

  void _showTitleEdit(String title, AudioResultNotifier n) {
    final controller = TextEditingController(text: title);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('제목 수정',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(hintText: '제목을 입력해 주세요'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () {
              n.setTitle(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('저장',
                style: TextStyle(color: AppColors.sage, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _demoSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// ··· 더보기: 삭제하기.
  void _showMoreMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  size: 22, color: AppColors.danger),
              title: const Text('삭제하기',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 창작물 삭제 — 확인 후 서재에서 지우고 이전 화면(서재)으로 돌아간다.
  void _confirmDelete() {
    final st = ref.read(audioResultProvider);
    final id = st.workId;
    if (id == null) {
      _demoSnack('저장된 작품이 아니라 삭제할 수 없어요');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('작품 삭제',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('《${st.title}》을(를) 삭제할까요?\n삭제한 작품은 되돌릴 수 없어요.',
            style: const TextStyle(fontSize: 13.5, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () {
              ref.read(libraryProvider.notifier).removeWork(id);
              Navigator.pop(ctx); // 다이얼로그 닫기
              Navigator.of(context).maybePop(); // 결과 화면 닫기 → 서재로
            },
            child: const Text('삭제',
                style: TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// 재생 동작을 실행하고, 서버 미연결 등 실패 시 안내한다.
  Future<void> _safePlay(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('서버에 연결할 수 없어 음성을 재생할 수 없어요')));
    }
  }
}

// ── 오디오 플레이어 카드 ─────────────────────────────────

class _PlayerCard extends StatelessWidget {
  const _PlayerCard(
      {required this.st,
      required this.n,
      required this.eq,
      required this.onPlayPause});

  final AudioResultState st;
  final AudioResultNotifier n;
  final AnimationController eq;
  final VoidCallback onPlayPause;

  @override
  Widget build(BuildContext context) {
    final curr = st.lines.where((l) => l.id == st.currentLine).firstOrNull;
    final colors = AppColors.characterColors(st.lines.map((l) => l.char));

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.alpha(AppColors.sage, 0x1E),
            AppColors.alpha(AppColors.sage, 0x08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.alpha(AppColors.sage, 0x30), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 현재 화자 + 이퀄라이저
          Row(
            children: [
              if (curr != null && !curr.isNarration) ...[
                CharBadge(char: curr.char!, color: colors[curr.char]),
                const SizedBox(width: 8),
                const Text('말하는 중',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDEAE5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('내레이션',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSub)),
                ),
                const SizedBox(width: 8),
                const Text('읽는 중',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
              const Spacer(),
              _equalizer(),
            ],
          ),
          const SizedBox(height: 14),
          // 웨이브폼 = 시크바: 터치/드래그로 원하는 위치에서 재생.
          LayoutBuilder(
            builder: (context, c) {
              final frac = st.totalMs > 0
                  ? (st.positionMs / st.totalMs).clamp(0.0, 1.0)
                  : 0.0;
              void seekAt(double dx) =>
                  n.seekToFraction((dx / c.maxWidth).clamp(0.0, 1.0));
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => seekAt(d.localPosition.dx),
                onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
                child: SizedBox(
                  height: 32,
                  width: double.infinity,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _WaveformPainter(progress: frac),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 5),
          // 시간 (실제 재생 위치 / 전체 길이)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmtMs(st.positionMs),
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.sage)),
              Text(_fmtMs(st.totalMs),
                  style: const TextStyle(fontSize: 10, color: Color(0xFFCCCCCC))),
            ],
          ),
          const SizedBox(height: 14),
          // 컨트롤: ←10 / 재생 / 10→
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _skipButton(back: true, onTap: () => n.skip(-10)),
              const SizedBox(width: 22),
              GestureDetector(
                onTap: onPlayPause,
                child: Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.sage,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.alpha(AppColors.sage, 0x55),
                          blurRadius: 20,
                          offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Icon(st.playing ? Icons.pause : Icons.play_arrow,
                      size: 26, color: Colors.white),
                ),
              ),
              const SizedBox(width: 22),
              _skipButton(back: false, onTap: () => n.skip(10)),
            ],
          ),
          const SizedBox(height: 14),
          // 재생 속도 (기획서: 0.8x / 1.0x / 1.2x)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final s in const [0.8, 1.0, 1.2]) ...[
                GestureDetector(
                  onTap: () => n.setSpeed(s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: st.speed == s ? AppColors.sage : const Color(0x80FFFFFF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: st.speed == s
                              ? AppColors.sage
                              : const Color(0x14000000)),
                    ),
                    child: Text('${s}x',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: st.speed == s ? Colors.white : AppColors.textSub)),
                  ),
                ),
                if (s != 1.2) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 재생 중일 때만 흔들리는 이퀄라이저 막대 5개.
  Widget _equalizer() {
    const heights = [10.0, 16.0, 12.0, 8.0, 14.0];
    return SizedBox(
      height: 16,
      child: AnimatedBuilder(
        animation: eq,
        builder: (context, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (int i = 0; i < heights.length; i++) ...[
              Container(
                width: 3,
                height: st.playing
                    ? 4 +
                        (heights[i] - 4) *
                            (0.5 + 0.5 * math.sin(eq.value * 2 * math.pi + i * 1.3))
                    : 4,
                decoration: BoxDecoration(
                  color: AppColors.sage
                      .withValues(alpha: st.playing ? 0.8 : 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (i < heights.length - 1) const SizedBox(width: 3),
            ],
          ],
        ),
      ),
    );
  }

  Widget _skipButton({required bool back, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x99FFFFFF),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x12000000)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (back)
              const Icon(Icons.fast_rewind, size: 14, color: Color(0xFF555555)),
            Text('10',
                style: const TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF555555))),
            if (!back)
              const Icon(Icons.fast_forward, size: 14, color: Color(0xFF555555)),
          ],
        ),
      ),
    );
  }
}

/// ms → "m:ss" 표기.
String _fmtMs(int ms) {
  final totalSec = (ms / 1000).floor();
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// 웨이브폼 막대. [progress] 이전 막대는 sage, 이후는 회색.
class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final n = kWaveHeights.length;
    final slot = size.width / n;
    final barW = slot * 0.7;
    for (int i = 0; i < n; i++) {
      final h = kWaveHeights[i] * 2.2;
      final filled = i / n < progress;
      final paint = Paint()
        ..color = filled
            ? AppColors.sage
            : const Color(0xFFE0E0E0).withValues(alpha: 0.55);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * slot + (slot - barW) / 2, (size.height - h) / 2, barW, h),
          Radius.circular(barW / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ── 대사 줄 ─────────────────────────────────────────────

class _AudioLineTile extends StatelessWidget {
  const _AudioLineTile(
      {required this.line,
      required this.st,
      required this.n,
      required this.onPlayFrom,
      this.colors});

  final ScriptLine line;
  final AudioResultState st;
  final AudioResultNotifier n;
  // 줄 탭 = 여기부터 재생. 호출 측에서 _safePlay 로 감싼 핸들러를 넘긴다.
  final void Function(int id) onPlayFrom;
  // 작품 단위로 인물마다 겹치지 않게 배정한 색 맵(_lineList 에서 한 번 만들어 전달).
  final Map<String, ({Color bg, Color fg})>? colors;

  @override
  Widget build(BuildContext context) {
    final isPlaying = line.id == st.currentLine;

    if (line.isNarration) {
      // 탭 = 이 구절부터 재생(seek). 꾹 누르면 액션 메뉴.
      return GestureDetector(
        onLongPress: () => n.selectLine(line.id),
        onTap: () =>
            st.selectedLine != null ? n.closeMenu() : onPlayFrom(line.id),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isPlaying
                ? AppColors.alpha(AppColors.sage, 0x10)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                  color: isPlaying ? AppColors.sage : Colors.transparent,
                  width: 3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 14,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(
                  color: isPlaying ? AppColors.sage : const Color(0xFFCECECE),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(line.text,
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        fontStyle: FontStyle.italic,
                        color: isPlaying ? AppColors.ink : AppColors.textSub)),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      // 탭 = 이 구절부터 재생(seek). 꾹 누르면 액션 메뉴.
      onLongPress: () => n.selectLine(line.id),
      onTap: () =>
          st.selectedLine != null ? n.closeMenu() : onPlayFrom(line.id),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isPlaying ? AppColors.alpha(AppColors.sage, 0x10) : Colors.transparent,
          border: Border(
            left: BorderSide(
                color: isPlaying ? AppColors.sage : Colors.transparent, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isPlaying) ...[
                  // 재생 중 표시 막대
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final h in const [8.0, 12.0, 6.0]) ...[
                        Container(
                          width: 2.5,
                          height: h,
                          margin: const EdgeInsets.only(right: 2),
                          decoration: BoxDecoration(
                            color: AppColors.sage,
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 4),
                ],
                CharBadge(char: line.char!, color: colors?[line.char]),
                // 지문(mood)이 없거나 null 로 들어오면 '(null)' 대신 아예 표시하지 않는다.
                if (hasMood(line.mood)) ...[
                  const SizedBox(width: 7),
                  Text('(${line.mood})',
                      style: const TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: Color(0xFFCCCCCC))),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(line.text,
                  style: TextStyle(
                      fontSize: isPlaying ? 14 : 13,
                      height: 1.65,
                      fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w400,
                      color: isPlaying ? AppColors.ink : const Color(0xFF555555))),
            ),
          ],
        ),
      ),
    );
  }
}
