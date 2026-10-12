# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# Google Sign-In & Auth
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Deep linking & URL Launcher
-keep class com.llfbandit.app_links.** { *; }
-dontwarn com.llfbandit.app_links.**

# SQLite
-keep class com.tekartik.sqflite.** { *; }
-dontwarn com.tekartik.sqflite.**

# Contacts & Permissions
-keep class co.quis.flutter_contacts.** { *; }
-dontwarn co.quis.flutter_contacts.**
