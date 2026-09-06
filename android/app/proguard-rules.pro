# The Flutter ML Kit text-recognition plugin supports several optional scripts.
# CNKH bundles Chinese (which also handles Latin) only. The plugin's generated
# switch still references the optional recognizer classes, so R8 must ignore
# those absent script packages during release shrinking.
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Keep the bundled Chinese text recognizer and Flutter plugin bridge intact.
-keep class com.google.mlkit.vision.text.chinese.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
