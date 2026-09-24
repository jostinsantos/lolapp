# =============================================================================
# android/app/proguard-rules.pro
# =============================================================================

# --- Play Core (Flutter deferred components; no las usas → solo dontwarn) ---
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# --- flutter_local_notifications + Gson (Missing type parameter) ---
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-keepclassmembers class com.dexterous.flutterlocalnotifications.models.** { *; }

-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.TypeToken { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keepclassmembers class * extends com.google.gson.TypeToken {
    <fields>;
    <methods>;
}

-keep class org.threeten.bp.** { *; }
-dontwarn org.threeten.bp.**

# --- Flutter ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }