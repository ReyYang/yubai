// Inputs: FOUNDATION, SCAFFOLD, FLOW, SPECS. No complete-UI raster is used.
await figma.setCurrentPageAsync(await figma.getNodeByIdAsync('0:1'));
await Promise.all([{family:'Noto Sans SC',style:'Regular'},{family:'Noto Sans SC',style:'Medium'},{family:'Noto Sans SC',style:'Bold'},{family:'Noto Serif SC',style:'Medium'}].map(f=>figma.loadFontAsync(f)));
const created=[],changed=[],edges=[],screenEvidence=[];
const remember=n=>{created.push(n.id);return n;};
const variables=Object.fromEntries(await Promise.all(Object.entries(FOUNDATION.variables).map(async([k,id])=>[k,await figma.variables.getVariableByIdAsync(id)])));
const components=Object.fromEntries(await Promise.all(Object.entries(FOUNDATION.components).map(async([k,v])=>[k,await figma.getNodeByIdAsync(v.id)])));
const icons=Object.fromEntries(await Promise.all(Object.entries(FOUNDATION.icons).map(async([k,id])=>[k,await figma.getNodeByIdAsync(id)])));
const styles=Object.fromEntries(await Promise.all(Object.entries(FOUNDATION.styles).map(async([k,id])=>[k,await figma.getStyleByIdAsync(id)])));
const theme=await figma.variables.getVariableCollectionByIdAsync(FOUNDATION.collections.theme);
function paint(key){return figma.variables.setBoundVariableForPaint({type:'SOLID',color:{r:0,g:0,b:0}},'color',variables['color/'+key]);}
function round(node,r){for(const p of ['topLeftRadius','topRightRadius','bottomLeftRadius','bottomRightRadius'])node.setBoundVariable(p,variables['radius/'+r]);}
function auto(parent,name,width,dir='VERTICAL',gap=14,padding=0,bg=null){const n=remember(figma.createAutoLayout(dir));n.name=name;n.fills=bg?[paint(bg)]:[];n.resize(width,10);n.layoutSizingHorizontal='FIXED';n.layoutSizingVertical='HUG';n.itemSpacing=gap;if(variables['space/'+gap])n.setBoundVariable('itemSpacing',variables['space/'+gap]);if(padding){for(const p of ['paddingTop','paddingBottom','paddingLeft','paddingRight']){n[p]=padding;if(variables['space/'+padding])n.setBoundVariable(p,variables['space/'+padding]);}}parent.appendChild(n);return n;}
function txt(parent,value,width,style='Body',color='text',size=null){const n=remember(figma.createText());n.name=value.slice(0,30);n.fontName=styles[style].fontName;n.textStyleId=styles[style].id;n.characters=value;n.resize(Math.max(20,width),24);n.textAutoResize='HEIGHT';n.fills=[paint(color)];if(size)n.fontSize=size;parent.appendChild(n);return n;}
function instance(parent,kind,values,width){const c=components[kind],def=FOUNDATION.components[kind];if(!c)throw new Error('Missing component '+kind);const n=remember(c.createInstance());n.name=kind+' / '+(values.label||values.title||'');const props={};for(const [k,v] of Object.entries(values))if(def.props[k])props[def.props[k]]=String(v);n.setProperties(props);parent.appendChild(n);n.resize(width,n.height);if(!kind.startsWith('Button/')&&!kind.startsWith('TabItem/')&&!kind.startsWith('Toggle/')&&kind!=='Row'&&kind!=='EntryRow')n.layoutSizingVertical='HUG';return n;}
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
 case 'card':node=auto(parent,'Card / '+item.title,w,'VERTICAL',14,20,'card');round(node,22);txt(node,item.title,w-40,'Headline');for(const child of item.items)bodyNode(node,child,w-40,spec);break;
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
  node=auto(parent,'Chart / '+item.kind,w,'VERTICAL',12,20,'card');round(node,22);const cw=w-40;
  txt(node,item.kind==='funds'?'接下来的余地':'消费的节奏',cw,'Headline');txt(node,item.kind==='funds'?'从今天出发，沿着真实付款日期':'只看属于你的生活支出',cw,'Caption','secondary');
  const graph=auto(node,'Editable plot',cw,'VERTICAL',6);const color=spec.variant==='dark'?'#75C7A6':'#1F6657';
  let plot='<svg xmlns="http://www.w3.org/2000/svg" width="352" height="170" viewBox="0 0 352 170" fill="none"><path d="M0 20H352M0 70H352M0 120H352M0 165H352" stroke="#A7AEA9" stroke-opacity=".25"/>';
  if(item.kind==='funds')plot+='<path d="M4 70L78 76L148 78L178 122L245 128L318 144L348 145" stroke="'+color+'" stroke-width="2.5"/><path d="M4 65L78 70L80 30L148 32L178 55L218 55L221 15L310 17L312 5L348 5" stroke="'+color+'" stroke-opacity=".4" stroke-width="2" stroke-dasharray="6 5"/>';
  else for(let i=0;i<12;i++){const h=[47,90,72,118,60,78,125,54,83,108,59,78][i];plot+='<rect x="'+(i*29+3)+'" y="'+(165-h)+'" width="17" height="'+h+'" rx="5" fill="'+color+'" opacity="'+(i===8?1:.55)+'"/>';}
  svg(graph,plot+'</svg>',cw,170,'Editable chart vectors');const labels=auto(node,'Chart dates',cw,'HORIZONTAL',0);['10月','11月','12月'].forEach(x=>{const t=txt(labels,x,cw/3,'Small','secondary');t.textAlignHorizontal='CENTER';});
  txt(node,item.kind==='funds'?'— 保守余量     ··· 预计收入到账后':'金额单位：元 · 固定合成示例',cw,'Small','secondary');break;
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
 root.fills=[paint('canvas')];root.layoutMode='VERTICAL';root.itemSpacing=0;root.setExplicitVariableModeForCollection(theme,spec.variant==='dark'?FOUNDATION.modes.Dark:FOUNDATION.modes.Light);changed.push(root.id);
 const status=auto(root,'Status bar',440,'HORIZONTAL',0,0);status.resize(440,44);status.layoutSizingVertical='FIXED';status.paddingLeft=30;status.paddingRight=30;status.counterAxisAlignItems='CENTER';const time=txt(status,'9:41',310,'Body');time.fontName={family:'Noto Sans SC',style:'Medium'};time.fontSize=16;icon(status,'wifi',20);icon(status,'battery-full',25);
 const top=auto(root,'Navigation bar',440,'HORIZONTAL',8,0);top.resize(440,spec.nav?48:60);top.layoutSizingVertical='FIXED';top.paddingLeft=22;top.paddingRight=22;top.counterAxisAlignItems='CENTER';
 if(spec.nav){
  const space=auto(top,'Leading space',284,'HORIZONTAL',0);space.resize(284,44);space.layoutSizingVertical='FIXED';const a=auto(top,'Import action',44,'HORIZONTAL',0);a.resize(44,44);a.layoutSizingVertical='FIXED';a.primaryAxisAlignItems='CENTER';a.counterAxisAlignItems='CENTER';icon(a,'download');link(a,'I01','导入账单',spec.id);const b=auto(top,'Add action',44,'HORIZONTAL',0);b.resize(44,44);b.layoutSizingVertical='FIXED';b.primaryAxisAlignItems='CENTER';b.counterAxisAlignItems='CENTER';icon(b,'plus');link(b,spec.nav==='安排'?'P02':'L06','添加',spec.id);
  const name=auto(root,'Large navigation title',440,'VERTICAL',0,0);name.resize(440,60);name.layoutSizingVertical='FIXED';name.paddingLeft=22;name.paddingRight=22;name.primaryAxisAlignItems='CENTER';txt(name,spec.nav==='我的'?'我的余白':spec.nav==='安排'?'资金安排':spec.nav,396,'Title','text',32);
  const demo=auto(root,'Demo banner',440,'HORIZONTAL',0,0,'soft');demo.resize(440,30);demo.layoutSizingVertical='FIXED';demo.paddingLeft=22;demo.paddingRight=22;demo.counterAxisAlignItems='CENTER';txt(demo,spec.variant==='large'?'示例账本':'示例账本 · 不含你的真实数据',322,'Small');const exit=txt(demo,'退出',74,'Caption','jade');exit.textAlignHorizontal='RIGHT';link(exit,'A01','退出示例',spec.id);
 }else if(spec.id==='A01'){
  txt(top,'余白',396,'Body');
 }else{
  actionText(top,spec.back?'‹ 返回':'关闭',spec.back||'O01',58,spec.id);const title=txt(top,spec.title.split(' · ')[0],246,'Body');title.textAlignHorizontal='CENTER';if(spec.save)actionText(top,spec.save[0],spec.save[1],76,spec.id,'jade','RIGHT');else actionText(top,'完成',spec.back||'O01',76,spec.id,'jade','RIGHT');
 }
 const viewport=auto(root,'Scroll viewport',440,'VERTICAL',0);viewport.resize(440,spec.nav?690:818);viewport.layoutSizingVertical='FIXED';viewport.clipsContent=true;viewport.overflowDirection='VERTICAL';
 const content=auto(viewport,'Scrollable content',440,'VERTICAL',22,22);content.paddingTop=24;content.paddingBottom=30;
 for(const item of spec.body)bodyNode(content,item,396,spec);
 if(spec.nav){
  const nav=auto(root,'Tab bar',440,'HORIZONTAL',2,0,'card');nav.resize(440,84);nav.layoutSizingVertical='FIXED';nav.paddingLeft=20;nav.paddingRight=20;nav.paddingTop=5;nav.counterAxisAlignItems='MIN';
  const items=[['现在','O01','wallet'],['账本','L01','book-open'],['安排','P01','calendar-days'],['洞察','N01','chart-no-axes-combined'],['我的','S01','circle-user-round']];
  for(const [label,target,image] of items){const kind='TabItem/'+(label===spec.nav?'Active':'Idle');const tab=instance(nav,kind,{label},78);tab.resize(78,63);tab.setProperties({[FOUNDATION.components[kind].props.icon]:FOUNDATION.icons[image]});link(tab,target,label,spec.id);}
 }else{const bottom=auto(root,'Home indicator area',440,'HORIZONTAL',0);bottom.resize(440,34);bottom.layoutSizingVertical='FIXED';bottom.primaryAxisAlignItems='CENTER';bottom.counterAxisAlignItems='CENTER';const line=remember(figma.createRectangle());line.name='Home indicator';line.resize(134,5);line.cornerRadius=2.5;line.fills=[paint('text')];bottom.appendChild(line);}
 if(spec.autoNext)await root.setReactionsAsync([{trigger:{type:'AFTER_TIMEOUT',timeout:1.5},actions:[{type:'NODE',destinationId:SCAFFOLD.screens[spec.autoNext].frameId,navigation:'NAVIGATE',transition:null}]}]);
 const board=await figma.getNodeByIdAsync(info.boardId);board.placeholder=false;changed.push(board.id);
 const descendants=root.findAll(()=>true);const counts={};for(const n of descendants)counts[n.type]=(counts[n.type]||0)+1;const images=descendants.filter(n=>'fills'in n&&Array.isArray(n.fills)&&n.fills.some(p=>p.type==='IMAGE')).map(n=>n.id);
 screenEvidence.push({id:spec.id,nodeId:root.id,size:[root.width,root.height],contentHeight:content.height,viewportHeight:viewport.height,counts,imageNodeIds:images,fonts:[...new Set(root.findAllWithCriteria({types:['TEXT']}).flatMap(t=>t.getStyledTextSegments(['fontName']).map(s=>s.fontName.family)))]});

}
for(const edge of edges){if(edge.source===edge.target)continue;const n=await figma.getNodeByIdAsync(edge.nodeId);const commonPicker=/^X0[234578]$/.test(edge.source)&&['L06','P03','S02','A02','A08','S17'].includes(edge.target);await n.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[commonPicker?{type:'BACK'}:{type:'NODE',destinationId:SCAFFOLD.screens[edge.target].frameId,navigation:'NAVIGATE',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.16},resetScrollPosition:true}]}]);}
const wrap=await figma.getNodeByIdAsync(SCAFFOLD.wrappers[FLOW.key]);wrap.placeholder=false;changed.push(wrap.id);
return {flow:FLOW.key,createdNodeIds:[...new Set(created)],mutatedNodeIds:changed,screenEvidence,edges,screenCount:SPECS.length,edgeCount:edges.length,wrapper:{id:wrap.id,width:wrap.width,height:wrap.height}};
