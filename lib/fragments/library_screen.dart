import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sample_data.dart';
import '../services/books_service.dart';
import '../services/cover_picker.dart';
import '../state/create_main_state.dart'
    show CreateMode, createMainProvider, levelDisplayLabel;
import '../state/library_state.dart';
import '../state/navigation.dart';
import '../theme/app_colors.dart';
import '../widgets/phone_shell.dart' show NavBackButton;
import '../widgets/result_shared.dart' show TagChip;
import 'audio_result_screen.dart';
import 'dialogue_result_screen.dart';
import 'original_read_screen.dart';

/// 내 서재. 앱 셸의 탭 1.
/// 책장(원작별 책등) → 책을 누르면 원작별 창작물 보기(페이지 넘김)로 전환.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(libraryProvider);
    // 원작 목록은 서버(GET /books, SQLite 캐시)에서. 로딩 전엔 빈 목록 → 창작물 있는 원작만 표시.
    final serverTitles =
        ref.watch(booksProvider).valueOrNull?.map((b) => b.title).toList() ??
            const <String>[];
    final originals = allOriginals(st.works, st.sort, serverTitles, st.favorites);

    if (st.openSource != null) {
      final works = originals
              .where((g) => g.$1 == st.openSource)
              .firstOrNull
              ?.$2 ??
          const [];
      return _BookView(
          key: ValueKey(st.openSource), source: st.openSource!, works: works);
    }
    return _ShelfView(
        groups: originals, sort: st.sort, favorites: st.favorites);
  }
}

// ── 책장 화면 ────────────────────────────────────────────

class _ShelfView extends ConsumerWidget {
  const _ShelfView(
      {required this.groups, required this.sort, required this.favorites});

  /// 모든 원작(창작물 없는 원작 포함).
  final List<(String, List<CreativeWork>)> groups;
  final LibrarySort sort;
  final Set<String> favorites;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 한 칸(선반)에 책 5권씩 배치.
    const perRow = 5;
    final rows = <List<(String, List<CreativeWork>)>>[];
    for (int i = 0; i < groups.length; i += perRow) {
      rows.add(groups.sublist(
          i, i + perRow > groups.length ? groups.length : i + perRow));
    }

    // 최근 창작물(수정일 내림차순) 최대 3개.
    final recent = groups.expand((g) => g.$2).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final recentTop = recent.take(3).toList();

    return ColoredBox(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 헤더
          const SizedBox(
            height: 52,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('작품 보관함',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          // 본문
          Expanded(
            child: Container(
              color: AppColors.shelfBg,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 최근 창작물
                    if (recentTop.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _pillLabel('최근 완성작'),
                          _countBadge('${recent.length}개의 이야기'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (int i = 0; i < recentTop.length; i++)
                        _recentRow(context, recentTop[i],
                            last: i == recentTop.length - 1),
                      const SizedBox(height: 20),
                    ],
                    // 원작 라벨 + 정렬 토글(최신순/가나다순)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _pillLabel('원작'),
                        _sortToggle(ref),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 한 줄에 perRow 권이 정확히 들어가도록 책등 너비를 폭에 맞춰 계산.
                    LayoutBuilder(
                      builder: (context, c) {
                        const gap = 8.0;
                        const overhang = 4.0; // 선반이 책 양끝보다 더 나오는 정도
                        final spineW =
                            (c.maxWidth - overhang * 2 - gap * (perRow - 1)) /
                                perRow;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final row in rows)
                              _shelfRow(
                                  context, ref, row, spineW, gap, overhang),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 섹션 라벨/배지 ──
  Widget _pillLabel(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.shelfWood),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8A7350))),
      );

  // ── 정렬 토글 (최신순 | 가나다순) ──
  Widget _sortToggle(WidgetRef ref) {
    Widget seg(String label, LibrarySort mode) {
      final on = sort == mode;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(libraryProvider.notifier).setSort(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: on ? AppColors.sage : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : AppColors.textSub)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.shelfWood),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('최신순', LibrarySort.recent),
          seg('가나다순', LibrarySort.title),
        ],
      ),
    );
  }

