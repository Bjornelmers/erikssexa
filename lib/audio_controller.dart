import 'dart:js' as js;

class AudioController {
  static final AudioController instance = AudioController._internal();

  AudioController._internal();

  bool _isMuted = true;
  bool get isMuted => _isMuted;

  void init() {
    // Initialized on index.html script load
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    try {
      js.context.callMethod('eval', ['window.daocAudio.toggleMute($_isMuted)']);
    } catch (e) {
      print("Error calling toggleMute in JS: $e");
    }
  }

  void requestThemeMusic() {
    _isMuted = false;
    try {
      js.context.callMethod('eval', ['window.daocAudio.requestThemeMusic();']);
    } catch (e) {
      print("Error calling requestThemeMusic in JS: $e");
    }
  }

  void playThemeMusic() {
    requestThemeMusic();
  }

  void playLevelUpSound() {
    try {
      js.context.callMethod('eval', ['window.daocAudio.playLevelUp()']);
    } catch (e) {
      print("Error calling playLevelUp in JS: $e");
    }
  }

  void playVictorySound() {
    try {
      js.context.callMethod('eval', ['window.daocAudio.playVictory()']);
    } catch (e) {
      print("Error calling playVictory in JS: $e");
    }
  }

  void pauseMusic() {
    try {
      js.context.callMethod('eval', ['window.daocAudio.stopMusic()']);
    } catch (e) {
      print("Error calling stopMusic in JS: $e");
    }
  }

  void resumeMusic() {
    if (!_isMuted) {
      requestThemeMusic();
    }
  }
}
