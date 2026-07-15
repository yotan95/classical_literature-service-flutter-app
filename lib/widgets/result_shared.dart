import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sample_data.dart';
import '../services/api_client.dart';
import '../services/connectivity_service.dart';
import '../state/create_main_state.dart' show levelDisplayLabel;
import '../theme/app_colors.dart';
import 'phone_shell.dart' show NavBackButton;

/// 대사극·오디오극 결과 화면이 함께 쓰는 작은 위젯 모음.

/// 대사 지문(mood) 을 화면에 보여 줄지 여부.
/// 비어 있거나 서버에서 null(문자열 'null' 포함)로 들어오면 표시하지 않는다.
bool hasMood(String? mood) {
  if (mood == null) return false;
  final m = mood.trim();
  return m.isNotEmpty && m.toLowerCase() != 'null';
}

/// 인물 이름 배지. [big] 이면 역할 읽기 강조용으로 크게.
class CharBadge extends StatelessWidget {
  const CharBadge({super.key, required this.char, this.big = false, this.color});

  final String char;
  final bool big;

  /// 작품 단위로 미리 배정한 색(있으면 이걸 쓴다). null 이면 이름 기반 폴백.
  final ({Color bg, Color fg})? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.characterColor(char);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: big ? 10 : 8, vertical: big ? 3 : 2),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(8)),
      child: Text(char,
          style: TextStyle(
              fontSize: big ? 12 : 11, fontWeight: FontWeight.w700, color: c.fg)),
    );
  }
}

/// 작은 태그 칩 (원작·모드·난이도 표시).
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, required this.bg, required this.fg});

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

/// 결과 화면 상단 내비바: ← 창작 결과물 ···
class ResultNavBar extends StatelessWidget {
  const ResultNavBar({super.key, this.onMore});

  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          NavBackButton(onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('작품 보기',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
          ),
          GestureDetector(
            onTap: onMore,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text('···',
                  style: TextStyle(
                      fontSize: 16, color: AppColors.textFaint, letterSpacing: 2)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 결과 화면 제목 영역: 제목 + 연필(인라인 수정) + 원작/모드/난이도 태그.
class ResultTitleSection extends StatelessWidget {
  const ResultTitleSection({
    super.key,
    required this.title,
    required this.source,
    required this.sourceColor,
    required this.mode,
    required this.level,
    this.onEditTitle,
  });

  final String title;
  final String source;
  final Color sourceColor;
  final String mode; // '대사극' | '오디오극'
  final String level;
  final VoidCallback? onEditTitle;

  @override
  Widget build(BuildContext context) {
    final displayLevel = levelDisplayLabel(level);
    // 난이도 태그 색: '고전의 결 살리기' 만 앰버 톤으로 구분.
    final levelBg = displayLevel == '고전의 결 살리기'
        ? const Color(0xFFFFF3E0)
        : const Color(0xFFEFEFEF);
    final levelFg = displayLevel == '고전의 결 살리기'
        ? const Color(0xFFA06020)
        : const Color(0xFF777777);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                        color: AppColors.ink)),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onEditTitle,
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.alpha(AppColors.sage, 0x18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.edit_outlined, size: 14, color: AppColors.sage),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TagChip(label: source, bg: AppColors.alpha(sourceColor, 0x22), fg: sourceColor),
              TagChip(
                  label: mode,
                  bg: AppColors.alpha(AppColors.sage, 0x18),
                  fg: AppColors.sage),
              // 결과 화면은 가로 여유가 있어 칩이 늘어나므로 항상 한 줄로 둔다.
              TagChip(label: displayLevel, bg: levelBg, fg: levelFg),
            ],
          ),
        ],
      ),
    );
  }
}

/// 줄을 탭/길게 눌렀을 때 나오는 인라인 액션 메뉴 (가로 3분할).
class LineActionMenu extends StatelessWidget {
  const LineActionMenu({super.key, required this.actions, this.borderColor});

