import 'package:shared_preferences/shared_preferences.dart';

/// 영속 플래그(shared_preferences) 접근을 한곳에 모은다.
/// 현재는 온보딩 '최초 1회' 노출 플래그만 사용.
class Prefs {
  Prefs._();

  static const String _kOnboardingSeen = 'onboarding_seen';

  /// 온보딩을 이미 봤는지 여부(처음이면 false).
  static Future<bool> onboardingSeen() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kOnboardingSeen) ?? false;
  }

  /// 온보딩 완료 표시(이후 실행부터는 바로 앱 셸로 진입).
  static Future<void> setOnboardingSeen() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kOnboardingSeen, true);
  }

  /// 데이터 초기화 시 플래그 제거(다음 실행에서 온보딩 재노출).
  static Future<void> clearOnboardingSeen() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kOnboardingSeen);
  }
}
