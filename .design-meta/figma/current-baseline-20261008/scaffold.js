await figma.setCurrentPageAsync(await figma.getNodeByIdAsync(PAGE_ID));
await Promise.all([{family:'SF Pro',style:'Regular'},{family:'SF Pro',style:'Bold'}].map(f=>figma.loadFontAsync(f)));
const created=[];const page=figma.currentPage;const wrappers={};const screens={};const rows={};
function auto(parent,name,direction,width,gap){const n=figma.createAutoLayout(direction);created.push(n.id);n.name=name;n.fills=[];n.resize(width,10);n.layoutSizingHorizontal='FIXED';n.layoutSizingVertical='HUG';n.itemSpacing=gap;parent.appendChild(n);return n;}
function txt(parent,chars,size,bold=false){const t=figma.createText();created.push(t.id);t.fontName={family:'SF Pro',style:bold?'Bold':'Regular'};t.fontSize=size;t.lineHeight={unit:'PERCENT',value:150};t.characters=chars;t.textAutoResize='HEIGHT';t.resize(parent.width-80,40);t.fills=[{type:'SOLID',color:{r:.08,g:.16,b:.13}}];parent.appendChild(t);return t;}
let bandY=180;
for(let f=0;f<CATALOG.flows.length;f+=2){
 let bandHeight=0;
 for(let offset=0;offset<2&&f+offset<CATALOG.flows.length;offset++){
  const flow=CATALOG.flows[f+offset];if(page.children.some(n=>n.name===flow.title))throw new Error('Scaffold already exists '+flow.key);
  const wrap=auto(page,flow.title,'VERTICAL',1930,28);wrap.x=200+offset*2090;wrap.y=bandY;wrap.paddingTop=40;wrap.paddingBottom=40;wrap.paddingLeft=40;wrap.paddingRight=40;wrap.cornerRadius=28;wrap.fills=[{type:'SOLID',color:{r:.965,g:.978,b:.968}}];wrap.placeholder=true;wrappers[flow.key]=wrap.id;
  txt(wrap,flow.title,36,true);txt(wrap,flow.summary,20);txt(wrap,'界面与状态 '+flow.screens.length+' 项  ·  '+flow.source,14);
  const rowIds=[];
  for(let j=0;j<flow.screens.length;j+=4){
   const line=auto(wrap,flow.key+' · 流程行 '+(j/4+1),'HORIZONTAL',1850,30);line.counterAxisAlignItems='MIN';rowIds.push(line.id);
   for(const id of flow.screens.slice(j,j+4)){
    const spec=CATALOG.screens.find(s=>s.id===id);const board=auto(line,id+' · '+spec.title,'VERTICAL',440,14);board.placeholder=true;
    const label=txt(board,id+'  /  '+spec.title,18,true);label.resize(440,30);
    const phone=auto(board,id+' · Screen','VERTICAL',440,0);phone.resize(440,956);phone.layoutSizingVertical='FIXED';phone.clipsContent=true;phone.cornerRadius=32;phone.fills=[{type:'SOLID',color:{r:.949,g:.949,b:.969}}];
    const caption=txt(board,spec.caption,13);caption.resize(440,90);const evidence=txt(board,spec.status,11);evidence.resize(440,20);
    screens[id]={boardId:board.id,frameId:phone.id,title:spec.title,flow:flow.key};
   }
  }
  rows[flow.key]=rowIds;bandHeight=Math.max(bandHeight,380+Math.ceil(flow.screens.length/4)*1210);
 }
 bandY+=bandHeight+180;
}
return {createdNodeIds:created,wrappers,screens,rows,flowCount:CATALOG.flows.length,screenCount:CATALOG.screens.length};
