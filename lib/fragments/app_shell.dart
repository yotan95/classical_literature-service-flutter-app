import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_keys.dart';
import '../theme/app_colors.dart';
import '../state/creation_job.dart';
import '../state/navigation.dart';
import '../state/settings_state.dart';
import '../widgets/app_bottom_nav_bar.dart';
import 'ai_generating_screen.dart';
import 'create_main_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';

/// 앱의 메인 셸. 하단 탭으로 한 번에 한 화면씩 보여준다(IndexedStack).
/// 백그라운드로 도는 창작 작업이 있으면 상단에 진행/완료 배너를 띄우고,
/// 알림 설정이 켜져 있으면 완료 시 어느 화면에서든 알림 스낵바를 띄운다.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(selectedTabProvider);
    final job = ref.watch(creationJobProvider);

    // 완료 순간: 알림 설정이 켜져 있으면 어느 화면에서든 보이도록 전역 스낵바를 띄운다.
    ref.listen<CreationJobState>(creationJobProvider, (prev, next) {
      final wasDone = prev?.status == CreationJobStatus.done;
      if (!wasDone &&
          next.status == CreationJobStatus.done &&
          next.result != null) {
        if (ref.read(settingsProvider).notificationsOn) {
          _notifyCompleted(ref, next);
        }
      }
    });

    return Scaffold(
      backgroundColor: AppColors.surface,
      // 완료 알림 스낵바가 떠 있을 때 화면 아무 곳이나 누르면 함께 사라지게 한다.
      // (Listener 는 제스처 경쟁에 끼지 않아 버튼/스크롤 동작은 그대로 살아있다)
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => appMessengerKey.currentState?.hideCurrentSnackBar(),
        child: SafeArea(
          bottom: false, // 하단 네비가 자체 SafeArea 처리
          child: Column(
            children: [
              if (job.isRunning || job.isDone || job.hasError)
                _JobBanner(job: job),
              Expanded(
                child: IndexedStack(
                  index: tab,
                  children: const [
                    CreateMainScreen(),
                    LibraryScreen(),
                    SettingsScreen(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNavBar(),
    );
  }

  /// 완료 알림(전역 스낵바). 짧은 진동과 함께 '보러가기'를 제공한다.
  void _notifyCompleted(WidgetRef ref, CreationJobState st) {
    HapticFeedback.mediumImpact();
    final messenger = appMessengerKey.currentState;
    if (messenger == null) return;
    final title = st.result?.work.title ?? '새 작품';
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        content: Text('🎉 ‘$title’ 완성! 열어볼까요?',
            style: const TextStyle(color: Colors.white)),
        action: SnackBarAction(
          label: '완성작 보기',
          textColor: const Color(0xFF9FD8BE),
          onPressed: () => openCreationResult(ref),
        ),
      ));
  }
}

/// 백그라운드 작업 배너(앱 셸 상단). 진행 중엔 진행 화면으로, 완료 시엔 결과로,
/// 실패 시엔(둘러보다 연결이 끊긴 경우 포함) 탭해서 같은 요청으로 다시 시도한다.
class _JobBanner extends ConsumerWidget {
  const _JobBanner({required this.job});

  final CreationJobState job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = job.isDone;
    final err = job.hasError;
    final title = job.result?.work.title ?? job.bookTitle;

    // 상태별 표시(배경/글자색·아이콘·문구).
    final Color bg;
    final Color fg;
    final Widget leading;
    final String label;
    if (err) {
      bg = AppColors.warnBg;
      fg = AppColors.warnText;
      leading = const Text('⚠️', style: TextStyle(fontSize: 16));
      label = '만들기에 실패했어요 — 탭해서 다시 시도';
    } else if (done) {
      bg = AppColors.sage;
      fg = Colors.white;
      leading = const Text('🎉', style: TextStyle(fontSize: 16));
      label = '‘$title’ 완성! 탭해서 열기';
    } else {
      bg = AppColors.alpha(AppColors.sage, 0x14);
      fg = AppColors.sage;
      leading = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator.adaptive(strokeWidth: 2),
      );
      label = '작품을 만들고 있어요… 탭하면 진행 보기';
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (err) {
          ref.read(creationJobProvider.notifier).retry();
        } else if (done) {
          openCreationResult(ref);
        } else {
          // 진행 화면으로 (관찰 전용 — 작업은 그대로 진행).
          Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AiGeneratingScreen()));
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          border: const Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: fg),
              ),
            ),
            Icon(err ? Icons.refresh : Icons.chevron_right, size: 18, color: fg),
          ],
        ),
      ),
    );
  }
}