  Widget _countBadge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF0EAE2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSub)),
      );

  // ── 최근 창작물 한 줄: 색 바 + 아이콘 + 제목/모드·날짜 + ›
  Widget _recentRow(BuildContext context, CreativeWork w,
      {required bool last}) {
    final color = bookColor(w.source);
    final modeLabel = w.mode == CreateMode.dialogue ? '대사극' : '오디오극';
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openWork(context, w),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  // 5:7 비율(가로:세로) — 사진 이미지 비율에 맞춰 가로만 줄임
                  width: 30,
                  height: 42,
                  alignment: Alignment.center,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.alpha(color, 0x33),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  // 창작물 썸네일: 표지(오프라인 캐시 우선 → 원격 URL) → (없으면) 대표 이모지/🎭.
                  child: w.coverDisplayPath != null
                      ? netOrAssetCover(w.coverDisplayPath!, color)
                      : Text(w.coverEmoji, style: const TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink)),
                      const SizedBox(height: 3),
                      Text('$modeLabel · ${_shortDate(w.updatedAt)}',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSub)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.textFaint),
              ],
            ),
          ),
        ),
        if (!last) const Divider(height: 1, color: AppColors.shelfWood),
      ],
    );
  }

  String _shortDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  /// 최근 창작물 탭 → 결과 화면을 바로 연다.
  void _openWork(BuildContext context, CreativeWork w) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => w.mode == CreateMode.dialogue
          ? DialogueResultScreen(
              workId: w.id, title: w.title, source: w.source, level: w.level)
          : AudioResultScreen(
              workId: w.id, title: w.title, source: w.source, level: w.level),
    ));
  }

  /// 책등 높이를 원작별로 살짝 다르게 해 자연스러운 책장 윗면을 만든다.
  double _spineHeight(String source) {
    final v = source.runes.fold(0, (a, b) => a + b) % 5; // 0..4
    return 168 + v * 9; // 168 ~ 204
  }

  /// 선반 한 칸: 책등들이 바닥 판자 위에 올라선 모양.
  Widget _shelfRow(BuildContext context, WidgetRef ref,
      List<(String, List<CreativeWork>)> row, double spineW, double gap,
      double overhang) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 책들은 양옆을 overhang 만큼 들여서, 아래 판자가 더 길게 보이도록.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: overhang),
            child: SizedBox(
              height: 204,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int i = 0; i < row.length; i++) ...[
                    _BookSpine(
                      source: row[i].$1,
                      count: row[i].$2.length,
                      width: spineW,
                      height: _spineHeight(row[i].$1),
                      favorite: favorites.contains(row[i].$1),
                      onTap: () => ref
                          .read(libraryProvider.notifier)
                          .openBook(row[i].$1),
                      onLongPress: () =>
                          _showBookMenu(context, ref, row[i].$1),
                    ),
                    if (i < row.length - 1) SizedBox(width: gap),
                  ],
                ],
              ),
            ),
          ),
          // 선반 판자
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.shelfWood,
              borderRadius: BorderRadius.circular(3),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 책을 길게 누르면 뜨는 메뉴: 원작 읽기 · 즐겨찾기 추가/삭제.
  void _showBookMenu(BuildContext context, WidgetRef ref, String source) {
    final n = ref.read(libraryProvider.notifier);
    final isFav = ref.read(libraryProvider).favorites.contains(source);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 손잡이
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFDEDEDE),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // 제목(원작명)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 18,
                    decoration: BoxDecoration(
                      color: bookColor(source),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(source,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Text('📖', style: TextStyle(fontSize: 20)),
              title: const Text('원작 읽기',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => OriginalReadScreen(source: source),
                ));
              },
            ),
            ListTile(
              leading: Text(isFav ? '⭐' : '☆', style: const TextStyle(fontSize: 20)),
              title: Text(isFav ? '즐겨찾기에서 빼기' : '즐겨찾기에 추가',
                  style:
                      const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                n.toggleFavorite(source);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 책등 1권. 제목 세로쓰기 + 하단 편수 배지.
class _BookSpine extends StatelessWidget {
  const _BookSpine(
      {required this.source,
      required this.count,
      required this.onTap,
      this.onLongPress,
      this.height = 182,
      this.width = 62,
      this.favorite = false});

  final String source;
  final int count;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double height;
  final double width;
  final bool favorite;

  @override
  Widget build(BuildContext context) {
    final color = bookColor(source);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: width,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(2, 3)),
          ],
        ),
        child: Stack(
          children: [
            // 책등 입체 음영: 좌측 접힘 그림자 → 가운데 광택 → 우측 둥근 음영
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0x33000000),
                      Color(0x0FFFFFFF),
                      Color(0x1AFFFFFF),
                      Color(0x00000000),
                      Color(0x26000000),
                    ],
                    stops: [0.0, 0.13, 0.42, 0.72, 1.0],
                  ),
                ),
              ),
            ),
            // 왼쪽 페이지(책배) 가장자리 밝은 선
            const Positioned(
              left: 4,
              top: 8,
              bottom: 8,
              width: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0x26FFFFFF)),
              ),
            ),
            // 콘텐츠: 장식 띠 + 세로 제목 + 편수
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Column(
                children: [
                  _band(),
                  Expanded(
                    child: Center(
                      // 5자 제목(예: 콩쥐팥쥐전)은 짧은 책등에선 1px 넘쳐 오버플로가 떴다.
                      // FittedBox(scaleDown) 로 남는 높이에 맞춰 살짝 줄여 항상 들어가게 한다.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 세로쓰기 제목 (최대 5자)
                            for (final ch
                                in source.replaceAll(' ', '').characters.take(5))
                              Text(ch,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.35,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _band(),
                  const SizedBox(height: 9),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0x4A000000),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$count편',
                        style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ],
              ),
            ),
            // 즐겨찾기 별
            if (favorite)
              const Positioned(
                top: 6,
                right: 6,
                child: Text('⭐', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  /// 하드커버 책등 느낌의 가는 장식 2줄.
  Widget _band() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                height: 1.5,
                width: double.infinity,
                child: ColoredBox(color: Color(0x59FFFFFF))),
            SizedBox(height: 2),
            SizedBox(
                height: 1.5,
                width: double.infinity,
                child: ColoredBox(color: Color(0x33FFFFFF))),
          ],
        ),
      );
}

