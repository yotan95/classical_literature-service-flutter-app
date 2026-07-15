import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/create_request.dart';
import '../models/sample_data.dart';
import '../services/books_service.dart';
import '../services/connectivity_service.dart';
import '../theme/app_colors.dart';
import '../state/create_main_state.dart';
import '../state/creation_job.dart';
import '../state/library_state.dart';
import '../state/navigation.dart';
import 'ai_generating_screen.dart';
import 'original_read_screen.dart';

/// 창작하기 메인 (콘텐츠 전용). 앱 셸의 탭 0 으로 사용.
/// 폰 셸/하단 네비를 포함하지 않으며, 본문은 내부에서 스크롤된다.
class CreateMainScreen extends ConsumerStatefulWidget {
  const CreateMainScreen({super.key});

  @override
  ConsumerState<CreateMainScreen> createState() => _CreateMainScreenState();
}

class _CreateMainScreenState extends ConsumerState<CreateMainScreen> {
  static const _tx = AppColors.ink;
  static const _ts = Color(0xFF909090);

  final ScrollController _scroll = ScrollController();
  final ScrollController _bookScroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    _bookScroll.dispose();
    super.dispose();
  }

  void _jumpBookPickerToStart() {
    if (!mounted || !_bookScroll.hasClients) return;
    _bookScroll.jumpTo(_bookScroll.position.minScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(createMainProvider);
    final n = ref.read(createMainProvider.notifier);

    // 창작하기 탭을 다시 누르면 본문을 맨 위로 부드럽게 올린다.
    ref.listen(createScrollTopProvider, (_, __) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });

    ref.listen(createBookScrollStartProvider, (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpBookPickerToStart();
      });
    });

    // 빈 곳을 누르면 키보드(포커스)를 내린다.
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ColoredBox(
        color: AppColors.surface,
        child: Column(
          children: [
            _header(),
            Expanded(
              // 오버스크롤 늘어남 제거는 앱 전역 AppScrollBehavior 에서 처리한다.
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _recommendBanner(st, n),
                    _modeSection(st, n),
                    _levelSection(st, n),
                    _bookSection(st, n),
                    _rangeSection(st, n),
                    const _IdeaSection(),
                    _cta(context, ref),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 헤더 ── (우상단 알람 아이콘 제거)
  Widget _header() => const SizedBox(
        height: 52,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('새로 만들기',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, color: _tx)),
          ),
        ),
      );

  Widget _secLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          t.toUpperCase(),
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: _ts),
        ),
      );

  // ── 오늘의 추천 배너 ──
  /// 책 목록(서버 GET /books, 로딩 전/실패 시 kBooks 폴백). 추천 인덱스 해석용.
  List<BookCover> _recommendBooks() {
    final serverBooks = ref.watch(booksProvider).valueOrNull;
    return (serverBooks != null && serverBooks.isNotEmpty)
        ? [for (final b in serverBooks) b.toCover()]
        : kBooks;
  }

  /// 받침에 따라 '으로/로' 보조사를 고른다(받침 없음·ㄹ받침 → '로', 그 외 → '으로').
  String _roParticle(String word) {
    if (word.isEmpty) return '로';
    final c = word.codeUnitAt(word.length - 1);
    if (c < 0xAC00 || c > 0xD7A3) return '로'; // 한글 음절이 아니면 기본값
    final jong = (c - 0xAC00) % 28; // 종성 인덱스(0=없음, 8=ㄹ)
    return (jong == 0 || jong == 8) ? '로' : '으로';
  }

  Widget _recommendBanner(CreateMainState st, CreateMainNotifier n) {
    final rec = ref.watch(recommendationProvider);
    final books = _recommendBooks();
    if (books.isEmpty) return const SizedBox.shrink();
    final idx = (rec.bookPick * books.length).floor().clamp(0, books.length - 1);
    final book = books[idx];
    final modeInfo = kModes.firstWhere((m) => m.$1 == rec.mode); // ($1,이모지,이름,설명)
    final verb = rec.mode == CreateMode.audio ? '들어봐요' : '만들어봐요';
    final headline =
        '${book.title}${_roParticle(book.title)} ${modeInfo.$3}을 $verb ${modeInfo.$2}';

    return GestureDetector(
      // 추천을 누르면 해당 원작·모드로 선택값만 채운다(생성은 CTA 버튼에서).
      onTap: () {
        n.setMode(rec.mode);
        n.setRangeMode(RangeMode.full); // 전체 줄거리로 맞춤
        n.setBook(book.title); // selScene 0 으로 초기화됨
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.sage,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: AppColors.alpha(AppColors.sage, 0x50),
                blurRadius: 20,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(builder: (_) {
              final now = DateTime.now();
              return Text('${now.year}년 ${now.month}월 ${now.day}일 · 오늘의 추천',
                  style: const TextStyle(
                      fontSize: 10, color: Color(0x9EFFFFFF), letterSpacing: 0.4));
            }),
            const SizedBox(height: 3),
            Text(headline,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  // ── 창작 모드 ──
  Widget _modeSection(CreateMainState st, CreateMainNotifier n) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 글씨 크기를 키우면 설명 줄 수가 달라져 두 카드 높이가 어긋난다.
            // IntrinsicHeight + stretch 로 항상 더 큰 카드 높이에 맞춰 나란히 맞춘다.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final m in kModes) ...[
                    Expanded(
                      child: _modeCard(m.$2, m.$3, m.$4, on: st.mode == m.$1,
                          onTap: () => n.setMode(m.$1)),
                    ),
                    if (m.$1 == CreateMode.dialogue) const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _modeCard(String icon, String name, String desc,
      {required bool on, required VoidCallback onTap}) {
    // 글씨가 크면 한 줄에 다 안 들어가 단어 중간(예: 이야|기)에서 어색하게 끊긴다.
    // 이때만 마지막 띄어쓰기를 줄바꿈으로 바꿔 '들으면서 감상하는 / 이야기' 처럼 끊는다.
    final big = MediaQuery.textScalerOf(context).scale(1) > 1.1;
    final sp = desc.lastIndexOf(' ');
    final descText = (big && sp > 0)
        ? '${desc.substring(0, sp)}\n${desc.substring(sp + 1)}'
        : desc;
    return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: on ? AppColors.sage : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? AppColors.sage : AppColors.border, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: on ? AppColors.alpha(AppColors.sage, 0x38) : const Color(0x0F000000),
                blurRadius: on ? 18 : 5,
                offset: Offset(0, on ? 4 : 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(icon, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 6),
              Text(name,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: on ? Colors.white : _tx)),
              const SizedBox(height: 3),
              Text(descText,
                  style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: on ? const Color(0xB8FFFFFF) : _ts)),
            ],
          ),
        ),
      );
  }

  // ── 난이도 (1×4) ──
  Widget _levelSection(CreateMainState st, CreateMainNotifier n) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _secLabel('난이도'),
            // 라벨 줄 수가 달라도 모든 카드 높이를 가장 큰 카드에 맞춘다.
            // (스크롤뷰 안에서는 세로 제약이 무한이라 stretch만으로는 안 되고
            //  IntrinsicHeight 로 가장 큰 카드 높이를 기준 높이로 잡아준다.)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < kLevels.length; i++) ...[
                    Expanded(child: _levelCard(kLevels[i].$1, kLevels[i].$2,
                      on: st.level == kLevels[i].$2.replaceAll('\n', ' '),
                      onTap: () => n.setLevel(kLevels[i].$2.replaceAll('\n', ' ')))),
                    if (i < kLevels.length - 1) const SizedBox(width: 7),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _levelCard(String icon, String label,
          {required bool on, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: on ? AppColors.sage : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? AppColors.sage : AppColors.border, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: on ? AppColors.alpha(AppColors.sage, 0x35) : const Color(0x0D000000),
                blurRadius: on ? 12 : 3,
                offset: Offset(0, on ? 3 : 1),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon, style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 5),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 9,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: on ? Colors.white : _tx),
              ),
            ],
          ),
        ),
      );

  // ── 원작 선택 (가로 스크롤 표지) ──
  /// 즐겨찾기한 원작을 앞에, 그 안에서는 가나다순으로 정렬해 보여 준다.
  Widget _bookSection(CreateMainState st, CreateMainNotifier n) {
    final favorites = ref.watch(libraryProvider.select((s) => s.favorites));
    // 원작 목록은 서버(GET /books)에서 받아 채운다. 로딩 전/실패 시 기존 kBooks 로 폴백.
    final serverBooks = ref.watch(booksProvider).valueOrNull;
    final base = (serverBooks != null && serverBooks.isNotEmpty)
        ? [for (final b in serverBooks) b.toCover()]
        : kBooks;
    final books = [...base]..sort((a, b) {
        final af = favorites.contains(a.title), bf = favorites.contains(b.title);
        if (af != bf) return af ? -1 : 1; // 즐겨찾기 먼저
        return a.title.compareTo(b.title); // 같은 그룹은 가나다순
      });
    // 사용자가 아직 원작을 직접 고르지 않았다면, 목록의 첫 항목을 기본 선택으로 맞춘다.
    // (빌드 중 상태 변경 금지 → 다음 프레임에 반영. defaultBook 이 중복/터치 시 무시한다.)
    if (books.isNotEmpty && !st.bookTouched && st.book != books.first.title) {
      final first = books.first.title;
      WidgetsBinding.instance.addPostFrameCallback((_) => n.defaultBook(first));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _secLabel('원작 선택'),
          ),
          SingleChildScrollView(
            controller: _bookScroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Row(
              children: [
                for (int i = 0; i < books.length; i++) ...[
                  _bookCover(books[i],
                      sel: st.book == books[i].title,
                      favorite: favorites.contains(books[i].title),
                      onTap: () => n.setBook(books[i].title)),
                  if (i < books.length - 1) const SizedBox(width: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 표지 이미지 채우기 — 서버 URL(http) 이면 네트워크, 아니면 에셋. 실패하면 이모지로 폴백.
  /// 원작 커버는 [bookImage] 로 로컬 에셋(assets/images/)을 우선 해석한다.
  Widget _coverFill(BookCover b) {
    final img = bookImage(b.title) ?? b.image!;
    final fallback = Align(
      alignment: const Alignment(0, -0.35),
      child: Text(b.icon, style: const TextStyle(fontSize: 32)),
    );
    if (img.startsWith('http')) {
      return Image.network(img,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
          loadingBuilder: (_, child, prog) =>
              prog == null ? child : fallback);
    }
    return Image.asset(img,
        fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
  }

  /// 표지를 꾹 눌렀을 때 뜨는 하단 시트.
  void _showBookSheet(BookCover b) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDEDEDE),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(b.title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: _tx)),
            ),
            ListTile(
              leading: const Text('📖', style: TextStyle(fontSize: 20)),
              title: const Text('원작 보기',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => OriginalReadScreen(source: b.title)));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _bookCover(BookCover b,
          {required bool sel,
          required VoidCallback onTap,
          bool favorite = false}) =>
      GestureDetector(
        onTap: onTap,
        // 꾹 누르면 하단에 '원작 보기' 시트를 띄운다.
        onLongPress: () => _showBookSheet(b),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 84,
          height: 116,
          transform: Matrix4.translationValues(0, sel ? -4 : 0, 0),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: b.color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Builder(builder: (_) {
            // 원작 커버는 로컬 에셋 우선, 없으면 서버 coverImageUrl.
            final hasCover = (bookImage(b.title) ?? b.image) != null;
            return Stack(
            children: [
              // 표지 이미지가 있으면 채우고, 없으면 이모지를 보여준다.
              // (서버 coverImageUrl=http 면 네트워크, 에셋 경로면 asset)
              if (hasCover) Positioned.fill(child: _coverFill(b)),
              // 하단 그라디언트
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x66000000)],
                      stops: [0.4, 1.0],
                    ),
                  ),
                ),
              ),
              if (!hasCover)
                Align(
                  alignment: const Alignment(0, -0.35),
                  child: Text(b.icon, style: const TextStyle(fontSize: 32)),
                ),
              // 즐겨찾기 별 (좌상단 — 선택 체크는 우상단이라 겹치지 않음)
              if (favorite)
                const Positioned(
                  top: 6,
                  left: 6,
                  child: Text('⭐', style: TextStyle(fontSize: 12)),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 9),
                  child: Text(
                    b.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 10,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        shadows: [Shadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 1))]),
                  ),
                ),
              ),
              if (sel)
                Positioned(
                  top: 7,
                  right: 7,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.sage,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.check, size: 11, color: Colors.white),
                  ),
                ),
              // 선택 테두리: 이미지 위에 덧그려 가장자리 색 프레임 없이 꽉 차게.
              if (sel)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.sage, width: 2.5),
                    ),
                  ),
                ),
            ],
          );
          }),
        ),
      );

  // ── 줄거리 범위 ──
  Widget _rangeSection(CreateMainState st, CreateMainNotifier n) {
    // 장면 칩은 서버(GET /books/{id})에서 받아 채운다. 로딩 전/실패 시 기존 kScenes 폴백.
    final book = ref.watch(booksByTitleProvider)[st.book];
    final serverScenes = book == null
        ? null
        : ref.watch(bookDetailProvider(book.bookId)).valueOrNull?.scenes;
    final scenes = (serverScenes != null && serverScenes.isNotEmpty)
        ? [for (final s in serverScenes) Scene(s.emoji, s.title, s.description)]
        : (kScenes[st.book] ?? const <Scene>[]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _secLabel('줄거리 범위'),
          Row(children: [
            Expanded(child: _rangeToggle('📜', '전체 줄거리',
                on: st.rangeMode == RangeMode.full,
                onTap: () => n.setRangeMode(RangeMode.full))),
            const SizedBox(width: 8),
            Expanded(child: _rangeToggle('🎬', '장면별 선택',
                on: st.rangeMode == RangeMode.scene,
                onTap: () => n.setRangeMode(RangeMode.scene))),
          ]),
          const SizedBox(height: 10),
          if (st.rangeMode == RangeMode.full)
            _fullSummaryCard()
          else
            Column(
              children: [
                for (int i = 0; i < scenes.length; i++) ...[
                  _sceneRow(scenes[i], on: st.selScene == i, onTap: () => n.setScene(i)),
                  if (i < scenes.length - 1) const SizedBox(height: 7),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _rangeToggle(String icon, String label,
          {required bool on, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.sage : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? AppColors.sage : AppColors.border, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: on ? AppColors.alpha(AppColors.sage, 0x35) : const Color(0x0D000000),
                blurRadius: on ? 12 : 3,
                offset: Offset(0, on ? 3 : 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: on ? Colors.white : _tx)),
            ],
          ),
        ),
      );

  Widget _fullSummaryCard() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.alpha(AppColors.sage, 0x10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.alpha(AppColors.sage, 0x30), width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Padding(
              padding: EdgeInsets.only(top: 1),
              child: Text('💡', style: TextStyle(fontSize: 18)),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('아주 짧은 요약으로 만들어요',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.sage)),
                  SizedBox(height: 3),
                  Text(
                    '선택한 이야기 전체를 3문장으로 압축한 요약본을 바탕으로 만들어요. '
                    '전체적인 흐름과 교훈을 담아요.',
                    style: TextStyle(fontSize: 11, height: 1.6, color: Color(0xFF666666)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _sceneRow(Scene sc, {required bool on, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: on ? AppColors.alpha(AppColors.sage, 0x10) : const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? AppColors.sage : AppColors.border, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? AppColors.sage : Colors.transparent,
                  border: Border.all(color: on ? AppColors.sage : const Color(0xFFCCCCCC), width: 2),
                ),
                child: on
                    ? Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))
                    : null,
              ),
              const SizedBox(width: 11),
              Text(sc.icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sc.title,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: on ? AppColors.sage : _tx)),
                    const SizedBox(height: 2),
                    Text(sc.desc,
                        style: const TextStyle(fontSize: 11, height: 1.4, color: _ts)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  // ── 선택값으로 /create 요청을 구성해 생성 중 화면으로 이동 ──
  // CTA 버튼과 '오늘의 추천' 배너가 공유한다.
  Future<void> _startCreate(BuildContext context, WidgetRef ref) async {
    // 새 작품 만들기는 온라인 전용 — 먼저 서버 연결부터 확인한다.
    // (오프라인이면 서버에서 장면 목록을 못 받아 아래 검증이 '장면을 선택해 주세요'로
    //  잘못 안내되므로, 그보다 먼저 오프라인 안내를 띄우고 중단한다. 과금/지연도 방지.)
    if (!await ensureOnline(context, ref, feature: '새 작품 만들기')) return;
    if (!context.mounted) return;
    final st = ref.read(createMainProvider);
    // 서버 Book 에서 실제 bookId 와 선택 장면의 sceneId 를 해석한다(하드코딩 매핑 제거).
    final book = ref.read(booksByTitleProvider)[st.book];
    final serverBookId = book?.bookId ?? bookIdForSource(st.book) ?? '';
    var sceneIds = const <String>[];
    if (st.rangeMode == RangeMode.scene) {
      if (book != null) {
        final detailScenes =
            ref.read(bookDetailProvider(book.bookId)).valueOrNull?.scenes ??
                const [];
        if (st.selScene >= 0 && st.selScene < detailScenes.length) {
          sceneIds = [detailScenes[st.selScene].sceneId];
        } else if ((kScenes[st.book]?.isNotEmpty ?? false)) {
          sceneIds = ['scene-${st.selScene + 1}'];
        }
      } else if ((kScenes[st.book]?.isNotEmpty ?? false)) {
        sceneIds = ['scene-${st.selScene + 1}'];
      }
    }
    final req = CreateRequest(
      bookId: serverBookId,
      mode: modeToApi(st.mode),
      difficulty: difficultyToApi(st.level),
      scope: scopeToApi(st.rangeMode),
      sceneIds: sceneIds,
      ideaText: st.idea,
    );
    // 사전 검증(백엔드 422 와 동일 규칙): 미지원 원작/장면 미선택 등.
    final err = req.validate();
    if (err != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final canReplace = await _confirmReplaceRunningCreation(context, ref);
    if (!canReplace || !context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AiGeneratingScreen(request: req)));
  }

  /// 둘러보기로 빠져나온 뒤 아직 생성 중인 작업이 있으면,
  /// 새 작업 시작 전에 기존 작업이 사라진다는 점을 확인한다.
  Future<bool> _confirmReplaceRunningCreation(
      BuildContext context, WidgetRef ref) async {
    if (!ref.read(creationJobProvider).isRunning) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('새 창작물을 만들까요?'),
        content: const Text(
          '지금 만들고 있는 창작물은 중단되고 사라져요.\n확인을 누르면 새 창작물만 만들어집니다.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              '취소',
              style: TextStyle(color: AppColors.textSub),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '확인',
              style: TextStyle(
                color: AppColors.sage,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  // ── CTA: 생성 중 화면으로 이동 ──
  Widget _cta(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
        child: GestureDetector(
          onTap: () => _startCreate(context, ref),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.sage,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: AppColors.alpha(AppColors.sage, 0x55),
                    blurRadius: 24,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: const Text('이 구성으로 창작하기 →',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      );
}

// ── 추가 아이디어 (입력창 + 예시 칩) ─────────────────────
// 칩을 누르면 입력창에 문구가 채워지고, 입력값은 createMainProvider 에 저장된다.
class _IdeaSection extends ConsumerStatefulWidget {
  const _IdeaSection();

  @override
  ConsumerState<_IdeaSection> createState() => _IdeaSectionState();
}

class _IdeaSectionState extends ConsumerState<_IdeaSection> {
  final TextEditingController _controller = TextEditingController();

  static const _chipIdeas = {
    '결말 바꾸기': '결말을 다르게 바꿔줘.',
    '새 인물 넣기': '새로운 인물을 한 명 넣어줘.',
    '더 웃기게': '이야기를 더 웃기게 만들어줘.',
    '더 감동적으로': '이야기를 더 감동적으로 만들어줘.',
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyChip(String label) {
    final text = _chipIdeas[label] ?? label;
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    ref.read(createMainProvider.notifier).setIdea(text);
  }

  @override
  Widget build(BuildContext context) {
    // 둘러보기·창작 시작 후 폼이 초기화돼 아이디어가 비워지면 입력창도 함께 비운다.
    // (입력으로 인한 변경은 next==controller.text 라 무시되어 되먹임이 생기지 않는다)
    ref.listen(createMainProvider.select((s) => s.idea), (_, next) {
      if (next != _controller.text) {
        _controller.text = next;
        _controller.selection = TextSelection.collapsed(offset: next.length);
      }
    });
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('내 아이디어 더하기',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color: Color(0xFF909090))),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _controller,
                  onChanged: ref.read(createMainProvider.notifier).setIdea,
                  maxLines: 2,
                  minLines: 1,
                  style: const TextStyle(fontSize: 13, color: AppColors.ink),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    hintText: '이 이야기에 더하고 싶은 생각이 있나요?',
                    hintStyle: TextStyle(fontSize: 13, color: Color(0xFFC0C0C0)),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final label in kIdeaChips)
                      GestureDetector(
                        onTap: () => _applyChip(label),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(label,
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF909090))),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('안 써도 만들 수 있어요',
                    style: TextStyle(fontSize: 10, color: AppColors.textFaint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
