import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../theme/app_colors.dart';

/// 서버(FastAPI) 연결 여부 확인 서비스.
///
/// 이 앱은 "온라인 전용" 기능(새 작품 만들기·AI 수정·오디오 재생·AI 사전 풀이·원작 받기)과
/// "오프라인 가능" 기능(저장된 작품 보기·서재·설정)이 섞여 있다. 온라인 전용 기능을
/// 오프라인에서 실행하면 한참 기다리다 알 수 없는 오류로 끝나므로, 동작 전에 서버가
/// 닿는지 가볍게 확인해 미리 안내한다.
///
/// 일반 인터넷 연결이 아니라 "우리 서버"가 닿는지를 본다(서버가 꺼져 있으면 인터넷이 있어도
/// 온라인 전용 기능은 못 쓰므로). 별도 패키지 없이 [http] 로 짧게 프로브한다.
class ConnectivityService {
  ConnectivityService(this._config);

  final AppConfig _config;

  /// 프로브 타임아웃(짧게 — 사용자를 오래 붙잡지 않는다).
  static const Duration _timeout = Duration(seconds: 4);

  /// 서버가 닿으면 true. mock 모드(useMock)면 서버가 필요 없으므로 항상 true.
  /// 가벼운 GET /books 로 확인한다(목록 캐시용 엔드포인트라 부작용 없음).
  Future<bool> isServerReachable() async {
    if (_config.useMock) return true;
    try {
      final res = await http
          .get(Uri.parse('${_config.baseUrl}/books'))
          .timeout(_timeout);
      return res.statusCode >= 200 && res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }
}

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService(ref.watch(appConfigProvider));
});

/// 온라인 전용 동작을 실행하기 전에 서버 연결을 확인한다.
/// - 연결됨: true 를 반환(동작을 그대로 진행).
/// - 끊김: 친절한 안내 다이얼로그를 띄우고 false 를 반환(동작 중단).
///
/// [feature] 는 안내 문구에 들어갈 기능 이름(예: '새 작품 만들기').
Future<bool> ensureOnline(
  BuildContext context,
  WidgetRef ref, {
  required String feature,
}) async {
  final online = await ref.read(connectivityServiceProvider).isServerReachable();
  if (online) return true;
  if (!context.mounted) return false;
  await showOfflineNotice(context, feature: feature);
  return false;
}

/// "지금은 오프라인이에요" 안내 다이얼로그. 온라인 전용 기능을 막을 때 공용으로 쓴다.
Future<void> showOfflineNotice(
  BuildContext context, {
  required String feature,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: const [
          Text('📡', style: TextStyle(fontSize: 20)),
          SizedBox(width: 8),
          Text('지금은 오프라인이에요',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
      content: Text(
        '$feature은(는) 인터넷에 연결돼 있어야 쓸 수 있어요.\n'
        'Wi-Fi나 데이터 연결을 확인하고 다시 시도해 주세요.',
        style: const TextStyle(fontSize: 13.5, height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('알겠어요',
              style:
                  TextStyle(color: AppColors.sage, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}
