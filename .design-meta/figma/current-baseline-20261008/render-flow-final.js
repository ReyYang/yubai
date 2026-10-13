// Inputs: FOUNDATION, SCAFFOLD, FLOW, SPECS. No complete-UI raster is used.
await figma.setCurrentPageAsync(await figma.getNodeByIdAsync(PAGE_ID));
await Promise.all([{family:'Noto Sans SC',style:'Regular'},{family:'Noto Sans SC',style:'Medium'},{family:'Noto Sans SC',style:'Bold'},{family:'SF Pro',style:'Regular'},{family:'Noto Sans SC',style:'Medium'},{family:'SF Pro',style:'Semibold'},{family:'SF Pro',style:'Bold'},{family:'SF Pro Rounded',style:'Medium'},{family:'SF Pro Rounded',style:'Semibold'},{family:'Noto Serif SC',style:'Medium'}].map(f=>figma.loadFontAsync(f)));
const created=[],changed=[],edges=[],screenEvidence=[];
const remember=n=>{created.push(n.id);return n;};
const variables=Object.fromEntries(await Promise.all(Object.entries(FOUNDATION.variables).map(async([k,id])=>[k,await figma.variables.getVariableByIdAsync(id)])));
const components=Object.fromEntries(await Promise.all(Object.entries(FOUNDATION.components).map(async([k,v])=>[k,await figma.getNodeByIdAsync(v.id)])));
const actualFonts=new Map();for(const c of Object.values(components)){for(const t of c.findAllWithCriteria({types:['TEXT']})){for(const s of t.getStyledTextSegments(['fontName']))actualFonts.set(JSON.stringify(s.fontName),s.fontName);}}await Promise.all([...actualFonts.values()].map(f=>figma.loadFontAsync(f)));
const icons=Object.fromEntries(await Promise.all(Object.entries(FOUNDATION.icons).map(async([k,id])=>[k,await figma.getNodeByIdAsync(id)])));
const styles=Object.fromEntries(await Promise.all(Object.entries(FOUNDATION.styles).map(async([k,id])=>[k,await figma.getStyleByIdAsync(id)])));
const theme=await figma.variables.getVariableCollectionByIdAsync(FOUNDATION.collections.theme);
function paint(key){return figma.variables.setBoundVariableForPaint({type:'SOLID',color:{r:0,g:0,b:0}},'color',variables['color/'+key]);}
function round(node,r){for(const p of ['topLeftRadius','topRightRadius','bottomLeftRadius','bottomRightRadius'])node.setBoundVariable(p,variables['radius/'+r]);}
function auto(parent,name,width,dir='VERTICAL',gap=14,padding=0,bg=null){const n=remember(figma.createAutoLayout(dir));n.name=name;n.fills=bg?[paint(bg)]:[];n.resize(width,10);n.layoutSizingHorizontal='FIXED';n.layoutSizingVertical='HUG';n.itemSpacing=gap;if(variables['space/'+gap])n.setBoundVariable('itemSpacing',variables['space/'+gap]);if(padding){for(const p of ['paddingTop','paddingBottom','paddingLeft','paddingRight']){n[p]=padding;if(variables['space/'+padding])n.setBoundVariable(p,variables['space/'+padding]);}}parent.appendChild(n);return n;}
function txt(parent,value,width,style='Body',color='text',size=null){const n=remember(figma.createText());n.name=value.slice(0,30);const fn=styles[style].fontName;n.fontName={family:fn.family,style:fn.style};n.textStyleId=styles[style].id;n.characters=value;n.resize(Math.max(20,width),24);n.textAutoResize='HEIGHT';n.fills=[paint(color)];if(size)n.fontSize=size;parent.appendChild(n);return n;}
function instance(parent,kind,values,width){const c=components[kind],def=FOUNDATION.components[kind];if(!c)throw new Error('Missing component '+kind);const n=remember(c.createInstance());n.name=kind+' / '+(values.label||values.title||'');const props={};for(const [k,v] of Object.entries(values))if(def.props[k])props[def.props[k]]=String(v);const nonText={};for(const [k,v] of Object.entries(props)){const texts=n.findAllWithCriteria({types:['TEXT']}).filter(t=>t.componentPropertyReferences&&t.componentPropertyReferences.characters===k);if(texts.length){for(const t of texts){const f=t.fontName;if(f===figma.mixed)throw Error('Mixed font in instance property '+k);t.fontName={family:f.family,style:f.style};t.characters=String(v);}}else nonText[k]=v;}if(Object.keys(nonText).length)n.setProperties(nonText);parent.appendChild(n);n.resize(width,n.height);if(!kind.startsWith('Button/')&&!kind.startsWith('TabItem/')&&!kind.startsWith('Toggle/')&&kind!=='Row'&&kind!=='EntryRow')n.layoutSizingVertical='HUG';return n;}
function link(n,target,label,screen){if(target&&SCAFFOLD.screens[target])edges.push({nodeId:n.id,target,source:screen,label});}
function icon(parent,name,size=22){const master=icons[name]||icons.wallet;const n=remember(master.createInstance());n.name='Icon / '+name;parent.appendChild(n);n.rescale(size/24);return n;}
function rule(parent,w,color='line'){const n=remember(figma.createRectangle());n.name='Divider';n.resize(w,1);n.fills=[paint(color)];parent.appendChild(n);return n;}
function actionText(parent,label,target,width,screen,color='jade',align='LEFT'){const frame=auto(parent,'Action / '+label,width,'HORIZONTAL',0);frame.resize(width,44);frame.layoutSizingVertical='FIXED';frame.counterAxisAlignItems='CENTER';const t=txt(frame,label,width,'Body',color);t.textAlignHorizontal=align;link(frame,target,label,screen);return frame;}
function svg(parent,value,w,h,name){const n=remember(figma.createNodeFromSvg(value));n.name=name;n.resize(w,h);parent.appendChild(n);return n;}
function bodyNode(parent,item,w,spec){
 let node;const large=spec.variant==='large';
 switch(item.type){
 case 'text':node=txt(parent,item.text,w,item.style||'Body','text',large&&(item.style||'Body')==='Body'?25:null);break;
 case 'field':node=instance(parent,'Field',{label:item.label,value:item.value||'请输入'},w);break;
 case 'row':
  if(large){node=auto(parent,'Large row / '+item.label,w,'VERTICAL',10,16,'card');round(node,14);txt(node,item.label,w-32,'Body','text',25);if(item.value&&item.value!=='›')txt(node,item.value,w-32,'Caption','secondary',19);}
  else node=instance(parent,'Row',{label:item.label,value:item.value||''},w);break;
 case 'button':node=instance(parent,'Button/'+(item.style||'Primary'),{label:item.label},w);node.resize(w,52);if(item.style==='Disabled')node.opacity=.62;break;
 case 'toggle':node=instance(parent,'Toggle/'+(item.on?'On':'Off'),{label:item.label},w);break;
 case 'entry':
  if(large){node=auto(parent,'Large EntryRow / '+item.title,w,'VERTICAL',10,20,'card');round(node,22);txt(node,item.title,w-40,'Body','text',25);txt(node,item.subtitle,w-40,'Caption','secondary',18);txt(node,item.amount,w-40,'MoneySmall','text',28);txt(node,item.date,w-40,'Caption','secondary',17);}
  else node=instance(parent,'EntryRow',{title:item.title,subtitle:item.subtitle,amount:item.amount,date:item.date},w);break;
 case 'note':node=instance(parent,'Note/'+(item.mood||'Info'),{title:item.title,body:item.body},w);break;
 case 'card':node=auto(parent,'Card / '+item.title,w,'VERTICAL',14,20,'card');round(node,22);if(item.title)txt(node,item.title,w-40,'Headline');for(const child of item.items)bodyNode(node,child,w-40,spec);break;
 case 'upcomingRow': {node=auto(parent,'Upcoming / '+item.title,w,'HORIZONTAL',12);const left=auto(node,'Title and date',w-110,'VERTICAL',5);txt(left,item.title,w-110,'Body','text',16);txt(left,item.date,w-110,'Caption','secondary');txt(node,item.amount,98,'MoneySmall');link(node,item.to,item.title,spec.id);break;}
 case 'occurrence': {node=auto(parent,'Occurrence / '+item.title,w,'VERTICAL',16,20,'card');round(node,22);const inner=w-40,top=auto(node,'Title and amount',inner,'HORIZONTAL',13);icon(top,item.inflow?'house':'calendar-days',28);const left=auto(top,'Title and date',inner-156,'VERTICAL',5);txt(left,item.title,inner-156,'Body','text',17);txt(left,item.date,inner-156,'Caption',item.date.includes('已到期')?'amber':'secondary');const amount=txt(top,item.amount,102,'MoneySmall','text',20);amount.textAlignHorizontal='RIGHT';const bottom=auto(node,'Status and action',inner,'HORIZONTAL',10);txt(bottom,item.inflow?'预计到账，尚未计入可动用资金':'已纳入资金安排',inner-106,'Caption','secondary',12);actionText(bottom,item.inflow?'登记到账':'登记付款',item.to,96,spec.id,'jade','RIGHT');break;}
 case 'stats': {node=auto(parent,'Card / 消费汇总',w,'VERTICAL',20,20,'card');round(node,22);const inner=w-40;txt(node,'这段时间，我的消费',inner,'Body','secondary',16);txt(node,'¥4,677.00',inner,'Money');const metric=auto(node,'Income and refunds',inner,'HORIZONTAL',20);for(const [label,value]of [['真实收入','¥18,500.00'],['已减去退款','¥0.00']]){const col=auto(metric,label,(inner-20)/2,'VERTICAL',6);txt(col,label,(inner-20)/2,'Caption','secondary');txt(col,value,(inner-20)/2,'MoneySmall');}rule(node,inner);txt(node,'60 笔记录 · 2026-09-09 — 2026-10-08',inner,'Caption','secondary');txt(node,'按实际发生日期汇总。排除内部转账、借还本金、投资申赎和分摊收款；房租只计本人承担的比例。',inner,'Caption','secondary');break;}
 case 'brand': {node=auto(parent,'Brand and account entry',w,'VERTICAL',18,20,'card');round(node,22);const top=auto(node,'BrandMark',w-40,'HORIZONTAL',12);const mark=remember(figma.createRectangle());mark.name='Brand mark from native screenshot';mark.resize(43,43);mark.fills=[{type:'IMAGE',imageHash:BRAND_HASH,scaleMode:'FILL'}];top.appendChild(mark);const brand=auto(top,'Name',86,'VERTICAL',1);txt(brand,'余白',86,'Title','text',23);txt(brand,'Y U B A I',86,'Small','secondary',8);const desc=auto(top,'Version',w-207,'VERTICAL',6);txt(desc,'个人资金管理',w-207,'Body','text',17);txt(desc,'1.0.0 · 本地优先',w-207,'Caption','secondary');rule(node,w-40);bodyNode(node,{type:'row',label:'账户与余额核对',value:'›',to:'A04'},w-40,spec);break;}
 case 'plainField': node=auto(parent,'Filled TextField / '+item.value,w,'VERTICAL',0);txt(node,item.value,w,'Body');rule(node,w);break;
 case 'quickActions': {node=auto(parent,'Quick actions',w,'HORIZONTAL',14);for(const [label,desc,img,to] of [['整理账单','一次导入，之后轻松补充','download','I01'],['购买前想一想','看清影响，再作自己的决定','sparkles','N04']]){const c=auto(node,'Quick / '+label,(w-14)/2,'VERTICAL',12,20,'card');round(c,22);icon(c,img,24);txt(c,label,(w-94)/2,'Headline','text',17);txt(c,desc,(w-94)/2,'Caption','secondary');link(c,to,label,spec.id);}break;}
 case 'quickAdvice': node=auto(parent,'Purchase advice entry',w,'VERTICAL',8,20,'card');round(node,22);txt(node,'有一笔购买正在犹豫？',w-40,'Headline');txt(node,'把它放进你的真实资金安排里看一看。',w-40,'Caption','secondary');link(node,'N04','购买前咨询',spec.id);break;
 case 'money':node=auto(parent,'AmountLabel / '+item.label,w,'VERTICAL',6);txt(node,item.label,w,'Caption','secondary');txt(node,item.value,w,'Money');break;
 case 'segments':{
  node=auto(parent,'Segmented picker',w,'HORIZONTAL',3,3,'line');round(node,12);const iw=(w-6-3*(item.items.length-1))/item.items.length;
  item.items.forEach((a,i)=>{const pill=auto(node,'Segment / '+a.label,iw,'VERTICAL',0,0,i===item.selected?'card':null);pill.resize(iw,35);pill.layoutSizingVertical='FIXED';pill.primaryAxisAlignItems='CENTER';pill.counterAxisAlignItems='CENTER';round(pill,12);const t=txt(pill,a.label,iw-2,'Small',i===item.selected?'jade':'secondary',item.items.length>4?11:12);t.textAlignHorizontal='CENTER';link(pill,a.to,a.label,spec.id);});break;
 }
 case 'hero':{
  node=auto(parent,'Hero / 保守可动用',w,'VERTICAL',22,26,'deepJade');round(node,26);const inner=w-52;
  const top=auto(node,'Hero title',inner,'HORIZONTAL',10);txt(top,'◐  保守可动用',inner-120,'Body','onBrand',16);const pill=auto(top,'Horizon',110,'HORIZONTAL',0,6);pill.fills=[{type:'SOLID',color:{r:1,g:1,b:1},opacity:.12}];round(pill,14);txt(pill,'未来 90 天',98,'Caption','onBrand');
  txt(node,item.amount,inner,'Money','onBrand',42);txt(node,item.first?'从真实余额开始，逐步加入你的安排。':'已为已知付款、还款和你的目标留出位置。',inner,'Body','onBrand',16);
  const divider=rule(node,inner,'onBrand');divider.opacity=.15;
  const metrics=auto(node,'Hero metrics',inner,'HORIZONTAL',12);const metricsData=[['现金余额',item.first?'¥25,000.00':'¥39,585.30'],['信用待还',item.first?'¥0.00':'¥2,386.00'],['付款与预留',item.first?'¥0.00':'¥25,391.00']];
  for(const [label,value] of metricsData){const col=auto(metrics,label,(inner-24)/3,'VERTICAL',6);const t=txt(col,label,(inner-24)/3,'Small','onBrand',11);t.opacity=.72;txt(col,item.hidden?'••••••':value,(inner-24)/3,'MoneySmall','onBrand',16);}
  actionText(node,'这笔数怎样算出来                 ›',spec.id==='O02'?'O01':'O02',inner,spec.id,'onBrand');break;
 }
 case 'chart':{
 node=auto(parent,'Chart / '+item.kind,w,'VERTICAL',16,20,'card');round(node,22);const cw=w-40;const color=spec.variant==='dark'?'#75C7A6':'#1F6657';
 if(item.kind==='categories'){
 txt(node,'钱花在了哪里',cw,'Headline');const values=[1492,1305.5,966,546,325.5,42],names=['餐饮','日用购物','学习工作','娱乐旅行','医疗健康','交通'],colors=['#1F6657','#007AFF','#FF9500','#AF52DE','#30B0C7','#FF2D55'];let angle=-Math.PI/2;
 let plot='<svg xmlns="http://www.w3.org/2000/svg" width="'+cw+'" height="180" viewBox="0 0 '+cw+' 180">';for(let i=0;i<values.length;i++){const next=angle+values[i]/4677*Math.PI*2, a=angle+.022,b=next-.022,cx=cw/2,cy=90,outer=83,inner=60;const pt=(r,t)=>[cx+r*Math.cos(t),cy+r*Math.sin(t)].map(v=>v.toFixed(2)).join(' ');plot+='<path d="M '+pt(outer,a)+' A '+outer+' '+outer+' 0 '+(b-a>Math.PI?1:0)+' 1 '+pt(outer,b)+' L '+pt(inner,b)+' A '+inner+' '+inner+' 0 '+(b-a>Math.PI?1:0)+' 0 '+pt(inner,a)+' Z" fill="'+colors[i]+'"/>';angle=next;}svg(node,plot+'</svg>',cw,180,'Editable category sectors');for(let i=0;i<values.length;i++)bodyNode(node,{type:'row',label:names[i],value:'¥'+values[i].toFixed(2)},cw,spec);
 }else {
 txt(node,item.kind==='funds'?'接下来的余地':'花费的节奏',cw,'Headline');txt(node,item.kind==='funds'?'从今天出发，沿着真实付款日期':'金额单位：元，退款按到账日冲减',cw,'Caption','secondary');const graph=auto(node,'Editable plot',cw,'VERTICAL',0);let plot='<svg xmlns="http://www.w3.org/2000/svg" width="'+cw+'" height="170" viewBox="0 0 '+cw+' 170" fill="none"><path d="M35 15H'+cw+'M35 65H'+cw+'M35 115H'+cw+'M35 165H'+cw+'" stroke="#A7AEA9" stroke-opacity=".25"/>';
 if(item.kind==='funds'){const pts=[],expected=[];for(let d=0;d<=90;d++){const bill=[6,36,66].filter(x=>x<=d).length*129+[12,42,72].filter(x=>x<=d).length*68+(d>=42?14300:0);const reserve=30399.3-bill-d*40;const income=[20,51,81].filter(x=>x<=d).length*18500+4800+[24,54,85].filter(x=>x<=d).length*2400;const x=35+(cw-40)*d/90;pts.push(x.toFixed(1)+','+(165-reserve/80000*150).toFixed(1));expected.push(x.toFixed(1)+','+(165-(reserve+income)/80000*150).toFixed(1));}plot+='<polyline points="'+pts.join(' ')+'" stroke="'+color+'" stroke-width="2.5"/><polyline points="'+expected.join(' ')+'" stroke="'+color+'" stroke-opacity=".4" stroke-width="1.5" stroke-dasharray="5 4"/>';
 }else {const amounts=[28,22,6,186.5,138,78,46.5,156],groups={};for(let i=0;i<58;i++){const day=Math.floor(i/2)+((i%8+1)>2?1:0);groups[day]=(groups[day]||0)+amounts[i%8];}for(const [day,v] of Object.entries(groups)){const h=Number(v)/270*145,x=35+(cw-40)*(29-Number(day))/30;plot+='<rect x="'+x.toFixed(1)+'" y="'+(165-h).toFixed(1)+'" width="6" height="'+h.toFixed(1)+'" rx="3" fill="'+color+'" opacity=".8"/>';}}
 svg(graph,plot+'</svg>',cw,170,'Editable chart vectors');const labels=auto(node,'Chart dates',cw,'HORIZONTAL',0);(item.kind==='funds'?['10月','11月','12月','1月']:['9月13日','9月20日','9月27日','10月4日']).forEach(x=>{const t=txt(labels,x,cw/4,'Small','secondary');t.textAlignHorizontal='CENTER';});if(item.kind==='funds')txt(node,'— 保守余量     ··· 预计收入到账后',cw,'Small','secondary');}
 break;
 }
 case 'progress':{
  node=auto(parent,'Progress',w,'VERTICAL',12);txt(node,item.label,w,'Caption','secondary');const track=remember(figma.createFrame());track.name='Progress track';track.resize(w,7);track.cornerRadius=3.5;track.fills=[paint('line')];node.appendChild(track);const fill=remember(figma.createRectangle());fill.name='Progress value';fill.resize(w*item.value,7);fill.cornerRadius=3.5;fill.fills=[paint('jade')];track.appendChild(fill);break;
 }
 case 'dialog':{
  node=auto(parent,'Dialog / '+item.title,w,'VERTICAL',18,24,'card');round(node,26);node.strokes=[paint('line')];node.strokeWeight=1;txt(node,item.title,w-48,'Headline');txt(node,item.message,w-48,'Body','secondary');for(const a of item.actions)bodyNode(node,{type:'button',...a},w-48,spec);break;
 }
 case 'calendar':{
  node=auto(parent,'DatePicker / Calendar',w,'VERTICAL',12,16,'card');round(node,22);const labels=['日','一','二','三','四','五','六'];const head=auto(node,'Weekdays',w-32,'HORIZONTAL',0);for(const x of labels){const t=txt(head,x,(w-32)/7,'Caption','secondary');t.textAlignHorizontal='CENTER';}
  for(let r=0;r<5;r++){const line=auto(node,'Calendar week '+r,w-32,'HORIZONTAL',0);for(let c=0;c<7;c++){const day=r*7+c-3;const cell=auto(line,'Date '+day,(w-32)/7,'HORIZONTAL',0);cell.resize((w-32)/7,42);cell.layoutSizingVertical='FIXED';cell.counterAxisAlignItems='CENTER';if(day===2){cell.fills=[paint('jade')];round(cell,14);}const t=txt(cell,day>0&&day<32?String(day):' ',(w-32)/7,'Body',day===2?'onBrand':'text');t.textAlignHorizontal='CENTER';}}break;
 }
 case 'keyboard':{
  node=auto(parent,'Keyboard / numeric',w,'VERTICAL',6,6,'line');round(node,14);for(const keys of [['1','2','3'],['4','5','6'],['7','8','9'],['.','0','⌫']]){const line=auto(node,'Key row',w-12,'HORIZONTAL',6);for(const k of keys){const key=auto(line,'Key '+k,(w-24)/3,'HORIZONTAL',0,6,'card');key.resize((w-24)/3,48);key.layoutSizingVertical='FIXED';key.counterAxisAlignItems='CENTER';round(key,12);const t=txt(key,k,(w-60)/3,'Body');t.textAlignHorizontal='CENTER';}}break;
 }
 default:throw new Error('Unknown UI block '+item.type);
 }
 if(item.to&&!(item.type==='button'&&item.style==='Disabled'))link(node,item.to,item.label||item.title||item.type,spec.id);
 return node;
}
for(const spec of SPECS){
 const info=SCAFFOLD.screens[spec.id];const root=await figma.getNodeByIdAsync(info.frameId);if(root.children.length)throw new Error('Screen already composed '+spec.id);
 root.resize(430,932);root.fills=[paint('canvas')];root.layoutMode='VERTICAL';root.itemSpacing=0;root.setExplicitVariableModeForCollection(theme,spec.variant==='dark'?FOUNDATION.modes.Dark:FOUNDATION.modes.Light);changed.push(root.id);
 const status=auto(root,'Status bar',430,'HORIZONTAL',0,0);status.resize(430,44);status.layoutSizingVertical='FIXED';status.paddingLeft=30;status.paddingRight=30;status.counterAxisAlignItems='CENTER';const time=txt(status,'9:41',310,'Body');time.fontName={family:'Noto Sans SC',style:'Medium'};time.fontSize=16;icon(status,'wifi',20);icon(status,'battery-full',25);
 const top=auto(root,'Navigation bar',430,'HORIZONTAL',8,0);top.resize(430,spec.nav?48:60);top.layoutSizingVertical='FIXED';top.paddingLeft=22;top.paddingRight=22;top.counterAxisAlignItems='CENTER';
 if(spec.nav){
  const space=auto(top,'Leading space',spec.nav==='我的'?386:260,'HORIZONTAL',0);space.resize(spec.nav==='我的'?386:260,44);space.layoutSizingVertical='FIXED';
  const actions=spec.nav==='现在'?[['download','I01','导入'],['plus','L06','记一笔']]:spec.nav==='账本'?[['batch','L11','批量'],['ellipsis','L14','更多'],['plus','L06','记一笔']]:spec.nav==='安排'?[['plus','P02','添加']]:spec.nav==='洞察'?[['sparkles','N04','购买前咨询']]:[];
  for(const [img,to,label] of actions){const a=auto(top,'Toolbar / '+label,44,'HORIZONTAL',0);a.resize(44,44);a.layoutSizingVertical='FIXED';a.primaryAxisAlignItems='CENTER';a.counterAxisAlignItems='CENTER';if(img==='batch')txt(a,'批量',44,'Caption','jade');else icon(a,img,22);link(a,to,label,spec.id);}
  const name=auto(root,'Large navigation title',430,'VERTICAL',0,0);name.resize(430,60);name.layoutSizingVertical='FIXED';name.paddingLeft=22;name.paddingRight=22;name.primaryAxisAlignItems='CENTER';txt(name,spec.nav==='我的'?'我的余白':spec.nav==='安排'?'资金安排':spec.nav,386,'Title','text',32);
  if(spec.nav==='账本'){const search=auto(root,'Native search',430,'HORIZONTAL',0);search.resize(430,48);search.layoutSizingVertical='FIXED';search.paddingLeft=22;search.paddingRight=22;const box=auto(search,'Search field',386,'HORIZONTAL',8,10,'line');round(box,14);icon(box,'search',16);txt(box,'搜索用途、商户、分类或单号',326,'Caption','secondary',13);link(box,'L03','搜索',spec.id);}
  const demo=auto(root,'Demo banner',430,'HORIZONTAL',0,0,'soft');demo.resize(430,30);demo.layoutSizingVertical='FIXED';demo.paddingLeft=22;demo.paddingRight=22;demo.counterAxisAlignItems='CENTER';txt(demo,spec.variant==='large'?'示例账本':'示例账本 · 不含你的真实数据',322,'Small');const exit=txt(demo,'退出示例',74,'Caption','jade');exit.textAlignHorizontal='RIGHT';link(exit,'A01','退出示例',spec.id);
 }else if(spec.id==='A01'){
  txt(top,'余白',386,'Body');
 }else{
  actionText(top,spec.back?'‹ 返回':'关闭',spec.back||'O01',58,spec.id);const title=txt(top,spec.title.split(' · ')[0],246,'Body');title.textAlignHorizontal='CENTER';if(spec.save)actionText(top,spec.save[0],spec.save[1],76,spec.id,'jade','RIGHT');else actionText(top,'完成',spec.back||'O01',76,spec.id,'jade','RIGHT');
 }
 const viewport=auto(root,'Scroll viewport',430,'VERTICAL',0);viewport.resize(430,spec.nav==='账本'?618:(spec.nav?666:794));viewport.layoutSizingVertical='FIXED';viewport.clipsContent=true;viewport.overflowDirection='VERTICAL';
 const content=auto(viewport,'Scrollable content',430,'VERTICAL',22,22);content.paddingTop=24;content.paddingBottom=30;
 for(const item of spec.body){if(spec.nav==='账本'&&item.type==='field'&&item.label?.includes('搜索'))continue;bodyNode(content,item,386,spec);}
 if(spec.nav){
  const footer=auto(root,'Tab area',430,'VERTICAL',0,0);footer.resize(430,84);footer.layoutSizingVertical='FIXED';footer.paddingLeft=20;footer.paddingRight=20;const nav=auto(footer,'Tab bar',400,'HORIZONTAL',2,0,'card');round(nav,26);nav.resize(390,70);nav.layoutSizingVertical='FIXED';nav.paddingLeft=1;nav.paddingRight=1;nav.paddingTop=5;nav.counterAxisAlignItems='MIN';
  const items=[['现在','O01','wallet'],['账本','L01','book-open'],['安排','P01','calendar-days'],['洞察','N01','chart-no-axes-combined'],['我的','S01','circle-user-round']];
  for(const [label,target,image] of items){const kind='TabItem/'+(label===spec.nav?'Active':'Idle');const tab=instance(nav,kind,{label},78);tab.resize(78,63);tab.setProperties({[FOUNDATION.components[kind].props.icon]:FOUNDATION.icons[image]});link(tab,target,label,spec.id);}
 }else{const bottom=auto(root,'Home indicator area',430,'HORIZONTAL',0);bottom.resize(430,34);bottom.layoutSizingVertical='FIXED';bottom.primaryAxisAlignItems='CENTER';bottom.counterAxisAlignItems='CENTER';const line=remember(figma.createRectangle());line.name='Home indicator';line.resize(134,5);line.cornerRadius=2.5;line.fills=[paint('text')];bottom.appendChild(line);}
 if(spec.autoNext)await root.setReactionsAsync([{trigger:{type:'AFTER_TIMEOUT',timeout:1.5},actions:[{type:'NODE',destinationId:SCAFFOLD.screens[spec.autoNext].frameId,navigation:'NAVIGATE',transition:null}]}]);
 const board=await figma.getNodeByIdAsync(info.boardId);board.placeholder=false;changed.push(board.id);
 const descendants=root.findAll(()=>true);const counts={};for(const n of descendants)counts[n.type]=(counts[n.type]||0)+1;const images=descendants.filter(n=>'fills'in n&&Array.isArray(n.fills)&&n.fills.some(p=>p.type==='IMAGE')).map(n=>n.id);
 screenEvidence.push({id:spec.id,nodeId:root.id,size:[root.width,root.height],contentHeight:content.height,viewportHeight:viewport.height,counts,imageNodeIds:images,fonts:[...new Set(root.findAllWithCriteria({types:['TEXT']}).flatMap(t=>t.getStyledTextSegments(['fontName']).map(s=>s.fontName.family)))]});

}
for(const edge of edges){if(edge.source===edge.target)continue;const n=await figma.getNodeByIdAsync(edge.nodeId);const commonPicker=/^X0[234578]$/.test(edge.source)&&['L06','P03','S02','A02','A08','S17'].includes(edge.target);await n.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[commonPicker?{type:'BACK'}:{type:'NODE',destinationId:SCAFFOLD.screens[edge.target].frameId,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.16},resetScrollPosition:true}]}]);}
const wrap=await figma.getNodeByIdAsync(SCAFFOLD.wrappers[FLOW.key]);wrap.placeholder=false;changed.push(wrap.id);
return {flow:FLOW.key,createdNodeIds:[...new Set(created)],mutatedNodeIds:changed,screenEvidence,edges,screenCount:SPECS.length,edgeCount:edges.length,wrapper:{id:wrap.id,width:wrap.width,height:wrap.height}};

