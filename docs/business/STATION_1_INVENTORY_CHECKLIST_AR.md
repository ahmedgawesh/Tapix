# المحطة 1 — قائمة إغلاق مسارات المخزون

تاريخ المراجعة: 21 سبتمبر 2026. مرتبطة بـ`REMAINING_ROADMAP_AR.md`.

هذه قائمة متابعة مستخرجة من البحث في الكود ومراجعة المسارات المذكورة. «مفتوح» يعني أن القرار والتحقق لم يكتملَا، وليس إثبات وجود خلل في كل سطر. حقول الرصيد القديمة ما زالت مرآة توافق للمخزن الرئيسي؛ وجود قراءة منها يحتاج تصنيفًا قبل تشغيل مواقع إضافية.

## البنود المحددة

| المعرف | المسار والأدلة | الحالة وما يلزم لإغلاقه |
| --- | --- | --- |
| S1-01 | `ProductVariantRepositoryImpl.writeOffAndDeleteVariant` | أُصلح في هذه الدفعة: قراءة الرصيد والتسوية والحذف معاملة واحدة؛ تحقق رفض الرصيد البعيد وفشل التعطيل مع WAC وFIFO. التقرير `WAREHOUSE_VARIANT_WRITEOFF_VERIFICATION_AR.md`. |
| S1-02 | `ProductRepositoryImpl.createProduct` و`bulkCreateProducts`؛ النماذج والاستيراد وحدث الإنشاء القديم | أُنجز: معاملات الإنشاء والتدقيق والحصة وربط الصفوف، ثم فرض صفر عند إنشاء بيانات الصنف وتسجيل الرصيد عبر المتغير داخل المعاملة. تقريران: `PRODUCT_CREATION_TRANSACTION_VERIFICATION_AR.md` و`PRODUCT_OPENING_STOCK_CONTRACT_VERIFICATION_AR.md`. |
| S1-03 | `PurchaseDao` مسار مرآة تكلفة الصنف البسيط (`UPDATE product_variants SET cost_cents` واختيار أول متغير نشط) | أُنجز: توجيه تكلفة المرآة عبر خدمة تكلفة المخزن، ورفض التحديد الملتبس، واختبار الشراء والإلغاء مع طرق التكلفة الثلاث والمقاس الاختياري. التقرير `WAREHOUSE_PURCHASE_COST_MIRROR_VERIFICATION_AR.md`. |
| S1-04 | `InventoryValuationDeltaService.capture` | أُنجز: قراءة رصيد المخزن عند طرفي المقارنة وتثبيت هويته، والتحقق من الملكية والنشاط ووضوح المتغير؛ 16 اختبارًا للكسور والتقريب والتوافق. التقرير `WAREHOUSE_VALUATION_DELTA_VERIFICATION_AR.md`. |
| S1-05 | استعلامات نقص/نفاد المخزون في `ProductDao`، و`DataIntegrityService` و`VoidImpactAnalyzer` و`UnifiedReturnService` | أُنجز: فلاتر نقص/نفاد المخزون وفحوص DataIntegrityService وقراءات الكمية في VoidImpactAnalyzer وUnifiedReturnService. التقارير `WAREHOUSE_STOCK_ALERTS_VERIFICATION_AR.md` و`WAREHOUSE_RETURN_READS_VERIFICATION_AR.md`. تصنيف نطاق استعلامات التاريخ المتبقية ضمن S1-06. |
| S1-06 | التقارير والتصدير وقراءات التاريخ وLAN | أُنجز: ثُبتت مصفوفة `REPORT_SCOPE_MATRIX_AR.md` ورُبط تقرير الأرباح بكامل تفاصيله بنطاق المستند. تقارير التحقق: `WAREHOUSE_PROFIT_SCOPE_VERIFICATION_AR.md` و`WAREHOUSE_TRANSACTION_REPORTS_VERIFICATION_AR.md` و`WAREHOUSE_TAX_DISCOUNT_VERIFICATION_AR.md` لتغطية الأرباح والمعاملات والضريبة والخصومات، ثم `WAREHOUSE_MOVEMENT_REPORTS_VERIFICATION_AR.md` لحركات المنتجات، و`WAREHOUSE_CUSTOMER_ANALYSIS_VERIFICATION_AR.md` لنشاط العملاء وعقد الحساب الكامل للأطراف. أُصلحت دقة تقرير العمولات في `COMMISSION_REPORT_ACCURACY_VERIFICATION_AR.md`، وأُضيف مصدر المرتجع الجديد ومطابقة مراجعة للحالات القديمة غير الملتبسة وفق `COMMISSION_RETURN_SOURCE_VERIFICATION_AR.md` و`COMMISSION_RECONCILIATION_DEVICE_VERIFICATION_AR.md`؛ اكتمل عرض نطاق المخزن مع إبقاء الحساب الكامل ومعالجة السجلات غير المنسوبة صراحةً في `WAREHOUSE_COMMISSION_SCOPE_VERIFICATION_AR.md`. أُنجز أيضًا نطاق تاريخ المرتجعات وتحليل الإلغاء في `WAREHOUSE_RETURN_HISTORY_VERIFICATION_AR.md`. أُنجز عزل مستندات LAN في `LAN_DOCUMENT_SCOPE_VERIFICATION_AR.md` مع إصلاح اكتمال قائمة مرتجعات الشراء. اكتملت أرصدة الكتالوج وCSV/Excel وتصنيف الحسابات المشتركة والوردية وفق `WAREHOUSE_CATALOG_EXPORT_VERIFICATION_AR.md`. بوابة البناء الختامية موثقة في `STATION_1_CLOSURE_VERIFICATION_AR.md`. |
| S1-07 | `AdminToolsScreen._runHealthCheck`، وكتابات التهيئة/الترقية والمحوّلات `toCompanion` | أُنجز: فحص الصحة يتراجع دائمًا؛ صُنفت الكتابات وواجهات DAO وحُميت إعدادات المخزون في release. أُصلحت إعادة بناء مخطط المتغيرات القديم ذريًا واختُبر الفشل والتعافي والترقية الفعلية من10085. التقارير `DATABASE_HEALTH_CHECK_VERIFICATION_AR.md` و`INVENTORY_POLICY_VALIDATION_AR.md` و`VARIANT_NULLABILITY_REPAIR_VERIFICATION_AR.md`. المخططات غير المعروفة أو بقايا إصلاح سابق تتوقف للمراجعة دون حذف تلقائي. |

