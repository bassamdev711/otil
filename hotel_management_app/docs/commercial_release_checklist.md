# قائمة تحقق الإصدار التجاري — مِفتاح

## نطاق الإصدار الأول

هذا الإصدار يعمل على جهاز واحد، دون مزامنة بين الأجهزة، مع تخزين محلي ومشفر وواجهة Flutter Web وواجهات أصلية قابلة للتجهيز. المزامنة وFirebase مؤجلتان لإصدار لاحق.

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
| اختبار البناء | تشغيل `flutter pub get`, `flutter analyze`, `flutter test`, ثم release builds |
| اختبار الأجهزة | Android، iPhone، iPad portrait/landscape، وDesktop مستهدف |
| النسخ والاستعادة | تجربة تصدير واستعادة على جهاز نظيف، وإثبات عدم فقدان البيانات |
| حماية النسخة | اعتماد سياسة حفظ ملف JSON الحساس، ويفضل تشفير الملف نفسه قبل بيع المنتج |
| المتجر والخصوصية | سياسة خصوصية، شروط استخدام، صفحة دعم، وصف المتجر، ولقطات شاشة |
| الفواتير | استبدال رسالة SnackBar الحالية بتصدير فاتورة فعلي إذا كان مطلوباً في نطاق البيع |

## أوامر التحقق

```bash
cd hotel_management_app
flutter pub get
flutter analyze
flutter test
flutter build web --release
flutter build apk --release
flutter build ios --release
```

لا تُشغّل أوامر iOS release إلا على macOS مع Xcode وحساب Apple Developer مضبوطين.
