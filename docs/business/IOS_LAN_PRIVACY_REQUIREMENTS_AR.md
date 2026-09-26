# متطلبات شبكة TapBix المحلية على iOS

- تستخدم ميزة الفروع على الشبكة المحلية بث UDP لاكتشاف الجهاز الرئيسي؛ لذلك يعلن التطبيق سبب الوصول عبر `NSLocalNetworkUsageDescription`.
- لا يستخدم التنفيذ الحالي Bonjour أو mDNS، لذلك لا يعلن `NSBonjourServices` وهميًا.
- نشر بث UDP أو multicast على iOS قد يحتاج استحقاق Apple المقيّد `com.apple.developer.networking.multicast`. يجب طلبه من Apple واختبار الاكتشاف على جهاز iPhone حقيقي قبل تمكين LAN في إصدار App Store. لا يُضاف الاستحقاق إلى ملف التوقيع قبل موافقة Apple حتى لا يفشل التوقيع.
- يستخدم التطبيق `local_auth`، لذلك يعلن سبب Face ID عبر `NSFaceIDUsageDescription`.
