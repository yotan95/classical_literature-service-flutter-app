import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 앱 전역 설정 단일 출처(서버 base URL 등).
/// 서버 IP/호스트/포트는 위젯에 하드코딩하지 말고 항상 여기(또는 [appConfigProvider])를 통한다.
class AppConfig {
  const AppConfig({
    this.baseUrl = kDefaultBaseUrl,
    this.useMock = kDefaultUseMock,
  });

  /// 백엔드(FastAPI) base URL. 기본값은 배포 서버(https://api.rasponline.xyz).
  /// 로컬 개발 서버로 붙으려면 `--dart-define=BASE_URL=...` 로 주입:
  /// - 안드로이드 에뮬레이터: http://10.0.2.2:8000
  /// - 같은 네트워크의 실기기: 서버의 LAN IP (Mac: `ipconfig getifaddr en0`)
  final String baseUrl;

  /// true 면 실제 서버 대신 캔드(mock) SSE 단계를 재생해 창작 흐름을 끝까지 시연한다.
  /// 서버가 없어도 UI 검증이 가능하도록 기본값 ON. 실서버 연동 시 false 로 바꾼다.
  final bool useMock;

  /// 기본 base URL. 빌드 시 `--dart-define=BASE_URL=...` 로 주입(코드 하드코딩 금지).
  /// 미주입 시 배포 서버(https://api.rasponline.xyz)로 붙는다.
  static const String kDefaultBaseUrl =
      String.fromEnvironment('BASE_URL', defaultValue: 'https://api.rasponline.xyz');

  /// 기본 mock 사용 여부. 기본은 **실서버(false)** — 책/창작 모두 FastAPI 와 연동.
  /// 서버 없이 흐름만 보려면 `--dart-define=USE_MOCK=true`.
  static const bool kDefaultUseMock =
      bool.fromEnvironment('USE_MOCK', defaultValue: false);

  AppConfig copyWith({String? baseUrl, bool? useMock}) => AppConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        useMock: useMock ?? this.useMock,
      );
}

/// 앱 전역 설정 프로바이더. 환경 전환이 필요하면 이 값을 교체한다.
final appConfigProvider =
    NotifierProvider<AppConfigNotifier, AppConfig>(AppConfigNotifier.new);

class AppConfigNotifier extends Notifier<AppConfig> {
  @override
  AppConfig build() => const AppConfig();

  void setBaseUrl(String url) => state = state.copyWith(baseUrl: url);
  void setUseMock(bool v) => state = state.copyWith(useMock: v);
}
