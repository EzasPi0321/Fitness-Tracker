# ML Kit text recognition references its optional Chinese, Devanagari, Japanese and
# Korean script packs. FitTrack only reads Latin-script labels and doesn't ship those packs,
# so tell R8 their absence is expected.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
