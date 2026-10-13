from pathlib import Path
import json
p=Path(__file__).parent;c=json.loads((p/'catalog.json').read_text());m={s['id']:s for s in c['screens']}
for s in c['screens']:
 if s['id'].startswith('O'):
  for b in s['body']:
   if b.get('type')=='card' and b.get('title')=='最近的安排':b['items']=[{'type':'upcomingRow','title':a,'date':d,'amount':v,'to':'P01'} for a,d,v in [('合租房租 · 应收分摊','2026-09-08 · 已到期','+¥2,400.00'),('合租房租 · 应收分摊','2026-10-01 · 已到期','+¥2,400.00'),('宽带与通信','2026-10-14','¥129.00'),('云服务订阅','2026-10-20','¥68.00')]]
for b in m['P01']['body']:
 if b.get('type')=='card':
  money=b['items'][0];inflow=money['value'].startswith('+');b.update(type='occurrence',date=money['label'],amount=money['value'],inflow=inflow,to='P04');b.pop('items')
m['N01']['body'][3]={'type':'stats'}
m['S01']['body'][0]={'type':'brand'}
(p/'catalog.json').write_text(json.dumps(c,ensure_ascii=False,indent=2))
r=(p/'render-flow-final.js').read_text()
# Ensure previous in-memory fixes are represented in the saved renderer.
r=r.replace("time.fontName={family:'SF Pro',style:'Medium'}","time.fontName={family:'Noto Sans SC',style:'Medium'}")
needle=" case 'plainField':"
extra=""" case 'upcomingRow': {node=auto(parent,'Upcoming / '+item.title,w,'HORIZONTAL',12);const left=auto(node,'Title and date',w-110,'VERTICAL',5);txt(left,item.title,w-110,'Body','text',16);txt(left,item.date,w-110,'Caption','secondary');txt(node,item.amount,98,'MoneySmall');link(node,item.to,item.title,spec.id);break;}
 case 'occurrence': {node=auto(parent,'Occurrence / '+item.title,w,'VERTICAL',16,20,'card');round(node,22);const inner=w-40,top=auto(node,'Title and amount',inner,'HORIZONTAL',13);icon(top,item.inflow?'house':'calendar-days',28);const left=auto(top,'Title and date',inner-156,'VERTICAL',5);txt(left,item.title,inner-156,'Body','text',17);txt(left,item.date,inner-156,'Caption',item.date.includes('已到期')?'amber':'secondary');const amount=txt(top,item.amount,102,'MoneySmall','text',20);amount.textAlignHorizontal='RIGHT';const bottom=auto(node,'Status and action',inner,'HORIZONTAL',10);txt(bottom,item.inflow?'预计到账，尚未计入可动用资金':'已纳入资金安排',inner-106,'Caption','secondary',12);actionText(bottom,item.inflow?'登记到账':'登记付款',item.to,96,spec.id,'jade','RIGHT');break;}
 case 'stats': {node=auto(parent,'Card / 消费汇总',w,'VERTICAL',20,20,'card');round(node,22);const inner=w-40;txt(node,'这段时间，我的消费',inner,'Body','secondary',16);txt(node,'¥4,677.00',inner,'Money');const metric=auto(node,'Income and refunds',inner,'HORIZONTAL',20);for(const [label,value]of [['真实收入','¥18,500.00'],['已减去退款','¥0.00']]){const col=auto(metric,label,(inner-20)/2,'VERTICAL',6);txt(col,label,(inner-20)/2,'Caption','secondary');txt(col,value,(inner-20)/2,'MoneySmall');}rule(node,inner);txt(node,'60 笔记录 · 2026-09-09 — 2026-10-08',inner,'Caption','secondary');txt(node,'按实际发生日期汇总。排除内部转账、借还本金、投资申赎和分摊收款；房租只计本人承担的比例。',inner,'Caption','secondary');break;}
 case 'brand': {node=auto(parent,'Brand and account entry',w,'VERTICAL',18,20,'card');round(node,22);const top=auto(node,'BrandMark',w-40,'HORIZONTAL',12);const mark=remember(figma.createRectangle());mark.name='Brand mark from native screenshot';mark.resize(43,43);mark.fills=[{type:'IMAGE',imageHash:BRAND_HASH,scaleMode:'FILL'}];top.appendChild(mark);const brand=auto(top,'Name',86,'VERTICAL',1);txt(brand,'余白',86,'Title','text',23);txt(brand,'Y U B A I',86,'Small','secondary',8);const desc=auto(top,'Version',w-207,'VERTICAL',6);txt(desc,'个人资金管理',w-207,'Body','text',17);txt(desc,'1.0.0 · 本地优先',w-207,'Caption','secondary');rule(node,w-40);bodyNode(node,{type:'row',label:'账户与余额核对',value:'›',to:'A04'},w-40,spec);break;}
"""
r=r.replace(needle,extra+needle)
# The native searchable field belongs under the navigation title, above the demo strip.
needle="  const demo=auto(root,'Demo banner'"
r=r.replace(needle,"""  if(spec.nav==='账本'){const search=auto(root,'Native search',430,'HORIZONTAL',0);search.resize(430,48);search.layoutSizingVertical='FIXED';search.paddingLeft=22;search.paddingRight=22;const box=auto(search,'Search field',386,'HORIZONTAL',8,10,'line');round(box,14);icon(box,'search',16);txt(box,'搜索用途、商户、分类或单号',326,'Caption','secondary',13);link(box,'L03','搜索',spec.id);}
"""+needle)
r=r.replace("viewport.resize(430,spec.nav?666:794)","viewport.resize(430,spec.nav==='账本'?618:(spec.nav?666:794))")
r=r.replace("for(const item of spec.body)bodyNode(content,item,386,spec);","for(const item of spec.body){if(spec.nav==='账本'&&item.type==='field'&&item.label?.includes('搜索'))continue;bodyNode(content,item,386,spec);}")
(p/'render-flow-final.js').write_text(r)
print('main-page refinements prepared')
