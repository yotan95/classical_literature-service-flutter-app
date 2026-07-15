import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 모든 화면의 공통 컨테이너. React 의 `<PhoneShell>` 대응.
/// 폭 375, 라운드 52, 노치 + 상태바(9:41) + 본문 + 홈 인디케이터.
class PhoneShell extends StatelessWidget {
  const PhoneShell({super.key, required this.child, this.bottomBar});

  /// 화면 본문(네비바부터 콘텐츠까지).
  final Widget child;

  /// 하단 탭바 등(없으면 홈 인디케이터만).
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 375,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(52),
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 100, offset: Offset(0, 32)),
        ],
      ),
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _StatusBar(),
              child,
              if (bottomBar != null) bottomBar!,
              const _HomeIndicator(),
            ],
          ),
          // 다이내믹 아일랜드
          Positioned(
            top: 14,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 120,
                height: 35,
                decoration: BoxDecoration(
                  color: const Color(0xFF000000),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 0, 26, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('9:41',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
            CustomPaint(size: Size(72, 13), painter: _StatusIconsPainter()),
          ],
        ),
      ),
    );
  }
}

/// 상태바 우측 글리프(신호/와이파이/배터리)를 원본 SVG 비율로 그린다.
class _StatusIconsPainter extends CustomPainter {
  const _StatusIconsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const ink = AppColors.ink;
    final fill = Paint()..color = ink;
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // ── 신호 막대 4개 (baseline y=12) ──
    void bar(double x, double top, [double opacity = 1]) {
      final p = Paint()..color = ink.withValues(alpha: opacity);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, top, 3, 12 - top), const Radius.circular(1)),
        p,
      );
    }

    bar(0, 7);
    bar(5, 4);
    bar(10, 1);
    bar(15, 0, 0.3);

    // ── 와이파이(중심 32,11) ──
    final c = const Offset(32, 11);
    canvas.drawCircle(c, 1.5, fill);
    canvas.drawArc(Rect.fromCircle(center: c, radius: 4.5), 3.6, 1.9, false, stroke);
    final faint = Paint()
      ..color = ink.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: c, radius: 7.5), 3.6, 1.9, false, faint);

    // ── 배터리 (좌측 x=46) ──
    final outline = Paint()
      ..color = ink.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(46.5, 1.5, 22, 10), const Radius.circular(3)),
      outline,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(68.5, 4, 3, 5), const Radius.circular(1.5)),
      Paint()..color = ink.withValues(alpha: 0.4),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(48, 3, 17, 7), const Radius.circular(1.5)),
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HomeIndicator extends StatelessWidget {
  const _HomeIndicator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Center(
        child: Container(
          width: 134,
          height: 5,
          decoration: BoxDecoration(
            color: AppColors.ink.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

/// 하단 3탭 바 (창작 / 보관함 / 설정).
class AppBottomTabBar extends StatelessWidget {
  const AppBottomTabBar({super.key, this.activeIndex = 0});

  final int activeIndex;

  static const _tabs = [('🎨', '창작'), ('📚', '보관함'), ('⚙', '설정')];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final active = i == activeIndex;
          return Expanded(
            child: SizedBox(
              height: 64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Opacity(
                    opacity: active ? 1 : 0.35,
                    child: Text(_tabs[i].$1, style: const TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _tabs[i].$2,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                      color: active ? AppColors.sage : AppColors.textFaint,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// 네비바 좌측의 둥근 ← 버튼 (여러 화면 공용).
class NavBackButton extends StatelessWidget {
  const NavBackButton({super.key, this.onTap, this.opacity = 1});
  final VoidCallback? onTap;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      // 버튼 30×30 영역 전체가 눌리도록(가장자리 탭도 인식).
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F3F0),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.chevron_left, size: 15, color: AppColors.ink),
        ),
      ),
    );
  }
}
