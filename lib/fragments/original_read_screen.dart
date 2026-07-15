import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sample_data.dart';
import '../services/books_service.dart';
import '../services/db_service.dart';
import '../state/library_state.dart';
import '../theme/app_colors.dart';
import '../widgets/phone_shell.dart' show NavBackButton;

/// 원작 읽기 화면.
/// 대표 이미지 + 줄거리 + 원작 본문(에셋 txt 로드). 읽던 위치 저장 · 즐겨찾기 지원.
class OriginalReadScreen extends ConsumerStatefulWidget {
  const OriginalReadScreen({super.key, required this.source});

  final String source;

  @override
  ConsumerState<OriginalReadScreen> createState() =>
      _OriginalReadScreenState();
}

class _OriginalReadScreenState extends ConsumerState<OriginalReadScreen> {
  late final ScrollController _scroll;
  LibraryNotifier? _lib; // dispose 에서 ref 를 쓰지 않도록 미리 잡아 두는 notifier
  Timer? _saveTimer; // 스크롤 중 잦은 저장을 막는 디바운스
  List<String> _paragraphs = const [];
  bool _loading = true;
  double _offset = 0; // 마지막 스크롤 위치(스크롤뷰가 분리돼도 유지).

  @override
  void initState() {
    super.initState();
    // 읽던 위치를 시작 오프셋으로 둔다. 본문이 그려지며 스크롤뷰가 처음 붙는 순간
    // 이 위치에서 시작하므로, "한 프레임 뒤 jumpTo" 의 타이밍 문제가 없다.
    // (저장 범위를 넘으면 첫 레이아웃에서 자동으로 최대치로 클램프된다)
    final saved = ref.read(libraryProvider).reading[widget.source] ?? 0;
    _offset = saved;
    _scroll = ScrollController(initialScrollOffset: saved);
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 저장에 쓸 notifier 를 미리 잡아 둔다(dispose 시 ref 접근 회피).
    _lib = ref.read(libraryProvider.notifier);
  }

  /// 스크롤할 때마다 위치를 기록하고, 잠시 멈추면 저장한다(디바운스).
  void _onScroll() {
    if (!_scroll.hasClients) return;
    _offset = _scroll.offset;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), _save);
  }

  void _save() => _lib?.setReading(widget.source, _offset);

  Future<void> _load() async {
    // 제목 → 서버 bookId 해석.
    final book = ref.read(booksByTitleProvider)[widget.source];
    if (book != null) {
      final db = ref.read(dbServiceProvider);
      // 1) 디바이스에 저장된 본문 우선(앱 실행 시 선반입됨 → 오프라인·즉시 표시).
      final stored = await db.getOriginalText(book.bookId);
      if (stored != null && stored.isNotEmpty) {
        _paragraphs = _parse(stored);
      } else {
        // 2) 아직 없으면(선반입 전/실패) 그때 받아서 표시하고 저장(폴백 + 선반입 보완).
        try {
          final raw =
              await ref.read(booksApiProvider).fetchOriginalText(book.bookId);
          _paragraphs = _parse(raw);
          if (raw.isNotEmpty) await db.setOriginalText(book.bookId, raw);
        } catch (_) {
          _paragraphs = const [];
        }
      }
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  /// 본문 파싱: 빈 줄·번호(2,3,4…)는 무시하고, 맨 앞 제목 줄도 제거.
  List<String> _parse(String raw) {
    final out = <String>[];
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (RegExp(r'^\d+$').hasMatch(t)) continue; // 문단 번호 무시
      out.add(t);
    }
    // 맨 앞 짧은 줄(제목)은 제외 — 표지에 제목이 이미 있음.
    if (out.isNotEmpty && out.first.replaceAll(' ', '').length <= 12) {
      out.removeAt(0);
    }
    return out;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    // 읽던 위치 저장(기록해 둔 마지막 offset + 미리 잡아 둔 notifier 사용).
    // dispose 는 위젯 트리 finalize(lockState) 도중 호출되므로, 여기서 provider 를
    // 곧바로 수정하면 Riverpod 가 막는다(트리 잠금 상태에서의 알림 금지).
    // libraryProvider 는 전역이라 화면이 unmount 돼도 살아 있으므로, 잠금이 풀린
    // 마이크로태스크로 미뤄 저장한다.
    final lib = _lib;
    if (lib != null) {
      final source = widget.source;
      final offset = _offset;
      scheduleMicrotask(() => lib.setReading(source, offset));
    }
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final color = bookColor(source);
    final img = bookImage(source);
    // 줄거리 요약: 서버 Book.shortDescription 우선, 없으면 로컬 팁/기본.
    final serverDesc = ref.watch(booksByTitleProvider)[source]?.shortDescription;
    final summary = (serverDesc != null && serverDesc.isNotEmpty)
        ? serverDesc
        : (kBookTips[source] ?? '선택한 원작에서 출발한 고전 이야기예요.');
    final isFav =
        ref.watch(libraryProvider.select((s) => s.favorites.contains(source)));

    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      body: SafeArea(
        child: Column(
          children: [
            // 상단 바
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  NavBackButton(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('원작',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                  ),
                  // 즐겨찾기
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => ref
                        .read(libraryProvider.notifier)
                        .toggleFavorite(source),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(isFav ? Icons.star : Icons.star_border,
                          size: 24,
                          color: isFav ? const Color(0xFFE8A93C) : AppColors.textFaint),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : SingleChildScrollView(
                      controller: _scroll,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _hero(source, color, img),
                          _section('줄거리',
                              child: Text(summary,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.8,
                                      color: Color(0xFF333333)))),
                          _content(),
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 헤더: 대표 이미지 + 제목 ──
  Widget _hero(String source, Color color, String? img) => SizedBox(
        height: 210,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (img != null)
              (img.startsWith('http')
                  ? Image.network(img,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(color: color))
                  : Image.asset(img, fit: BoxFit.cover))
            else
              ColoredBox(color: color),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x14000000), Color(0x99000000)],
                  stops: [0.4, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.alpha(Colors.black, 0x4D),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('원작',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: Colors.white)),
                  ),
                  const SizedBox(height: 8),
                  Text(source,
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                                color: Color(0x99000000),
                                blurRadius: 6,
                                offset: Offset(0, 2)),
                          ])),
                ],
              ),
            ),
          ],
        ),
      );

  // ── 본문(원작 내용) ──
  Widget _content() {
    if (_paragraphs.isEmpty) {
      return _section('원작 전문',
          child: const Text('원작은 준비 중이에요.',
              style: TextStyle(fontSize: 13, color: AppColors.textSub)));
    }
    return _section('원작 전문',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < _paragraphs.length; i++)
              Padding(
                padding: EdgeInsets.only(
                    bottom: i == _paragraphs.length - 1 ? 0 : 14),
                child: Text(_paragraphs[i],
                    style: const TextStyle(
                        fontSize: 14, height: 1.9, color: Color(0xFF2A2A2A))),
              ),
          ],
        ));
  }

  // ── 공통 섹션(라벨 + 내용 카드) ──
  Widget _section(String label, {required Widget child}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Color(0xFF909090))),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: child,
            ),
          ],
        ),
      );
}
