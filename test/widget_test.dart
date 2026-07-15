// 기본 Flutter 위젯 테스트.
//
// WidgetTester 로 위젯과 상호작용(탭, 스크롤 등)하거나
// 위젯 트리에서 자식을 찾아 텍스트/속성을 검증할 수 있다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:classic_theater/main.dart';
import 'package:classic_theater/fragments/onboarding_screen.dart';

void main() {
  testWidgets('최초 실행에는 온보딩 첫 화면이 뜬다', (WidgetTester tester) async {
    // 테스트 환경에는 sqflite 플러그인이 없어 온보딩 완료 플래그를 읽지 못하므로
    // (진입 게이트가 안전 기본값으로) 온보딩이 노출된다.
    await tester.pumpWidget(const ProviderScope(child: ClassicTheaterApp()));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('시작하기 →'), findsOneWidget);
  });
}
