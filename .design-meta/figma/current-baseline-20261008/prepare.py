from pathlib import Path
import json
p=Path(__file__).parent;old=p.parent
cat=json.loads((old/'catalog.json').read_text())
for s in cat['screens']:
 s['status']='当前实现映射 · 可编辑图层 · 合成数据'
 s['caption']+='；本次按原生源码校准。系统菜单、键盘、认证和模型状态为静态表达。'
by={s['id']:s for s in cat['screens']}
def text(x,style='Body'):return {'type':'text','text':x,'style':style}
def row(label,value='',to=None):return {'type':'row','label':label,'value':value,'to':to}
def card(title,items):return {'type':'card','title':title,'items':items}
def field(label,value):return {'type':'field','label':label,'value':value}
by['O01']['body'][0]['text']='10月8日 星期四'
for s in cat['screens']:
 if s['id'].startswith('O'):
  for i in s['body']:
   if i.get('text')=='10月2日 星期五':i['text']='10月8日 星期四'
  body=s['body'];replaced=[]
  for i in body:
   if i.get('type')=='button' and i.get('label')=='整理账单':replaced.append({'type':'quickActions'})
   elif i.get('type')=='button' and i.get('label')=='购买前想一想':continue
   else:replaced.append(i)
  s['body']=replaced
