import 'package:flutter/services.dart';

/// Real, working alert feedback using only Flutter's built-in APIs — no
/// external audio package or bundled sound asset required, so it works
/// immediately with zero extra setup.
///
/// Honest limitation: this plays the platform's short system alert sound
/// (a "ding", not a siren) repeated a few times, plus vibration. A louder,
/// custom siren sound would need a real audio asset file and a package
/// like `audioplayers` — swap the implementation of [playAlert] for that
/// once you can bundle and test a sound file.
class AlertSoundService {
  AlertSoundService._();

  static bool _playing = false;

  /// Plays a short repeated alert (system sound + vibration).
  /// [times] controls how many pulses — use more for a more urgent alert.
  static Future<void> playAlert({int times = 3}) async {
    if (_playing) return;
    _playing = true;
    try {
      for (int i = 0; i < times; i++) {
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.vibrate();
        if (i < times - 1) {
          await Future.delayed(const Duration(milliseconds: 450));
        }
      }
    } finally {
      _playing = false;
    }
  }
}
