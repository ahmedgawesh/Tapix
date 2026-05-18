# دليل الاختبار اليدوي — المرتجعات (Phases 0 → 4)

> **النطاق**: التحقق من أن إصلاحات Phase 0 → 4 تعمل كما هو متوقع من واجهة المستخدم.
> **البيئة**: نسخة dev نظيفة (DB جديد، schema v10053).
> **القاعدة الذهبية**: في كل سيناريو، سجِّل قيمة `Σ debit` و `Σ credit` للقيد المُنشأ من شاشة الـ Journal Entries — يجب أن يكونا متساويين دائماً.

---

## السيناريو 1 — Quantity Caps (سد الثغرة الرئيسية)

### الإعداد
- منتج عادي بدون متغيرات، tracking = standard، سعر بيع 100.00، VAT = 15%.
- إنشاء عميل اختبار "Cap Test".

### الخطوات

| # | الإجراء | المتوقع |
|---|---|---|
| 1 | بيع 10 قطعة للعميل (فاتورة `INV-001`) | ✅ تُنشأ بنجاح، `sale_items.quantity = 10`، `qty_returned_linked = 0`، `qty_returned_adjustment = 0` |
| 2 | مرتجع **مرتبط** من `INV-001` بكمية 7 | ✅ ينجح. بعد الـ post: `qty_returned_linked = 7` |
| 3 | محاولة مرتجع **مرتبط** آخر من `INV-001` بكمية 4 | ❌ يجب أن يفشل (لا تتجاوز 10 - 7 = 3) |
| 4 | إنشاء **adjustment return** للعميل بنفس المنتج، كمية = 4 | ❌ يجب أن يفشل بـ `QuantityExceedsHistoryException`: المتاح للإرجاع = 3 |
| 5 | إنشاء **adjustment return** بكمية 3 | ✅ ينجح. `qty_returned_adjustment = 3` |
| 6 | محاولة adjustment آخر بكمية 1 | ❌ يفشل (10 - 7 - 3 = 0) |

### نقاط التحقق المحاسبية
- مجموع المرتجعات (linked + adjustment) ≤ المُباع: `7 + 3 ≤ 10` ✅
- على جدول `sale_items`: `quantity - qty_returned_linked - qty_returned_adjustment = 0`

---

## السيناريو 2 — VAT في Linked Purchase Return (Regression للـ bug التاريخي)

### الإعداد
- مورد "VAT Bug Test"، منتج بـ VAT = 15%.

### الخطوات

| # | الإجراء | المتوقع |
|---|---|---|
| 1 | فاتورة شراء: 100 قطعة × 10.00 = 1000.00 + VAT 150.00 = **Total 1150.00** | يُنشأ قيد: `Dr 1200 Inventory 1000`, `Dr 1300 VAT Receivable 150`, `Cr 2000 AP 1150` |
| 2 | مرتجع مرتبط من هذه الفاتورة: 20 قطعة | الإجمالي المرتجع = 200 + 30 VAT = 230 |
| 3 | افتح قيد المرتجع | يجب أن يحوي **3 سطور**: `Dr 2000 AP 230`, `Cr 1300 VAT Receivable 30`, `Cr 1200 Inventory 200` |

### نقطة التحقق الحرجة 🔴
**قبل Phase 0**: السطر `Cr 1300 VAT Receivable 30` كان **غائباً** → VAT المُدخَلات يتضخم للأبد بـ 30.
**بعد Phase 0**: السطر موجود، رصيد 1300 يعود لـ 120 (= 150 − 30) كما يجب.

---

## السيناريو 3 — Customer Credit Note Ledger (2400)

### الإعداد
- عميل "Credit Note Test"، فاتورة سابقة `INV-CN-001` بقيمة 500.00 مدفوعة نقداً.

### الخطوات

| # | الإجراء | المتوقع |
|---|---|---|
| 1 | مرتجع مرتبط من `INV-CN-001` بقيمة 200.00 ، `refundMethod = credit` | ✅ يُنشأ قيد بدون لمس **1100 AR** |
| 2 | افتح القيد | `Dr 4090 Sales Returns 200`, `Cr 2400 Customer Credit Liability 200` (ضريبة إذا كانت تطبق) |
| 3 | افتح صفحة العميل → تبويب "Credit Notes" | يجب أن يظهر credit note برصيد 200.00 |
| 4 | فاتورة بيع جديدة 300.00 لنفس العميل → اضغط "Apply Credit" | الـ credit يطبَّق: `Dr 2400 200`, `Cr 1100 200` (يخفض AR بدلاً من إنشاء AR سالبة) |
| 5 | افتح Credit Notes مرة أخرى | الرصيد المتبقي = 0 (`used = 200`) |

### نقطة التحقق الحرجة 🔴
**قبل Phase 1**: المرتجع كان يخفض `1100 AR` مباشرة → AR سالبة بدون مرجع، يكسر تقارير الـ Aging.
**بعد Phase 1**: AR يبقى نظيفاً، الـ credit يعيش في حسابه الخاص (2400) كما في QuickBooks/Xero.

---

## السيناريو 4 — Disposition Routing (الـ adjustment returns)

### الإعداد
- منتج tracking = standard، مخزون = 50، تكلفة 10.00.

### الخطوات

| # | الإجراء | Disposition | المتوقع |
|---|---|---|---|
| 1 | adjustment purchase return، 5 قطع | `restock` | الـ 5 ترجع للمخزون: `Cr 1200 Inventory 50` |
| 2 | adjustment purchase return، 3 قطع | `damaged` | لا ترجع للمخزون: `Cr 5800 Inventory Shrinkage 30` |
| 3 | adjustment purchase return، 2 قطعة | `sendBack` | تذهب لـ "في الطريق": `Cr 1290 Returns in Transit 20` |

