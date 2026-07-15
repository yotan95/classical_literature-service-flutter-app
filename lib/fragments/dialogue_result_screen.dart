import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sample_data.dart';
import '../state/dialogue_result_state.dart';
import '../state/library_state.dart' show libraryProvider;
import '../theme/app_colors.dart';
import '../widgets/result_shared.dart';

/// 대사극 결과 화면.
/// 탭: 대본 / 역할 읽기 / 원작 정보.
/// - 대본: 줄을 길게 누르면 직접 수정 · AI로 바꾸기 · 표시하기 메뉴
/// - 어려운 단어(점선 밑줄)를 탭하면 용어 풀이 바텀시트
/// - 역할 읽기: 내 역할을 고르면 해당 인물 대사만 강조
class DialogueResultScreen extends ConsumerStatefulWidget {
  const DialogueResultScreen(
      {super.key, this.workId, this.title, this.source, this.level});

  /// 로컬 DB 창작물 id. 있으면 DB 에서 제목·대본을 로드한다(null 이면 샘플).
  final String? workId;

  /// 내 서재에서 열 때 넘겨받는 창작물 정보 (null 이면 기본 샘플).
  final String? title;
  final String? source;
  final String? level;

  @override
  ConsumerState<DialogueResultScreen> createState() => _DialogueResultScreenState();
}

