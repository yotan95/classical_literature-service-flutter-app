import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../models/sample_data.dart';
import '../services/audio_cache_store.dart';
import '../services/db_service.dart';
import '../services/tts_player.dart';
import 'create_main_state.dart' show normalizeLevelLabel;
import 'library_state.dart';

part 'audio_result_state.freezed.dart';

/// 오디오극 결과 화면 상태.
/// 재생/배속/현재 줄과, 줄을 탭했을 때의 액션 메뉴(여기부터 듣기 · 이 줄만 듣기).
@freezed
class AudioResultState with _$AudioResultState {
  const factory AudioResultState({
    String? workId, // 로컬 DB 창작물 id (null 이면 샘플)
    @Default('흥부의 두 번째 박') String title,
    @Default('흥부와 놀부') String source,
    @Default('청소년용') String level,
    @Default(false) bool playing,
    @Default(1.0) double speed, // 0.8 / 1.0 / 1.2
    @Default(0) int currentLine, // 재생 중인 줄 id
    int? selectedLine, // 탭해서 액션 메뉴가 열린 줄 id
    @Default(0.0) double progress, // 0~1 재생 진행률
    @Default(0) int positionMs, // 현재 재생 위치(ms)
    @Default(0) int totalMs, // 전체 길이(ms) = 마지막 timepoint endMs
    @Default(<ScriptLine>[]) List<ScriptLine> lines,
    @Default(<int, String>{}) Map<int, String> scenes, // 장면 번호 → 제목
  }) = _AudioResultState;
}

class AudioResultNotifier extends Notifier<AudioResultState> {
  DbService get _db => ref.read(dbServiceProvider);

