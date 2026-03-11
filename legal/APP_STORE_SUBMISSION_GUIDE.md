# دليل نشر Tapix على متاجر التطبيقات
## App Store Submission Complete Guide

> **آخر تحديث:** 8 مارس 2026  
> **الحالة:** جاهز للتنفيذ

---

## 📋 نظرة عامة

هذا الدليل الشامل يغطي **جميع** المتطلبات لنشر Tapix على:
- ✅ Apple App Store (iOS/iPadOS)
- ✅ Google Play Store (Android)
- ✅ Microsoft Store (Windows)

---

## 🎯 الملخص التنفيذي

### ما هو جاهز ✅
- [x] Bundle IDs صحيحة (`com.tapix.pos`)
- [x] أذونات الكاميرا مع أوصاف واضحة
- [x] دعم Desktop (fallback للإدخال اليدوي)
- [x] سياسة الخصوصية (EN, AR)
- [x] شروط الخدمة (EN)
- [x] التطبيق يعمل بشكل كامل

### ما ينقص ❌
- [ ] حسابات المطورين
- [ ] الأصول المرئية (أيقونات، لقطات شاشة)
- [ ] وصف التطبيق للمتاجر
- [ ] نظام الاشتراكات/الترخيص
- [ ] الاختبار النهائي

---

## 💰 التكاليف المطلوبة

| المتجر | التكلفة | التجديد | ملاحظات |
|--------|---------|---------|---------|
| **Apple Developer** | $99 | سنوياً | إلزامي للنشر على iOS |
| **Google Play Console** | $25 | مرة واحدة | إلزامي للنشر على Android |
| **Microsoft Partner Center** | $19 | سنوياً | للنشر على Windows Store |
| **المجموع (السنة الأولى)** | **$143** | - | بعدها $118/سنة |

---

## 📱 PART 1: Apple App Store

### 1.1 متطلبات الحساب

#### إنشاء Apple Developer Account
1. **الذهاب إلى:** https://developer.apple.com/programs/enroll/
2. **المطلوب:**
   - Apple ID شخصي
   - بطاقة ائتمان صالحة
   - $99 رسوم سنوية
   - معلومات الهوية (جواز سفر أو بطاقة هوية)

3. **خطوات التسجيل:**
   ```
   1. تسجيل الدخول بـ Apple ID
   2. اختيار نوع الحساب: Individual أو Organization
   3. ملء معلومات الاتصال
   4. الموافقة على اتفاقية المطور
   5. دفع $99
   6. انتظار الموافقة (1-2 يوم عمل)
   ```

#### إعداد App Store Connect
1. **الذهاب إلى:** https://appstoreconnect.apple.com
2. **إنشاء App ID:**
   ```
   - Bundle ID: com.tapix.pos
   - App Name: Tapix POS
   - Primary Language: English
   - SKU: TAPIX-POS-001
   ```

### 1.2 الأصول المرئية المطلوبة

#### App Icon (أيقونة التطبيق)
**المطلوب:**
- **1024x1024 px** - App Store (بدون شفافية، بدون alpha channel)
- يجب أن تكون بصيغة PNG أو JPEG
- لا يجوز أن تحتوي على نص "Beta" أو "New"

**نصائح التصميم:**
```
✅ بسيطة وواضحة
✅ تعمل بأحجام صغيرة
✅ تمثل العلامة التجارية
❌ لا تستخدم صور فوتوغرافية معقدة
❌ لا تقلد أيقونات Apple
```

#### Screenshots (لقطات الشاشة)
**iPhone:**
- **6.7" Display** (iPhone 14 Pro Max, 15 Pro Max):
  - الحجم: 1290 x 2796 pixels
  - العدد المطلوب: 3-10 لقطات
  
- **6.5" Display** (iPhone 11 Pro Max, XS Max):
  - الحجم: 1242 x 2688 pixels
  - العدد المطلوب: 3-10 لقطات

**iPad:**
- **12.9" Display** (iPad Pro):
  - الحجم: 2048 x 2732 pixels
  - العدد المطلوب: 3-10 لقطات

**نصائح لقطات الشاشة:**
```
✅ أظهر الميزات الرئيسية
✅ استخدم بيانات واقعية (ليست Lorem Ipsum)
✅ أضف نصوص توضيحية قصيرة
✅ رتبها حسب الأهمية
✅ استخدم لغة واحدة لكل مجموعة
```

