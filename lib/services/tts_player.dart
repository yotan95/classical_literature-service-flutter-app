import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// 오디오극 재생기 — 서버 `/create` 결과의 **단일 MP3**(`audio.audioUrl`)를 재생한다.
/// 라인별 합성(/tts)이 아니라 하나의 MP3 를 재생하고, `timepoints` 의 startMs 로 **seek** 한다.
/// `/audio` 는 HTTP Range 를 지원하므로 스트리밍+seek 가능.
class TtsPlayer {
  TtsPlayer();

  final AudioPlayer _player = AudioPlayer();
  // 현재 로드된 소스 키. 같은 소스면 재로드를 생략(`url:<url>` 또는 `file:<path>`).
  String? _source;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _durSub;

  /// 재생 중 여부 스트림.
  Stream<bool> get playingStream =>
      _player.onPlayerStateChanged.map((s) => s == PlayerState.playing);

  /// 재생 진행률(0~1) 스트림.
  Stream<double> get progressStream => _player.onPositionChanged.map((pos) {
        final total = _duration.inMilliseconds;
        if (total <= 0) return 0.0;
        return (pos.inMilliseconds / total).clamp(0.0, 1.0);
      });

  /// 현재 재생 위치(ms) 스트림(현재 문장 하이라이트·마지막 위치 저장용).
  Stream<int> get positionMsStream =>
      _player.onPositionChanged.map((pos) => pos.inMilliseconds);

  /// 재생이 끝까지 갔을 때.
  Stream<void> get completeStream => _player.onPlayerComplete;

  bool get isPlaying => _player.state == PlayerState.playing;

  /// MP3 가 로드돼 있는지.
  bool get hasAudio => (_source ?? '').isNotEmpty;

  int get durationMs => _duration.inMilliseconds;

  /// 서버 MP3 URL 을 로드(자동재생 안 함). 같은 소스면 무시 — 온라인 스트리밍용.
  Future<void> setUrl(String url) async {
    final key = 'url:$url';
    if (_source == key) return;
    _source = key;
    _durSub ??= _player.onDurationChanged.listen((d) => _duration = d);
    await _player.setSourceUrl(url);
  }

  /// 디스크에 받아 둔 로컬 MP3 파일을 로드(자동재생 안 함). 같은 소스면 무시 —
  /// 오프라인 재생용. Range/seek 는 로컬 파일에서도 그대로 동작한다.
  Future<void> setLocalFile(String path) async {
    final key = 'file:$path';
    if (_source == key) return;
    _source = key;
    _durSub ??= _player.onDurationChanged.listen((d) => _duration = d);
    await _player.setSource(DeviceFileSource(path));
  }

  /// 현재 위치부터 재생.
  Future<void> resume() => _player.resume();

  Future<void> pause() => _player.pause();

  /// 네트워크 스트림 seek 이 응답하지 않을 때 audioplayers 기본 30초까지 UI 가 멈추는 것을 막는
  /// 자체 타임아웃. 로컬 파일 seek 은 즉시 끝나므로 실질적으로 스트리밍 구간에서만 의미가 있다.
  /// 초과하면 [TimeoutException] 을 던진다 — 호출 측에서 "재생 불가" 안내/무시로 처리한다.
  static const Duration seekTimeout = Duration(seconds: 8);

  Future<void> _seek(Duration pos) => _player.seek(pos).timeout(seekTimeout);

  Future<void> seekMs(int ms) => _seek(Duration(milliseconds: ms));

  /// 배속 변경(재생 중에도 즉시 반영).
  Future<void> setSpeed(double speed) => _player.setPlaybackRate(speed);

  /// 현재 위치에서 [seconds] 만큼 앞/뒤로 이동.
  Future<void> skip(int seconds) async {
    final pos = await _player.getCurrentPosition() ?? Duration.zero;
    var target = pos + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;
    await _seek(target);
  }

  Future<void> dispose() async {
    await _durSub?.cancel();
    await _player.dispose();
  }
}
