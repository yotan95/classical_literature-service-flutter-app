import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 메인 하단 탭 인덱스. (탭 순서/구성은 그대로, 기본 진입 탭만 내 서재로 변경)
const int kTabCreate = 0; // 창작하기
const int kTabLibrary = 1; // 내 서재
const int kTabSettings = 2; // 설정

/// 메인 하단 탭 인덱스. 온보딩 후 첫 화면은 내 서재이므로 기본값 = [kTabLibrary].
class SelectedTab extends Notifier<int> {
  @override
  int build() => kTabLibrary;

  void select(int index) => state = index;
}

final selectedTabProvider =
    NotifierProvider<SelectedTab, int>(SelectedTab.new);

/// 창작하기 탭을 다시 눌렀을 때 본문을 맨 위로 올리기 위한 신호(틱).
/// 값이 바뀌는 것 자체가 신호이며, 창작하기 화면이 이를 듣고 스크롤을 0으로 올린다.
class CreateScrollTop extends Notifier<int> {
  @override
  int build() => 0;

  void requestTop() => state++;
}

final createScrollTopProvider =
    NotifierProvider<CreateScrollTop, int>(CreateScrollTop.new);

/// 창작 폼이 초기화될 때 원작 가로 목록을 첫 항목 위치로 되돌리기 위한 신호(틱).
class CreateBookScrollStart extends Notifier<int> {
  @override
  int build() => 0;

  void requestStart() => state++;
}

final createBookScrollStartProvider =
    NotifierProvider<CreateBookScrollStart, int>(CreateBookScrollStart.new);
