import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../models/create_request.dart';

/// 현재 [AppConfig] 로 구성된 창작 API 클라이언트.
final createApiProvider = Provider<CreateApi>((ref) {
  final config = ref.watch(appConfigProvider);
  return CreateApi(config);
});

/// `/create` SSE 진행 단계(원작 분석 → 구성 → 대사 집필 → 마무리).
/// 문자열은 백엔드 API 명세와 동일해야 한다.
const List<String> kCreateStages = ['analysis', 'structure', 'writing', 'finalize'];

/// `/create` 에서 흘러오는 이벤트(진행/결과/오류).
sealed class CreateEvent {
  const CreateEvent();

  /// `data: <json>` 한 줄을 이벤트로 파싱(미지원 타입이면 null).
  static CreateEvent? fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'progress':
        return CreateProgress(
          stage: j['stage'] as String? ?? '',
          status: j['status'] as String? ?? '',
        );
      case 'result':
        final data = j['data'];
        return CreateResult(data is Map<String, dynamic> ? data : <String, dynamic>{});
      case 'error':
        return CreateError(j['message'] as String? ?? '알 수 없는 오류가 발생했어요.');
      default:
        return null;
    }
  }
}

class CreateProgress extends CreateEvent {
  const CreateProgress({required this.stage, required this.status});
  final String stage; // analysis | structure | writing | finalize
  final String status; // running | done

  /// kCreateStages 내 인덱스(미지원 stage 면 -1).
  int get stageIndex => kCreateStages.indexOf(stage);
}

class CreateResult extends CreateEvent {
  const CreateResult(this.data);
  final Map<String, dynamic> data; // §7 result.data
}

class CreateError extends CreateEvent {
  const CreateError(this.message);
  final String message;
}

/// 창작 API 클라이언트. base URL/useMock 은 [AppConfig] 에서 주입한다(하드코딩 금지).
class CreateApi {
  CreateApi(this.config);

  final AppConfig config;

  /// `POST /create` 를 호출하고 SSE 이벤트를 [Stream] 으로 흘린다.
  /// [AppConfig.useMock] 이 true 면 서버 없이 캔드 이벤트를 재생한다.
  Stream<CreateEvent> create(CreateRequest req) {
    return config.useMock ? _mock(req) : _live(req);
  }

  // ── 실제 서버 호출 (SSE) ────────────────────────────────
  Stream<CreateEvent> _live(CreateRequest req) async* {
    final uri = Uri.parse('${config.baseUrl}/create');
    final client = http.Client();
    try {
      final request = http.Request('POST', uri)
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'text/event-stream'
        ..body = jsonEncode(req.toJson());

      final res = await client.send(request);

      if (res.statusCode != 200) {
        // 422 등은 스트림 시작 전 오류 — 본문을 읽어 메시지로.
        final body = await res.stream.bytesToString();
        yield CreateError(_extractDetail(body) ?? '요청이 거부됐어요 (HTTP ${res.statusCode}).');
        return;
      }

      // `data: <json>\n\n` 단위로 누적 파싱.
      var buffer = '';
      await for (final chunk
          in res.stream.transform(utf8.decoder)) {
        buffer += chunk;
        int idx;
        while ((idx = buffer.indexOf('\n\n')) != -1) {
          final rawEvent = buffer.substring(0, idx);
          buffer = buffer.substring(idx + 2);
          final ev = _parseSseBlock(rawEvent);
          if (ev != null) yield ev;
        }
      }
    } catch (e) {
      yield CreateError('서버에 연결하지 못했어요. 네트워크와 주소(${config.baseUrl})를 확인해 주세요.');
    } finally {
      client.close();
    }
  }

  /// SSE 블록(여러 `data:` 줄 가능)에서 첫 JSON 이벤트를 파싱.
  CreateEvent? _parseSseBlock(String block) {
    for (final line in const LineSplitter().convert(block)) {
      final trimmed = line.trimLeft();
      if (!trimmed.startsWith('data:')) continue;
      final payload = trimmed.substring(5).trim();
      if (payload.isEmpty) continue;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) return CreateEvent.fromJson(decoded);
      } catch (_) {
        // JSON 이 아니면 무시.
      }
    }
    return null;
  }

  String? _extractDetail(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] != null) return j['detail'].toString();
    } catch (_) {}
    return null;
  }

  // ── Mock 재생 (서버 없이 흐름 시연) ─────────────────────
  Stream<CreateEvent> _mock(CreateRequest req) async* {
    const step = Duration(milliseconds: 900);
    for (final stage in kCreateStages) {
      yield CreateProgress(stage: stage, status: 'running');
      await Future<void>.delayed(step);
      yield CreateProgress(stage: stage, status: 'done');
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    yield CreateResult(_mockResult(req));
  }

  /// 결과 화면은 아직 sample_data 를 쓰므로, mock 결과는 저장소(created_data) 검증용
  /// 최소 §7 형태만 갖춘다.
  Map<String, dynamic> _mockResult(CreateRequest req) => {
        'creationId': 'mock-${DateTime.now().millisecondsSinceEpoch}',
        'bookId': req.bookId,
        'title': '새 작품',
        'mode': req.mode,
        'difficulty': req.difficulty,
        'tags': <String>[],
        'intro': '',
        'characters': <Map<String, dynamic>>[],
        'scenes': <Map<String, dynamic>>[],
      };
}