## أجزاء متحققة سابقًا

- خدمات الكمية والتكلفة وتجميع الأب ومواقع الدفعات: تقارير `WAREHOUSE_*` المرتبطة بالخطة الأصلية.
- تحديث بيانات الصنف والمتغير لا يكتب الكمية والتكلفة العامة، وحماية الحذف/التعطيل تشمل جميع المخازن.
- إنشاء المتغير والباركود والرصيد الافتتاحي معاملة واحدة، مع رفض الرصيد الافتتاحي السالب.
- نطاق ترحيل وإلغاء الفواتير والمرتجعات: `DOCUMENT_POSTING_SCOPE_VERIFICATION_AR.md`.

## شرط إغلاق المحطة

إغلاق البنود المفتوحة بقرار واضح واختبارات مناسبة، ثم إعادة البحث عن مسارات تتجاوز الخدمات وتوثيق الاستثناءات الضرورية للتوافق والترقية. لا يكفي نجاح البناء وحده لإغلاق المحطة. أي اكتشاف تابع يُضاف تحت المعرف المناسب، مع ذكر أثره الفعلي؛ المحطة2 هي التي تفتح تشغيل مخزن محدد فعليًا.

## نتيجة الإغلاق

أُغلقت البنود السبعة وبوابة المحطة:3166 اختبارًا ناجحًا، تحليل دون ملاحظات، وبناء Linux وAndroid Release ناجحان. التفصيل في `STATION_1_CLOSURE_VERIFICATION_AR.md`. المحطة2 لم تكتمل بعد ولا تُفتح المخازن الإضافية للعملاء بهذا الإغلاق وحده.
