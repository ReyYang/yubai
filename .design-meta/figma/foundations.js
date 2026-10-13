// Source-derived Figma foundations; no application code is changed.
// Collection helper adapted from figma-generate-library/scripts/createVariableCollection.js.
const created = [];
const changed = [];
const remember = n => { created.push(n.id); return n; };
async function collection(name, names) {
  const old = (await figma.variables.getLocalVariableCollectionsAsync()).find(c => c.name === name);
  if (old) return {collection:old, modes:Object.fromEntries(old.modes.map(m=>[m.name,m.modeId]))};
  const c = figma.variables.createVariableCollection(name); c.renameMode(c.modes[0].modeId,names[0]);
  for(const name of names.slice(1)) c.addMode(name);
  return {collection:c,modes:Object.fromEntries(c.modes.map(m=>[m.name,m.modeId]))};
}
const cn = {family:'Noto Sans SC',style:'Regular'};
await Promise.all([
  cn,{family:'Noto Sans SC',style:'Medium'},{family:'Noto Sans SC',style:'Bold'},
  {family:'Noto Serif SC',style:'Medium'}, {family:'SF Pro',style:'Regular'},
  {family:'SF Pro',style:'Semibold'},{family:'SF Pro Rounded',style:'Medium'}
].map(f=>figma.loadFontAsync(f)));
const main = await figma.getNodeByIdAsync('0:1'); main.name='01 · 全动作 UI / UX'; changed.push(main.id);
let page=figma.root.children.find(p=>p.name==='02 · 组件与参考');
if(!page){page=remember(figma.createPage());page.name='02 · 组件与参考';}
await figma.setCurrentPageAsync(page);
const {collection:primitive,modes:pm}=await collection('Yubai / Primitives',['Value']);
const {collection:theme,modes:tm}=await collection('Yubai / Semantic',['Light','Dark']);
const oldVars=await figma.variables.getLocalVariablesAsync();
const vars={};
function rgba(hex){return {r:parseInt(hex.slice(0,2),16)/255,g:parseInt(hex.slice(2,4),16)/255,b:parseInt(hex.slice(4,6),16)/255,a:1};}
function variable(name,c,type,values,scopes,syntax){
  let v=oldVars.find(x=>x.name===name&&x.variableCollectionId===c.id);
  if(!v){v=figma.variables.createVariable(name,c,type);for(const [mode,value] of Object.entries(values))v.setValueForMode(mode,value);v.scopes=scopes;v.setVariableCodeSyntax('iOS',syntax);}
  vars[name]=v;return v;
}
const palette={jade:'1F6657',mint:'75C7A6',white:'FFFFFF',black:'000000',canvas:'F2F2F7',darkCard:'1C1C1E',ink:'121D19',secondary:'68716D',darkSecondary:'A7AEA9',line:'DFE4E1',darkLine:'383C39',amber:'AD661A',darkAmber:'E9AE66',soft:'E7F0EB',darkSoft:'173329',red:'B43F3F',darkRed:'FF9B96'};
const pv={};for(const [name,hex] of Object.entries(palette))pv[name]=variable('primitive/'+name,primitive,'COLOR',{[pm.Value]:rgba(hex)},[],name);
const aliases={canvas:['canvas','black'],card:['white','darkCard'],text:['ink','white'],secondary:['secondary','darkSecondary'],line:['line','darkLine'],jade:['jade','mint'],deepJade:['jade','jade'],onBrand:['white','white'],soft:['soft','darkSoft'],amber:['amber','darkAmber'],danger:['red','darkRed']};
for(const [name,[light,dark]] of Object.entries(aliases))variable('color/'+name,theme,'COLOR',{[tm.Light]:{type:'VARIABLE_ALIAS',id:pv[light].id},[tm.Dark]:{type:'VARIABLE_ALIAS',id:pv[dark].id}},['FRAME_FILL','SHAPE_FILL','TEXT_FILL','STROKE_COLOR'],name==='canvas'?'YubaiTheme.canvas':name==='card'?'YubaiTheme.card':'YubaiTheme.'+name);
for(const n of [6,10,12,14,16,20,22,26,32,44,50])variable('space/'+n,primitive,'FLOAT',{[pm.Value]:n},['GAP'],'CGFloat('+n+')');
for(const n of [12,14,22,26])variable('radius/'+n,primitive,'FLOAT',{[pm.Value]:n},['CORNER_RADIUS'],'CGFloat('+n+')');
function paint(key){return figma.variables.setBoundVariableForPaint({type:'SOLID',color:{r:0,g:0,b:0}},'color',vars['color/'+key]);}
function corners(n,r){for(const p of ['topLeftRadius','topRightRadius','bottomLeftRadius','bottomRightRadius'])n.setBoundVariable(p,vars['radius/'+r]);}
const styles={};const existingStyles=await figma.getLocalTextStylesAsync();
for(const [name,size,weight,family] of [['Body',17,'Regular','Noto Sans SC'],['Headline',20,'Medium','Noto Sans SC'],['Caption',13,'Regular','Noto Sans SC'],['Small',11,'Regular','Noto Sans SC'],['Title',28,'Bold','Noto Sans SC'],['Money',38,'Medium','Noto Sans SC'],['MoneySmall',17,'Medium','Noto Sans SC'],['Welcome',32,'Medium','Noto Serif SC']]){
 let s=existingStyles.find(x=>x.name==='Yubai/'+name);if(!s){s=figma.createTextStyle();s.name='Yubai/'+name;s.fontName={family,style:weight};s.fontSize=size;s.lineHeight={unit:'PERCENT',value:145};}styles[name]=s;
}
function text(parent,name,chars,style='Body',width=340,color='text'){
 const n=remember(figma.createText());n.name=name;n.fontName=styles[style].fontName;n.textStyleId=styles[style].id;n.characters=chars;n.resize(width,24);n.textAutoResize='HEIGHT';n.fills=[paint(color)];parent.appendChild(n);return n;
}
function auto(parent,name,dir='VERTICAL',width=352,gap=10){const n=remember(figma.createAutoLayout(dir));n.name=name;n.fills=[];n.resize(width,10);n.layoutSizingHorizontal='FIXED';n.layoutSizingVertical='HUG';n.itemSpacing=gap;if(vars['space/'+gap])n.setBoundVariable('itemSpacing',vars['space/'+gap]);parent.appendChild(n);return n;}
function prop(c,n,label){const key=c.addComponentProperty(label,'TEXT',n.characters);n.componentPropertyReferences={characters:key};return key;}
let cx=200,cy=120;const components={};
function base(name,w,h,dir='VERTICAL'){
 const full='Yubai/'+name;let old=page.children.find(n=>n.type==='COMPONENT'&&n.name===full);if(old)throw new Error('Foundation already exists; resume from state instead of recreating '+name);
 const n=remember(figma.createComponent());n.name=full;n.description='余白原生界面的可编辑派生组件。源码：Sources/YubaiApp/DesignSystem.swift；中文字体为画布替代字体。';n.resize(w,h);n.layoutMode=dir;n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='FIXED';n.fills=[];n.x=cx;n.y=cy;cy+=h+65;if(cy>1100){cy=120;cx+=460;}return n;
}
for(const type of ['Primary','Secondary','Danger','Disabled']){
 const c=base('Button/'+type,352,52,'HORIZONTAL');c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.primaryAxisAlignItems='CENTER';c.counterAxisAlignItems='CENTER';corners(c,14);c.fills=[paint(type==='Primary'?'deepJade':type==='Disabled'?'line':'soft')];
 const t=text(c,'Label','保存','Body',320,type==='Primary'?'onBrand':type==='Danger'?'danger':type==='Disabled'?'secondary':'jade');t.textAlignHorizontal='CENTER';components['Button/'+type]={id:c.id,props:{label:prop(c,t,'Label')}};
}
{
const c=base('Field',352,70);c.paddingTop=10;c.paddingBottom=10;c.paddingLeft=14;c.paddingRight=14;c.itemSpacing=3;c.fills=[paint('card')];corners(c,12);c.strokes=[paint('line')];c.strokeWeight=1;
const a=text(c,'Label','账户名称','Caption',324,'secondary'),b=text(c,'Value','微信零钱','Body',324);components.Field={id:c.id,props:{label:prop(c,a,'Label'),value:prop(c,b,'Value')}};
}
{
const c=base('Row',352,58,'HORIZONTAL');c.primaryAxisSizingMode='FIXED';c.counterAxisAlignItems='CENTER';c.itemSpacing=12;c.paddingLeft=12;c.paddingRight=12;c.fills=[paint('card')];corners(c,12);
const a=text(c,'Label','账户与余额核对','Body',225),b=text(c,'Value','›','Caption',90,'secondary');b.textAlignHorizontal='RIGHT';components.Row={id:c.id,props:{label:prop(c,a,'Label'),value:prop(c,b,'Value')}};
}
{
const c=base('EntryRow',352,82,'HORIZONTAL');c.primaryAxisSizingMode='FIXED';c.counterAxisAlignItems='CENTER';c.itemSpacing=12;c.paddingLeft=10;c.paddingRight=10;c.fills=[paint('card')];corners(c,12);
const left=auto(c,'Purpose','VERTICAL',210,6),right=auto(c,'Amount & date','VERTICAL',110,6);
const a=text(left,'Title','午餐','Body',210),b=text(left,'Subtitle','餐饮 · 工资卡','Caption',210,'secondary'),d=text(right,'Amount','−¥28.50','MoneySmall',110),e=text(right,'Date','10月2日','Small',110,'secondary');d.textAlignHorizontal='RIGHT';e.textAlignHorizontal='RIGHT';components.EntryRow={id:c.id,props:{title:prop(c,a,'Title'),subtitle:prop(c,b,'Subtitle'),amount:prop(c,d,'Amount'),date:prop(c,e,'Date')}};
}
for(const mood of ['Info','Warning','Success']){
const c=base('Note/'+mood,352,100);c.paddingTop=14;c.paddingBottom=14;c.paddingLeft=14;c.paddingRight=14;c.itemSpacing=5;c.fills=[paint('soft')];corners(c,14);
const a=text(c,'Title',mood==='Warning'?'需要留意':'保留你的选择','Caption',324,mood==='Warning'?'amber':'jade'),b=text(c,'Body','金额始终来自原始账单，可以稍后继续。','Caption',324,'secondary');components['Note/'+mood]={id:c.id,props:{title:prop(c,a,'Title'),body:prop(c,b,'Body')}};
}
for(const active of [false,true]){
const c=base('Toggle/'+(active?'On':'Off'),352,58,'HORIZONTAL');c.counterAxisAlignItems='CENTER';c.primaryAxisSizingMode='FIXED';c.paddingLeft=12;c.paddingRight=12;c.itemSpacing=10;c.fills=[paint('card')];corners(c,12);
const t=text(c,'Label','允许使用设备端 AI','Body',268);const toggle=remember(figma.createFrame());toggle.name='Switch';toggle.resize(50,30);toggle.cornerRadius=15;toggle.fills=[paint(active?'jade':'line')];c.appendChild(toggle);const dot=remember(figma.createEllipse());dot.resize(26,26);dot.x=active?22:2;dot.y=2;dot.fills=[paint('onBrand')];toggle.appendChild(dot);components['Toggle/'+(active?'On':'Off')]={id:c.id,props:{label:prop(c,t,'Label')}};
}
const iconComponents={};
for(const [name,svg] of Object.entries(ICONS)){
const c=base('Icon/'+name,24,24);c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';const node=remember(figma.createNodeFromSvg(svg.replace(/currentColor/g,'#121D19')));node.name=name;node.resize(24,24);c.appendChild(node);for(const v of node.findAllWithCriteria({types:['VECTOR']})){if(Array.isArray(v.strokes)&&v.strokes.length)v.strokes=v.strokes.map(p=>p.type==='SOLID'?paint('text'):p);if(Array.isArray(v.fills)&&v.fills.length)v.fills=v.fills.map(p=>p.type==='SOLID'?paint('text'):p);created.push(v.id);}iconComponents[name]=c.id;
}
for(const active of [false,true]){
const c=base('TabItem/'+(active?'Active':'Idle'),76,63);c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.primaryAxisAlignItems='CENTER';c.counterAxisAlignItems='CENTER';c.itemSpacing=4;c.fills=active?[paint('soft')]:[];corners(c,22);
const ic=await figma.getNodeByIdAsync(iconComponents.wallet);const ins=remember(ic.createInstance());c.appendChild(ins);const iconProp=c.addComponentProperty('Icon','INSTANCE_SWAP',ic.id);ins.componentPropertyReferences={mainComponent:iconProp};const label=text(c,'Label','现在','Small',72,active?'jade':'text');label.textAlignHorizontal='CENTER';components['TabItem/'+(active?'Active':'Idle')]={id:c.id,props:{label:prop(c,label,'Label'),icon:iconProp}};
}
// Responsive component text constraints verified against 440px and 1240px layouts.
for(const [key,val] of Object.entries(components)) {
 const c=await figma.getNodeByIdAsync(val.id);
 if(key==='Row'||key.startsWith('Toggle/')) c.children[0].layoutSizingHorizontal='FILL';
 else if(key==='EntryRow') { c.children[0].layoutSizingHorizontal='FILL'; for(const t of c.children[0].children){t.layoutSizingHorizontal='FILL';t.textAutoResize='HEIGHT';} }
 else if(key==='Field'||key.startsWith('Note/')||key.startsWith('Button/')) for(const t of c.children.filter(n=>n.type==='TEXT')) {t.layoutSizingHorizontal='FILL';t.textAutoResize='HEIGHT';}
}
const all=page.findAll(()=>true);const ids=[...new Set(created.concat(all.map(n=>n.id)))];
return {pageId:page.id,mainPageId:main.id,createdNodeIds:ids,mutatedNodeIds:changed,components,icons:iconComponents,variables:Object.fromEntries(Object.entries(vars).map(([n,v])=>[n,v.id])),collections:{primitive:primitive.id,theme:theme.id},modes:tm,styles:Object.fromEntries(Object.entries(styles).map(([n,s])=>[n,s.id])),counts:{components:page.findAllWithCriteria({types:['COMPONENT']}).length,variables:Object.keys(vars).length,textStyles:Object.keys(styles).length},fontSubstitution:'Noto Sans SC for body and money; Noto Serif SC for welcome; app system fonts unchanged'};