by['L01']['body']=[i for i in by['L01']['body'] if i.get('type')!='entry' and i.get('label') not in ['批量选择','更多 · 回收站 / 规则'] and not i.get('text','').endswith('笔记录')]
by['L01']['body']+=[text('74 笔记录','Caption')]+[{'type':'entry','title':a,'subtitle':b,'amount':c,'date':d,'to':'L05'} for a,b,c,d in [('工作日午餐','餐饮 · 工资卡','−¥28.00','10月8日'),('咖啡与阅读','餐饮 · 微信零钱','−¥22.00','10月8日'),('地铁出行','交通 · 微信零钱','−¥6.00','10月6日'),('周末采购','日用购物 · 工资卡','−¥186.50','10月6日'),('订阅工具','学习工作 · 微信零钱','−¥138.00','10月5日'),('电影之夜','娱乐旅行 · 微信零钱','−¥78.00','10月5日')]]
by['P01']['body'].insert(1,text('安排跟随日期和实际发生的收支，不按月清零。','Caption'))
by['P01']['body']=by['P01']['body'][:3]+[card(title,[{'type':'money','label':date,'value':value},text('预计到账，尚未计入可动用资金' if inflow else '已纳入资金安排','Caption'),{'type':'button','label':'登记到账' if inflow else '登记付款','to':'P04','style':'Secondary'}]) for title,date,value,inflow in [('合租房租 · 应收分摊','2026-09-08 · 已到期','+¥2,400.00',True),('合租房租 · 应收分摊','2026-10-01 · 已到期','+¥2,400.00',True),('宽带与通信','2026-10-14','−¥129.00',False),('云服务订阅','2026-10-20','−¥68.00',False),('信用卡还款','2026-10-23','−¥2,386.00',False),('工资到账','2026-10-28','+¥18,500.00',True),('合租房租 · 季付','2026-11-19','−¥14,400.00',False)]]
by['N01']['body']=[text('看懂花费，也看见自己。','Title'),text('从真实记录中找线索，不为每一笔小快乐打分。','Caption'),by['N01']['body'][1],card('这段时间，我的消费',[{'type':'money','label':'','value':'¥4,677.00'},row('真实收入','¥18,500.00'),row('已减去退款','¥0.00'),text('60 笔记录 · 2026-09-09 — 2026-10-08','Caption'),text('按实际发生日期汇总。排除内部转账、借还本金、投资申赎和分摊收款；房租只计本人承担的比例。','Caption')]),{'type':'chart','kind':'categories'},{'type':'chart','kind':'spending'},card('值得看一眼的线索',[text('餐饮是这段时间最大的消费去向，共 ¥1,492.00。它是否符合你最近的重心？'),text('比前一段同样长的时间多 ¥3,405.00。先确认两个区间的账单都完整，再判断变化。'),text('你有 2 项持续付款约定。可以在安排中核对仍然需要的服务。'),text('这些线索来自本地计算，不是 AI 推断，也不代表必须削减消费。','Caption')]),{'type':'quickAdvice'}]
by['N03']['title']='消费分类区 · 同页滚动'
by['N03']['body']=[{'type':'chart','kind':'categories'}]
by['N03']['caption']='洞察页内“钱花在了哪里”的滚动阅读状态。当前应用没有独立可点击的分类明细页；该能力留待改版讨论，未擅自补上。'
by['S01']['body']=[card('余白 · 个人资金管理',[text('1.0.0 · 本地优先','Caption'),row('账户与余额核对','›','A04')]),text('资金偏好','Caption'),card('',[row('从今天向前看','90 天','X07'),{'type':'plainField','value':'5000'},{'type':'plainField','value':'40'},{'type':'plainField','value':'为长期有用和真正喜欢的事物花钱'},{'type':'button','label':'保存资金偏好','to':'X06','style':'Secondary'},text('日常生活预留用于未逐项列出的零碎开销。不要把同一笔固定付款既列为安排又放进日常预留。调整不会改动真实账单。','Caption')]),text('整理与保护','Caption'),card('',[row('收支分类','›','S03'),row('自动分类规则','›','S05'),row('备份、恢复与导出','›','S07'),row('导入批次与本地恢复','›','S12'),{'type':'toggle','label':'使用设备解锁保护账本','on':False,'to':'S15'},text('使用设备现有的 Face ID、Touch ID 或密码。原始账单和本地账本不会上传。请另存一份加密备份，防止设备丢失。','Caption')]),text('界面与本机智能','Caption'),card('',[row('外观','跟随系统','S17'),{'type':'toggle','label':'允许使用设备端 AI','on':True,'to':'S17'},text('此设备不支持 Apple Intelligence；资金计算与本地规则正常可用','Caption'),text('本机规则先归类，设备端 AI 可补充未匹配用途并回答购买价值问题；金额与资金性质不交给 AI 修改。当前版本不会连接云端模型。','Caption')]),text('了解余白','Caption'),card('',[row('使用指南与计算口径','›','S18'),row('退出示例账本','›','A01'),text('余白 1.0.0\n把钱理清，把生活留给自己。\n不执行转账，不连接银行，不自动交易。','Caption')])]
by['S01']['caption']='当前设置是同页表单，资金偏好没有被移到二级页。5000和40输入值显示后缺少标签，是现有缺陷，保持现状供讨论。'
(p/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2))
sc=(old/'scaffold.js').read_text().replace("await figma.setCurrentPageAsync(await figma.getNodeByIdAsync('0:1'));","await figma.setCurrentPageAsync(await figma.getNodeByIdAsync(PAGE_ID));").replace("{family:'Noto Sans SC',style:'Regular'},{family:'Noto Sans SC',style:'Bold'}","{family:'SF Pro',style:'Regular'},{family:'SF Pro',style:'Bold'}").replace("family:'Noto Sans SC'","family:'SF Pro'").replace("n.name===flow.title","n.name===flow.title").replace('let bandY=1420','let bandY=180')
(p/'scaffold.js').write_text(sc)
r=(old/'render-flow.js').read_text().replace("await figma.setCurrentPageAsync(await figma.getNodeByIdAsync('0:1'));","await figma.setCurrentPageAsync(await figma.getNodeByIdAsync(PAGE_ID));")
r=r.replace("[{family:'Noto Sans SC',style:'Regular'},{family:'Noto Sans SC',style:'Medium'},{family:'Noto Sans SC',style:'Bold'},{family:'Noto Serif SC',style:'Medium'}]","[{family:'SF Pro',style:'Regular'},{family:'SF Pro',style:'Medium'},{family:'SF Pro',style:'Semibold'},{family:'SF Pro',style:'Bold'},{family:'SF Pro Rounded',style:'Medium'},{family:'SF Pro Rounded',style:'Semibold'},{family:'Noto Serif SC',style:'Medium'}]")
r=r.replace("time.fontName={family:'Noto Sans SC',style:'Medium'}","time.fontName={family:'SF Pro',style:'Medium'}")
r=r.replace("txt(node,item.title,w-40,'Headline');for(const child", "if(item.title)txt(node,item.title,w-40,'Headline');for(const child")
# New cases mirror the native two-column quick actions and plain filled TextFields.
needle=" case 'money':"
extra=""" case 'plainField': node=auto(parent,'Filled TextField / '+item.value,w,'VERTICAL',0);txt(node,item.value,w,'Body');rule(node,w);break;
 case 'quickActions': {node=auto(parent,'Quick actions',w,'HORIZONTAL',14);for(const [label,desc,img,to] of [['整理账单','一次导入，之后轻松补充','download','I01'],['购买前想一想','看清影响，再作自己的决定','sparkles','N04']]){const c=auto(node,'Quick / '+label,(w-14)/2,'VERTICAL',12,20,'card');round(c,22);icon(c,img,24);txt(c,label,(w-94)/2,'Headline','text',17);txt(c,desc,(w-94)/2,'Caption','secondary');link(c,to,label,spec.id);}break;}
 case 'quickAdvice': node=auto(parent,'Purchase advice entry',w,'VERTICAL',8,20,'card');round(node,22);txt(node,'有一笔购买正在犹豫？',w-40,'Headline');txt(node,'把它放进你的真实资金安排里看一看。',w-40,'Caption','secondary');link(node,'N04','购买前咨询',spec.id);break;
"""
r=r.replace(needle,extra+needle)
start=r.index(" case 'chart':{");end=r.index(" case 'progress':",start)
chart=""" case 'chart':{
 node=auto(parent,'Chart / '+item.kind,w,'VERTICAL',16,20,'card');round(node,22);const cw=w-40;const color=spec.variant==='dark'?'#75C7A6':'#1F6657';
 if(item.kind==='categories'){
 txt(node,'钱花在了哪里',cw,'Headline');const values=[1492,1305.5,966,546,325.5,42],names=['餐饮','日用购物','学习工作','娱乐旅行','医疗健康','交通'],colors=['#1F6657','#007AFF','#FF9500','#AF52DE','#30B0C7','#FF2D55'];let angle=-Math.PI/2;
 let plot='<svg xmlns="http://www.w3.org/2000/svg" width="'+cw+'" height="180" viewBox="0 0 '+cw+' 180">';for(let i=0;i<values.length;i++){const next=angle+values[i]/4677*Math.PI*2, a=angle+.022,b=next-.022,cx=cw/2,cy=90,outer=83,inner=60;const pt=(r,t)=>[cx+r*Math.cos(t),cy+r*Math.sin(t)].map(v=>v.toFixed(2)).join(' ');plot+='<path d="M '+pt(outer,a)+' A '+outer+' '+outer+' 0 '+(b-a>Math.PI?1:0)+' 1 '+pt(outer,b)+' L '+pt(inner,b)+' A '+inner+' '+inner+' 0 '+(b-a>Math.PI?1:0)+' 0 '+pt(inner,a)+' Z" fill="'+colors[i]+'"/>';angle=next;}svg(node,plot+'</svg>',cw,180,'Editable category sectors');for(let i=0;i<values.length;i++)bodyNode(node,{type:'row',label:names[i],value:'¥'+values[i].toFixed(2)},cw,spec);
 }else {
 txt(node,item.kind==='funds'?'接下来的余地':'花费的节奏',cw,'Headline');txt(node,item.kind==='funds'?'从今天出发，沿着真实付款日期':'金额单位：元，退款按到账日冲减',cw,'Caption','secondary');const graph=auto(node,'Editable plot',cw,'VERTICAL',0);let plot='<svg xmlns="http://www.w3.org/2000/svg" width="'+cw+'" height="170" viewBox="0 0 '+cw+' 170" fill="none"><path d="M35 15H'+cw+'M35 65H'+cw+'M35 115H'+cw+'M35 165H'+cw+'" stroke="#A7AEA9" stroke-opacity=".25"/>';
 if(item.kind==='funds'){const pts=[],expected=[];for(let d=0;d<=90;d++){const bill=[6,36,66].filter(x=>x<=d).length*129+[12,42,72].filter(x=>x<=d).length*68+(d>=42?14400:0);const reserve=30399.3-bill-d*40;const income=[20,51,81].filter(x=>x<=d).length*18500+4800+[24,54,85].filter(x=>x<=d).length*2400;const x=35+(cw-40)*d/90;pts.push(x.toFixed(1)+','+(165-reserve/80000*150).toFixed(1));expected.push(x.toFixed(1)+','+(165-(reserve+income)/80000*150).toFixed(1));}plot+='<polyline points="'+pts.join(' ')+'" stroke="'+color+'" stroke-width="2.5"/><polyline points="'+expected.join(' ')+'" stroke="'+color+'" stroke-opacity=".4" stroke-width="1.5" stroke-dasharray="5 4"/>';
 }else {const amounts=[28,22,6,186.5,138,78,46.5,156],groups={};for(let i=0;i<58;i++){const day=Math.floor(i/2)+((i%8+1)>2?1:0);groups[day]=(groups[day]||0)+amounts[i%8];}for(const [day,v] of Object.entries(groups)){const h=Number(v)/270*145,x=35+(cw-40)*(29-Number(day))/30;plot+='<rect x="'+x.toFixed(1)+'" y="'+(165-h).toFixed(1)+'" width="6" height="'+h.toFixed(1)+'" rx="3" fill="'+color+'" opacity=".8"/>';}}
 svg(graph,plot+'</svg>',cw,170,'Editable chart vectors');const labels=auto(node,'Chart dates',cw,'HORIZONTAL',0);(item.kind==='funds'?['10月','11月','12月','1月']:['9月13日','9月20日','9月27日','10月4日']).forEach(x=>{const t=txt(labels,x,cw/4,'Small','secondary');t.textAlignHorizontal='CENTER';});if(item.kind==='funds')txt(node,'— 保守余量     ··· 预计收入到账后',cw,'Small','secondary');}
 break;
 }
"""
r=r[:start]+chart+r[end:]
# Replace inaccurate toolbar actions while retaining actual capabilities.
start=r.index("  const space=auto(top,'Leading space'");end=r.index("  const name=auto(root,'Large navigation title'",start)
r=r[:start]+"""  const space=auto(top,'Leading space',spec.nav==='我的'?396:260,'HORIZONTAL',0);space.resize(spec.nav==='我的'?396:260,44);space.layoutSizingVertical='FIXED';
  const actions=spec.nav==='现在'?[['download','I01','导入'],['plus','L06','记一笔']]:spec.nav==='账本'?[['batch','L11','批量'],['ellipsis','L14','更多'],['plus','L06','记一笔']]:spec.nav==='安排'?[['plus','P02','添加']]:spec.nav==='洞察'?[['sparkles','N04','购买前咨询']]:[];
  for(const [img,to,label] of actions){const a=auto(top,'Toolbar / '+label,44,'HORIZONTAL',0);a.resize(44,44);a.layoutSizingVertical='FIXED';a.primaryAxisAlignItems='CENTER';a.counterAxisAlignItems='CENTER';if(img==='batch')txt(a,'批量',44,'Caption','jade');else icon(a,img,22);link(a,to,label,spec.id);}
"""+r[end:]
r=r.replace("txt(demo,'退出',74", "txt(demo,'退出示例',74")
# Float the native-style tab pill in its footer rather than a full rectangular bar.
r=r.replace("const nav=auto(root,'Tab bar',440,'HORIZONTAL',2,0,'card');nav.resize(440,84);", "const footer=auto(root,'Tab area',440,'VERTICAL',0,0);footer.resize(440,84);footer.layoutSizingVertical='FIXED';footer.paddingLeft=20;footer.paddingRight=20;const nav=auto(footer,'Tab bar',400,'HORIZONTAL',2,0,'card');round(nav,26);nav.resize(400,70);")
r=r.replace('nav.paddingLeft=20;nav.paddingRight=20;', 'nav.paddingLeft=1;nav.paddingRight=1;')
r=r.replace("if(target&&SCAFFOLD.screens[target])", "if(target&&SCAFFOLD.screens[target])")
(p/'render-flow.js').write_text(r)
print('prepared',len(cat['screens']),'screens',len(r),'renderer bytes')
