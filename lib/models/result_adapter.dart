import '../services/books_service.dart' show resolveMediaUrl;
import '../services/db_service.dart';
import 'sample_data.dart';

/// 서버 `POST /create` 결과(result.data)를 **기존 UI 모델**
/// ([CreativeWork] 메타 + [WorkContent] 본문)로 변환하는 어댑터.
///
/// 기존 결과 화면/서재는 정수 id 의 [ScriptLine] 과 장면 맵을 쓰므로, 서버의 문자열 id·정규화 구조를
/// 그대로 그 셰이프에 맞춰 흘려보낸다(화면은 건드리지 않음).
class AdaptedCreation {
  const AdaptedCreation(this.work, this.content);
  final CreativeWork work;
  final WorkContent content;
}

/// API difficulty enum → 앱 난이도(한글 라벨).
const Map<String, String> _levelByDifficulty = {
  'children': '동화책 수준',
  'korean_learner': '한국어 배우는 중',
  'youth': '청소년용',
  'original': '고전의 결 살리기',
};

/// 화자가 내레이터인지(기존 UI 는 char==null 을 내레이션으로 본다).
bool _isNarration(String speaker, String speakerName) =>
    speakerName == '내레이터' ||
    speaker.toLowerCase().contains('narrator');

/// [baseUrl] 이 주어지면 서버가 내려준 미디어 상대경로(창작물 표지·오디오)를
/// 절대 URL 로 보정한다(저장 전에 절대 URL 로 굳혀 둔다).
AdaptedCreation adaptCreation(Map<String, dynamic> data, {String baseUrl = ''}) {
  final creationId = (data['creationId'] as String?)?.isNotEmpty == true
      ? data['creationId'] as String
      : 'cre-${DateTime.now().millisecondsSinceEpoch}';
  final mode = data['mode'] as String? ?? 'dialogue';
  final difficulty = data['difficulty'] as String? ?? 'youth';
  final title = (data['title'] as String?)?.isNotEmpty == true
      ? data['title'] as String
      : '새 작품';
  final intro = data['intro'] as String? ?? '';
  // 창작물 대표 이미지/이모지 — 원작 표지(source.coverImageUrl)와 별개.
  // 이미지는 상대경로로 내려오므로 baseUrl 기준 절대 URL 로 보정해 저장한다.
  // (최상위 data.coverImageUrl 은 더 이상 창작물 커버로 쓰지 않는다.)
  final creationCoverImageUrl =
      resolveMediaUrl(data['creationCoverImageUrl'] as String?, baseUrl);
  final creationCoverEmoji = data['creationCoverEmoji'] as String?;
  // source 객체(title)가 있으면 그 제목을, 없으면 bookId(슬러그)를 제목으로 정규화한다.
  // (result.data 는 보통 제목 없이 bookId 만 줌 → 서재 그룹핑/표지가 제목 키와 어긋나지 않게.)
  final source = data['source'];
  final sourceTitle = (source is Map && source['title'] is String)
      ? source['title'] as String
      : resolveBookKey(data['bookId'] as String? ?? '');

  // scenes → lines 를 재생 순서대로 펼쳐 정수 id 의 ScriptLine 으로.
  final scenesRaw = data['scenes'] as List? ?? const [];
  final lines = <ScriptLine>[];
  final scenesMap = <int, String>{};
  final lineIdToInt = <String, int>{}; // 서버 lineId → 정수 id (timepoints 매핑용)
  var idx = 0;
  for (final s in scenesRaw) {
    if (s is! Map<String, dynamic>) continue;
    final order = (s['order'] as num?)?.toInt() ?? (scenesMap.length + 1);
    scenesMap[order] = (s['title'] as String?) ?? '장면 $order';
    for (final l in (s['lines'] as List? ?? const [])) {
      if (l is! Map<String, dynamic>) continue;
      final speaker = l['speaker'] as String? ?? '';
      final speakerName = l['speakerName'] as String? ?? '';
      lines.add(ScriptLine(
        id: idx,
        scene: order,
        char: _isNarration(speaker, speakerName) ? null : speakerName,
        mood: l['direction'] as String?,
        text: l['text'] as String? ?? '',
      ));
      lineIdToInt[(l['lineId'] as String?) ?? '$idx'] = idx;
      idx++;
    }
  }

  // 어휘 사전: 서버가 문맥에 맞춰 내려준 vocab({단어:{hanja?,meaning,note?}}).
  // 키는 본문(line.text)에 등장한 표기 그대로 → text 를 손대지 않았으므로
  // VocabText 가 그대로 밑줄을 칠 수 있다. 모양이 앱 모델과 동일해 그대로 흘려보낸다.
  final vocabRaw = (data['vocab'] as Map?) ?? const {};
  final vocab = <String, VocabEntry>{
    for (final e in vocabRaw.entries)
      if (e.value is Map)
        '${e.key}': VocabEntry.fromMap((e.value as Map).cast<String, dynamic>()),
  };

  // 오디오극: 단일 MP3 + timepoints → ScriptLine.id(정수) 기준 매핑.
  String? audioUrl;
  final timepoints = <int, (int, int)>{};
  final audio = data['audio'];
  if (audio is Map) {
    // 오디오도 상대경로(/audio/...)로 내려올 수 있어 같은 방식으로 보정한다.
    audioUrl = resolveMediaUrl(audio['audioUrl'] as String?, baseUrl);
    for (final t in (audio['timepoints'] as List? ?? const [])) {
      if (t is! Map<String, dynamic>) continue;
      final intId = lineIdToInt[t['lineId'] as String? ?? ''];
      if (intId != null) {
        timepoints[intId] = (
          (t['startMs'] as num?)?.toInt() ?? 0,
          (t['endMs'] as num?)?.toInt() ?? 0,
        );
      }
    }
  }

  final work = CreativeWork(
    id: creationId,
    title: title,
    source: sourceTitle,
    mode: createModeFromName(mode),
    level: _levelByDifficulty[difficulty] ?? '청소년용',
    desc: intro,
    updatedAt: DateTime.now(),
    creationCoverImageUrl: creationCoverImageUrl,
    creationCoverEmoji: creationCoverEmoji,
  );
  final content = WorkContent(
    lines: lines,
    scenes: scenesMap,
    vocab: vocab,
    audioUrl: audioUrl,
    timepoints: timepoints,
  );
  return AdaptedCreation(work, content);
}