  final List<(String icon, String label, Color color, VoidCallback? onTap)> actions;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor ?? AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x17000000), blurRadius: 14, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          for (int i = 0; i < actions.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: actions[i].$4,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                  decoration: BoxDecoration(
                    border: i < actions.length - 1
                        ? const Border(right: BorderSide(color: AppColors.border))
                        : null,
                  ),
                  child: Column(
                    children: [
                      Text(actions[i].$1, style: const TextStyle(fontSize: 17)),
                      const SizedBox(height: 4),
                      Text(actions[i].$2,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 9,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                              color: actions[i].$3)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 어휘 사전 (대사극·오디오극 공용) ─────────────────────────
//
// 생성 결과에 임베드된 어휘({단어:{hanja?,meaning,note?}})의 단어는 본문에서 찾아
// 점선 밑줄 + 즉시 풀이로 보여 준다(서버 호출 없음, 탭하면 바로 뜻).
// 그 밖의 단어는 기본적으로 '일반 텍스트'다(탭해도 사전이 뜨지 않음 — 단어마다 떠서
// 거슬리는 문제 방지). [longPressLookup] 을 켜면 그 외 단어를 '꾹 누를 때만' 서버
// /vocab 으로 즉석(on-demand) 풀이를 받아 온다(온라인 전용). 화면에서 줄 탭/롱프레스가
// 다른 동작에 쓰이면(예: 대사극 줄 메뉴=롱프레스) 끄고, 그렇지 않으면 켜서 쓴다.
// (백엔드 계약: 기본 사전은 /create finalize 의 result.vocab, /vocab 은 미임베드 폴백)

/// /vocab 즉석 풀이 세션 캐시. 같은 (수준|단어) 는 한 번만 호출한다(과금/지연 절약).
final Map<String, VocabEntry> _vocabLiveCache = {};

/// 임베드(핵심) 단어는 점선 밑줄 + 탭하면 즉시 뜻을 보여 준다.
/// [longPressLookup] 이 켜져 있으면 그 외 단어는 '꾹 누를 때만' /vocab 으로 즉석 조회한다.
/// [level] 은 서버 /vocab(on-demand) 호출에 함께 보낸다.
class VocabText extends ConsumerStatefulWidget {
  const VocabText({
    super.key,
    required this.text,
    required this.baseStyle,
    required this.vocab,
    this.level = '청소년용',
    this.highlighted = false,
    this.longPressLookup = false,
  });

  final String text;
  final TextStyle baseStyle;
  final Map<String, VocabEntry> vocab; // 이 작품의 어휘 사전
  final String level; // 읽기 수준(/vocab 호출용)
  final bool highlighted; // 표시하기(노란색) 적용 여부
  // 임베드에 없는 단어를 '꾹 누르면' /vocab 으로 즉석 풀이. 줄 롱프레스가 다른 동작에
  // 쓰이는 화면(대사극 줄 메뉴)에서는 꺼 둔다(기본 off).
  final bool longPressLookup;

  @override
  ConsumerState<VocabText> createState() => _VocabTextState();
}

class _VocabTextState extends ConsumerState<VocabText> {
  final List<GestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  // 탭 가능한 단어 묶음(한글 음절/영문/숫자 연속). 사이의 공백·문장부호는 일반 텍스트.
  static final RegExp _wordRe = RegExp(r'[가-힣A-Za-z0-9]+');

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final base = widget.baseStyle;
    final text = widget.text;

    // 1) 임베드 사전(생성 결과 vocab)에 있는 단어 위치를 먼저 찾는다(부분 문자열).
    final keys = widget.vocab.keys.where(text.contains).toList();
    final embedded = <List<int>>[]; // [start, end]
    if (keys.isNotEmpty) {
      final pattern = RegExp(keys.map(RegExp.escape).join('|'));
      for (final m in pattern.allMatches(text)) {
        embedded.add([m.start, m.end]);
      }
      embedded.sort((a, b) => a[0].compareTo(b[0]));
    }

    final spans = <InlineSpan>[];
    int cursor = 0;
    for (final range in embedded) {
      final start = range[0], end = range[1];
      if (start < cursor) continue; // 겹치면 건너뜀
      if (start > cursor) _addTokenized(spans, text.substring(cursor, start));
      final word = text.substring(start, end);
      spans.add(TextSpan(
        text: word,
        recognizer: _tap(word, widget.vocab[word]),
        style: base.copyWith(
          color: AppColors.sage,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
          decorationColor: AppColors.sage,
        ),
      ));
      cursor = end;
    }
    if (cursor < text.length) _addTokenized(spans, text.substring(cursor));

    return _highlight(Text.rich(TextSpan(children: spans, style: base)));
  }

  /// 임베드되지 않은 구간. 기본은 그냥 일반 텍스트(탭해도 사전 안 뜸).
  /// [longPressLookup] 이 켜져 있을 때만 단어를 '꾹 누르면' /vocab 으로 즉석 조회한다.
  void _addTokenized(List<InlineSpan> spans, String segment) {
    if (!widget.longPressLookup) {
      spans.add(TextSpan(text: segment));
      return;
    }
    int c = 0;
    for (final wm in _wordRe.allMatches(segment)) {
      if (wm.start > c) spans.add(TextSpan(text: segment.substring(c, wm.start)));
      final w = wm.group(0)!;
      spans.add(TextSpan(text: w, recognizer: _longPress(w)));
      c = wm.end;
    }
    if (c < segment.length) spans.add(TextSpan(text: segment.substring(c)));
  }

  /// 임베드 단어 탭 → 즉시 풀이 시트([prebuilt] 가 있어 서버 호출 없음).
  TapGestureRecognizer _tap(String word, VocabEntry? prebuilt) {
    final r = TapGestureRecognizer()
      ..onTap = () => showWordSheet(
            context,
            ref,
            word: word,
            prebuilt: prebuilt,
            contextLine: widget.text,
            level: widget.level,
          );
    _recognizers.add(r);
    return r;
  }

  /// 임베드에 없는 단어를 '꾹 누르면' 풀이 시트를 연다(시트가 /vocab 로 즉석 조회).
  /// 탭은 비워 둬 화면의 다른 제스처(줄 탭=재생 등)와 부딪히지 않게 한다.
  LongPressGestureRecognizer _longPress(String word) {
    final r = LongPressGestureRecognizer()
      ..onLongPress = () => showWordSheet(
            context,
            ref,
            word: word,
            prebuilt: null,
            contextLine: widget.text,
            level: widget.level,
          );
    _recognizers.add(r);
    return r;
  }

  /// 표시하기: 글자마다 높낮이가 다른 backgroundColor 대신,
  /// 텍스트 전체에 균일한 형광펜 배경을 입혀 쉼표·공백에서 어긋나지 않게 한다.
  Widget _highlight(Widget child) {
    if (!widget.highlighted) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.highlight,
        borderRadius: BorderRadius.circular(3),
      ),
      child: child,
    );
  }
}

