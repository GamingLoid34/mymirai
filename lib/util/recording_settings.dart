import 'package:shared_preferences/shared_preferences.dart';

const _kAutoDeleteAudioPref = 'auto_delete_recording_audio';
const _kAutoDeleteAskedPref = 'auto_delete_recording_asked';
const _kRecordingLanguagePref = 'recording_language_code';

Future<bool> getAutoDeleteRecordingAudio() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kAutoDeleteAudioPref) ?? false;
}

Future<void> setAutoDeleteRecordingAudio(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kAutoDeleteAudioPref, value);
}

/// `true` om vi redan frågat användaren en gång om autoradering.
Future<bool> hasAskedAutoDeleteRecording() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kAutoDeleteAskedPref) ?? false;
}

Future<void> markAskedAutoDeleteRecording() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kAutoDeleteAskedPref, true);
}

Future<String> getRecordingLanguageCode() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kRecordingLanguagePref) ?? 'sv-SE';
}

Future<void> setRecordingLanguageCode(String code) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kRecordingLanguagePref, code);
}