### نقطة التحقق
- مخزون بعد العمليات الثلاث = 50 + 5 = 55 (الـ 3 damaged و 2 sendBack لم ترجع).
- 5800 Shrinkage يحوي 30.00 (للتقرير).
- 1290 Returns in Transit يحوي 20.00 لحين الإرسال الفعلي للمورد.

---

## السيناريو 5 — Period Close Enforcement

### الإعداد
- في **Settings → Fiscal Periods**: أغلق فترة يناير 2026 (status = closed).

### الخطوات

| # | الإجراء | المتوقع |
|---|---|---|
| 1 | محاولة post مرتجع بـ `effectiveDate = 2026-01-15` | ❌ يفشل بـ `ClosedFiscalPeriodException` |
| 2 | محاولة void مرتجع تم post-ه قبل الإغلاق بتاريخ في يناير | ❌ يفشل بنفس الـ exception |
| 3 | post مرتجع بـ `effectiveDate = 2026-02-01` (بعد الفترة المغلقة) | ✅ ينجح |
| 4 | أعد فتح يناير من Settings | ✅ post/void يعمل مجدداً |

### نقطة التحقق
- لا يوجد أي قيد بتاريخ داخل فترة مغلقة (SOX compliance basics).

---

## السيناريو 6 — Approval Workflow

### الإعداد
- في **Settings → Returns**: ضع `return_approval_threshold_cents = 100000` (1000.00).

### الخطوات

| # | الإجراء | المتوقع |
|---|---|---|
| 1 | adjustment return بقيمة 500.00 | ✅ يُنشأ بحالة `approved` (تحت الحد) و post-able مباشرة |
| 2 | adjustment return بقيمة 1500.00 | ✅ يُنشأ بحالة `pending_approval`، **لا يُنشأ قيد** بعد |
| 3 | محاولة post-ه بدون موافقة | ❌ يفشل |
| 4 | تسجيل دخول كـ manager → اضغط "Approve" | حالته → `approved`، يصبح post-able |
| 5 | adjustment return **بدون فاتورة أصلية** بقيمة 100.00 | ✅ يُنشأ بحالة `pending_approval` بصرف النظر عن المبلغ |

### نقطة التحقق
- `approval_status`, `approved_by`, `approved_at` تُملأ على الـ header.
- audit columns (`posted_by`, `posted_at`) تُسجَّل عند الـ post.

---

## السيناريو 7 — Idempotency Keys

### الإعداد
- شاشة adjustment return، فورم مملوء بالكامل.

### الخطوات

| # | الإجراء | المتوقع |
|---|---|---|
| 1 | اضغط زر "Submit" مرتين بسرعة (double-tap) | ✅ المرتجع يُنشأ **مرة واحدة فقط**. المرة الثانية تُرفض بصمت (نفس الـ `idempotency_key`) |
| 2 | افتح الـ DB → جدول `sale_return_adjustments` | صف واحد فقط بهذا الـ key |
| 3 | لا يوجد قيدان مزدوجان في `journal_entries` للمرتجع | ✅ |

### نقطة التحقق
- العمود `idempotency_key TEXT UNIQUE` على الـ 4 جداول returns.
- أي retry من الـ UI / network آمن.

---

## السيناريو 8 (إضافي) — E-Invoice Dispatch (Phase 4)

### الإعداد
- في `app_settings`:
  - `einvoice_enabled = true`
  - `einvoice_jurisdiction = KSA_ZATCA_PHASE2`
  - `tax_registration_number = 300000000000003`

### الخطوات

| # | الإجراء | المتوقع |
|---|---|---|
| 1 | إنشاء فاتورة بيع | جدول `einvoice_documents` يحوي صفاً جديداً: `icv = 1`, `previous_hash = NULL`, status = `reported` (offline mode) |
| 2 | فاتورة ثانية | `icv = 2`, `previous_hash = document_hash` الخاص بالفاتورة الأولى |
| 3 | مرتجع مرتبط بالفاتورة الأولى | صف جديد في `einvoice_documents` بـ `source_table = sale_returns`, `document_type = credit_note`, `original_invoice_uuid` يشير للفاتورة الأصلية |
| 4 | تعطيل e-invoice من Settings | الفواتير اللاحقة لا تنتج صفوفاً (silent no-op، المسار المحاسبي لا يتأثر) |

### نقطة التحقق
- ICV chain monotonic ومتسلسل بلا فجوات.
- PIH chain صحيح (كل صف يشير للسابق).
- فشل الـ dispatch لا يكسر post الفاتورة (الصف يظل `rejected` مع `last_error` للـ retry).

---

## قائمة التحقق النهائية ✅

قبل الإطلاق، تأكد من:

- [ ] كل القيود متوازنة: `Σ Dr = Σ Cr` لكل entry.
- [ ] لا يوجد AR / AP سالب بسبب credit notes (الـ 2400 يستوعبها).
- [ ] لا يمكن إرجاع كمية > المُباع/المُورَّد - المُرجَع سابقاً.
- [ ] VAT Receivable / Payable يعود لقيمته الصحيحة بعد المرتجعات.
- [ ] التالف (damaged/scrap) يصل لـ 5800 لا 1200.
- [ ] الفترات المغلقة محصَّنة ضد post/void.
- [ ] المرتجعات > الحد أو بدون فاتورة تطلب موافقة.
- [ ] Double-tap لا يُنشئ قيدين.
- [ ] `flutter test` → 1835/1835 pass.
- [ ] `flutter analyze` → 0 issues.

---

## في حال وجود أي فشل
شارك:
1. اسم السيناريو ورقم الخطوة.
2. القيد المُنشأ (من شاشة Journal Entries).
3. أي exception أو رسالة خطأ في الـ logs.