#### ما يجب تصويره:
1. **الشاشة الرئيسية** - Dashboard
2. **شاشة المبيعات** - POS Interface
3. **إدارة المنتجات** - Product List
4. **التقارير** - Reports/Analytics
5. **ماسح الباركود** - Barcode Scanner
6. **الفواتير** - Invoice View

### 1.3 معلومات التطبيق

#### App Information
```yaml
App Name: Tapix POS
Subtitle: Point of Sale & Inventory
Category: 
  Primary: Business
  Secondary: Finance
Age Rating: 4+ (No objectionable content)
```

#### Description (الوصف)
**Short Description (170 characters max):**
```
Complete offline POS system for retail & wholesale. Manage sales, inventory, customers & reports. Works without internet. Multi-language support.
```

**Full Description (4000 characters max):**
```markdown
Transform your business with Tapix POS - the complete offline point of sale solution designed for modern retailers and wholesalers.

🚀 KEY FEATURES:

📊 SALES & POS
• Fast and intuitive checkout interface
• Multiple payment methods (Cash, Card, Credit)
• Invoice printing and sharing
• Sales returns and refunds
• Customer account management

📦 INVENTORY MANAGEMENT
• Product variants (colors, sizes)
• Barcode scanning and generation
• Stock tracking and alerts
• Low stock notifications
• Batch product import

👥 CUSTOMER & SUPPLIER MANAGEMENT
• Customer profiles and purchase history
• Account balances and credit limits
• Supplier management
• Payment tracking

💰 FINANCIAL REPORTS
• Daily sales summary
• Profit & loss reports
• Inventory valuation
• Customer/Supplier statements
• Tax reports

👨‍💼 EMPLOYEE MANAGEMENT
• User roles and permissions
• Employee tracking
• Salary management
• Attendance records

🌍 MULTI-LANGUAGE SUPPORT
• English, Arabic, French
• RTL support for Arabic
• Easy language switching

🔒 OFFLINE-FIRST & SECURE
• Works 100% offline - no internet required
• Your data stays on your device
• Encrypted local database
• Secure user authentication

💡 WHY CHOOSE TAPIX?

✅ No monthly fees for basic features
✅ One-time purchase option available
✅ No data limits
✅ Fast and responsive
✅ Regular updates and improvements
✅ Professional support

Perfect for:
• Retail stores
• Wholesale businesses
• Pharmacies
• Grocery stores
• Fashion boutiques
• Electronics shops
• And any business that needs a reliable POS system

Download Tapix today and take control of your business!
```

#### Keywords (100 characters max)
```
pos,point of sale,inventory,retail,sales,barcode,invoice,business,shop,store
```

#### Support URL
```
https://tapixsolutions.com/support
```

#### Marketing URL (optional)
```
https://tapixsolutions.com
```

#### Privacy Policy URL (إلزامي)
```
https://tapixsolutions.com/privacy-policy
```

### 1.4 App Review Information

#### Contact Information
```
First Name: [اسمك]
Last Name: [اسم العائلة]
Phone: [رقم هاتفك مع كود الدولة]
Email: support@tapixsolutions.com
```

#### Demo Account (للمراجعة)
```
Username: demo@tapix.com
Password: Demo123!
Notes: This is a demo account with sample data for review purposes.
```

#### Notes for Reviewer
```
Tapix is an offline-first POS application. All data is stored locally on the device.

TESTING INSTRUCTIONS:
1. Login with demo account (demo@tapix.com / Demo123!)
2. The app will load with sample data
3. Test sales by adding products to cart
4. Test barcode scanner (use manual entry on simulator)
5. View reports in the Reports section

CAMERA PERMISSION:
- Used only for barcode scanning
- Optional - manual entry available
- On desktop/simulator, shows manual input UI

The app works 100% offline and does not require internet connection.
```

### 1.5 App Privacy

#### Data Collection
**يجب الإجابة على:**

**Does this app collect data from users?**
```
NO - All data is stored locally on device
```

**Third-party SDKs:**
```
None that collect user data
```

### 1.6 Pricing and Availability

#### Price
```
Free with In-App Purchases
OR
Paid App: $299 (one-time)
```

#### In-App Purchases (إذا اخترت نموذج الاشتراك)
```
1. Monthly Subscription
   - Product ID: com.tapix.pos.monthly
   - Price: $9.99/month
   - Type: Auto-renewable subscription

2. Annual Subscription
   - Product ID: com.tapix.pos.annual
   - Price: $99.99/year
   - Type: Auto-renewable subscription

3. Lifetime License
   - Product ID: com.tapix.pos.lifetime
   - Price: $299
   - Type: Non-consumable
```

