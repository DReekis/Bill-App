# ==============================================================================
# R8 / ProGuard Optimization & Obfuscation Configuration
# Designed for Google Play compliance (R8 Full Mode & High Obfuscation)
# ==============================================================================

# Preserve annotations and signatures essential for runtime reflection & Flutter channels
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# Keep native JNI bindings without blocking obfuscation of surrounding classes
-keepclasseswithmembernames class * {
    native <methods>;
}

# Flutter Application & Engine Entry Points
-keep class io.flutter.app.FlutterApplication { *; }
-keep class io.flutter.embedding.android.FlutterActivity { *; }
-keep class io.flutter.embedding.android.FlutterFragmentActivity { *; }
-keep class io.flutter.embedding.android.FlutterView { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Keep Flutter plugin public lifecycle & MethodChannel interfaces intact
# Allows internal plugin implementation classes and methods to be obfuscated & shrunk
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin {
    public *;
}
-keep class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler {
    public *;
}
-keep class * implements io.flutter.embedding.engine.plugins.activity.ActivityAware {
    public *;
}

# Google Play Core Deferred Components (suppress deferred class warning when split install is unused)
-dontwarn com.google.android.play.core.**

# Razorpay SDK (requires SDK reflection & JavaScript interfaces)
-dontwarn com.razorpay.**
-keep class com.razorpay.** { *; }
-keepclasseswithmembers class * {
    public void onPaymentSuccess(java.lang.String);
    public void onPaymentError(int, java.lang.String);
    public void onPaymentSuccess(java.lang.String, com.razorpay.PaymentData);
    public void onPaymentError(int, java.lang.String, com.razorpay.PaymentData);
}
-dontwarn org.slf4j.**
-keep class com.google.android.gms.wallet.** { *; }

# Google ML Kit Barcode Scanning & Vision
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }

# Biometrics / Local Auth
-dontwarn androidx.biometric.**

# Google Sign-In
-dontwarn com.google.android.gms.auth.api.signin.**

# Camera & Hardware
-dontwarn androidx.camera.**
-dontwarn dev.steenbakker.mobile_scanner.**

# General warnings suppression for safe R8 full mode shrinking
-dontwarn okio.**
-dontwarn javax.annotation.**
-dontwarn org.codehaus.mojo.animal_sniffer.**
-dontwarn com.tekartik.sqflite.**
