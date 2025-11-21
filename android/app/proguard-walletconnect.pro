# Preserve WalletConnect v2 SDK classes that rely on reflection for JSON parsing.
-keep class com.walletconnect.** { *; }
-keep class com.squareup.moshi.** { *; }
-keepclassmembers class ** {
    @com.squareup.moshi.* <fields>;
}

# Avoid stripping Kotlin metadata used by WalletConnect core types.
-keepclassmembers class kotlin.Metadata { *; }

# Silence warnings from generated or optional modules.
-dontwarn com.walletconnect.**
