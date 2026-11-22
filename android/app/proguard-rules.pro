# Plobby · reglas de R8 (Seguridad Fase 5). Flutter añade las suyas automáticamente.
# flutter_secure_storage usa Tink (EncryptedSharedPreferences): sus anotaciones opcionales no están en el APK.
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn com.google.crypto.tink.**
-keep class com.google.crypto.tink.** { *; }
# Flutter deferred components (no se usan, pero el motor los referencia)
-dontwarn com.google.android.play.core.**
