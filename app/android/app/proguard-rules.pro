# Flutter ProGuard Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Razorpay SDK
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** { *; }
-keepclasseswithmembers class * {
    public void onPaymentSuccess(java.lang.String);
    public void onPaymentError(int, java.lang.String);
}
-keepclasseswithmembers class * {
    public void onPaymentSuccess(java.lang.String, com.razorpay.PaymentData);
    public void onPaymentError(int, java.lang.String, com.razorpay.PaymentData);
}
-dontwarn org.slf4j.**
-keep class com.google.android.gms.wallet.** { *; }

# Mobile Scanner Plugin
-keep class dev.steenbakker.mobile_scanner.** { *; }
-dontwarn dev.steenbakker.mobile_scanner.**

# Google ML Kit Barcode Scanning & Vision (prevents getClass() NullPointerException)
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_code_scanner.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.gms.tasks.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# AndroidX Camera / CameraX
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# SQLite / Sqflite
-keep class com.tekartik.sqflite.** { *; }
-dontwarn com.tekartik.sqflite.**

# Biometric / Local Auth
-keep class io.flutter.plugins.localauth.** { *; }
-keep class androidx.biometric.** { *; }
-dontwarn androidx.biometric.**

# Google Sign-In
-keep class io.flutter.plugins.googlesignin.** { *; }
-keep class com.google.android.gms.auth.api.signin.** { *; }
-dontwarn com.google.android.gms.auth.api.signin.**

# Image Picker
-keep class io.flutter.plugins.imagepicker.** { *; }
-dontwarn io.flutter.plugins.imagepicker.**

# Share Plus
-keep class dev.fluttercommunity.plus.share.** { *; }
-dontwarn dev.fluttercommunity.plus.share.**

# Printing & PDF
-keep class net.nfet.flutter.printing.** { *; }
-dontwarn net.nfet.flutter.printing.**

# Core Platform Utilities
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }

# Flutter Engine & Play Core Deferred Components
-dontwarn com.google.android.play.core.**

# General warnings suppression for safe R8 shrinking
-dontwarn okio.**
-dontwarn javax.annotation.**
-dontwarn org.codehaus.mojo.animal_sniffer.**

# Preserve annotations and signatures for reflection
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
