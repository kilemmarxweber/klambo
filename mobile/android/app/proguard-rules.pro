# Flutter / plugins — keep entry points used by reflection.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Generated plugin registrant
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# WebRTC
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**
-keep class com.cloudwebrtc.** { *; }
-dontwarn com.cloudwebrtc.**

# Secure storage / shared prefs
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# Local notifications
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# Play Core (deferred components) — referenced by Flutter embedding
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Misc
-dontwarn com.google.android.gms.**
-dontwarn javax.annotation.**
-dontwarn org.bouncycastle.**
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