/// 단어 풀이 바텀시트. [prebuilt] 은 생성 시 받아 둔 풀이(있으면 즉시 표시),
/// 'AI 사전' 버튼을 누르면 서버 /vocab 으로 문맥 반영 풀이를 받아 더 자세히 보여준다.
Future<void> showWordSheet(
  BuildContext context,
  WidgetRef ref, {
  required String word,
  VocabEntry? prebuilt,
  required String contextLine,
  required String level,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => _WordSheet(
      word: word,
      prebuilt: prebuilt,
      contextLine: contextLine,
      level: level,
    ),
  );
}

class _WordSheet extends ConsumerStatefulWidget {
  const _WordSheet({
    required this.word,
    required this.prebuilt,
    required this.contextLine,
    required this.level,
  });

  final String word;
  final VocabEntry? prebuilt;
  final String contextLine;
  final String level;

  @override
  ConsumerState<_WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends ConsumerState<_WordSheet> {
  late VocabEntry? _entry = widget.prebuilt;
  bool _loading = false;
  bool _fromServer = false; // 서버 /vocab 풀이인지(임베드 사전 아님)
  bool _offline = false; // 오프라인이라 못 불러옴
  bool _failed = false; // 서버 호출 실패(502 등)

  @override
  void initState() {
    super.initState();
    final cached = _vocabLiveCache['${widget.level}|${widget.word}'];
    if (cached != null) {
      _entry = cached;
      _fromServer = true;
    } else if (widget.prebuilt == null) {
      // 임베드 사전에 없는 단어 → 열리자마자 서버 /vocab 으로 즉석 조회.
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
    }
  }

  /// 서버 /vocab 으로 문맥 반영 풀이를 받아 온다(온라인 전용, 미임베드 폴백).
  Future<void> _lookup() async {
    final key = '${widget.level}|${widget.word}';
    final cached = _vocabLiveCache[key];
    if (cached != null) {
      setState(() {
        _entry = cached;
        _fromServer = true;
        _offline = false;
        _failed = false;
      });
      return;
    }
    // 오프라인이면 호출하지 않고(과금·무한 대기 방지) 안내만 표시한다.
    final online =
        await ref.read(connectivityServiceProvider).isServerReachable();
    if (!mounted) return;
    if (!online) {
      setState(() {
        _offline = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _offline = false;
      _failed = false;
    });
    try {
      final entry = await ref.read(apiClientProvider).vocab(
            word: widget.word,
            context: widget.contextLine,
            level: widget.level,
          );
      _vocabLiveCache[key] = entry;
      if (!mounted) return;
      setState(() {
        _entry = entry;
        _fromServer = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _entry;
    final hasMeaning = data?.meaning.isNotEmpty ?? false;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: _SheetHandle()),
          // 단어 + 한자
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(widget.word,
                      style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink)),
                ),
                if (data?.hanja != null) ...[
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(data!.hanja!,
                        style: const TextStyle(
                            fontSize: 17, color: AppColors.textFaint)),
                  ),
                ],
                const Spacer(),
                if (_fromServer)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.alpha(AppColors.sage, 0x18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('✨ AI 사전',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.sage)),
                  ),
              ],
            ),
          ),
          // 뜻 / 로딩 / 오프라인 / 실패
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('뜻',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: Color(0xFFCCCCCC))),
                const SizedBox(height: 9),
                if (_loading)
                  Row(
                    children: const [
                      SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text('AI 사전에서 뜻을 찾고 있어요…',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSub)),
                    ],
                  )
                else if (hasMeaning)
                  Text(data!.meaning,
                      style: const TextStyle(
                          fontSize: 14, height: 1.75, color: Color(0xFF333333)))
                else if (_offline)
                  const Text(
                      '오프라인이라 이 단어 뜻을 불러올 수 없어요.\n인터넷에 연결한 뒤 다시 시도해 주세요.',
                      style: TextStyle(
                          fontSize: 13, height: 1.7, color: AppColors.textSub))
                else if (_failed)
                  const Text('뜻을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
                      style: TextStyle(
                          fontSize: 13, height: 1.7, color: AppColors.textSub))
                else
                  const Text('뜻을 찾는 중이에요…',
                      style: TextStyle(
                          fontSize: 13, height: 1.7, color: AppColors.textSub)),
              ],
            ),
          ),
          if (hasMeaning && data?.note != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.alpha(AppColors.sage, 0x0C),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.alpha(AppColors.sage, 0x20)),
              ),
              child: Text('💡 ${data!.note}',
                  style: const TextStyle(
                      fontSize: 12, height: 1.65, color: Color(0xFF555555))),
            ),
          // 오프라인·실패 시 다시 시도 버튼.
          if (!_loading && !hasMeaning && (_offline || _failed))
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: GestureDetector(
                onTap: _lookup,
                child: Container(
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.alpha(AppColors.sage, 0x10),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppColors.alpha(AppColors.sage, 0x30)),
                  ),
                  child: const Text('다시 시도',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.sage)),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.sage,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.alpha(AppColors.sage, 0x40),
                        blurRadius: 16,
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: const Text('확인',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 바텀시트 손잡이(공용).
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
