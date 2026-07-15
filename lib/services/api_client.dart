import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_config.dart';
import '../models/sample_data.dart';
import '../state/create_main_state.dart'
    show CreateMode, RangeMode, levelApiLabel;

/// 서버(FastAPI) 호출 클라이언트.
/// AI 생성·TTS·어휘 로직은 전부 서버에 있고, 여기서는 "부르기만" 한다.
/// 응답 JSON 은 앱 모델(ScriptLine/VocabEntry 등)로 파싱한다.
class ApiClient {
  /// [baseUrl] 은 [AppConfig.baseUrl] 에서 주입한다(서버 호스트 단일 출처 — 여기 하드코딩 금지).
  /// [dio] 는 테스트에서 목 클라이언트를 주입할 때만 쓴다.
  ApiClient({String baseUrl = '', Dio? dio}) : _dio = dio ?? _defaultDio(baseUrl);

  final Dio _dio;

  /// 서버 요청 타임아웃(연결/수신).
  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _receiveTimeout = Duration(seconds: 60);

  static Dio _defaultDio(String baseUrl) => Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: _connectTimeout,
        receiveTimeout: _receiveTimeout,
        headers: const {'Content-Type': 'application/json'},
      ));

  /// POST /generate — 원작·설정으로 대본을 생성한다.
  /// 요청: {book, mode, level, rangeMode, scene, idea}
  /// 응답: {title, scenes, lines:[{id,scene,char,mood,text}], vocab:{...}}
  Future<GenerateResult> generate({
    required String book,
    required CreateMode mode,
    required String level,
    required RangeMode rangeMode,
    required int scene,
    required String idea,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>('/generate', data: {
      'book': book,
      'mode': mode.name,
      'level': levelApiLabel(level),
      'rangeMode': rangeMode.name,
      'scene': scene,
      'idea': idea,
    });
    return GenerateResult.fromMap(res.data ?? const {});
  }

  /// POST /tts — 대본 줄을 음성으로 합성한다. 오디오 바이트를 반환.
  /// 요청: {lines, speed}
  Future<Uint8List> tts({
    required List<ScriptLine> lines,
    required double speed,
  }) async {
    final res = await _dio.post<List<int>>(
      '/tts',
      data: {
        'lines': [for (final l in lines) l.toMap()],
        'speed': speed,
      },
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const []);
  }

  /// POST /rewrite-line — 한 줄을 지시에 맞게 다시 쓴다.
  /// 요청: {line, context, instruction, level} → 응답: {text}
  Future<String> rewriteLine({
    required String line,
    required String context,
    required String instruction,
    required String level,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>('/rewrite-line', data: {
      'line': line,
      'context': context,
      'instruction': instruction,
      'level': levelApiLabel(level),
    });
    return (res.data?['text'] as String?) ?? line;
  }

  // 어휘 풀이(vocab) 흐름: 흔한 단어는 `POST /create` 결과의 `vocab` 사전이 본문과 함께
  // 내려와 SQLite(works.vocab)에 저장되고, 탭하면 그 로컬 맵에서 즉시 보여 준다(오프라인 동작).
  // 동봉 사전에 없는 단어만 아래 [vocab] 로 서버 /vocab 즉석 조회한다(온라인 전용 폴백).
  // 자세한 흐름은 dialogue_result_screen.dart 참고.

  /// POST /vocab — 동봉 사전에 없는 단어를 문맥 반영해 즉석 풀이한다(온라인 전용 폴백).
  /// 요청: {word, context, level}. 응답을 VocabEntry 로 파싱한다.
  Future<VocabEntry> vocab({
    required String word,
    required String context,
    required String level,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>('/vocab', data: {
      'word': word,
      'context': context,
      'level': levelApiLabel(level),
    });
    return VocabEntry.fromMap(res.data ?? const {});
  }

  /// GET /books/{bookId}/original — 원작 전문(全文) 읽기 텍스트.
  /// 서버가 순번/공백 줄을 걸러 문단 합본 text 를 준다. 읽기 화면은 에셋과
  /// 동일하게 이 문자열을 파싱해 렌더링한다. [bookId] 는 백엔드 슬러그(언더스코어).
  Future<String> bookOriginal(String bookId) async {
    final res =
        await _dio.get<Map<String, dynamic>>('/books/$bookId/original');
    return (res.data?['text'] as String?) ?? '';
  }
}

/// POST /generate 응답 파싱 결과.
class GenerateResult {
  const GenerateResult({
    required this.title,
    required this.scenes,
    required this.lines,
    required this.vocab,
  });

  final String title;
  final Map<int, String> scenes; // 장면 번호 → 장면 제목
  final List<ScriptLine> lines;
  final Map<String, VocabEntry> vocab; // 단어 → 풀이

  factory GenerateResult.fromMap(Map<String, dynamic> m) {
    final scenesRaw = m['scenes'];
    final scenes = <int, String>{};
    if (scenesRaw is Map) {
      scenesRaw.forEach((k, v) {
        final n = int.tryParse('$k');
        if (n != null) scenes[n] = '$v';
      });
    } else if (scenesRaw is List) {
      for (var i = 0; i < scenesRaw.length; i++) {
        scenes[i + 1] = '${scenesRaw[i]}';
      }
    }

    final linesRaw = (m['lines'] as List<dynamic>?) ?? const [];
    final lines = [
      for (final e in linesRaw) ScriptLine.fromMap(e as Map<String, dynamic>),
    ];

    final vocabRaw = (m['vocab'] as Map<dynamic, dynamic>?) ?? const {};
    final vocab = <String, VocabEntry>{
      for (final e in vocabRaw.entries)
        '${e.key}': VocabEntry.fromMap((e.value as Map).cast<String, dynamic>()),
    };

    return GenerateResult(
      title: (m['title'] as String?) ?? '새 작품',
      scenes: scenes,
      lines: lines,
      vocab: vocab,
    );
  }
}

/// 앱 전역에서 공유하는 API 클라이언트.
/// 서버 호스트는 [AppConfig.baseUrl] 단일 출처에서 주입한다(별도 ApiConfig 없음).
/// [appConfigProvider] 를 watch 하므로 base URL 이 바뀌면 클라이언트도 새로 만들어진다.
final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  return ApiClient(baseUrl: config.baseUrl);
});
