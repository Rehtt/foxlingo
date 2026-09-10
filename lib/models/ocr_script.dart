import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

enum OcrScript { latin, chinese, japanese, korean }

extension OcrScriptMlKit on OcrScript {
  TextRecognitionScript get mlKitScript {
    return switch (this) {
      OcrScript.latin => TextRecognitionScript.latin,
      OcrScript.chinese => TextRecognitionScript.chinese,
      OcrScript.japanese => TextRecognitionScript.japanese,
      OcrScript.korean => TextRecognitionScript.korean,
    };
  }
}
