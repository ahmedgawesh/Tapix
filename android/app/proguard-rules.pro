# TapBix release keep-rules (R8/ProGuard)
# Flutter's own rules are applied automatically by the Flutter Gradle plugin.

# --- Flutter engine ---
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# --- Play Core / deferred components (referenced by Flutter, may be absent) ---
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# --- Firebase (Core + Crashlytics) ---
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
# Keep Crashlytics line numbers / source info
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# --- RevenueCat (purchases_flutter) + Google Play Billing ---
-keep class com.revenuecat.purchases.** { *; }
-dontwarn com.revenuecat.purchases.**
-keep class com.android.vending.billing.** { *; }
-keep class com.android.billingclient.** { *; }

# --- SQLite3 / SQLCipher (SQLite3MultipleCiphers) ---
-keep class org.sqlite.** { *; }
-keep class com.github.requery.android.database.** { *; }
-dontwarn org.sqlite.**

# --- Kotlin metadata ---
-keep class kotlin.Metadata { *; }
-keepclassmembers class **$WhenMappings { <fields>; }
