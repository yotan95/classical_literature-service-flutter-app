import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_colors.dart';
import '../state/library_state.dart';
import '../state/navigation.dart';
import '../state/settings_state.dart';

/// 메인 하단 네비게이션 바.
/// 디자인 전용 커스텀 바(이모지 + 라벨, sage 강조)이며 [selectedTabProvider] 와 연동된다.
/// 앱 셸의 `Scaffold.bottomNavigationBar` 로 사용한다.
class AppBottomNavBar extends ConsumerWidget {
  const AppBottomNavBar({super.key});

  static const _tabs = [
    ('🎨', '창작'),
    ('📚', '보관함'),
    ('⚙', '설정'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(selectedTabProvider);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final on = i == active;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final current = ref.read(selectedTabProvider);
                    if (i == current) {
                      // 이미 보고 있는 탭을 다시 누르면 그 탭의 첫 화면으로 되돌린다.
                      if (i == 0) {
                        ref.read(createScrollTopProvider.notifier).requestTop();
                      }
                      if (i == 1) ref.read(libraryProvider.notifier).closeBook();
                      if (i == 2) ref.read(settingsProvider.notifier).back();
                    } else {
                      // 다른 탭으로 이동할 때는 각 탭의 상태를 그대로 둔다.
                      ref.read(selectedTabProvider.notifier).select(i);
                    }
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Opacity(
                        opacity: on ? 1 : 0.4,
                        child: Text(_tabs[i].$1,
                            style: const TextStyle(fontSize: 20)),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _tabs[i].$2,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                          color: on ? AppColors.sage : AppColors.textFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
