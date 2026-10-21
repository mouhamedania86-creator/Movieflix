# MovieFlix

مشغل IPTV (Xtream) بواجهة مثل Netflix: Android وAndroid TV وWindows وiPhone.

## البناء (GitHub Actions)
ارفع المشروع على GitHub، ومن **Actions** حمل من Artifacts:
- `android-apk` : ملفات APK (للتليفون وAndroid TV، اختر `app-arm64-v8a-release.apk`)
- `windows-app` : `MovieFlix-windows.zip` (فك الضغط وشغل `movieflix.exe`)
- `ios-ipa` : `MovieFlix-unsigned.ipa` (بدون توقيع، لازم توقيع قبل التثبيت)

## iPhone
الـ IPA ما يتثبتش مباشرة. تحتاج واحدة من:
- Sideloadly أو AltStore بحساب Apple مجاني (التطبيق يتجدد كل 7 أيام).
- حساب Apple Developer مدفوع للتوقيع الدائم أو TestFlight.

## قسم "قريباً"
أضف مفتاح TMDB المجاني من الإعدادات (themoviedb.org).
