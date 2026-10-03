# =============================================================================
# flutter_local_notifications + Gson (evita "Missing type parameter" en release)
# Copia estas líneas a: android/app/proguard-rules.pro
# Y en android/app/build.gradle (release):
#   minifyEnabled true
#   proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
# =============================================================================

# Plugin
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# Gson (TypeToken necesita Signature)
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

# Modelos que el plugin serializa (scheduled notifications)
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-keepclassmembers class com.dexterous.flutterlocalnotifications.models.** { *; }

# Timezone / Android
-keep class org.threeten.bp.** { *; }
-dontwarn org.threeten.bp.**