#### Availability
```
Available in: All countries
```

---

## 🤖 PART 2: Google Play Store

### 2.1 متطلبات الحساب

#### إنشاء Google Play Console Account
1. **الذهاب إلى:** https://play.google.com/console/signup
2. **المطلوب:**
   - حساب Google
   - بطاقة ائتمان
   - $25 رسوم لمرة واحدة
   - معلومات المطور

3. **خطوات التسجيل:**
   ```
   1. تسجيل الدخول بحساب Google
   2. دفع $25 (مرة واحدة فقط)
   3. ملء معلومات المطور
   4. قبول اتفاقية التوزيع
   5. انتظار الموافقة (عادة فوري)
   ```

### 2.2 الأصول المرئية المطلوبة

#### App Icon
```
- 512 x 512 px (PNG, 32-bit)
- بدون شفافية
- بدون حواف مستديرة (Android يضيفها تلقائياً)
```

#### Feature Graphic (إلزامي)
```
- 1024 x 500 px
- JPEG or PNG
- يظهر في أعلى صفحة المتجر
```

**نصيحة:** صمم Feature Graphic جذاب يعرض:
- شعار التطبيق
- اسم التطبيق
- شعار تسويقي قصير
- لقطة شاشة أو mockup

#### Screenshots
**Phone:**
```
- Min: 320 px
- Max: 3840 px
- Recommended: 1080 x 1920 px (Portrait)
- العدد: 2-8 لقطات (يفضل 4-6)
```

**Tablet (7-inch):**
```
- Recommended: 1200 x 1920 px
- العدد: 2-8 لقطات
```

**Tablet (10-inch):**
```
- Recommended: 1600 x 2560 px
- العدد: 2-8 لقطات
```

### 2.3 Store Listing

#### App Details
```
App name: Tapix POS
Short description (80 characters):
"Complete offline POS for retail. Sales, inventory, reports. Works without internet."

Full description (4000 characters):
[نفس الوصف المستخدم في App Store]
```

#### Categorization
```
App Category: Business
Tags: pos, point of sale, retail, inventory, sales
```

#### Contact Details
```
Website: https://tapixsolutions.com
Email: support@tapixsolutions.com
Phone: [رقمك]
Privacy Policy: https://tapixsolutions.com/privacy-policy (إلزامي)
```

### 2.4 Content Rating

**يجب ملء استبيان تصنيف المحتوى:**

**Questions:**
```
Q: Does your app contain violence?
A: No

Q: Does your app contain sexual content?
A: No

Q: Does your app contain profanity?
A: No

Q: Does your app contain controlled substances?
A: No

Q: Does your app allow users to interact?
A: No (offline app)

Q: Does your app share user location?
A: No

Expected Rating: PEGI 3 / ESRB Everyone
```

### 2.5 Pricing & Distribution

#### Pricing
```
Free or Paid: Free (with in-app purchases)
OR
Paid: $299
```

#### Countries
```
Available in: All countries
```

#### Content Guidelines
```
Ads: No
In-app purchases: Yes (if using subscription model)
```

---

## 🪟 PART 3: Microsoft Store (Windows)

### 3.1 متطلبات الحساب

#### Microsoft Partner Center
1. **الذهاب إلى:** https://partner.microsoft.com/dashboard
2. **التكلفة:** $19/سنة (Individual) أو $99/سنة (Company)
3. **المطلوب:**
   - حساب Microsoft
   - معلومات الدفع
   - معلومات الهوية

### 3.2 الأصول المرئية

#### App Icons
```
- 50 x 50 px
- 150 x 150 px
- 300 x 300 px
- PNG with transparency
```

#### Screenshots
```
- Min: 1366 x 768 px
- Max: 3840 x 2160 px
- Recommended: 1920 x 1080 px
- العدد: 1-10 لقطات
```

### 3.3 App Information
```
App Name: Tapix POS
Category: Business > Finance
Age Rating: 3+
Description: [نفس الوصف]
Privacy Policy: https://tapixsolutions.com/privacy-policy
```

---

## 🎨 PART 4: إنشاء الأصول المرئية

### 4.1 تصميم الأيقونة

**خيارات التصميم:**

#### Option 1: استخدام مصمم محترف
```
منصات مقترحة:
- Fiverr: $20-100
- Upwork: $50-200
- 99designs: $299+ (مسابقة تصميم)
```