  final TtsPlayer _tts = TtsPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];
  int _lastPosMs = 0; // 마지막 재생 위치(저장용)
  int _restorePosMs = 0; // 불러온 작품의 이어 들을 위치
  String? _audioUrl; // 서버 단일 MP3 URL (없으면 재생 불가: 데모/대사극)
  String? _localPath; // 받아 둔 로컬 MP3 절대경로(있으면 서버 무관 오프라인 재생)
  bool _downloadTried = false; // 첫 재생 시 캐시 다운로드 시도 여부(중복 방지)
  Map<int, (int, int)> _timepoints = const {}; // ScriptLine.id → (startMs,endMs)
  Timer? _lineStopTimer; // '이 줄만 듣기' 종료 타이머
  int _playEpoch = 0; // 재생 시퀀스 토큰: 비동기 load/seek 도중 화면을 떠나거나(stopAndPersist)
  //                     다른 재생이 시작되면 증가 → 뒤늦게 resume() 하지 못하게 막는다.

  /// 재생 가능한 소스가 있는지(로컬 캐시 또는 서버 URL).
  bool get _hasSource => ((_localPath ?? _audioUrl) ?? '').isNotEmpty;

  /// 재생 위치(ms)에 해당하는 현재 줄 id(없으면 null).
  int? _lineAt(int ms) {
    for (final e in _timepoints.entries) {
      if (ms >= e.value.$1 && ms < e.value.$2) return e.key;
    }
    return null;
  }

  @override
  AudioResultState build() {
    // 플레이어 이벤트를 상태에 반영(재생 여부·진행률·구간 종료).
    _subs.add(_tts.playingStream.listen((p) {
      state = state.copyWith(playing: p);
      // 첫 재생이 실제로 시작되면 스트리밍과 동시에 MP3 를 받아 둔다(다음부터 오프라인).
      if (p) _maybeCacheAudio();
    }));
    _subs.add(_tts.progressStream.listen((v) {
      state = state.copyWith(progress: v);
    }));
    _subs.add(_tts.positionMsStream.listen((ms) {
      _lastPosMs = ms;
      // 현재 위치 + '지금 읽는 문장' 하이라이트.
      final cur = _lineAt(ms);
      state = state.copyWith(
        positionMs: ms,
        currentLine: cur ?? state.currentLine,
      );
    }));
    _subs.add(_tts.completeStream.listen((_) {
      state = state.copyWith(playing: false);
      _lastPosMs = 0;
      _persistPosition();
    }));
    ref.onDispose(() {
      _persistPosition();
      _lineStopTimer?.cancel();
      for (final s in _subs) {
        s.cancel();
      }
      _tts.dispose();
    });
    return const AudioResultState(lines: kScriptEasy, scenes: kSceneNames);
  }

  /// 결과 화면을 연다.
  /// [workId] 가 있으면 로컬 DB 에서 제목·대본·장면·오디오 상태를 불러오고,
  /// 없으면 전달된 정보 + 샘플 대본으로 채운다(데모/디자인 확인용).
  void load({String? workId, String? title, String? source, String? level}) {
    _restorePosMs = 0;
    _audioUrl = null;
    _localPath = null;
    _downloadTried = false;
    _timepoints = const {};
    _lineStopTimer?.cancel();
    state = AudioResultState(
      workId: workId,
      title: title ?? state.title,
      source: source ?? state.source,
      level: normalizeLevelLabel(level ?? state.level),
      lines: kScriptEasy,
      scenes: kSceneNames,
    );
    if (workId != null) _loadFromDb(workId);
  }

  Future<void> _loadFromDb(String workId) async {
    try {
      final work = await _db.getWork(workId);
      final content = await _db.getWorkContent(workId);
      if (state.workId != workId) return; // 그 사이 다른 창작물로 바뀌면 무시
      _restorePosMs = content?.lastPositionMs ?? 0;
      // 서버 단일 MP3 + timepoints 를 보관하고 플레이어에 로드한다.
      _audioUrl = content?.audioUrl;
      _timepoints = content?.timepoints ?? const {};
      // 2회차(히스토리 재진입) 소스 결정: **DB 플래그가 아니라 실제 디스크 파일 존재**로 판단한다.
      //   받아 둔 mp3 있음 → 로컬 파일 재생, 없음 → 서버 URL 스트리밍.
      // 다운로드는 .part→.mp3 원자적 rename 이라 파일이 있으면 항상 완본이고,
      // 다운로드 도중 다른 작품으로 전환돼 DB(audio_local_path) 기록을 못 한 경우에도
      // 디스크에 받아 둔 파일을 확실히 쓴다(플래그-디스크 불일치 방지).
      final path = await ref.read(audioCacheStoreProvider).localPath(workId);
      if (state.workId != workId) return; // await 사이 작품 전환 방지(재확인)
      _localPath = path; // 디스크에 있으면 절대경로, 없으면 null → 스트리밍 폴백
      final firstId = (content?.lines.isNotEmpty ?? false)
          ? content!.lines.first.id
          : state.currentLine;
      // 전체 길이 = timepoints 의 마지막 endMs(서버 보장: == totalDurationMs).
      final totalMs = _timepoints.values.fold<int>(
          0, (m, t) => t.$2 > m ? t.$2 : m);
      state = state.copyWith(
        title: work?.title ?? state.title,
        source: work?.source ?? state.source,
        level: normalizeLevelLabel(work?.level ?? state.level),
        lines: (content?.lines.isEmpty ?? true) ? state.lines : content!.lines,
        scenes:
            (content?.scenes.isEmpty ?? true) ? state.scenes : content!.scenes,
        speed: content?.audioSpeed ?? state.speed,
        // 저장된 위치(이어듣기)로 시크바/현재 줄을 맞춘다. 없으면 0(처음부터).
        currentLine: _lineAt(_restorePosMs) ?? firstId,
        positionMs: _restorePosMs,
        totalMs: totalMs,
        progress: totalMs > 0 ? (_restorePosMs / totalMs).clamp(0.0, 1.0) : 0.0,
      );
      if (_hasSource) {
        // 캐시가 아직 없으면(스트리밍 구간) 진입 즉시 백그라운드 다운로드를 시작한다.
        // 재생 시작에 의존하지 않으므로, 한 번도 못 틀었어도 다음 진입부터 오프라인 파일을 쓴다
        // (재생 전 seek 이 막혀 재생이 시작 안 되던 자기모순 루프도 끊는다). 이미 받아 둔 경우엔 noop.
        _maybeCacheAudio();
        await _loadSource();
        await _tts.setSpeed(state.speed);
        // 플레이어 위치도 저장 지점으로 맞춰 둔다(재생 누르면 그 시점부터).
        // 로드 단계의 스트리밍 seek 은 실패할 수 있으나(서버 불안정) 조용히 넘긴다.
        if (_restorePosMs > 0) await _tts.seekMs(_restorePosMs);
      }
    } catch (_) {
      // DB 미지원: 이미 채운 샘플을 유지한다.
    }
  }

  /// 재생/일시정지 토글. 서버 단일 MP3 를 재생한다(없으면 무시: 데모/대사극).
  Future<void> togglePlay() async {
    _lineStopTimer?.cancel();
    if (_tts.isPlaying) {
      await _tts.pause();
      _persistPosition();
      return;
    }
    if (!_hasSource) return; // 재생할 MP3 없음
    final epoch = ++_playEpoch;
    await _loadSource();
    await _tts.setSpeed(state.speed);
    if (_restorePosMs > 0) {
      await _tts.seekMs(_restorePosMs);
      _restorePosMs = 0;
    }
    if (epoch != _playEpoch) return; // 로드 도중 화면 이탈/다른 재생 → resume 취소
    await _tts.resume();
  }

  void setSpeed(double s) {
    state = state.copyWith(speed: s);
    _tts.setSpeed(s).catchError((_) {});
    final id = state.workId;
    if (id != null) _db.updateAudio(id, speed: s).catchError((_) {});
  }

  /// 시크바 터치/드래그: 0~1 비율 위치로 이동(재생 상태는 유지). 드래그 중 미리보기 갱신.
  Future<void> seekToFraction(double fraction) async {
    _lineStopTimer?.cancel();
    final total = state.totalMs;
    if (total <= 0 || !_hasSource) return;
    final ms = (fraction.clamp(0.0, 1.0) * total).round();
    _lastPosMs = ms;
    state = state.copyWith(
      positionMs: ms,
      currentLine: _lineAt(ms) ?? state.currentLine,
    );
    // 시크바는 위치를 이미 화면에 반영했으므로, 스트리밍 seek 이 실패해도(서버 불안정)
    // 조용히 넘긴다 — 매 드래그마다 안내를 띄우면 오히려 시끄럽다.
    try {
      await _loadSource();
      await _tts.seekMs(ms);
    } catch (_) {}
  }

  /// 마지막 재생 위치를 로컬 DB 에 저장(workId 가 있을 때만).
  void _persistPosition() {
    final id = state.workId;
    if (id != null) {
      _db.updateAudio(id, positionMs: _lastPosMs).catchError((_) {});
    }
  }

  /// 현재 작품의 재생 소스를 플레이어에 로드한다.
  /// 받아 둔 로컬 캐시가 있으면 **오프라인 파일**, 없으면 **서버 URL 스트리밍**.
  /// (다운로드 트리거는 재생이 실제 시작될 때 [_maybeCacheAudio] 가 따로 처리)
  Future<void> _loadSource() async {
    final local = _localPath;
    if (local != null && local.isNotEmpty) {
      await _tts.setLocalFile(local);
      return;
    }
    final url = _audioUrl;
    if (url != null && url.isNotEmpty) await _tts.setUrl(url);
  }

  /// 첫 재생이 시작되면 서버 MP3 를 백그라운드로 받아 디스크에 캐시하고,
  /// 완료되면 DB(works.audio_local_path)에 파일명을 기록한다.
  /// 이미 로컬에 있거나 이번 작품에서 이미 시도했으면 아무것도 안 한다.
  /// (이미 재생 중인 스트림은 끊지 않는다 — 다음 진입부터 오프라인 파일로 재생)
  void _maybeCacheAudio() {
    if (_downloadTried || _localPath != null) return;
    final id = state.workId;
    final url = _audioUrl;
    if (id == null || url == null || url.isEmpty) return;
    _downloadTried = true;
    final cache = ref.read(audioCacheStoreProvider);
    cache.download(url, id).then((name) async {
      if (name == null) {
        _downloadTried = false; // 실패: 다음 재생에서 재시도
        return;
      }
      // 파일명은 어떤 작품이 떠 있든 그 작품(id)의 행에 기록한다(작품 전환과 무관).
      // 다운로드 도중 다른 작품으로 넘어가도 이 작품의 캐시 기록이 유실되지 않게.
      await _db.setAudioLocalPath(id, name);
      final path = await cache.localPath(id);
      if (state.workId != id) return; // 현재 떠 있는 작품일 때만 메모리 소스 갱신
      _localPath = path;
    }).catchError((Object _) {
      _downloadTried = false;
    });
  }

  /// 화면을 떠나거나(뒤로 가기) 앱이 백그라운드로 가거나 화면이 잠길 때 재생을 멈추고 현재 위치를 저장한다.
  /// 전역 provider 라 화면 pop 으로 자동 dispose 되지 않으므로 화면 dispose / 라이프사이클 콜백에서 호출.
  /// (다음에 다시 들어오면 load 가 저장된 위치를 복원 → 그 시점부터 재생 가능)
  ///
  /// [updateState] 가 false 면 state 를 건드리지 않는다 — 화면 dispose 시점에는 이 provider 를
  /// watch 하던 Element 가 이미 defunct 라, 여기서 state 를 바꾸면 markNeedsBuild 가 호출돼
  /// '_lifecycleState != defunct' assert 가 터진다(화면은 곧 사라지므로 갱신도 불필요).
  /// 라이프사이클(paused) 콜백은 위젯이 살아 있으므로 true 로 두어 재생버튼을 즉시 끈다.
  void stopAndPersist({bool updateState = true}) {
    _playEpoch++; // 진행 중인 재생 시퀀스를 무효화 → 로드/seek 완료 후 resume() 못 하게(화면 떠난 뒤 재생 방지)
    _lineStopTimer?.cancel();
    _tts.pause().catchError((_) {});
    _persistPosition();
    if (updateState) state = state.copyWith(playing: false);
  }

  /// ←10 / 10→ : 현재 위치에서 [seconds] 만큼 이동.
  void skip(int seconds) => _tts.skip(seconds).catchError((_) {});

  /// 줄 탭: 액션 메뉴 토글 (같은 줄 다시 탭하면 닫힘).
  void selectLine(int id) => state = state.copyWith(
        selectedLine: state.selectedLine == id ? null : id,
      );

  void closeMenu() => state = state.copyWith(selectedLine: null);

  /// '여기부터 듣기' — 선택한 줄의 시작 위치로 seek 후 끝까지 재생.
  Future<void> playFrom(int id) async {
    _lineStopTimer?.cancel();
    state = state.copyWith(selectedLine: null, currentLine: id);
    if (!_hasSource) return;
    final epoch = ++_playEpoch;
    await _loadSource();
    await _tts.setSpeed(state.speed);
    final tp = _timepoints[id];
    if (tp != null) await _tts.seekMs(tp.$1);
    if (epoch != _playEpoch) return; // 로드 도중 화면 이탈/다른 재생 → resume 취소
    await _tts.resume();
  }

  /// '이 줄만 듣기' — 선택한 줄 시작으로 seek 후 그 줄 끝에서 멈춘다(배속 반영).
  Future<void> playLineOnly(int id) async {
    _lineStopTimer?.cancel();
    state = state.copyWith(selectedLine: null, currentLine: id);
    final tp = _timepoints[id];
    if (!_hasSource || tp == null) return;
    final epoch = ++_playEpoch;
    await _loadSource();
    await _tts.setSpeed(state.speed);
    await _tts.seekMs(tp.$1);
    if (epoch != _playEpoch) return; // 로드 도중 화면 이탈/다른 재생 → resume 취소
    await _tts.resume();
    final durMs = ((tp.$2 - tp.$1) / state.speed).round();
    _lineStopTimer = Timer(Duration(milliseconds: durMs), () {
      _tts.pause();
      _persistPosition();
    });
  }

  void setTitle(String t) {
    if (t.trim().isEmpty) return;
    final title = t.trim();
    state = state.copyWith(title: title);
    final id = state.workId;
    if (id != null) {
      _db.updateTitle(id, title).then((_) {
        ref.read(libraryProvider.notifier).refresh();
      }).catchError((_) {});
    }
  }

}

final audioResultProvider =
    NotifierProvider<AudioResultNotifier, AudioResultState>(
        AudioResultNotifier.new);
