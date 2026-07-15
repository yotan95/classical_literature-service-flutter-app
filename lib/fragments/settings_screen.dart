import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/prefs.dart';
import '../services/creation_store.dart';
import '../services/media_cache.dart';
import '../theme/app_colors.dart';
import '../widgets/phone_shell.dart';
import '../state/library_state.dart';
import '../state/navigation.dart';
import '../state/onboarding_state.dart' show onboardingProvider;
import '../state/settings_state.dart';
import 'onboarding_screen.dart';

/// 설정 화면. 서브 뷰(글자 크기/속도/목적/수준)는
/// [settingsProvider] 의 view 상태로 전환된다. 데이터 초기화는 루트 맨 아래.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _tx = AppColors.ink;
  static const _ts = AppColors.textSub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);

    final Widget body = switch (st.view) {
      SettingsView.fontSize => _fontSizeView(st, n),
      SettingsView.speed => _speedView(st, n),
      SettingsView.purpose => _purposeView(st, n),
      SettingsView.level => _levelView(st, n),
      SettingsView.settings => _settingsMain(context, ref, st, n),
    };

    // 콘텐츠 전용: 폰 셸/하단바는 앱 셸이 제공. 본문은 내부에서 스크롤.
    return ColoredBox(
      color: AppColors.surface,
      child: SingleChildScrollView(child: body),
    );
  }

  // ───────────────────────── 설정 메인 ─────────────────────────
  Widget _settingsMain(
          BuildContext context, WidgetRef ref, SettingsState st, SettingsNotifier n) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 헤더
          Container(
            height: 52,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border))),
            child: const Text('설정',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _tx)),
          ),
          const SizedBox(height: 10),
          _section('읽기 설정', [
            _row('글자 크기', sub: st.fontSize, onTap: () => n.open(SettingsView.fontSize)),
            _row('읽기 기본 속도', sub: st.speed, onTap: () => n.open(SettingsView.speed)),
            _row('사용 목적', sub: st.purpose, onTap: () => n.open(SettingsView.purpose)),
            _row('기본 읽기 수준', sub: st.level, last: true, onTap: () => n.open(SettingsView.level)),
          ]),
          _section('알림', [
            _row('창작 완료 알림',
                sub: '작품이 완성되면 알려드려요',
                last: true,
                trailing: Switch.adaptive(
                  value: st.notificationsOn,
                  activeThumbColor: AppColors.sage,
                  onChanged: (_) => n.toggleNotifications(),
                )),
          ]),
          _section('정보', [
            _row('앱 버전',
                last: true,
                trailing: const Text('1.2.3', style: TextStyle(fontSize: 13, color: _ts))),
          ]),
          // 데이터 초기화 — 설정 화면 맨 아래.
          _section('데이터', [
            _row('데이터 초기화',
                sub: '내가 만든 작품과 설정이 모두 지워져요',
                danger: true,
                last: true,
                onTap: () => _confirmReset(context, ref)),
          ]),
          const SizedBox(height: 16),
        ],
      );

  // ───────────────────────── 글자 크기 ─────────────────────────
  Widget _fontSizeView(SettingsState st, SettingsNotifier n) {
    double prev(String v) =>
        v == '작게' ? 13 : v == '보통' ? 16 : v == '크게' ? 20 : 24;
    double prevSub(String v) =>
        v == '작게' ? 11 : v == '보통' ? 13 : v == '크게' ? 16 : 20;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _subNav('글자 크기', n),
        // 미리보기는 직접 지정한 크기를 보여주므로 전역 글자 배율은 끈다.
        MediaQuery.withNoTextScaling(
          child: Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('미리보기',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: Color(0xFFAAAAAA))),
              const SizedBox(height: 10),
              Text('봄날, 흥부네 마당에 제비 한 마리가 날아들었다.',
                  style: TextStyle(fontSize: prev(st.fontSize), height: 1.6, color: _tx)),
              const SizedBox(height: 5),
              Text('흥부: "에고, 별말씀을요."',
                  style: TextStyle(
                      fontSize: prevSub(st.fontSize), height: 1.6, color: const Color(0xFF666666))),
            ],
          ),
          ),
        ),
        const SizedBox(height: 20),
        _secLabel('크기 선택'),
        _grouped([
          for (int i = 0; i < kFontSizes.length; i++)
            _radioRow(kFontSizes[i].$1, kFontSizes[i].$2,
                selected: st.fontSize == kFontSizes[i].$1,
                last: i == kFontSizes.length - 1,
                onTap: () => n.setFontSize(kFontSizes[i].$1)),
        ]),
      ],
    );
  }

  // ───────────────────────── 읽기 속도 ─────────────────────────
  Widget _speedView(SettingsState st, SettingsNotifier n) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _subNav('읽기 기본 속도', n),
          const SizedBox(height: 20),
          _secLabel('속도 선택'),
          _grouped([
            for (int i = 0; i < kSpeeds.length; i++)
              _radioRow(kSpeeds[i].$1, kSpeeds[i].$2,
                  selected: st.speed == kSpeeds[i].$1,
                  last: i == kSpeeds.length - 1,
                  onTap: () => n.setSpeed(kSpeeds[i].$1)),
          ]),
        ],
      );

  // ───────────────────────── 이용 목적 ─────────────────────────
  Widget _purposeView(SettingsState st, SettingsNotifier n) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _subNav('이용 목적', n),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 4),
            child: Text('목적에 맞는 콘텐츠를 추천해 드려요',
                style: TextStyle(fontSize: 13, color: _ts)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                for (final p in kPurposes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _selectCard(p.$1, p.$2, p.$3,
                        on: st.purpose == p.$2,
                        iconBoxed: true,
                        onTap: () => n.setPurpose(p.$2)),
                  ),
              ],
            ),
          ),
        ],
      );

  // ───────────────────────── 읽기 수준 ─────────────────────────
  Widget _levelView(SettingsState st, SettingsNotifier n) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _subNav('기본 읽기 수준', n),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 4),
            child: Text('창작할 때 언제든 다시 바꿀 수 있어요',
                style: TextStyle(fontSize: 13, color: _ts)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                for (final d in kLevels)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _selectCard(d.$1, d.$2, d.$3,
                        on: st.level == d.$2,
                        iconBoxed: false,
                        onTap: () => n.setLevel(d.$2)),
                  ),
              ],
            ),
          ),
        ],
      );

  /// 데이터 초기화 확인 모달.
  /// 창작물·설정을 모두 비우고 온보딩(시작 화면)부터 다시 시작한다. 되돌릴 수 없다.
  void _confirmReset(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('데이터 초기화',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
            '내가 만든 작품과 모든 설정이 지워져요.\n삭제한 데이터는 되돌릴 수 없어요.',
            style: TextStyle(fontSize: 13, height: 1.6)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // 로컬 상태 초기화 (메모리 + 영속 데이터)
              ref.read(libraryProvider.notifier).clearAll();
              ref.read(settingsProvider.notifier).resetAll();
              ref.invalidate(onboardingProvider);
              ref.read(selectedTabProvider.notifier).select(kTabLibrary);
              // 앱 전용 창작물 폴더(created_data), 캐시 이미지, 온보딩 플래그도 비운다.
              await ref.read(creationStoreProvider).clear();
              await ref.read(mediaCacheProvider).clear();
              await Prefs.clearOnboardingSeen();
              if (!context.mounted) return;
              // 온보딩(시작 화면)으로 이동하며 기존 화면 스택을 모두 비운다.
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(
                    builder: (_) => const OnboardingScreen()),
                (route) => false,
              );
            },
            child: const Text('초기화',
                style: TextStyle(
                    color: Color(0xFFD04040), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── 공용 조각 ─────────────────────────
  Widget _secLabel(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 6),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: Color(0xFF909090))),
      );

  Widget _grouped(List<Widget> children) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.border),
            bottom: BorderSide(color: AppColors.border),
          ),
        ),
        child: Column(children: children),
      );

  Widget _section(String title, List<Widget> rows) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_secLabel(title), _grouped(rows)],
        ),
      );

  Widget _row(String label,
          {String? sub, Widget? trailing, bool last = false, bool danger = false, VoidCallback? onTap}) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 14, color: danger ? const Color(0xFFD04040) : _tx)),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Text(sub, style: const TextStyle(fontSize: 12, color: _ts)),
                    ],
                  ],
                ),
              ),
              if (danger)
                const SizedBox.shrink()
              else
                trailing ??
                    const Icon(Icons.chevron_right,
                        size: 14, color: Color(0xFFCCCCCC)),
            ],
          ),
        ),
      );

  Widget _radioRow(String label, String sub,
          {required bool selected, required bool last, VoidCallback? onTap}) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? AppColors.alpha(AppColors.sage, 0x07) : null,
            border: last ? null : const Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                            color: selected ? AppColors.sage : _tx)),
                    const SizedBox(height: 2),
                    Text(sub, style: const TextStyle(fontSize: 12, color: _ts)),
                  ],
                ),
              ),
              _radioDot(selected),
            ],
          ),
        ),
      );

  Widget _selectCard(String icon, String name, String desc,
          {required bool on, required bool iconBoxed, VoidCallback? onTap}) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: on ? AppColors.alpha(AppColors.sage, 0x14) : AppColors.surface,
            borderRadius: BorderRadius.circular(iconBoxed ? 16 : 14),
            border: Border.all(color: on ? AppColors.sage : AppColors.border, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: on ? AppColors.alpha(AppColors.sage, 0x28) : const Color(0x0D000000),
                blurRadius: on ? 16 : 4,
                offset: Offset(0, on ? 4 : 1),
              ),
            ],
          ),
          child: Row(
            children: [
              if (iconBoxed)
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? AppColors.sage : const Color(0xFFF5F3F0),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(icon, style: const TextStyle(fontSize: 21)),
                )
              else
                Text(icon, style: const TextStyle(fontSize: 20)),
              SizedBox(width: iconBoxed ? 14 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: on ? AppColors.sage : _tx)),
                    const SizedBox(height: 2),
                    Text(desc, style: const TextStyle(fontSize: 11, color: _ts)),
                  ],
                ),
              ),
              _radioDot(on),
            ],
          ),
        ),
      );

  Widget _radioDot(bool on) => Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? AppColors.sage : const Color(0x00000000),
          border: Border.all(color: on ? AppColors.sage : const Color(0xFFD0D0D0), width: 2),
        ),
        child: on
            ? Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                    color: Color(0xFFFFFFFF), shape: BoxShape.circle))
            : null,
      );

  Widget _subNav(String title, SettingsNotifier n) => Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(
          children: [
            NavBackButton(onTap: n.back),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: _tx)),
            ),
          ],
        ),
      );
}