#### Option 2: استخدام أدوات AI
```
- Midjourney: $10/شهر
- DALL-E: $15 لـ 115 صورة
- Canva Pro: $12.99/شهر (قوالب جاهزة)
```

#### Option 3: DIY مع Figma/Canva
```
مجاني - استخدم قوالب جاهزة
```

### 4.2 أخذ لقطات الشاشة

**الأدوات:**

#### للموبايل:
```bash
# iOS Simulator
xcrun simctl io booted screenshot screenshot.png

# Android Emulator
adb shell screencap -p /sdcard/screenshot.png
adb pull /sdcard/screenshot.png
```

#### للتحسين:
```
استخدم:
- Figma: لإضافة إطارات وأجهزة
- Canva: لإضافة نصوص توضيحية
- Photoshop: للتحرير المتقدم
```

### 4.3 قائمة الأصول الكاملة

**Checklist:**
```
iOS:
[ ] App Icon 1024x1024
[ ] iPhone 6.7" screenshots (3-10)
[ ] iPhone 6.5" screenshots (3-10)
[ ] iPad 12.9" screenshots (3-10)

Android:
[ ] App Icon 512x512
[ ] Feature Graphic 1024x500
[ ] Phone screenshots (2-8)
[ ] 7" Tablet screenshots (2-8)
[ ] 10" Tablet screenshots (2-8)

Windows:
[ ] App Icons (50, 150, 300 px)
[ ] Screenshots 1920x1080 (1-10)
```

---

## 📝 PART 5: نظام الاشتراكات والترخيص

### 5.1 خيارات نموذج الأعمال

#### Option A: In-App Purchase (الأسهل)
```
المميزات:
✅ Apple/Google يديرون كل شيء
✅ مدمج في المتجر
✅ آمن ومضمون

العيوب:
❌ عمولة 15-30%
❌ محدود بقواعد المتاجر
```

#### Option B: License Key System (الأفضل لك)
```
المميزات:
✅ لا عمولات
✅ سيطرة كاملة
✅ يعمل على جميع المنصات

العيوب:
❌ تحتاج backend بسيط
❌ تحتاج إدارة يدوية
```

### 5.2 تطبيق License Key System

**الخطوات:**

#### 1. Backend API بسيط
```javascript
// Node.js + Express مثال
app.post('/api/verify-license', async (req, res) => {
  const { licenseKey, deviceId } = req.body;
  
  // التحقق من قاعدة البيانات
  const license = await db.licenses.findOne({ key: licenseKey });
  
  if (!license) {
    return res.json({ valid: false, message: 'Invalid license' });
  }
  
  if (license.expiryDate < new Date()) {
    return res.json({ valid: false, message: 'License expired' });
  }
  
  if (license.deviceId && license.deviceId !== deviceId) {
    return res.json({ valid: false, message: 'License already activated on another device' });
  }
  
  // تحديث آخر استخدام
  await db.licenses.updateOne(
    { key: licenseKey },
    { $set: { lastUsed: new Date(), deviceId } }
  );
  
  return res.json({ 
    valid: true, 
    expiryDate: license.expiryDate,
    plan: license.plan 
  });
});
```

#### 2. Flutter Integration
```dart
// lib/core/services/license_service.dart
class LicenseService {
  static const String _licenseKeyKey = 'license_key';
  static const String _lastCheckKey = 'last_license_check';
  
  Future<bool> verifyLicense(String licenseKey) async {
    try {
      final deviceId = await _getDeviceId();
      final response = await http.post(
        Uri.parse('https://api.tapixsolutions.com/verify-license'),
        body: {
          'licenseKey': licenseKey,
          'deviceId': deviceId,
        },
      );
      
      final data = json.decode(response.body);
      
      if (data['valid']) {
        await _saveLicenseKey(licenseKey);
        await _saveLastCheck(DateTime.now());
        return true;
      }
      
      return false;
    } catch (e) {
      // إذا فشل الاتصال، تحقق من آخر تحقق
      return await _checkOfflineLicense();
    }
  }
  
  Future<bool> _checkOfflineLicense() async {
    final lastCheck = await _getLastCheck();
    if (lastCheck == null) return false;
    
    // السماح بـ 7 أيام بدون تحقق
    final daysSinceCheck = DateTime.now().difference(lastCheck).inDays;
    return daysSinceCheck < 7;
  }
}
```

