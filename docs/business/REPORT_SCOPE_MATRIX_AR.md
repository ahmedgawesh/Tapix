# مصفوفة نطاق التقارير وقراءات التاريخ — S1-06

21 سبتمبر2026. هذه مصفوفة مراجعة؛ البنود المفتوحة لم تُعتمد بعد للتشغيل متعدد المواقع. البرنامج لا يتيح تشغيل مخزن إضافي بمجرد إضافة فلتر إلى تقرير.

| المجموعة | الملفات/الخدمات | نطاق القراءة المقصود والتحقق | الحالة |
| --- | --- | --- | --- |
| تقييم وجرد المخزون | `InventoryReportsBloc`، `SupplierStocktakeReportBloc`، تقييم `JournalLocalDatasource` | أرصدة ودفعات المخزن الرئيسي؛ إبقاء التاريخ عند التعطيل | منجز في تقارير التحقق السابقة |
| الأرباح | `ProfitReportsBloc` | كل مستند بيع/مرتجع يتبع موقعه وتاريخه؛ تفاصيل الصنف والتصنيف والعميل والفاتورة والضريبة تتطابق، مع ثبات التكلفة المجمدة | منجز في `WAREHOUSE_PROFIT_SCOPE_VERIFICATION_AR.md` |
| المبيعات والمشتريات والمرتجعات والفواتير | `SalesReportsBloc`، `PurchaseReportsBloc`، `CustomerSalesReturnsBloc`، `SupplierReturnsReportBloc`، `CustomerInvoicesReportBloc`، `SupplierInvoicesReportBloc` | عرض حركة الموقع الحالي؛ اختبارات استبعاد مستندات أخرى لكل نوع وإعادة التحديث | منجز في `WAREHOUSE_TRANSACTION_REPORTS_VERIFICATION_AR.md` |
| الضريبة والخصومات | `SalesTaxReportBloc`، `PurchaseTaxReportBloc`، `DiscountReportsBloc` | مصدر كل فاتورة ومرتجع حسب موقعه؛ تجميع خصومات الصنف والتصنيف والعميل والفاتورة، مع التحديث الحي | منجز في `WAREHOUSE_TAX_DISCOUNT_VERIFICATION_AR.md` |
| حركات المنتجات المستقلة | `ProductVariantMovementBloc`، `CategoryMovementBloc`، `ProductMovementDetailBloc`، `StockMovementReportBloc` | مصادر البيع والشراء والمرتجعات الستة حسب موقع المستند؛ هذه التقارير تعرض حركة الفترة وليست رصيدًا مخزنيًا كاملًا | منجز لعزل المصادر الحالية في `WAREHOUSE_MOVEMENT_REPORTS_VERIFICATION_AR.md` |
| نشاط العملاء وتحليلهم | `CustomerSalesReportBloc`، `CustomerAnalysisReportBloc`، `TopCustomersBloc` | حركة فواتير الموقع الحالي؛ لا تمثل رصيد العميل أو صافي نشاطه بعد المرتجعات | منجز في `WAREHOUSE_CUSTOMER_ANALYSIS_VERIFICATION_AR.md` |
| كشوف حساب الأطراف | `CustomerLedgerReportBloc`، `SupplierLedgerReportBloc` و`PartyStatementLedgerService` | حساب الطرف الكامل داخل القاعدة، شامل الافتتاحي والمدفوعات والتسويات عبر مواقع المستندات؛ لا يُصفّى بالفواتير وحدها | صُنّف العقد واختُبر؛ صلاحية عرضه متعدد المواقع مطلوبة في المحطة4 |
| العمولات | `SalespeopleCommissionReportBloc` و`CommissionSourceScope` | حساب كامل افتراضي، وعرض مستقل للمخزن حسب مصدر العمولة/المرتجع وتاريخ الحدث؛ مصدر مجهول يمنع الإجمالي المحلي الجزئي دون إخفاء الحساب الكامل | منجز في `WAREHOUSE_COMMISSION_SCOPE_VERIFICATION_AR.md`؛ مطابقة البيانات القديمة غير الواضحة تحتاج مراجعة صريحة دون تخمين، وصلاحيات الحساب الكامل عبر الشبكة ضمن المحطة4 |
| اختيار تاريخ المرتجعات وتحليل الإلغاء | `UnifiedReturnService`، `VoidImpactAnalyzer` | بحث فواتير الموقع ومرشحي الارتباط والمرتجعات المتداخلة مع حفظ السعر الأصلي؛ قراءات كمية المخزون أُنجزت في S1-05 | منجز في `WAREHOUSE_RETURN_HISTORY_VERIFICATION_AR.md`؛ مرشحو التسوية لا يمثلون سجل تخصيص دقيقًا |
| مستندات LAN | `LanMasterBusinessGateway` وقوائم وتفاصيل المبيعات والفواتير القابلة للإرجاع والمرتجعات | الخادم يفرض نطاق المستند قبل الترقيم والتفاصيل وإحصائيات المبيعات؛ سقوف الإرجاع كاملة | منجز في `LAN_DOCUMENT_SCOPE_VERIFICATION_AR.md` |
| التصدير وكتالوج LAN | `WarehouseCatalogScope` و`WarehouseExportStockReader` | أرصدة وتكاليف المخزن الرئيسي؛ معاملة تصدير واحدة ومعاينة حية؛ رفض الرصيد الناقص والتحديد الملتبس | منجز في `WAREHOUSE_CATALOG_EXPORT_VERIFICATION_AR.md` |
| بيانات LAN المشتركة والوردية | العملاء والموردون والمندوبون و`CashierShiftService` | دليل مشترك داخل القاعدة، رصيد العميل كامل، والوردية حسب رابطها الفعلي ومستخدم الجلسة | صُنّف العقد في `WAREHOUSE_CATALOG_EXPORT_VERIFICATION_AR.md`؛ صلاحيات الحساب الكامل وموقع الوردية شرط لتفعيل المواقع الإضافية ضمن المحطتين2 و4 |

## قاعدة الربط

موقع المستند مصدر الحركة هو حد التجميع. الرجوع إلى الفاتورة الأصلية للحصول على اسم العميل أو التكلفة التاريخية ليس إدراجًا جديدًا لحركة تلك الفاتورة. في تقرير الأرباح يُنسب المرتجع إلى موقع وتاريخ مستند المرتجع، ولا يُحذف لمجرد خروج تاريخ فاتورته الأصلية من الفترة. التقرير المجمع للمؤسسة سيحتاج واجهة وصلاحية صريحة في مرحلة المركز؛ لا يُستنتج من قراءة كل صفوف القاعدة.

لا تُغلق S1-06 قبل حسم كل مجموعة مفتوحة وإضافة دليل تحقق مناسب. البحث النصي حدد مواقع المراجعة ولا يثبت وحده سلامة كل مسار.
