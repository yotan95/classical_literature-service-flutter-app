import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'onboarding_state.freezed.dart';

/// 온보딩 목적 선택지 (이모지, 이름, 설명).
const List<(String, String, String)> kPurposes = [
  ('🌏', '한국어 배우는 중', '외국어로서 한국어를 공부해요'),
  ('📚', '한국 문학 탐구', '수업·독서 활동으로 읽어요'),
  ('🎭', '창작이 재미있어서', '이야기 만들기를 좋아해요'),
  ('👨‍👧', '아이와 함께', '가족이 함께 읽고 즐겨요'),
];

/// 기본 읽기 수준 선택지 (이모지, 이름). 창작하기 난이도 프리셋과 동일.
const List<(String, String)> kReadLevels = [
  ('📖', '동화책 수준'),
  ('🌿', '한국어 배우는 중'),
  ('⭐', '청소년용'),
  ('🏮', '고전의 결 살리기'),
];

/// 온보딩 상태: 현재 페이지, 사용 목적, 기본 읽기 수준. (이름 입력 단계 없음)
@freezed
class OnboardingState with _$OnboardingState {
  const factory OnboardingState({
    @Default(0) int page,
    @Default(0) int purpose, // kPurposes 인덱스 (기본: 한국어 배우는 중)
    @Default(0) int level, // kReadLevels 인덱스 (기본: 동화책 수준)
  }) = _OnboardingState;
}

class OnboardingNotifier extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => const OnboardingState();

  void setPage(int i) => state = state.copyWith(page: i);
  void setPurpose(int i) => state = state.copyWith(purpose: i);
  void setLevel(int i) => state = state.copyWith(level: i);
}

final onboardingProvider =
    NotifierProvider<OnboardingNotifier, OnboardingState>(OnboardingNotifier.new);
