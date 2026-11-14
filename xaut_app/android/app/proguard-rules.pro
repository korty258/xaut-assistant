# Flutter wrapper & embedding
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keepattributes *Annotation*

# App entry point & native MethodChannel
-keep class io.github.korty258.jinhua_assistant.** { *; }

# Keep @JavascriptInterface callbacks for WebView JS Bridge
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepclassmembers class * {
    @androidx.annotation.Keep <methods>;
}

# flutter_secure_storage & Google Tink / AndroidX Security
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.google.crypto.tink.** { *; }
-keep class androidx.security.crypto.** { *; }
-keep class androidx.core.content.FileProvider { *; }
-keep class dev.fluttercommunity.plus.share.** { *; }
-keep class kotlin.Metadata { *; }

# Suppress optional JVM-only annotation / Conscrypt warnings in Tink & plugins
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
-dontwarn java.lang.instrument.**
