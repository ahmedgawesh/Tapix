#!/usr/bin/env python3
"""Rebuild the Arabic customer handbook from reviewed, editable content."""
from pathlib import Path
from html import escape
import json
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/user-guide'; OUT.mkdir(exist_ok=True)
sections=json.loads((OUT/'sections-ar.json').read_text())
font='../../assets/fonts/IBMPlexSansArabic-Regular.ttf'
bold='../../assets/fonts/IBMPlexSansArabic-Bold.ttf'
logo='../../assets/logos/logo.png'
css='''@font-face{font-family:Plex;src:url(FONT)}@font-face{font-family:Plex;src:url(BOLD);font-weight:700}
@page{size:A4;margin:0}*{box-sizing:border-box}body{margin:0;background:#e7eef4;color:#193044;font-family:Plex,sans-serif;font-size:12pt;line-height:1.85}.page{width:210mm;min-height:297mm;background:white;padding:17mm 18mm 22mm;position:relative;break-after:page}.page:last-child{break-after:auto}.brand{font-size:10pt;color:#526b7a;display:flex;justify-content:space-between;border-bottom:1px solid #d9e4eb;padding-bottom:4mm;margin-bottom:7mm}h1{font-size:28pt;line-height:1.45;color:#104b70;margin:3mm 0 6mm}h2{font-size:20pt;line-height:1.5;color:#104b70;margin:0 0 4mm}h3{font-size:13pt;color:#137bb1;margin:4mm 0 1mm}p{margin:2mm 0 3mm}ol,ul{margin:2mm 0;padding-right:7mm}li{margin-bottom:2mm}table{width:100%;border-collapse:collapse;font-size:10.5pt;margin:4mm 0}td,th{padding:2mm 3mm;border:1px solid #dce6ed;text-align:right}th{background:#edf6fb}.note{background:#edf7fc;border-right:4px solid #249fdd;padding:3mm 4mm;margin-top:5mm;font-size:11pt}.example{background:#fff8e9;border-right:4px solid #c68c23;padding:3mm 4mm;margin-top:4mm}.footer{position:absolute;bottom:10mm;right:18mm;left:18mm;border-top:1px solid #d9e4eb;padding-top:2mm;display:flex;justify-content:space-between;font-size:9pt;color:#667d8b}.cover{background:#0e3047;color:#effaff;display:flex;flex-direction:column;justify-content:center}.cover h1{color:white;font-size:40pt}.cover .eyebrow{color:#7cd0ff}.cover img{width:55mm;align-self:flex-start;margin-bottom:8mm}.cover .footer{color:#b9d8e9}.cover p{font-size:15pt}.tag{font-size:10pt;color:#1986bf;font-weight:bold}.toc{display:grid;grid-template-columns:1fr 1fr;gap:0 8mm;font-size:9pt;line-height:1.5}.toc a{color:#193044;text-decoration:none;display:flex;justify-content:space-between;border-bottom:1px solid #e4edf2;padding:1mm 0}.path{font-size:10.5pt;color:#5d7280}.flow{display:flex;gap:3mm;margin:5mm 0}.flow span{flex:1;background:#eaf5fb;padding:3mm;text-align:center;border-radius:3mm;font-size:11pt}.small{font-size:10.5pt}@media print{body{background:white}a{color:inherit}}
'''.replace('FONT',font).replace('BOLD',bold)
def footer(page):return f'<footer class="footer"><span>TapBix · دليل المستخدم · الإصدار 1.3.2</span><span>{page}</span></footer>'
pages=[f'<section class="page cover"><img src="{logo}" alt="TapBix"><div class="eyebrow">دليل عملي لأصحاب الأعمال وفرق العمل</div><h1>دليل المستخدم</h1><p>من تجهيز أول صنف إلى متابعة الفروع<br>والمخزون والحسابات اليومية</p><p class="small">الإصدار 1.3.2 · أكتوبر 2026<br>التشغيل المحلي والربط عبر الشبكة المحلية</p>{footer(1)}</section>']
toc=''.join(f'<a href="#s{i}"><span>{i:02} · {escape(s["title"])}</span><span>{i+2}</span></a>' for i,s in enumerate(sections,1))
pages.append(f'<section class="page"><div class="brand"><b>TapBix</b><span>ابدأ من المهمة التي تريد تنفيذها</span></div><h1>فهرس الدليل</h1><p class="small">اضغط على اسم القسم للانتقال إليه. تختلف الخيارات الظاهرة بحسب صلاحيات حسابك ونوع الجهاز والاشتراك.</p><div class="toc">{toc}</div><div class="note">يغطي هذا الدليل الوظائف المتاحة في الإصدار المحدد. ربط الفروع عبر الإنترنت قيد التطوير، ولا يُشرح هنا بوصفه خدمة متاحة للشراء أو التشغيل.</div>{footer(2)}</section>')
for i,s in enumerate(sections,1):
 pages.append(f'<section class="page" id="s{i}"><div class="brand"><b>TapBix</b><span>{escape(s["group"])}</span></div><div class="tag">القسم {i:02}</div><h2>{escape(s["title"])}</h2><p class="path">{escape(s.get("path",""))}</p>{s["body"]}{footer(i+2)}</section>')
(OUT/'TapBix-User-Guide-AR-1.3.2.html').write_text('<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><title>TapBix — دليل المستخدم 1.3.2</title><style>'+css+'</style></head><body>'+''.join(pages)+'</body></html>')
print(f'Generated {len(pages)} designed pages. Print with Chrome using --no-pdf-header-footer.')
