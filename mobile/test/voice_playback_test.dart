import 'package:flutter_test/flutter_test.dart';
import 'package:groopx/features/chat/data/voice_playback.dart';

void main() {
  test('voice playback speed cycles through supported values', () {
    expect(nextVoicePlaybackSpeed(1), 1.5);
    expect(nextVoicePlaybackSpeed(1.5), 2);
    expect(nextVoicePlaybackSpeed(2), 1);
  });

  test('unknown playback speed returns to normal', () {
    expect(nextVoicePlaybackSpeed(1.25), 1);
  });
}
