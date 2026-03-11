# دليل رفع الموقع على Hostinger
## خطوة بخطوة - بسيط جداً!

> **لمن هذا الدليل؟** لأي شخص ليس مبرمجاً ويريد رفع موقع على Hostinger

---

## 📋 ما ستحتاجه

```
✅ حساب Hostinger (لديك بالفعل)
✅ الملفات الجاهزة (أنا عملتها لك):
   - index.html (الصفحة الرئيسية)
   - privacy-policy-ar.html (سياسة الخصوصية)
   - privacy-policy-en.html (سياسة الخصوصية بالإنجليزي)
   - terms-of-service-ar.html (شروط الخدمة)
   - terms-of-service-en.html (شروط الخدمة بالإنجليزي)
```

---

## 🚀 الطريقة 1: رفع الملفات عبر File Manager (الأسهل)

### الخطوة 1: تسجيل الدخول إلى Hostinger

```
1. اذهب إلى: https://hpanel.hostinger.com
2. أدخل بريدك الإلكتروني وكلمة المرور
3. اضغط "Log In"
```

### الخطوة 2: افتح File Manager

```
1. في لوحة التحكم (hPanel)
2. ابحث عن "Files" أو "الملفات"
3. اضغط على "File Manager" أو "مدير الملفات"
```

### الخطوة 3: اذهب إلى مجلد الموقع

```
1. ستجد مجلدات مثل:
   - public_html  ← هذا المجلد المهم!
   - logs
   - tmp
   
2. اضغط مرتين على "public_html"
   (هذا المجلد حيث تضع ملفات الموقع)
```

### الخطوة 4: احذف الملفات القديمة (إن وجدت)

```
⚠️ إذا كان هناك ملفات قديمة في public_html:

1. حدد كل الملفات (Ctrl+A أو Cmd+A)
2. اضغط "Delete" أو "حذف"
3. أكد الحذف

✅ الآن المجلد فارغ وجاهز
```

### الخطوة 5: ارفع الملفات الجديدة

```
1. اضغط "Upload" أو "رفع" (في الأعلى)

2. اختر الملفات من جهازك:
   
   من مجلد: /home/ahmed/AhmedF/tapix projects/tapix/website/
   ارفع:
   ☐ index.html
   
   من مجلد: /home/ahmed/AhmedF/tapix projects/tapix/legal/
   ارفع:
   ☐ privacy-policy-ar.html
   ☐ privacy-policy-en.html
   ☐ terms-of-service-ar.html
   ☐ terms-of-service-en.html

3. انتظر حتى يكتمل الرفع
   (شريط أخضر سيظهر)

4. اضغط "Close" أو "إغلاق"
```

### الخطوة 6: تنظيم الملفات (اختياري لكن موصى به)

```
لتنظيم أفضل، أنشئ مجلد للصفحات القانونية:

1. في public_html، اضغط "+ New Folder" أو "مجلد جديد"
2. اسم المجلد: legal
3. اضغط "Create"

4. حرك الملفات القانونية إلى مجلد legal:
   - اختر privacy-policy-ar.html
   - اضغط "Move" أو "نقل"
   - اختر مجلد legal
   - كرر لباقي الملفات القانونية

النتيجة:
public_html/
├── index.html
└── legal/
    ├── privacy-policy-ar.html
    ├── privacy-policy-en.html
    ├── terms-of-service-ar.html
    └── terms-of-service-en.html
```

### الخطوة 7: اختبر الموقع

```
1. افتح متصفح جديد

2. اذهب إلى موقعك:
   https://tapixsolutions.com
   (أو أي domain لديك)

3. يجب أن ترى الصفحة الرئيسية الجميلة!

4. جرب الروابط:
   https://tapixsolutions.com/legal/privacy-policy-ar.html
   https://tapixsolutions.com/legal/terms-of-service-ar.html
```

---

## 🔧 الطريقة 2: رفع الملفات عبر FTP (للمتقدمين)

### إذا أردت استخدام برنامج FTP:

#### الخطوة 1: احصل على معلومات FTP

```
في Hostinger hPanel:
1. اذهب إلى "Files" > "FTP Accounts"
2. ستجد:
   - Hostname: ftp.tapixsolutions.com
   - Username: u123456789
   - Password: [كلمة المرور]
   - Port: 21
```

#### الخطوة 2: حمّل برنامج FTP

```
أفضل برنامج مجاني: FileZilla

1. اذهب إلى: https://filezilla-project.org
2. حمّل FileZilla Client (مجاني)
3. ثبته على جهازك
```

#### الخطوة 3: اتصل بالسيرفر

```
في FileZilla:
1. Host: ftp.tapixsolutions.com
2. Username: [اسم المستخدم من Hostinger]
3. Password: [كلمة المرور]
4. Port: 21
5. اضغط "Quickconnect"
```

#### الخطوة 4: ارفع الملفات

