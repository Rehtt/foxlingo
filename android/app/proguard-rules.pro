# google_mlkit_text_recognition references optional script option classes
# in initialize(), but this app does not ship the Devanagari recognizer.
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