// ── 원작별 창작물 보기 ────────────────────────────────────

class _BookView extends ConsumerStatefulWidget {
  const _BookView({super.key, required this.source, required this.works});

  final String source;
  final List<CreativeWork> works;

  @override
  ConsumerState<_BookView> createState() => _BookViewState();
}

class _BookViewState extends ConsumerState<_BookView>
    with SingleTickerProviderStateMixin {
  // 책장 넘김 애니메이션. 천천히(약 0.8초) 넘어가도록 설정.
  late final AnimationController _flip;
  bool _animating = false;
  int _fromIndex = 0; // 넘기기 시작한 페이지
  int _toIndex = 0; // 도착할 페이지
  int _dir = 1; // 1: 다음(오른쪽 페이지가 왼쪽을 덮음) / -1: 이전

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 820));
    _flip.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // 넘김 완료 → 실제 페이지를 도착 페이지로 확정.
        ref.read(libraryProvider.notifier).setPage(_toIndex);
        _flip.reset();
        if (mounted) setState(() => _animating = false);
      }
    });
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  // 첫 장(0)은 항상 원작, 그다음 장부터 창작물. 창작물이 없으면 [원작, 빈 페이지] 2장.
  int get _pageCount => widget.works.isEmpty ? 2 : widget.works.length + 1;

  /// 페이지 index 에 해당하는 창작물 (0=원작 → null, 창작물 없는 빈 페이지 → null).
  CreativeWork? _workAt(int index) =>
      (index >= 1 && index <= widget.works.length)
          ? widget.works[index - 1]
          : null;

  /// 페이지를 [delta]만큼 이동(범위 밖이거나 애니메이션 중이면 무시).
  void _go(int delta) {
    if (_animating) return;
    final maxIdx = _pageCount - 1;
    final cur = ref.read(libraryProvider).page.clamp(0, maxIdx);
    final next = (cur + delta).clamp(0, maxIdx);
    if (next == cur) return;
    setState(() {
      _fromIndex = cur;
      _toIndex = next;
      _dir = delta > 0 ? 1 : -1;
      _animating = true;
    });
    _flip.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final n = ref.read(libraryProvider.notifier);
    // 표지 변경 시 다시 그리도록 covers 도 구독.
    ref.watch(libraryProvider.select((s) => s.covers));
    final isFav = ref
        .watch(libraryProvider.select((s) => s.favorites.contains(widget.source)));
    final committed = ref
        .watch(libraryProvider.select((s) => s.page))
        .clamp(0, _pageCount - 1);
    // 인디케이터/툴바/CTA는 넘기는 중이면 도착 페이지를 미리 반영.
    final shownPage = _animating ? _toIndex : committed;
    final shownWork = _workAt(shownPage);

    return ColoredBox(
      color: AppColors.shelfBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(n, isFav),
          // 책을 화면 중앙에 크게 배치.
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                // 화면 폭에 맞춰 카드 크기 산정(최대 330×231 비율 유지).
                final cardW = (c.maxWidth - 48).clamp(0.0, 330.0).toDouble();
                final cardH = cardW * 231 / 330;
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 카드 위 툴바(이미지/수정/삭제) — 창작물 페이지에서만.
                      SizedBox(
                        width: cardW,
                        height: 32,
                        child: shownWork != null ? _toolbar(shownWork, n) : null,
                      ),
                      const SizedBox(height: 12),
                      // 책 카드 (탭 · 스와이프/넘김 애니메이션)
                      GestureDetector(
                        onTap: _animating ? null : () => _onCardTap(shownPage),
                        onHorizontalDragEnd: (d) {
                          final v = d.primaryVelocity ?? 0;
                          if (v < -120) {
                            _go(1);
                          } else if (v > 120) {
                            _go(-1);
                          }
                        },
                        child: _animating
                            ? _flipBook(cardW, cardH)
                            : _staticCard(committed, cardW, cardH),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(width: cardW, child: _indicator(shownPage)),
                    ],
                  ),
                );
              },
            ),
          ),
          _pageCta(shownPage),
        ],
      ),
    );
  }

  /// 카드 탭: 창작물 → 열기, 원작 → 원작 보기, 빈 페이지 → 동작 없음(아래 CTA로 창작).
  void _onCardTap(int index) {
    final w = _workAt(index);
    if (w != null) {
      _openWork(w);
    } else if (index == 0) {
      _openOriginal();
    }
  }

  /// 정적(고정) 카드: 페이지 index 의 좌/우 내용을 펼친 책으로.
  Widget _staticCard(int index, double w, double h) {
    return SizedBox(
      width: w + 24,
      height: h + 12,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          ..._bookSheets(w, h),
          _bookSpread(
            left: _leftContent(index),
            right: _rightContent(index),
            w: w,
            h: h,
          ),
        ],
      ),
    );
  }

  // ── 페이지별 좌/우 내용 (0=원작, 1..=창작물, 창작물 없으면 1=빈 페이지) ──
  Widget _leftContent(int i) {
    if (i == 0) return _originalCoverContent(widget.source);
    final w = _workAt(i);
    if (w == null) return _emptyLeftContent(widget.source);
    final cover = ref.read(libraryProvider).covers[w.id];
    return _coverPageContent(w, coverImage: cover);
  }

  Widget _rightContent(int i) {
    if (i == 0) return _originalInfoContent(widget.source);
    final w = _workAt(i);
    if (w == null) return _emptyRightContent();
    return _infoPageContent(w);
  }

  Widget _leftFace(int i, double w, double h) => ClipRRect(
        borderRadius:
            const BorderRadius.horizontal(left: Radius.circular(_kBookRadius)),
        child: SizedBox(width: w, height: h, child: _leftContent(i)),
      );

  Widget _rightFace(int i, double w, double h) => ClipRRect(
        borderRadius:
            const BorderRadius.horizontal(right: Radius.circular(_kBookRadius)),
        child: SizedBox(width: w, height: h, child: _rightContent(i)),
      );

  // ── 페이지 넘김(책장 플립) ──
  /// 책등(가운데)을 축으로 한 장이 3D로 회전하며 넘어간다.
  /// - 다음(_dir>0): 오른쪽 페이지가 왼쪽으로 접히며 왼쪽 페이지를 덮는다.
  /// - 이전(_dir<0): 왼쪽 페이지가 오른쪽으로 접히며 오른쪽 페이지를 덮는다.
  Widget _flipBook(double w, double h) {
    final halfW = w / 2;
    final forward = _dir > 0;

    return AnimatedBuilder(
      animation: _flip,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_flip.value);
        final angle = (forward ? -1.0 : 1.0) * math.pi * t; // 0 → ±180°
        final showFront = t < 0.5;

        // 아래(정적) 레이어: 넘어가는 페이지 뒤로 드러나는 면.
        final bottomLeft = _leftContent(forward ? _fromIndex : _toIndex);
        final bottomRight = _rightContent(forward ? _toIndex : _fromIndex);

        // 넘어가는 페이지의 앞/뒷면. 뒷면은 회전으로 좌우가 뒤집히므로 미리 미러.
        final Widget face;
        if (forward) {
          face = showFront
              ? _rightFace(_fromIndex, halfW, h)
              : _mirrorX(_leftFace(_toIndex, halfW, h));
        } else {
          face = showFront
              ? _leftFace(_fromIndex, halfW, h)
              : _mirrorX(_rightFace(_toIndex, halfW, h));
        }

        final transform = Matrix4.identity()
          ..setEntry(3, 2, 0.0012) // 원근감
          ..rotateY(angle);

        return SizedBox(
          width: w + 24,
          height: h + 12,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              ..._bookSheets(w, h),
              SizedBox(
                width: w,
                height: h,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 정적 카드(펼친 책 + 제본 골)
                    _bookSpread(
                      left: bottomLeft,
                      right: bottomRight,
                      w: w,
                      h: h,
                    ),
                    // 넘어가는 페이지
                    Positioned(
                      left: forward ? halfW : 0,
                      top: 0,
                      width: halfW,
                      height: h,
                      child: Transform(
                        alignment: forward
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        transform: transform,
                        child: face,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _mirrorX(Widget child) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
        child: child,
      );

  // ── 원작 페이지(첫 장) ──
  /// 왼쪽: 원작 대표 이미지.
  Widget _originalCoverContent(String source) {
    final img = bookImage(source);
    final color = bookColor(source);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (img != null)
          netOrAssetCover(img, color)
        else
          ColoredBox(color: color),
        // 하단 가독성 그라데이션
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x73000000)],
              stops: [0.45, 1.0],
            ),
          ),
        ),
        // 오른쪽 책등 그림자
        const Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: 20,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [Color(0x2E000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
        // '원작' 배지
        Positioned(
          top: 10,
          left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.alpha(Colors.black, 0x59),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('원작',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Colors.white)),
          ),
        ),
        // 제목(하단)
        Positioned(
          left: 10,
          right: 10,
          bottom: 12,
          child: Text(source,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                        color: Color(0x80000000),
                        blurRadius: 4,
                        offset: Offset(0, 1)),
                  ])),
        ),
      ],
    );
  }

  /// 오른쪽: 원작 정보(줄거리 + 주요 인물). GET /books/{id} 의 summary·characters 사용(로딩 전 로컬 폴백).
  Widget _originalInfoContent(String source) {
    final color = bookColor(source);
    // 제목 → 서버 bookId → 상세(요약/인물). 로딩 전/실패 시 로컬값 폴백.
    final book = ref.watch(booksByTitleProvider)[source];
    final detail = book == null
        ? null
        : ref.watch(bookDetailProvider(book.bookId)).valueOrNull;
    final summary = (detail != null && detail.summary.isNotEmpty)
        ? detail.summary
        : (kBookTips[source] ?? book?.shortDescription ?? '');
    final chars = (detail != null && detail.characterNames.isNotEmpty)
        ? detail.characterNames
        : (kBookCharacters[source] ?? const <String>[]);
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFFFAF6F0)),
        const Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          width: 16,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0x14000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1C1A17))),
              const SizedBox(height: 8),
              _miniLabel('줄거리'),
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.topLeft,
                child: Text(summary,
                    maxLines: 2, // 줄거리는 1~2줄 미리보기
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10, height: 1.55, color: Color(0xFF5A5A5A))),
              ),
              const SizedBox(height: 6),
              _miniLabel('주요 인물'),
              const SizedBox(height: 5),
              // 인물이 많거나 글씨가 크면 칩이 페이지를 넘쳐 오버플로 경고가 떴다.
              // ① 주요 인물은 최대 5명까지만 노출하고, ② 남는 공간만큼만 칩을 보여 주되
              //    NeverScrollableScrollPhysics 로 감싸 넘쳐도 잘리게(경고 X) 한다.
              Flexible(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final c in chars.take(5))
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.alpha(color, 0x1F),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(c,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: color)),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniLabel(String t) => Text(t,
      style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: Color(0xFFAFAFAF)));

  // ── 창작물 없는 원작의 빈 페이지 — 왼쪽도 책 커버 ──
  Widget _emptyLeftContent(String source) {
    final img = bookImage(source);
    final color = bookColor(source);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (img != null)
          netOrAssetCover(img, color)
        else ...[
          ColoredBox(color: color),
          Center(
            child: Opacity(
              opacity: 0.30,
              child: Text(bookEmoji(source),
                  style: const TextStyle(fontSize: 52)),
            ),
          ),
        ],
        const Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: 20,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [Color(0x1F000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyRightContent() {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFFFAF6F0)),
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('📝', style: TextStyle(fontSize: 30)),
                SizedBox(height: 10),
                Text('아직 만든\n작품이 없어요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                        color: Color(0xFF1C1A17))),
                SizedBox(height: 6),
                Text('아래 버튼으로 만들어봐요',
                    style: TextStyle(fontSize: 11, color: AppColors.textSub)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 헤더: ← 원작 제목 · ☆ 즐겨찾기 · n편 ──
  Widget _header(LibraryNotifier n, bool isFav) => Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: AppColors.surface,
        child: Row(
          children: [
            NavBackButton(onTap: n.closeBook),
            const SizedBox(width: 12),
            Expanded(
              child: Text(widget.source,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink)),
            ),
            // 즐겨찾기 토글
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => n.toggleFavorite(widget.source),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Icon(
                  isFav ? Icons.star : Icons.star_border,
                  size: 24,
                  color: isFav ? const Color(0xFFE8A93C) : AppColors.textFaint,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.alpha(bookColor(widget.source), 0x22),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${widget.works.length}편',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: bookColor(widget.source))),
            ),
          ],
        ),
      );

  // ── 카드 위 툴바 ──
  Widget _toolbar(CreativeWork work, LibraryNotifier n) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _toolBtn('🖼',
              bg: AppColors.alpha(Colors.white, 0xB3),
              onTap: () => _showCoverSheet(context, work)),
          Row(
            children: [
              _toolBtn('✏️',
                  bg: AppColors.alpha(Colors.white, 0xB3),
                  onTap: () => _showRename(context, n, work)),
              const SizedBox(width: 6),
              _toolBtn('🗑',
                  bg: const Color(0xD9FFE8E8),
                  onTap: () => _confirmDelete(context, n, work)),
            ],
          ),
        ],
      );

  Widget _toolBtn(String emoji,
          {required Color bg, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x24000000), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 14)),
        ),
      );

  // ── 페이지 인디케이터(← · 도트 · →) ──
  Widget _indicator(int page) {
    final count = _pageCount; // 원작(1) + 창작물들
    final ac = bookColor(widget.source);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _arrow(Icons.chevron_left, enabled: page > 0, onTap: () => _go(-1)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < count; i++) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: i == page ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == page ? ac : const Color(0x2E000000),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              if (i < count - 1) const SizedBox(width: 5),
            ],
          ],
        ),
        _arrow(Icons.chevron_right,
            enabled: page < count - 1, onTap: () => _go(1)),
      ],
    );
  }

  Widget _arrow(IconData icon,
      {required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.alpha(Colors.white, enabled ? 0xD9 : 0x4D),
          shape: BoxShape.circle,
          boxShadow: enabled
              ? const [
                  BoxShadow(
                      color: Color(0x24000000),
                      blurRadius: 8,
                      offset: Offset(0, 2)),
                ]
              : null,
        ),
        child: Icon(icon,
            size: 20,
            color: enabled ? const Color(0xFF555555) : const Color(0xFFBBBBBB)),
      ),
    );
  }

  // ── 페이지별 하단 CTA ──
  /// 창작물: 대본 열기/이어 듣기 · 원작: 원작 내용 보기 · 빈 페이지: 이 원작으로 창작하기.
  Widget _pageCta(int index) {
    final w = _workAt(index);
    if (w != null) {
      return _ctaButton(
        w.mode == CreateMode.dialogue ? '대본 열기 🎭' : '이어 듣기 🎙',
        () => _openWork(w),
      );
    }
    if (index == 0) {
      return _ctaButton('원작 읽기 📖', _openOriginal);
    }
    return _ctaButton('이 작품으로 창작하기 ✏️', _createFromOriginal);
  }

  Widget _ctaButton(String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.sage,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: AppColors.alpha(AppColors.sage, 0x50),
                    blurRadius: 20,
                    offset: const Offset(0, 5)),
              ],
            ),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ),
      );

  /// 원작 내용 보기 → 원작 읽기 화면으로 이동.
  void _openOriginal() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => OriginalReadScreen(source: widget.source),
    ));
  }

  /// 이 원작으로 창작하기 → 창작 탭으로 이동(해당 원작 선택).
  void _createFromOriginal() {
    ref.read(createMainProvider.notifier).setBook(widget.source);
    ref.read(libraryProvider.notifier).closeBook();
    ref.read(selectedTabProvider.notifier).select(0);
  }

  /// 결과 화면 재사용: 내 서재에서 연 창작물도 같은 결과 화면으로 본다(기획서 7-4).
  void _openWork(CreativeWork work) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => work.mode == CreateMode.dialogue
          ? DialogueResultScreen(
              workId: work.id,
              title: work.title,
              source: work.source,
              level: work.level)
          : AudioResultScreen(
              workId: work.id,
              title: work.title,
              source: work.source,
              level: work.level),
    ));
  }

  /// 대표 이미지 바꾸기 바텀시트 (기획서 7-3: 3가지 후보 중 선택).
  /// '원작 대표 이미지'를 고르면 해당 원작의 표지 이미지를 실제로 적용한다.
  void _showCoverSheet(BuildContext context, CreativeWork work) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text('대표 이미지 바꾸기',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            // 갤러리에서 사진 가져오기 — 실제 적용.
            ListTile(
              leading: const Text('🖼', style: TextStyle(fontSize: 20)),
              title: const Text('갤러리에서 가져오기',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                _pickCoverFromGallery(context, work);
              },
            ),
            // AI가 처음 만든 창작물 대표 이미지(creationCoverImageUrl) — 있으면 실제 적용.
            ListTile(
              leading: const Text('✨', style: TextStyle(fontSize: 20)),
              title: const Text('AI가 처음 만든 이미지',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                // 받아 둔 로컬 AI 표지(오프라인) 우선, 없으면 원격 URL.
                final img = work.coverLocalAbsPath ?? work.creationCoverImageUrl;
                if (img != null && img.isNotEmpty) {
                  ref.read(libraryProvider.notifier).setCover(work.id, img);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('이 작품에는 AI 대표 이미지가 없어요')));
                }
              },
            ),
            // 원작 대표 이미지 — 실제 적용.
            ListTile(
              leading: const Text('📖', style: TextStyle(fontSize: 20)),
              title: const Text('원작 대표 이미지',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                final img = bookImage(work.source);
                if (img != null) {
                  ref.read(libraryProvider.notifier).setCover(work.id, img);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('이 원작은 대표 이미지가 없어요')));
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 갤러리에서 사진을 골라 앱 문서 폴더에 복사한 뒤 표지로 적용.
  Future<void> _pickCoverFromGallery(
      BuildContext context, CreativeWork work) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await CoverPicker().pickFromGallery(work.id);
      if (path == null) return; // 사용자가 취소
      ref.read(libraryProvider.notifier).setCover(work.id, path);
      messenger.showSnackBar(
          const SnackBar(content: Text('표지를 갤러리 사진으로 바꿨어요')));
    } on PlatformException catch (e) {
      // 사진 접근이 거부된 경우: 설정에서 켜는 방법을 안내.
      if (e.code == 'photo_access_denied') {
        if (context.mounted) _showPhotoPermissionDialog(context);
      } else {
        messenger.showSnackBar(
            const SnackBar(content: Text('사진을 불러오지 못했어요')));
      }
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('사진을 불러오지 못했어요')));
    }
  }

  /// 사진 접근 권한이 거부됐을 때, 설정에서 다시 켜는 방법을 안내.
  void _showPhotoPermissionDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('사진 접근 권한이 필요해요',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
          '표지로 쓸 사진을 가져오려면 사진 접근을 허용해 주세요.\n\n'
          '설정 앱 → 이 앱 → 사진에서 권한을 켤 수 있어요.',
          style: TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showRename(BuildContext context, LibraryNotifier n, CreativeWork work) {
    final controller = TextEditingController(text: work.title);
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () {
              n.renameWork(work.id, controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('저장',
                style: TextStyle(color: AppColors.sage, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// 삭제는 실수 방지를 위해 확인 모달을 거친다(기획서 12).
  void _confirmDelete(BuildContext context, LibraryNotifier n, CreativeWork work) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('작품 삭제',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('《${work.title}》을(를) 삭제할까요?\n삭제한 작품은 되돌릴 수 없어요.',
            style: const TextStyle(fontSize: 13, height: 1.6)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () {
              n.removeWork(work.id);
              Navigator.pop(ctx);
            },
            child: const Text('삭제',
                style: TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}


// ── 책 카드 공통 빌더(정적·플립 공용) ──────────────────────

const double _kBookRadius = 14;

/// 카드 본체 장식(라운드 + 2겹 그림자).
BoxDecoration _bookCardDecoration() => BoxDecoration(
      borderRadius: BorderRadius.circular(_kBookRadius),
      boxShadow: const [
        BoxShadow(
            color: Color(0x4D000000), blurRadius: 44, offset: Offset(0, 14)),
        BoxShadow(
            color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 2)),
      ],
    );

/// 펼친 책 한 면(좌:표지 + 우:정보)을 카드로 조립.
/// 가운데 제본 골(거터) 그림자와 바닥 음영으로 '펼친 책' 입체감을 준다.
Widget _bookSpread({
  required Widget left,
  required Widget right,
  required double w,
  required double h,
}) {
  return Container(
    width: w,
    height: h,
    clipBehavior: Clip.antiAlias,
    decoration: _bookCardDecoration(),
    child: Stack(
      children: [
        Row(
          children: [
            SizedBox(width: w / 2, child: left),
            Expanded(child: right),
          ],
        ),
        // 가운데 제본 골(펼친 책 안쪽 그림자)
        Positioned(
          top: 0,
          bottom: 0,
          left: w / 2 - 15,
          width: 30,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0x00000000),
                  Color(0x33000000),
                  Color(0x00000000),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        // 바닥 음영(아래쪽 그라운딩)
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0x1F000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// 페이지 두께감: 좌·우 각각 3장(깊은 것부터 어둡게).
List<Widget> _bookSheets(double w, double h) => [
      _bookSheet(side: -1, off: 8, color: const Color(0xFFCEC5B8), w: w, h: h),
      _bookSheet(side: 1, off: 8, color: const Color(0xFFCEC5B8), w: w, h: h),
      _bookSheet(side: -1, off: 5, color: const Color(0xFFD8D0C4), w: w, h: h),
      _bookSheet(side: 1, off: 5, color: const Color(0xFFD8D0C4), w: w, h: h),
      _bookSheet(side: -1, off: 2, color: const Color(0xFFE4DDD4), w: w, h: h),
      _bookSheet(side: 1, off: 2, color: const Color(0xFFE4DDD4), w: w, h: h),
    ];

/// 카드 뒤 한 장. [side] -1=왼쪽, 1=오른쪽. 해당 방향으로 [off]px 삐져나온다.
Widget _bookSheet(
        {required int side,
        required double off,
        required Color color,
        required double w,
        required double h}) =>
    Transform.translate(
      offset: Offset(side * off, 0),
      child: Container(
        width: w,
        height: h + 6, // 위아래로 살짝 더 크게
        decoration: BoxDecoration(
          color: color,
          borderRadius: side < 0
              ? const BorderRadius.horizontal(left: Radius.circular(_kBookRadius))
              : const BorderRadius.horizontal(
                  right: Radius.circular(_kBookRadius)),
        ),
      ),
    );

/// 왼쪽 페이지 — 표지. [coverImage] 가 있으면 표지 이미지로 꽉 채운다.
/// 표지 이미지를 소스 종류에 맞게 렌더(서버 http URL → 네트워크, 에셋 경로 → asset, 로컬 파일 → file).
/// 실패하면 [fallback] 색으로 채운다. (서버 coverImageUrl 도입 후 Image.asset URL 로드 실패 방지)
Widget netOrAssetCover(String img, Color fallback) {
  if (img.startsWith('http')) {
    return Image.network(img,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => ColoredBox(color: fallback));
  }
  if (coverIsAsset(img)) {
    return Image.asset(img,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => ColoredBox(color: fallback));
  }
  return Image.file(File(img),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => ColoredBox(color: fallback));
}

Widget _coverPageContent(CreativeWork work, {String? coverImage}) {
  final coverColor = bookColor(work.source);
  // 창작물 썸네일 우선순위: 사용자 지정 표지 → 창작물 대표 이미지(오프라인 캐시 우선, 없으면 URL)
  // → (이미지 없음) creationCoverEmoji/🎭. 원작 표지(source.cover)로 폴백하지 않는다.
  final cover = coverImage ?? work.coverDisplayPath;
  return Stack(
    fit: StackFit.expand,
    children: [
      if (cover != null)
        netOrAssetCover(cover, coverColor)
      else ...[
        ColoredBox(color: coverColor),
        // 입체감 오버레이 (white.12 → black.22)
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0x1FFFFFFF), Color(0x38000000)],
            ),
          ),
        ),
      ],
      // 오른쪽 책등 그림자
      const Positioned(
        top: 0,
        bottom: 0,
        right: 0,
        width: 20,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: [Color(0x2E000000), Color(0x00000000)],
            ),
          ),
        ),
      ),
      // 내용(위: 이모지 / 아래: 원작 라벨 + 작품명) — 표지 이미지가 없을 때만.
      if (cover == null)
        Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(work.coverEmoji,
                    style: const TextStyle(fontSize: 38)),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('원작',
                    style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 0.6,
                        color: AppColors.alpha(Colors.white, 0x80))),
                const SizedBox(height: 2),
                Text(work.source,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: Colors.white)),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

/// 오른쪽 페이지 — 창작물 정보(태그 / 제목 / 아이디어 / 수정일).
Widget _infoPageContent(CreativeWork work) {
  final modeLabel = work.mode == CreateMode.dialogue ? '대사극' : '오디오극';
  return Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: Color(0xFFFAF6F0)),
      // 왼쪽 경계(책 안쪽) 그림자
      const Positioned(
        top: 0,
        bottom: 0,
        left: 0,
        width: 16,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0x14000000), Color(0x00000000)],
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(14),
        child: Builder(builder: (context) {
          // 글씨를 아주 크게 키우면 페이지(고정 높이)를 넘쳐 오버플로 경고가 떴다.
          // ① 글씨가 크면 우선순위가 낮은 '아이디어 박스'를 숨겨 여백을 확보하고,
          // ② 윗 영역은 NeverScrollableScrollPhysics 스크롤뷰로 감싸 어떤 경우에도
          //    RenderFlex 오버플로(노란 줄무늬)가 뜨지 않도록 한다(넘치면 잘림).
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final showIdea = scale <= 1.3;
          final bigText = scale > 1.1; // 글씨 '크게'(1.15)부터 난이도 칩을 두 줄로
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          TagChip(
                              label: modeLabel,
                              bg: AppColors.alpha(AppColors.sage, 0x2E),
                              fg: AppColors.sage),
                          const SizedBox(width: 5),
                          Flexible(
                            child: TagChip(
                                label: levelDisplayLabel(work.level,
                                    wrap: bigText),
                                bg: const Color(0xFFEFEFEF),
                                fg: const Color(0xFF777777)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(work.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              height: 1.3,
                              color: Color(0xFF1C1A17))),
                      // 아이디어 박스 — 글씨가 아주 크면 표시하지 않는다.
                      if (showIdea) ...[
                        const SizedBox(height: 9),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDE8E0),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('"${work.desc}"',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10,
                                  height: 1.6,
                                  fontStyle: FontStyle.italic,
                                  color: Color(0xFF7A6A5A))),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('마지막 수정',
                      style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 0.4,
                          color: Color(0xFFCCCCCC))),
                  const SizedBox(height: 1),
                  Text(formatDate(work.updatedAt),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF999999))),
                ],
              ),
            ],
          );
        }),
      ),
    ],
  );
}
