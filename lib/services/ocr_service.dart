import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class LocalOcrService {
  LocalOcrService()
      : _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  Future<String> recognizeFile(String path) async {
    final image = InputImage.fromFilePath(path);
    final result = await _recognizer.processImage(image);
    return result.text;
  }

  Future<void> close() => _recognizer.close();
}
