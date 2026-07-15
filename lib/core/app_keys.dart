import 'package:flutter/material.dart';

/// 앱 전역 키.
/// 화면 밖(프로바이더/리스너)에서 네비게이션·스낵바를 띄울 때 쓴다.
/// - [appNavigatorKey]: 창작 완료 시 결과 화면으로 이동(배너 '보러가기' 등).
/// - [appMessengerKey]: 어느 화면에서든 완료 알림 스낵바를 띄운다.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