class _DialogueResultScreenState extends ConsumerState<DialogueResultScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return; // 프레임 전에 화면을 떠났으면 로드 생략(ref-after-disposed 방지)
      ref.read(dialogueResultProvider.notifier).load(
          workId: widget.workId,
          title: widget.title,
          source: widget.source,
          level: widget.level);
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(dialogueResultProvider);
    final n = ref.read(dialogueResultProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      body: SafeArea(
        child: Column(
          children: [
            ResultNavBar(onMore: () => _showMoreMenu(context)),
            ResultTitleSection(
              title: st.title,
              source: st.source,
              sourceColor: bookColor(st.source),
              mode: '대사극',
              level: st.level,
              onEditTitle: () => _showTitleEdit(context, st.title, n),
            ),
            _tabBar(st.tab, n),
            Expanded(
              // 줄 메뉴(직접 수정 등)가 열려 있을 때 다른 빈 곳을 누르면 닫는다.
              // translucent + onTap 이라, 줄/단어/메뉴 버튼 탭은 각자의 제스처가
              // 먼저 가져가고(닫힘 처리 안 함) 빈 곳 탭만 여기서 처리된다.
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: st.openLine != null ? n.closeLineMenu : null,
                child: SingleChildScrollView(
                  child: switch (st.tab) {
                    0 => _ScriptTab(st: st, n: n),
                    1 => _RoleTab(st: st, n: n),
                    _ => _SourceTab(source: st.source, scenes: st.scenes),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBar(int active, DialogueResultNotifier n) {
    const tabs = ['대본', '역할 읽기', '원작'];
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          for (int i = 0; i < tabs.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => n.setTab(i),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: i == active ? AppColors.sage : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                  child: Text(
                    tabs[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: i == active ? FontWeight.w700 : FontWeight.w400,
                      color: i == active ? AppColors.sage : AppColors.textFaint,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// ··· 더보기: 텍스트 복사하기 · 삭제하기.
  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHandle(),
            ListTile(
              leading: const Text('📋', style: TextStyle(fontSize: 20)),
              title: const Text('텍스트 복사하기',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink)),
              onTap: () {
                Navigator.pop(ctx);
                _copyScript(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  size: 22, color: AppColors.danger),
              title: const Text('삭제하기',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 현재 대본을 일반 텍스트로 만들어 클립보드에 복사.
  Future<void> _copyScript(BuildContext context) async {
    final st = ref.read(dialogueResultProvider);
    await Clipboard.setData(ClipboardData(text: _scriptToText(st)));
    if (context.mounted) _demoSnack(context, '대본 텍스트를 복사했어요');
  }

  /// 대본 상태를 사람이 읽기 좋은 텍스트로 변환(장면 제목 + 화자: 대사).
  String _scriptToText(DialogueResultState st) {
    final buf = StringBuffer()
      ..writeln(st.title)
      ..writeln('${st.source} · 대사극')
      ..writeln();
    int? curScene;
    for (final l in st.lines) {
      if (l.scene != curScene) {
        curScene = l.scene;
        final name = st.scenes[l.scene];
        if (name != null) {
          buf
            ..writeln()
            ..writeln('[$name]');
        }
      }
      final who = (l.char != null && l.char!.isNotEmpty) ? '${l.char}: ' : '';
      buf.writeln('$who${l.text}');
    }
    return buf.toString().trim();
  }

  /// 창작물 삭제 — 확인 후 서재에서 지우고 이전 화면으로 돌아간다.
  void _confirmDelete(BuildContext context) {
    final st = ref.read(dialogueResultProvider);
    final id = st.workId;
    if (id == null) {
      _demoSnack(context, '저장된 작품이 아니라 삭제할 수 없어요');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('작품 삭제',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('《${st.title}》을(를) 삭제할까요?\n삭제한 작품은 되돌릴 수 없어요.',
            style: const TextStyle(fontSize: 13.5, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () {
              ref.read(libraryProvider.notifier).removeWork(id);
              Navigator.pop(ctx); // 다이얼로그 닫기
              Navigator.of(context).maybePop(); // 결과 화면 닫기 → 서재로
            },
            child: const Text('삭제',
                style: TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// 제목 인라인 수정 다이얼로그. 비어 있으면 기존 제목 유지.
  void _showTitleEdit(BuildContext context, String title, DialogueResultNotifier n) {
    final controller = TextEditingController(text: title);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('제목 수정',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(hintText: '제목을 입력해 주세요'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () {
              n.setTitle(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('저장',
                style: TextStyle(color: AppColors.sage, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

void _demoSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFDEDEDE),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

// ── 대본 탭 ─────────────────────────────────────────────

class _ScriptTab extends StatelessWidget {
  const _ScriptTab({required this.st, required this.n});

  final DialogueResultState st;
  final DialogueResultNotifier n;

  @override
  Widget build(BuildContext context) {
    final scenes = st.lines.map((l) => l.scene).toSet().toList()..sort();
    // 작품 단위로 인물마다 겹치지 않는 색을 미리 배정한다.
    final colors = AppColors.characterColors(st.lines.map((l) => l.char));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final sc in scenes) ...[
          if (sc != scenes.first) Container(height: 6, color: AppColors.shelfPlank),
          _sceneHeader(sc),
          const SizedBox(height: 4),
          for (final line in st.lines.where((l) => l.scene == sc)) ...[
            _LineTile(line: line, st: st, n: n, colors: colors),
            if (st.openLine == line.id) _lineMenu(context, line),
          ],
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _sceneHeader(int sc) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Text(
          '장면 $sc · ${st.scenes[sc] ?? ''}',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Color(0xFF666666)),
        ),
      );

  /// 길게 누른 줄의 인라인 메뉴: 직접 수정 / AI로 바꾸기 / 표시하기.
  Widget _lineMenu(BuildContext context, ScriptLine line) {
    final marked = st.highlighted.contains(line.id);
    return LineActionMenu(actions: [
      ('✏️', '직접 수정', AppColors.ink, () => _showEditDialog(context, line)),
      ('✨', 'AI로 바꾸기', AppColors.sage, () => _showAiSheet(context, line)),
      ('🔖', marked ? '표시 지우기' : '표시하기', const Color(0xFFB8860B),
          () => n.toggleHighlight(line.id)),
    ]);
  }

  void _showEditDialog(BuildContext context, ScriptLine line) {
    final controller = TextEditingController(text: line.text);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(line.char == null ? '내레이션 수정' : '${line.char}의 대사 수정',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          style: const TextStyle(fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () {
              n.editLine(line.id, controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('저장',
                style: TextStyle(color: AppColors.sage, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// AI 부분 수정 바텀시트 — 선택한 한 줄만 수정한다(기획서 6-2).
  void _showAiSheet(BuildContext context, ScriptLine line) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: _SheetHandle()),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text('✨ AI로 어떻게 바꿀까요?',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.sage)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                '선택한 줄만 바꿔요. 앞뒤 대사는 그대로 둘게요.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final opt in ['더 쉽게', '더 짧게', '더 재미있게', '감정을 더 분명하게'])
                    GestureDetector(
                      onTap: () async {
                        // async 이후 context 사용을 피하려고 messenger 를 미리 잡아 둔다.
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(ctx);
                        void snack(String m) => messenger
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(content: Text(m)));
                        snack('"$opt"(으)로 바꾸고 있어요...');
                        try {
                          await n.aiRewriteLine(line.id, opt);
                          snack('한 줄을 새로 고쳤어요 ✨');
                        } catch (_) {
                          snack('서버에 연결할 수 없어 수정하지 못했어요');
                        }
                      },
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.alpha(AppColors.sage, 0x12),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: AppColors.alpha(AppColors.sage, 0x30)),
                        ),
                        child: Text(opt,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.sage)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 대본 한 줄(내레이션/대사). 길게 누르면 편집 메뉴 토글.
class _LineTile extends StatelessWidget {
  const _LineTile(
      {required this.line, required this.st, required this.n, this.colors});

  final ScriptLine line;
  final DialogueResultState st;
  final DialogueResultNotifier n;

  /// 작품 단위로 배정한 인물 색 맵(없으면 이름 기반 폴백).
  final Map<String, ({Color bg, Color fg})>? colors;

  @override
  Widget build(BuildContext context) {
    final open = st.openLine == line.id;
    final marked = st.highlighted.contains(line.id);

    if (line.isNarration) {
      return GestureDetector(
        onLongPress: () => n.toggleLineMenu(line.id),
        onTap: open ? n.closeLineMenu : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: open ? const Color(0xFFE4E1DC) : const Color(0xFFEDEAE5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('내레이션',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.textMuted)),
              const SizedBox(height: 4),
              VocabText(
                text: line.text,
                vocab: st.vocab,
                level: st.level,
                highlighted: marked,
                baseStyle: const TextStyle(
                    fontSize: 13,
                    height: 1.65,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF555555)),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onLongPress: () => n.toggleLineMenu(line.id),
      onTap: open ? n.closeLineMenu : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: open ? AppColors.alpha(AppColors.sage, 0x0A) : Colors.transparent,
          border: Border(
            left: BorderSide(
                color: open ? AppColors.sage : Colors.transparent, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CharBadge(char: line.char!, color: colors?[line.char]),
                // 지문(mood)이 없거나 null 로 들어오면 '(null)' 대신 아예 표시하지 않는다.
                if (hasMood(line.mood)) ...[
                  const SizedBox(width: 7),
                  Text('(${line.mood})',
                      style: const TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: Color(0xFFCCCCCC))),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: VocabText(
                text: line.text,
                vocab: st.vocab,
                level: st.level,
                highlighted: marked,
                baseStyle: const TextStyle(
                    fontSize: 13, height: 1.65, color: AppColors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ── 역할 읽기 탭 ─────────────────────────────────────────

class _RoleTab extends StatelessWidget {
  const _RoleTab({required this.st, required this.n});

  final DialogueResultState st;
  final DialogueResultNotifier n;

  @override
  Widget build(BuildContext context) {
    // 실제 생성된 대본의 화자들(내레이션 제외, 등장 순서)을 역할 후보로 사용한다.
    final roles = <String>[];
    for (final l in st.lines) {
      final c = l.char;
      if (c != null && c.isNotEmpty && !roles.contains(c)) roles.add(c);
    }

    // 대사가 없으면(내레이션만) 역할 읽기를 안내만 표시한다.
    if (roles.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(24, 40, 24, 40),
        child: Center(
          child: Text('이 작품에는 인물 대사가 없어 역할 읽기를 할 수 없어요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.textMuted)),
        ),
      );
    }

    // 선택된 역할이 후보에 없으면(샘플 기본값 등) 첫 번째 인물로 표시한다.
    final role = roles.contains(st.role) ? st.role : roles.first;
    // 작품 단위로 인물마다 겹치지 않는 색을 배정한다.
    final colors = AppColors.characterColors(st.lines.map((l) => l.char));
    final rc = colors[role] ?? AppColors.characterColor(role);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 역할 선택
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('내 역할 선택',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                      color: AppColors.textMuted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in roles)
                    _roleChip(r,
                        sel: r == role,
                        c: colors[r] ?? AppColors.characterColor(r)),
                ],
              ),
            ],
          ),
        ),
        // 힌트 배너
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: rc.bg,
          child: Text('$role의 대사에서 내 차례예요. 크게 읽어봐요! 🎭',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: rc.fg)),
        ),
        const SizedBox(height: 4),
        // 대본 (내 역할만 강조, 내용은 대본 탭과 동일)
        for (final line in st.lines) _roleLine(line, rc, role, colors),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _roleChip(String role,
      {required bool sel, required ({Color bg, Color fg}) c}) {
    return GestureDetector(
      onTap: () => n.setRole(role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? c.fg : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? c.fg : AppColors.border, width: 1.5),
          boxShadow: sel
              ? [
                  BoxShadow(
                      color: AppColors.alpha(c.fg, 0x40),
                      blurRadius: 10,
                      offset: const Offset(0, 3)),
                ]
              : null,
        ),
        child: Text(role,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: sel ? Colors.white : c.fg)),
      ),
    );
  }

  Widget _roleLine(ScriptLine line, ({Color bg, Color fg}) rc, String role,
      Map<String, ({Color bg, Color fg})> colors) {
    if (line.isNarration) {
      return Opacity(
        opacity: 0.7,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFEDEAE5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(line.text,
              style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF777777))),
        ),
      );
    }

    final isMe = line.char == role;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isMe ? rc.bg : Colors.transparent,
        border: Border(
          left: BorderSide(color: isMe ? rc.fg : Colors.transparent, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CharBadge(char: line.char!, big: isMe, color: colors[line.char]),
          SizedBox(height: isMe ? 6 : 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(line.text,
                style: TextStyle(
                    fontSize: isMe ? 15 : 12,
                    height: 1.6,
                    fontWeight: isMe ? FontWeight.w700 : FontWeight.w400,
                    color: isMe ? AppColors.ink : const Color(0xFFAAAAAA))),
          ),
        ],
      ),
    );
  }
}

// ── 원작 정보 탭 ─────────────────────────────────────────

class _SourceTab extends StatelessWidget {
  const _SourceTab({required this.source, required this.scenes});

  final String source;
  final Map<int, String> scenes; // 실제 생성에 쓰인 장면(번호 → 제목)

  @override
  Widget build(BuildContext context) {
    final color = bookColor(source);
    // 생성 결과의 장면을 번호 순으로 정렬.
    final sceneEntries = scenes.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 원작 카드
        Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: AppColors.alpha(color, 0x55),
                  blurRadius: 28,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('원작',
                  style: TextStyle(
                      fontSize: 10, letterSpacing: 0.8, color: Color(0x8CFFFFFF))),
              const SizedBox(height: 5),
              Text(source,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: [
                  for (final t in ['설화', '고전소설', '공공 원전'])
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(t,
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xD8FFFFFF))),
                    ),
                ],
              ),
            ],
          ),
        ),
        // 사용한 장면
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('사용한 장면',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                      color: AppColors.textMuted)),
              const SizedBox(height: 10),
              if (sceneEntries.isEmpty)
                const Text('장면 정보가 없어요.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted))
              else
                for (int i = 0; i < sceneEntries.length; i++) ...[
                  if (i > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, color: AppColors.divider),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 50,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.alpha(color, 0x22),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('장면 ${sceneEntries[i].key}',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: color)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(sceneEntries[i].value,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.4,
                                color: AppColors.ink)),
                      ),
                    ],
                  ),
                ],
            ],
          ),
        ),
        // 출처 (기획서 15: 출처 표기)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.alpha(AppColors.sage, 0x0C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.alpha(AppColors.sage, 0x22)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('이 작품은 《$source》 공공 원전 자료를 바탕으로 AI가 새롭게 구성했습니다.',
                  style: const TextStyle(
                      fontSize: 11, height: 1.8, color: Color(0xFF666666))),
              const SizedBox(height: 5),
              const Text('출처: 한국고전번역원 · 공공누리 1유형',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.sage)),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
