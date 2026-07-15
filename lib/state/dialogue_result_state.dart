import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../models/sample_data.dart';
import '../services/api_client.dart';
import '../services/db_service.dart';
import 'create_main_state.dart' show normalizeLevelLabel;
import 'library_state.dart';

part 'dialogue_result_state.freezed.dart';

/// 대사극 결과 화면 상태.
/// 탭(대본/역할 읽기/원작 정보), 펼친 줄 메뉴, 내 역할, 표시(하이라이트), 대본 내용.
@freezed
class DialogueResultState with _$DialogueResultState {
  const factory DialogueResultState({
    String? workId, // 로컬 DB 창작물 id (null 이면 샘플)
    @Default('흥부의 두 번째 박') String title,
    @Default('흥부와 놀부') String source,
    @Default('고전의 결 살리기') String level,
    @Default(0) int tab,
    int? openLine, // 인라인 편집 메뉴가 열린 줄 id
    @Default('흥부') String role, // 역할 읽기에서 선택한 내 역할
    @Default(<int>{4}) Set<int> highlighted, // 표시하기(노란색) 된 줄 id
    @Default(<ScriptLine>[]) List<ScriptLine> lines,
    @Default(<int, String>{}) Map<int, String> scenes, // 장면 번호 → 제목
    @Default(<String, VocabEntry>{}) Map<String, VocabEntry> vocab, // 단어 → 풀이
  }) = _DialogueResultState;
}

class DialogueResultNotifier extends Notifier<DialogueResultState> {
  DbService get _db => ref.read(dbServiceProvider);

  @override
  DialogueResultState build() => const DialogueResultState(
        lines: kScriptClassical,
        scenes: kSceneNames,
        vocab: kVocab,
      );

  /// 결과 화면을 연다.
  /// [workId] 가 있으면 로컬 DB 에서 제목·대본·장면·어휘·표시를 불러오고,
  /// 없으면 전달된 정보 + 샘플 대본으로 채운다(데모/디자인 확인용).
  void load({String? workId, String? title, String? source, String? level}) {
    if (workId == null) {
      state = DialogueResultState(
        title: title ?? state.title,
        source: source ?? state.source,
        level: normalizeLevelLabel(level ?? state.level),
        lines: kScriptClassical,
        scenes: kSceneNames,
        vocab: kVocab,
      );
      return;
    }
    // 우선 전달값으로 즉시 표시하고, DB 로드가 끝나면 교체한다.
    state = DialogueResultState(
      workId: workId,
      title: title ?? state.title,
      source: source ?? state.source,
      level: normalizeLevelLabel(level ?? state.level),
      lines: kScriptClassical,
      scenes: kSceneNames,
      vocab: kVocab,
    );
    _loadFromDb(workId);
  }

  Future<void> _loadFromDb(String workId) async {
    try {
      final work = await _db.getWork(workId);
      final content = await _db.getWorkContent(workId);
      if (state.workId != workId) return; // 그 사이 다른 창작물로 바뀌면 무시
      state = state.copyWith(
        title: work?.title ?? state.title,
        source: work?.source ?? state.source,
        level: normalizeLevelLabel(work?.level ?? state.level),
        lines: (content?.lines.isEmpty ?? true) ? state.lines : content!.lines,
        scenes: (content?.scenes.isEmpty ?? true) ? state.scenes : content!.scenes,
        // 불러온 창작물은 서버가 내려준 어휘를 그대로 쓴다(비어 있으면 밑줄 없음).
        // 데모 kVocab 으로 폴백하면 다른 원작인데 흥부전 뜻이 뜨는 버그가 난다.
        vocab: content?.vocab ?? state.vocab,
        highlighted: content?.highlighted ?? state.highlighted,
      );
    } catch (_) {
      // DB 미지원: 이미 채운 샘플을 유지한다.
    }
  }

  void setTab(int i) => state = state.copyWith(tab: i, openLine: null);

  /// 줄 메뉴 토글 (길게 누르기로 열고, 다시 누르면 닫힘).
  void toggleLineMenu(int id) =>
      state = state.copyWith(openLine: state.openLine == id ? null : id);

  void closeLineMenu() => state = state.copyWith(openLine: null);

  void setRole(String r) => state = state.copyWith(role: r);

  /// 표시하기/표시 지우기 (MVP: 노란색 1종).
  void toggleHighlight(int id) {
    final next = Set<int>.from(state.highlighted);
    next.contains(id) ? next.remove(id) : next.add(id);
    state = state.copyWith(highlighted: next, openLine: null);
    final wid = state.workId;
    if (wid != null) _db.updateHighlighted(wid, next).catchError((_) {});
  }

  /// 직접 수정: 선택한 줄의 텍스트만 바꾼다.
  void editLine(int id, String text) {
    if (text.trim().isEmpty) return; // 빈 입력은 무시
    final lines = [
      for (final l in state.lines) l.id == id ? l.copyWith(text: text.trim()) : l,
    ];
    state = state.copyWith(openLine: null, lines: lines);
    _persistLines(lines);
  }

  /// AI 수정 결과 등으로 한 줄의 텍스트를 교체한다(메뉴는 유지).
  void replaceLineText(int id, String text) {
    if (text.trim().isEmpty) return;
    final lines = [
      for (final l in state.lines) l.id == id ? l.copyWith(text: text.trim()) : l,
    ];
    state = state.copyWith(lines: lines);
    _persistLines(lines);
  }

  /// 제목 수정. 비어 있으면 기존 제목 유지(기획서: 자동 제목 복원).
  void setTitle(String t) {
    if (t.trim().isEmpty) return;
    final title = t.trim();
    state = state.copyWith(title: title);
    final id = state.workId;
    if (id != null) {
      _db.updateTitle(id, title).then((_) {
        ref.read(libraryProvider.notifier).refresh();
      }).catchError((_) {});
    }
  }

  /// AI 부분 수정: 선택한 한 줄만 서버에 보내 다시 쓴다(앞뒤 대사는 그대로).
  /// 성공하면 그 줄 텍스트를 교체하고 DB 에 반영한다. 실패는 호출 측에서 처리.
  Future<void> aiRewriteLine(int id, String instruction) async {
    final line = state.lines.where((l) => l.id == id).firstOrNull;
    if (line == null) return;
    final context = state.lines.map((l) => l.text).join('\n');
    final text = await ref.read(apiClientProvider).rewriteLine(
          line: line.text,
          context: context,
          instruction: instruction,
          level: state.level,
        );
    replaceLineText(id, text);
  }

  /// 변경된 대본 줄을 로컬 DB 에 반영(workId 가 있을 때만).
  void _persistLines(List<ScriptLine> lines) {
    final id = state.workId;
    if (id == null) return;
    _db.updateLines(id, lines).then((_) {
      ref.read(libraryProvider.notifier).refresh();
    }).catchError((_) {});
  }
}

final dialogueResultProvider =
    NotifierProvider<DialogueResultNotifier, DialogueResultState>(
        DialogueResultNotifier.new);
