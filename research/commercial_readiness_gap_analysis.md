# Commercial Readiness Gap Analysis

## Scope

الإصدار الأول: جهاز واحد، تشغيل دون اتصال، تخزين محلي، واجهات Flutter Web وواجهات أصلية قابلة للتجهيز لاحقاً.

## Confirmed gaps

| Area | Current state | Commercial requirement |
|---|---|---|
| Runtime validation | Flutter/Dart غير متوفرين في بيئة التدقيق | تشغيل `flutter pub get`, analyzer, tests, and release builds |
| Android identity | applicationId وnamespace على قيم `com.example.hotel_management_app`، والتوقيع release يستخدم debug | معرّف تجاري فريد، اسم مِفتاح، signing config إنتاجي |
| iOS identity | display name وbundle identifiers ما زالت افتراضية | اسم مِفتاح، bundle identifier تجاري، إعدادات signing وApp Store |
| macOS identity | product name وbundle identifier افتراضيان | metadata تجاري أو استبعاد المنصة بوضوح |
| Native icon packaging | أصول Web محدثة، لكن launcher icon native ما زال قالباً | توليد Android adaptive icons وiOS/macOS/Windows assets |
| Backup and restore | غير موجود | تصدير نسخة احتياطية مشفرة، استيراد مع تحقق ومخطط وترحيل |
| Billing/invoice | زر طباعة الفاتورة يعرض SnackBar فقط | فاتورة قابلة للطباعة/التصدير PDF أو HTML، حسب نطاق الإصدار |
| Validation | نماذج الإضافة ذات تحقق خفيف | تحقق موحد، منع تعارض الحجز، منع قيم سالبة ومدد غير صحيحة |
| Recovery | لا توجد شاشة أو مسار استعادة بعد تلف البيانات | فحص سلامة، نسخة تلقائية، وضع استرداد، رسائل فشل واضحة |
| Quality gates | اختبارات وحدات قليلة ولا يوجد analyzer/build في البيئة | تغطية منطق البيانات، اختبارات Widget، analyzer صارم، release smoke test |
| Documentation | تشغيل محلي موثق، لكن لا توجد حزمة توزيع أو دليل نسخ احتياطي | دليل تثبيت وتشغيل ودعم واستعادة وإصدارات |

## Release acceptance

لا يُعتبر الإصدار جاهزاً للتوزيع التجاري قبل نجاح: بناء Release على المنصة المستهدفة، تشغيل التطبيق على جهاز فعلي، إنشاء واستعادة نسخة احتياطية، اختبار فقدان/تلف البيانات، اختبار الحسابات والصلاحيات، اختبار الدوران وأحجام iPad، والتحقق من عدم ظهور بيانات الاعتماد الافتراضية في وضع الإنتاج.
