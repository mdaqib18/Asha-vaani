import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

enum MicPermissionState { granted, denied, permanentlyDenied }

abstract class AudioCaptureService {
  Future<MicPermissionState> ensurePermission();
  Future<String> createTempWavPath();
  Future<void> startRecording(String filePath);
  Future<Stream<Uint8List>?> startPcmStream();
  Future<String?> stopRecording();
  Future<bool> openSettings();
  void dispose();
}

class RecordAudioCaptureService implements AudioCaptureService {
  RecordAudioCaptureService() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<MicPermissionState> ensurePermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    if (status.isGranted) return MicPermissionState.granted;
    if (status.isPermanentlyDenied) {
      return MicPermissionState.permanentlyDenied;
    }
    return MicPermissionState.denied;
  }

  @override
  Future<String> createTempWavPath() async {
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}/visit_$ts.wav';
  }

  @override
  Future<void> startRecording(String filePath) async {
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        noiseSuppress: true,
        echoCancel: true,
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceRecognition,
        ),
      ),
      path: filePath,
    );
  }

  @override
  Future<Stream<Uint8List>?> startPcmStream() async {
    return _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        noiseSuppress: true,
        echoCancel: true,
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceRecognition,
        ),
      ),
    );
  }

  @override
  Future<String?> stopRecording() async {
    return _recorder.stop();
  }

  @override
  Future<bool> openSettings() async {
    return openAppSettings();
  }

  @override
  void dispose() {
    _recorder.dispose();
  }
}
