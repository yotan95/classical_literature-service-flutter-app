import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../services/db_service.dart';

part 'settings_state.freezed.dart';

/// 설정 화면의 서브 뷰. 메인(settings)에서 각 항목을 누르면 전환된다.
enum SettingsView { settings, fontSize, speed, purpose, level }

@freezed
class SettingsState with _$SettingsState {
  const factory SettingsState({
    @Default(SettingsView.settings) SettingsView view,
    @Default('보통') String fontSize,
    @Default('보통') String speed,
    @Default('한국어 배우는 중') String purpose,
    @Default('동화책 수준') String level,
    @Default(true) bool notificationsOn,
  }) = _SettingsState;
}

// 로컬 DB(app_kv) 저장 키.
const _kSettingsKey = 'app_settings';

class SettingsNotifier extends Notifier<SettingsState> {
  DbService get _db => ref.read(dbServiceProvider);

  @override
  SettingsState build() {
    _load();
    return const SettingsState();
  }

  /// 저장해 둔 설정값을 불러와 반영(서브 뷰 nav 는 저장하지 않음).
  Future<void> _load() async {
    try {
      final json = await _db.getKv(_kSettingsKey);
      if (json == null || json.isEmpty) return;
      final m = jsonDecode(json) as Map<String, dynamic>;
      state = state.copyWith(
        fontSize: (m['fontSize'] as String?) ?? state.fontSize,
        speed: (m['speed'] as String?) ?? state.speed,
        purpose: (m['purpose'] as String?) ?? state.purpose,
        level: _normalizeLevelLabel((m['level'] as String?) ?? state.level),
        notificationsOn: (m['notificationsOn'] as bool?) ?? state.notificationsOn,
      );
    } catch (_) {
      // DB 미지원 환경: 기본값 유지.
    }
  }

  /// 현재 설정값을 로컬 DB 에 저장(전환용 view 는 제외).
  void _persist() {
    _db
        .setKv(
            _kSettingsKey,
            jsonEncode({
              'fontSize': state.fontSize,
              'speed': state.speed,
              'purpose': state.purpose,
              'level': state.level,
              'notificationsOn': state.notificationsOn,
            }))
        .catchError((_) {});
  }

  /// 서브 뷰 열기.
  void open(SettingsView v) => state = state.copyWith(view: v);

  /// 메인으로 돌아가기.
  void back() => state = state.copyWith(view: SettingsView.settings);

  void setFontSize(String v) {
    state = state.copyWith(fontSize: v);
    _persist();
  }

  void setSpeed(String v) {
    state = state.copyWith(speed: v);
    _persist();
  }

  void setPurpose(String v) {
    state = state.copyWith(purpose: v);
    _persist();
  }

  void setLevel(String v) {
    state = state.copyWith(level: _normalizeLevelLabel(v));
    _persist();
  }

  void toggleNotifications() {
    state = state.copyWith(notificationsOn: !state.notificationsOn);
    _persist();
  }

  /// 데이터 초기화: 모든 설정을 기본값으로 되돌린다(메인 뷰로 복귀 포함).
  /// 온보딩 완료 플래그도 지워, 다음 실행 때 시작 화면이 다시 보이게 한다.
  void resetAll() {
    state = const SettingsState();
    _db.removeKv(_kSettingsKey).catchError((_) {});
    _db.setOnboarded(false).catchError((_) {});
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);

// ── 데이터 ─────────────────────────────────────────────

String _normalizeLevelLabel(String level) => switch (level) {
      '읽기 도움 많이' => '동화책 수준',
      '원작 느낌 살리기' => '고전의 결 살리기',
      _ => level,
    };

/// 글자 크기 선택지 (라벨, 설명).
const List<(String, String)> kFontSizes = [
  ('작게', '작은 화면에 더 많은 내용을'),
  ('보통', '표준 크기'),
  ('크게', '읽기 편한 큰 글씨'),
  ('아주 크게', '가장 큰 글씨'),
];

/// 읽기 기본 속도 선택지 (라벨, 설명).
const List<(String, String)> kSpeeds = [
  ('느리게', '천천히 또박또박 읽어요'),
  ('보통', '자연스러운 속도로 읽어요'),
  ('빠르게', '빠르게 술술 읽어요'),
];

/// 이용 목적 선택지 (이모지, 이름, 설명). 온보딩 화면과 순서·내용을 동일하게 맞춤.
const List<(String, String, String)> kPurposes = [
  ('🌏', '한국어 배우는 중', '외국어로서 한국어를 공부해요'),
  ('📚', '한국 문학 탐구', '수업·독서 활동으로 읽어요'),
  ('🎭', '창작이 재미있어서', '이야기 만들기를 좋아해요'),
  ('👨‍👧', '아이와 함께', '가족이 함께 읽고 즐겨요'),
];

/// 기본 읽기 수준 선택지 (이모지, 이름, 설명).
const List<(String, String, String)> kLevels = [
  ('📖', '동화책 수준', '쉬운 단어와 짧은 문장으로'),
  ('🌿', '한국어 배우는 중', '기초 한국어 학습자에 맞춰'),
  ('⭐', '청소년용', '청소년 눈높이의 표현으로'),
  ('🏮', '고전의 결 살리기', '고전의 맛을 살린 표현으로'),
];
