# Keep rules for the Google Mobile Ads SDK and its bundled UMP consent SDK.
# There are recurring release-only crashes (NoSuchMethodError /
# ClassNotFoundException at startup) when R8 strips or rewrites parts of the
# consent SDK, which runs on the app's very first frame. Keeping these
# packages whole costs a little APK size and removes that class of failure.
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.android.ump.** { *; }
-keep class com.google.android.gms.internal.consent_sdk.** { *; }

# Play Billing (in_app_purchase): same insurance for the purchase flow.
-keep class com.android.billingclient.** { *; }
-dontwarn com.google.android.gms.**
