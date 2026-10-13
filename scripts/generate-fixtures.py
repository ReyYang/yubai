#!/usr/bin/env python3
"""Synthetic fixtures only. No customer statement or real financial data."""
from pathlib import Path
from datetime import datetime
from zipfile import ZipFile, ZIP_DEFLATED
from xml.sax.saxutils import escape
root = Path(__file__).resolve().parents[1] / 'Tests/YubaiCoreTests/Fixtures'
root.mkdir(parents=True, exist_ok=True)
(root / 'wechat.csv').write_text('''微信支付账单明细
说明,本文件为人工合成测试资料
----------------------微信支付账单明细列表--------------------
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-09-20 12:30:00,商户消费,午餐店,工作日午餐,支出,28.00,零钱,支付成功,wx001,m001,/
2026-09-20 13:00:00,商户消费,书店,一本书,支出,66.00,银行卡,支付成功,wx002,m002,/
2026-09-20 14:00:00,转账,测试账户,转账,收入,1200.00,零钱,已收钱,wx003,m003,/
2026-09-20 15:00:00,商户消费,商店,未付款商品,支出,50.00,零钱,交易关闭,wx004,m004,/
not-a-date,商户消费,商店,异常行,支出,20.00,零钱,支付成功,wx005,m005,/
''', encoding='utf-8-sig')
alipay = '''支付宝交易记录明细
交易创建时间,交易类型,交易对方,商品说明,收/支,金额,交易状态,交易订单号,备注
2026-09-21 10:00:00,消费,商户,日用采购,支出,"1,234.56",交易成功,ali001,合成资料
2026-09-22 10:00:00,退款,商户,采购退款,收入,234.56,退款成功,ali002,部分退款
'''
(root / 'alipay-gb18030.csv').write_bytes(alipay.encode('gb18030'))
shared = ['日期', '收支', '金额', '名称', '交易单号', '支出', '早餐', 'x001', '收入', '工资', 'x002']
strings = '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' + ''.join('<si><t>' + escape(x) + '</t></si>' for x in shared) + '</sst>'
serial = (datetime(2026, 9, 20) - datetime(1899, 12, 30)).days
def c(ref, value, shared=False): return f'<c r="{ref}"' + (' t="s"' if shared else '') + f'><v>{value}</v></c>'
header = '<row r="1">' + ''.join(c(chr(65+i)+'1', i, True) for i in range(5)) + '</row>'
row2 = '<row r="2">' + c('A2',serial) + c('B2',5,True) + c('C2','32.00') + c('D2',6,True) + c('E2',7,True) + '</row>'
row3 = '<row r="3">' + c('A3',serial+1) + c('B3',8,True) + c('C3','18000.00') + c('D3',9,True) + c('E3',10,True) + '</row>'
sheet = '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>' + header + row2 + row3 + '</sheetData></worksheet>'
with ZipFile(root / 'bank.xlsx', 'w', ZIP_DEFLATED) as z:
    z.writestr('xl/worksheets/sheet1.xml', sheet)
    z.writestr('xl/sharedStrings.xml', strings)
    z.writestr('[Content_Types].xml', '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>')
with ZipFile(root / 'bank-1904.xlsx', 'w', ZIP_DEFLATED) as z:
    z.writestr('xl/worksheets/sheet1.xml', sheet.replace(f'<v>{serial}</v>', f'<v>{serial-1462}</v>').replace(f'<v>{serial+1}</v>', f'<v>{serial+1-1462}</v>'))
    z.writestr('xl/sharedStrings.xml', strings)
    z.writestr('xl/workbook.xml', '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><workbookPr date1904="1"/></workbook>')
    z.writestr('[Content_Types].xml', '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>')
with ZipFile(root / 'wide-invalid.xlsx', 'w', ZIP_DEFLATED) as z:
    z.writestr('xl/worksheets/sheet1.xml', '<worksheet><sheetData><row r="1"><c r="XFD1"><v>1</v></c></row></sheetData></worksheet>')
print('Created synthetic CSV/GB18030/XLSX fixtures.')
