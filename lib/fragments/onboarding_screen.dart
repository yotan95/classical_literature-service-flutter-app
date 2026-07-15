import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/prefs.dart';
import '../state/onboarding_state.dart';
import '../state/settings_state.dart' show settingsProvider;
import '../theme/app_colors.dart';
import 'app_shell.dart';

/// 온보딩 3단계: 서비스 소개 → 목적 선택 → 기본 설정(이름 입력 없음).
/// 마지막 단계에서 시작하면 '최초 1회' 플래그를 저장하고 [AppShell] 로 교체 이동한다.
/// 이후 실행부터는 main.dart 가 온보딩을 건너뛴다.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    final page = ref.read(onboardingProvider).page;
    if (page < 2) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    // 온보딩에서 고른 이용 목적/기본 읽기 수준을 설정에 저장한다(이름 입력은 없음).
    final ob = ref.read(onboardingProvider);
    ref.read(settingsProvider.notifier)
      ..setPurpose(kPurposes[ob.purpose].$2)
      ..setLevel(kReadLevels[ob.level].$2);
    // 최초 1회 노출 플래그 저장 → 다음 실행부터는 온보딩을 건너뛴다.
    await Prefs.setOnboardingSeen();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AppShell()));
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(onboardingProvider);
    final n = ref.read(onboardingProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        // 상태바(시간·와이파이) 영역에는 그라데이션이 들어가지 않도록 SafeArea 안에 둔다.
        child: DecoratedBox(
          // 옅은 그라데이션 배경 (위 sage 틴트 → 아래 흰색)
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x143D8A65), AppColors.surface],
              stops: [0.0, 0.4],
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: n.setPage,
                  children: const [_IntroPage(), _PurposePage(), _SetupPage()],
                ),
              ),
              // 페이지 점 + CTA
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < 3; i++) ...[
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: i == st.page ? 22 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == st.page
                                  ? AppColors.sage
                                  : const Color(0xFFD8D8D8),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          if (i < 2) const SizedBox(width: 6),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _next,
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
                        child: Text(
                          st.page == 1 ? '계속하기 →' : '시작하기 →',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('계속하면 이용약관에 동의하는 것으로 간주합니다',
                        style: TextStyle(
                            fontSize: 10, color: AppColors.textFaint)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 1단계: 서비스 소개 ───────────────────────────────────

class _IntroPage extends StatelessWidget {
  const _IntroPage();

  static const _features = [
    ('🎭', '고전을 내 대본으로', '흥부와 놀부, 홍길동전 같은 이야기를 직접 골라 짧은 극으로 만들어요'),
    ('🎙', '목소리로 들어요', '인물별 목소리로 생생하게 듣는 오디오극을 즐겨봐요'),
    ('✏️', '내 맘대로 고쳐요', '마음에 안 드는 대사는 직접 고치거나 AI에게 맡겨요'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('📖', style: TextStyle(fontSize: 48)),
                SizedBox(height: 12),
                Text('쉬운 고전 창작 극장',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                        color: AppColors.sage)),
                SizedBox(height: 6),
                Text('고전을 내 이야기로\n바꿔봐요',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        height: 1.3,
                        color: AppColors.ink)),
                SizedBox(height: 8),
                Text('어렵게 느껴지던 고전이\n내가 만드는 이야기가 돼요',
                    style: TextStyle(
                        fontSize: 13, height: 1.6, color: Color(0xFF5F5F5F))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
            child: Column(
              children: [
                for (final (icon, title, desc) in _features)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border, width: 1.5),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x0F000000),
                            blurRadius: 5,
                            offset: Offset(0, 1)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.alpha(AppColors.sage, 0x18),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Text(icon, style: const TextStyle(fontSize: 22)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink)),
                              const SizedBox(height: 2),
                              Text(desc,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      height: 1.5,
                                      color: Color(0xFF909090))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 2단계: 목적 선택 ─────────────────────────────────────

class _PurposePage extends ConsumerWidget {
  const _PurposePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sel = ref.watch(onboardingProvider.select((s) => s.purpose));
    final n = ref.read(onboardingProvider.notifier);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('👋', style: TextStyle(fontSize: 42)),
                SizedBox(height: 10),
                Text('어떻게 오셨나요?',
                    style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink)),
                SizedBox(height: 6),
                Text('목적에 맞는 콘텐츠를 추천해 드릴게요',
                    style: TextStyle(fontSize: 13, color: Color(0xFF5F5F5F))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
            child: Column(
              children: [
                for (int i = 0; i < kPurposes.length; i++)
                  _purposeCard(kPurposes[i], on: i == sel, onTap: () => n.setPurpose(i)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _purposeCard((String, String, String) p,
      {required bool on, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: on ? AppColors.sage : AppColors.border,
              width: on ? 2 : 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.sage : const Color(0xFFF5F3F0),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(p.$1, style: const TextStyle(fontSize: 21)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.$2,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: on ? AppColors.sage : AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(p.$3,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF909090))),
                ],
              ),
            ),
            _radio(on),
          ],
        ),
      ),
    );
  }
}

// ── 3단계: 기본 설정 ─────────────────────────────────────

class _SetupPage extends ConsumerWidget {
  const _SetupPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(onboardingProvider);
    final n = ref.read(onboardingProvider.notifier);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('👓', style: TextStyle(fontSize: 42)),
                SizedBox(height: 10),
                Text('어떻게 읽을까요?',
                    style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink)),
                SizedBox(height: 6),
                Text('나중에 설정에서 언제든 바꿀 수 있어요',
                    style: TextStyle(fontSize: 13, color: Color(0xFF5F5F5F))),
              ],
            ),
          ),
          // 기본 읽기 수준
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('기본 읽기 수준',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                        color: Color(0xFF909090))),
                const SizedBox(height: 10),
                for (int i = 0; i < kReadLevels.length; i++)
                  GestureDetector(
                    onTap: () => n.setLevel(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: st.level == i
                                ? AppColors.sage
                                : AppColors.border,
                            width: st.level == i ? 2 : 1.5),
                      ),
                      child: Row(
                        children: [
                          Text(kReadLevels[i].$1,
                              style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(kReadLevels[i].$2,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: st.level == i
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: st.level == i
                                        ? AppColors.sage
                                        : AppColors.ink)),
                          ),
                          _radio(st.level == i),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 선택 라디오 점.
Widget _radio(bool on) => Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? AppColors.sage : Colors.transparent,
        border: Border.all(
            color: on ? AppColors.sage : const Color(0xFFD0D0D0), width: 2),
      ),
      child: on
          ? Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle))
          : null,
    );
