# قائمة تحقق الإصدار التجاري — مِفتاح

## نطاق الإصدار الأول

هذا الإصدار يعمل على جهاز واحد، دون مزامنة بين الأجهزة، مع تخزين محلي ومشفر وتطبيق Flutter أصلي لـ Android وiOS، إضافة إلى نسخة Web اختيارية. المزامنة وFirebase مؤجلتان لإصدار لاحق.

## مكتمل في المستودع

- هوية مِفتاح وأيقونات Web وAndroid وiOS.
- اسم التطبيق في Flutter وWeb وAndroid وiOS وmacOS.
- تخزين Hive مشفر ومهاجرة من الصندوق القديم.
- كلمات مرور مملحة للحسابات الجديدة وقفل مؤقت للمحاولات الفاشلة.
- صلاحيات داخل AppController.
- فهارس بحث للغرف والضيوف والحجوزات.
- تصدير واستعادة نسخة احتياطية JSON مع تحقق من المخطط والروابط.
- إعداد iPad العمودي والأفقي وSafe Area في Web.
- إصدار التطبيق `1.0.0+2`.

## مطلوب قبل النشر الفعلي

| البند | المسؤول أو المدخل المطلوب |
|---|---|
| توقيع Android | keystore إنتاجي، كلمة مرور، وبيانات Play Console |
| توقيع iOS | Apple Developer Team، Bundle ID نهائي، شهادات وProvisioning |
| معرفات المتاجر | تأكيد أن `com.miftah.hotelmanagement` متاح ومملوك للفريق |
| اختبار البناء | تشغيل `flutter pub get`, `flutter analyze`, `flutter test`, و`flutter build apk --release --target-platform android-arm64` و`flutter build appbundle --release --target-platform android-arm64`؛ ويفحص CI بناء iOS دون توقيع على macOS |
| اختبار الأجهزة | هاتف Android، iPhone، iPad portrait/landscape، وDesktop مستهدف؛ يلزم اختبار فعلي قبل النشر العام |
| النسخ والاستعادة | تجربة تصدير واستعادة على جهاز نظيف، وإثبات عدم فقدان البيانات |
| حماية النسخة | تم اعتماد ملف `.miftah` مشفر بكلمة مرور عبر PBKDF2 وAES-GCM؛ يلزم اختبار الاستعادة عملياً |
| المتجر والخصوصية | سياسة خصوصية، شروط استخدام، صفحة دعم، وصف المتجر، ولقطات شاشة |
| الفواتير | تم إضافة فاتورة PDF عربية قابلة للطباعة؛ يبقى اعتماد قالب الضرائب والبيانات القانونية حسب البلد |

## أوامر التحقق والبناء

```bash
cd hotel_management_app
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build appbundle --release
flutter build web --release
```

للفحص على macOS دون توقيع:

```bash
flutter build ios --release --no-codesign
```

حزمة APK الناتجة من CI مناسبة للتثبيت المباشر على أجهزة Android الحديثة ARM64 فقط، ولا تحتوي على دعم 32-bit أو x86. حزمة AAB تحتاج keystore إنتاجياً قبل رفعها إلى Google Play. أما IPA الموقّع فيحتاج macOS وXcode وApple Developer Team وشهادات Provisioning؛ لا يمكن إنتاج IPA موقّع من Ubuntu.
