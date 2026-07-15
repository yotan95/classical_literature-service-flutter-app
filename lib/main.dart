import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/app_keys.dart';
import 'core/prefs.dart';
import 'theme/app_colors.dart';
import 'state/settings_state.dart';
import 'fragments/app_shell.dart';
import 'fragments/onboarding_screen.dart';

/// 앱 진입점.
/// 실행 전: dart run build_runner build --delete-conflicting-outputs
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 최초 1회만 온보딩 노출 — 이미 봤으면 바로 앱 셸로 진입한다.
  final onboardingSeen = await Prefs.onboardingSeen();
  runApp(ProviderScope(child: ClassicTheaterApp(onboardingSeen: onboardingSeen)));
}

class ClassicTheaterApp extends ConsumerWidget {
  const ClassicTheaterApp({super.key, this.onboardingSeen = false});

  /// 온보딩을 이미 본 적이 있는지(첫 실행이면 false).
  final bool onboardingSeen;

  /// 설정의 글자 크기 → 앱 전역 글자 배율.
  static double _scaleFor(String fontSize) {
    switch (fontSize) {
      case '작게':
        return 0.9;
      case '크게':
        return 1.15;
      case '아주 크게':
        return 1.3;
      default: // 보통
        return 1.0;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.sage,
        primary: AppColors.sage,
      ),
      scaffoldBackgroundColor: AppColors.surface,
      fontFamily: 'NotoSansKR', // pubspec 에 폰트 등록 시
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );

    final scale = _scaleFor(ref.watch(settingsProvider.select((s) => s.fontSize)));

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // 화면 밖(완료 알림·배너)에서 네비게이션/스낵바를 띄우기 위한 전역 키.
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appMessengerKey,
      theme: theme,
      // 모든 화면 공통: 오버스크롤 시 늘어남/글로우 없이 끝에서 멈춘다.
      scrollBehavior: const AppScrollBehavior(),
      // 설정의 글자 크기를 앱 전체 텍스트에 반영.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        );
      },
      // 최초 실행만 온보딩, 이후엔 앱 셸(하단 탭)로 바로 진입.
      home: onboardingSeen ? const AppShell() : const OnboardingScreen(),
    );
  }
}

/// 앱 전역 스크롤 동작.
/// - 오버스크롤 인디케이터(Android stretch / glow)를 표시하지 않는다.
/// - iOS 의 바운스도 끄고 끝에서 멈추도록 ClampingScrollPhysics 를 사용한다.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}