#### 3. License Key Generator
```python
# Python script لتوليد license keys
import secrets
import string

def generate_license_key():
    """Generate a license key in format: XXXX-XXXX-XXXX-XXXX"""
    chars = string.ascii_uppercase + string.digits
    parts = []
    for _ in range(4):
        part = ''.join(secrets.choice(chars) for _ in range(4))
        parts.append(part)
    return '-'.join(parts)

# مثال: TAPX-A7B9-C3D5-E1F2
```

---

## ✅ PART 6: Submission Checklist

### Pre-Submission Checklist

#### Technical Requirements
```
[ ] App builds successfully without errors
[ ] All features tested on real devices
[ ] No crashes or critical bugs
[ ] Performance is acceptable
[ ] Memory usage is reasonable
[ ] Battery usage is optimized
[ ] App works offline as advertised
[ ] All permissions have clear descriptions
[ ] Privacy policy is accessible
[ ] Terms of service are accessible
```

#### Content Requirements
```
[ ] App icon designed (all sizes)
[ ] Screenshots taken (all required sizes)
[ ] Feature graphic created (Android)
[ ] App description written (EN, AR if needed)
[ ] Keywords researched and added
[ ] Support email is active
[ ] Website is live
[ ] Privacy policy is hosted
[ ] Terms of service are hosted
```

#### Legal Requirements
```
[ ] Privacy policy complies with GDPR/CCPA
[ ] Terms of service are complete
[ ] Age rating is appropriate
[ ] Content rating questionnaire completed
[ ] All required permissions justified
[ ] No copyright violations
[ ] No trademark violations
```

#### Account Requirements
```
[ ] Apple Developer account active ($99 paid)
[ ] Google Play Console account active ($25 paid)
[ ] Microsoft Partner Center account (if Windows)
[ ] Payment methods configured
[ ] Tax information submitted
[ ] Bank account for payouts (if applicable)
```

---

## 🚀 PART 7: Submission Process

### iOS Submission Steps

```
1. في Xcode:
   - Archive the app
   - Validate the archive
   - Upload to App Store Connect

2. في App Store Connect:
   - Select the uploaded build
   - Fill all required information
   - Add screenshots
   - Set pricing
   - Submit for review

3. Review Process:
   - Wait 1-7 days
   - Respond to any questions
   - Fix any issues if rejected
   - Resubmit if needed

4. After Approval:
   - App goes live automatically or manually
   - Monitor reviews and ratings
   - Respond to user feedback
```

### Android Submission Steps

```
1. في Android Studio:
   - Generate signed AAB (Android App Bundle)
   - Test on multiple devices

2. في Google Play Console:
   - Create new app
   - Upload AAB
   - Fill store listing
   - Add screenshots
   - Complete content rating
   - Set pricing and distribution
   - Submit for review

3. Review Process:
   - Usually 1-3 days
   - May be instant for simple apps
   - Fix any policy violations

4. After Approval:
   - App goes live
   - Can do staged rollout
   - Monitor crash reports
```

---

## 📊 PART 8: Post-Launch

### Monitoring
```
- Check reviews daily
- Monitor crash reports
- Track download numbers
- Analyze user feedback
- Update regularly
```

### Marketing
```
- Share on social media
- Create demo videos
- Write blog posts
- Reach out to tech blogs
- Consider paid ads
```

### Support
```
- Respond to reviews
- Answer support emails
- Create FAQ
- Make tutorial videos
- Build community
```

---

## 📞 الخطوات التالية

### الأولوية 1 (الأسبوع 1):
1. ✅ إنشاء حسابات المطورين
2. ✅ تصميم الأيقونة
3. ✅ أخذ لقطات الشاشة
4. ✅ كتابة الأوصاف

### الأولوية 2 (الأسبوع 2):
1. ✅ رفع Privacy Policy على الموقع
2. ✅ رفع Terms of Service على الموقع
3. ✅ إعداد نظام الترخيص (إذا اخترت هذا الخيار)
4. ✅ الاختبار النهائي

### الأولوية 3 (الأسبوع 3):
1. ✅ رفع على Google Play (الأسرع)
2. ✅ رفع على App Store
3. ✅ رفع على Microsoft Store (اختياري)

---

## 🆘 الدعم والمساعدة

إذا احتجت مساعدة في أي خطوة:
- 📧 Email: support@tapixsolutions.com
- 🌐 Website: https://tapixsolutions.com
- 📱 WhatsApp: [رقمك]

---

**ملاحظة نهائية:** هذا الدليل شامل ومفصل. لا تقلق إذا بدا كثيراً - سنأخذ كل خطوة على حدة! 🚀