```
1. في الجهة اليسرى: ملفات جهازك
2. في الجهة اليمنى: ملفات السيرفر

3. اذهب إلى public_html في الجهة اليمنى

4. اسحب الملفات من اليسار إلى اليمين
   (Drag & Drop)

5. انتظر حتى يكتمل الرفع
```

---

## 📝 تعديل الروابط في الملفات

### بعد الرفع، عدّل الروابط:

#### في index.html:

```html
<!-- ابحث عن هذا السطر: -->
<a href="privacy-policy">الخصوصية</a>

<!-- غيره إلى: -->
<a href="legal/privacy-policy-ar.html">الخصوصية</a>

<!-- وهذا: -->
<a href="privacy-policy">سياسة الخصوصية</a>

<!-- غيره إلى: -->
<a href="legal/privacy-policy-ar.html">سياسة الخصوصية</a>

<!-- وهذا: -->
<a href="terms-of-service">شروط الخدمة</a>

<!-- غيره إلى: -->
<a href="legal/terms-of-service-ar.html">شروط الخدمة</a>
```

**كيف تعدل:**
1. في File Manager، اضغط على index.html
2. اضغط "Edit" أو "تحرير"
3. عدّل الروابط
4. اضغط "Save" أو "حفظ"

---

## 🌐 ربط Domain (إذا لم يكن مربوط)

### إذا كان لديك domain جديد:

```
1. في Hostinger hPanel
2. اذهب إلى "Domains"
3. اضغط "Add Domain" أو "إضافة نطاق"
4. أدخل: tapixsolutions.com
5. اتبع التعليمات
6. انتظر 24-48 ساعة للتفعيل
```

---

## ✅ Checklist النهائي

```
☐ الملفات مرفوعة على public_html
☐ الموقع يفتح على https://tapixsolutions.com
☐ سياسة الخصوصية تعمل
☐ شروط الخدمة تعمل
☐ الروابط في الصفحة الرئيسية تعمل
☐ الموقع يظهر بشكل جميل على الموبايل
```

---

## 🎨 تخصيص الموقع (اختياري)

### تغيير الألوان:

```css
في index.html، ابحث عن:

background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);

غيّر الألوان إلى ما تريد:
- #667eea = أزرق فاتح
- #764ba2 = بنفسجي

جرب ألوان جديدة من:
https://cssgradient.io
```

### تغيير النصوص:

```
ببساطة:
1. افتح index.html في File Manager
2. اضغط Edit
3. غيّر أي نص تريده
4. احفظ
```

### إضافة شعارك:

```
1. ارفع صورة الشعار (logo.png) إلى public_html
2. في index.html، ابحث عن:
   <div class="logo">🛒 تابكس POS</div>
3. غيره إلى:
   <div class="logo"><img src="logo.png" height="40"></div>
```

---

## ❓ الأسئلة الشائعة

### س: كم يستغرق ظهور الموقع؟

```
⏱️ فوري!
- بعد الرفع مباشرة
- إذا لم يظهر، امسح cache المتصفح (Ctrl+F5)
```

### س: الموقع لا يفتح!

```
الحلول:
1. تأكد أن الملفات في public_html (ليس في مجلد فرعي)
2. تأكد أن اسم الملف index.html (بحروف صغيرة)
3. امسح cache المتصفح
4. جرب متصفح آخر
5. انتظر 5 دقائق وحاول مرة أخرى
```

### س: الصفحة تظهر بدون تنسيق!

```
السبب: CSS لم يُحمّل

الحل:
1. تأكد أن الملف index.html كامل
2. افتح الملف في File Manager
3. تأكد أن قسم <style> موجود
4. احفظ مرة أخرى
```

### س: أريد تغيير الموقع لاحقاً

```
✅ سهل جداً!
1. ارجع إلى File Manager
2. اضغط Edit على أي ملف
3. عدّل
4. احفظ
5. التغييرات فورية!
```

---

## 🔒 نصائح الأمان

```
1. لا تشارك معلومات FTP مع أحد
2. استخدم كلمة مرور قوية
3. اعمل نسخة احتياطية من الملفات
4. فعّل SSL (HTTPS) من Hostinger
```

---

## 📞 تحتاج مساعدة؟

```
🌐 دعم Hostinger:
https://www.hostinger.com/support

💬 Chat مباشر:
في hPanel، اضغط على أيقونة الدردشة

📧 راسلني:
أنا هنا لمساعدتك في أي خطوة!
```

---

## 🎉 تهانينا!

```
✅ موقعك الآن على الإنترنت!
✅ الناس يمكنهم زيارته
✅ Google Play و App Store يمكنهم الوصول لسياسة الخصوصية

الخطوة التالية:
→ ارجع لدليل Google Play
→ أكمل رفع التطبيق
```

---

**تم إنشاؤه بواسطة:** Cascade AI  
**التاريخ:** 8 مارس 2026  
**الوقت المتوقع:** 15-30 دقيقة  
**الصعوبة:** سهل جداً ⭐

**حظاً موفقاً! 🚀**
