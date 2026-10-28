import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const voicePlaybackSpeeds = <double>[1, 1.5, 2];

double nextVoicePlaybackSpeed(double current) {
  final index = voicePlaybackSpeeds.indexWhere(
    (value) => (value - current).abs() < 0.01,
  );
  return voicePlaybackSpeeds[(index + 1) % voicePlaybackSpeeds.length];
}

class VoicePlaybackController extends ChangeNotifier {
  VoicePlaybackController._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'playbackCompleted' || call.method == 'playbackError') {
        if (call.arguments == currentUrl) {
          playing = false;
          loading = false;
          positionMs = call.method == 'playbackCompleted' ? durationMs : 0;
          if (call.method == 'playbackError') currentUrl = null;
          _timer?.cancel();
          notifyListeners();
        }
      }
      if (call.method == 'playbackSpeedChanged') {
        final value = call.arguments;
        if (value is num) {
          speed = value.toDouble();
          notifyListeners();
        }
      }
    });
  }

  static final instance = VoicePlaybackController._();
  static const _channel = MethodChannel('com.futureittouch.groopx/audio_player');

  String? currentUrl;
  bool playing = false;
  bool loading = false;
  int positionMs = 0;
  int durationMs = 0;
  double speed = 1;
  Timer? _timer;

  bool isCurrent(String url) => currentUrl == url;

  Future<void> toggle(String url, int knownDurationMs) async {
    if (loading) return;
    if (isCurrent(url) && playing) {
      await _channel.invokeMethod<void>('pause');
      playing = false;
      _timer?.cancel();
      notifyListeners();
      return;
    }
    if (isCurrent(url) && !playing && positionMs < durationMs) {
      await _channel.invokeMethod<void>('resume');
      playing = true;
      _startTimer();
      notifyListeners();
      return;
    }
    loading = true;
    currentUrl = url;
    positionMs = 0;
    durationMs = knownDurationMs;
    notifyListeners();
    try {
      final nativeDuration = await _channel.invokeMethod<int>('play', url) ?? 0;
      if (currentUrl != url) return;
      durationMs = nativeDuration > 0 ? nativeDuration : knownDurationMs;
      playing = true;
      _startTimer();
    } catch (_) {
      if (currentUrl == url) {
        currentUrl = null;
        positionMs = 0;
        playing = false;
      }
      rethrow;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> seek(String url, int value) async {
    if (!isCurrent(url)) return;
    positionMs = value.clamp(0, durationMs).toInt();
    notifyListeners();
    await _channel.invokeMethod<void>('seek', positionMs);
  }

  Future<void> cycleSpeed(String url) async {
    if (!isCurrent(url) || loading) return;
    final requested = nextVoicePlaybackSpeed(speed);
    final applied = await _channel.invokeMethod<num>('setSpeed', requested);
    speed = applied?.toDouble() ?? requested;
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!playing) return;
      try {
        positionMs = await _channel.invokeMethod<int>('position') ?? positionMs;
        notifyListeners();
      } catch (_) {}
    });
  }
}
