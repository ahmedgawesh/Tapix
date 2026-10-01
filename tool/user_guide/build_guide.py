#!/usr/bin/env python3
"""Rebuild a customer handbook from reviewed, editable content."""
from pathlib import Path
from html import escape
import argparse
import json
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--language", choices=("ar", "en"), default="ar")
lang = parser.parse_args().language
en = lang == "en"
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/user-guide'; OUT.mkdir(exist_ok=True)
sections=json.loads((OUT/f'sections-{lang}.json').read_text())
font='../../assets/fonts/IBMPlexSansArabic-Regular.ttf'
bold='../../assets/fonts/IBMPlexSansArabic-Bold.ttf'
logo='../../assets/logos/logo.png'
css='''@font-face{font-family:Plex;src:url(FONT)}@font-face{font-family:Plex;src:url(BOLD);font-weight:700}
@page{size:A4;margin:0}*{box-sizing:border-box}body{margin:0;background:#e7eef4;color:#193044;font-family:Plex,sans-serif;font-size:12pt;line-height:1.85}.page{width:210mm;min-height:297mm;background:white;padding:17mm 18mm 22mm;position:relative;break-after:page}.page:last-child{break-after:auto}.brand{font-size:10pt;color:#526b7a;display:flex;justify-content:space-between;border-bottom:1px solid #d9e4eb;padding-bottom:4mm;margin-bottom:7mm}h1{font-size:28pt;line-height:1.45;color:#104b70;margin:3mm 0 6mm}h2{font-size:20pt;line-height:1.5;color:#104b70;margin:0 0 4mm}h3{font-size:13pt;color:#137bb1;margin:4mm 0 1mm}p{margin:2mm 0 3mm}ol,ul{margin:2mm 0;padding-right:7mm}li{margin-bottom:2mm}table{width:100%;border-collapse:collapse;font-size:10.5pt;margin:4mm 0}td,th{padding:2mm 3mm;border:1px solid #dce6ed;text-align:right}th{background:#edf6fb}.note{background:#edf7fc;border-right:4px solid #249fdd;padding:3mm 4mm;margin-top:5mm;font-size:11pt}.example{background:#fff8e9;border-right:4px solid #c68c23;padding:3mm 4mm;margin-top:4mm}.footer{position:absolute;bottom:10mm;right:18mm;left:18mm;border-top:1px solid #d9e4eb;padding-top:2mm;display:flex;justify-content:space-between;font-size:9pt;color:#667d8b}.cover{background:#0e3047;color:#effaff;display:flex;flex-direction:column;justify-content:center}.cover h1{color:white;font-size:40pt}.cover .eyebrow{color:#7cd0ff}.cover img{width:55mm;align-self:flex-start;margin-bottom:8mm}.cover .footer{color:#b9d8e9}.cover p{font-size:15pt}.tag{font-size:10pt;color:#1986bf;font-weight:bold}.toc{display:grid;grid-template-columns:1fr 1fr;gap:0 8mm;font-size:9pt;line-height:1.5}.toc a{color:#193044;text-decoration:none;display:flex;justify-content:space-between;border-bottom:1px solid #e4edf2;padding:1mm 0}.path{font-size:10.5pt;color:#5d7280}.flow{display:flex;gap:3mm;margin:5mm 0}.flow span{flex:1;background:#eaf5fb;padding:3mm;text-align:center;border-radius:3mm;font-size:11pt}.small{font-size:10.5pt}@media print{body{background:white}a{color:inherit}}
'''.replace('FONT',font).replace('BOLD',bold)
if en:
 css += "body{line-height:1.65}ol,ul{padding-right:0;padding-left:7mm}td,th{text-align:left}.note,.example{border-right:0;border-left:4px solid #249fdd}.example{border-left-color:#c68c23}.cover h1{font-size:38pt}"
labels = {
 "title": "User handbook" if en else "دليل المستخدم",
 "edition": "Version 1.3.2" if en else "الإصدار 1.3.2",
 "eyebrow": "A practical guide for business owners and teams" if en else "دليل عملي لأصحاب الأعمال وفرق العمل",
 "subtitle": "From your first product to daily sales,<br>branch operations, inventory and accounts" if en else "من تجهيز أول صنف إلى متابعة الفروع<br>والمخزون والحسابات اليومية",
 "scope": "October 2026<br>Local operation and local network connections" if en else "أكتوبر 2026<br>التشغيل المحلي والربط عبر الشبكة المحلية",
 "toc": "Contents" if en else "فهرس الدليل",
 "start": "Start with the task you want to complete" if en else "ابدأ من المهمة التي تريد تنفيذها",
 "toc_help": "Select a section title to jump to it. Available options depend on account permissions, device function and subscription." if en else "اضغط على اسم القسم للانتقال إليه. تختلف الخيارات الظاهرة بحسب صلاحيات حسابك ونوع الجهاز والاشتراك.",
 "notice": "This handbook covers the stated application version. Internet-based branch linking is under development and is not described here as a service available to purchase or use." if en else "يغطي هذا الدليل الوظائف المتاحة في الإصدار المحدد. ربط الفروع عبر الإنترنت قيد التطوير، ولا يُشرح هنا بوصفه خدمة متاحة للشراء أو التشغيل.",
 "section": "Section" if en else "القسم",
}
def footer(page):
 return f'<footer class="footer"><span>TapBix · {labels["title"]} · {labels["edition"]}</span><span>{page}</span></footer>'
pages=[f'<section class="page cover"><img src="{logo}" alt="TapBix"><div class="eyebrow">{labels["eyebrow"]}</div><h1>{labels["title"]}</h1><p>{labels["subtitle"]}</p><p class="small">{labels["edition"]} · {labels["scope"]}</p>{footer(1)}</section>']
toc=''.join(f'<a href="#s{i}"><span>{i:02} · {escape(s["title"])}</span><span>{i+2}</span></a>' for i,s in enumerate(sections,1))
pages.append(f'<section class="page"><div class="brand"><b>TapBix</b><span>{labels["start"]}</span></div><h1>{labels["toc"]}</h1><p class="small">{labels["toc_help"]}</p><div class="toc">{toc}</div><div class="note">{labels["notice"]}</div>{footer(2)}</section>')
for i,s in enumerate(sections,1):
 pages.append(f'<section class="page" id="s{i}"><div class="brand"><b>TapBix</b><span>{escape(s["group"])}</span></div><div class="tag">{labels["section"]} {i:02}</div><h2>{escape(s["title"])}</h2><p class="path">{escape(s.get("path",""))}</p>{s["body"]}{footer(i+2)}</section>')
direction = 'ltr' if en else 'rtl'
target = OUT/f'TapBix-User-Guide-{lang.upper()}-1.3.2.html'
target.write_text(f'<!doctype html><html lang="{lang}" dir="{direction}"><head><meta charset="utf-8"><title>TapBix — {labels["title"]} 1.3.2</title><style>'+css+'</style></head><body>'+''.join(pages)+'</body></html>')
print(f'Generated {len(pages)} designed pages: {target.name}. Print with Chrome using --no-pdf-header-footer.')
