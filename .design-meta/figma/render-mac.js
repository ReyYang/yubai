function fitInstance(node,w){
 const texts=node.findAllWithCriteria({types:['TEXT']});
 if(node.name.startsWith('Row / ')){const a=node.children[0];a.resize(w-126,a.height);a.textAutoResize='HEIGHT';}
 else if(node.name.startsWith('EntryRow')){const left=node.children[0];left.resize(w-142,left.height);left.layoutSizingVertical='HUG';for(const t of left.findAllWithCriteria({types:['TEXT']})){t.resize(w-142,t.height);t.textAutoResize='HEIGHT';}}
 else if(node.name.startsWith('Field')||node.name.startsWith('Note/'))for(const t of texts){t.resize(w-28,t.height);t.textAutoResize='HEIGHT';}
 else if(node.name.startsWith('Button/'))for(const t of texts){t.resize(w-32,t.height);t.textAutoResize='HEIGHT';}
 else if(node.name.startsWith('Toggle/')){texts[0].resize(w-84,texts[0].height);texts[0].textAutoResize='HEIGHT';}
}
const oldInstance=instance;instance=function(parent,kind,values,w){const n=oldInstance(parent,kind,values,w);fitInstance(n,w);return n;};
const navItems=[['现在','O01','wallet'],['账本','L01','book-open'],['安排','P01','calendar-days'],['洞察','N01','chart-no-axes-combined'],['我的','S01','circle-user-round']];
function mainWindow(root,spec){
 root.fills=[paint('canvas')];root.setExplicitVariableModeForCollection(theme,FOUNDATION.modes.Light);
 const bar=auto(root,'Window titlebar',1240,'HORIZONTAL',12,0,'card');bar.resize(1240,52);bar.layoutSizingVertical='FIXED';bar.paddingLeft=20;bar.paddingRight=20;bar.counterAxisAlignItems='CENTER';
 const traffic=auto(bar,'Window controls',178,'HORIZONTAL',8);for(const color of ['#FF5F57','#FEBC2E','#28C840']){const dot=remember(figma.createEllipse());dot.resize(12,12);dot.fills=[{type:'SOLID',color:{r:parseInt(color.slice(1,3),16)/255,g:parseInt(color.slice(3,5),16)/255,b:parseInt(color.slice(5,7),16)/255}}];traffic.appendChild(dot);}txt(bar,spec.title,680,'Headline');actionText(bar,'导入  ⌘I','I01',120,spec.id);actionText(bar,'记一笔  ⌘N','L06',160,spec.id);
 const split=auto(root,'NavigationSplitView',1240,'HORIZONTAL',0);split.resize(1240,798);split.layoutSizingVertical='FIXED';
 const side=auto(split,'Sidebar',210,'VERTICAL',18,20,'soft');side.resize(210,798);side.layoutSizingVertical='FIXED';side.paddingTop=28;txt(side,'◐  余白',170,'Title');txt(side,'Y U B A I',170,'Small','secondary');
 for(const [label,to,symbol]of navItems){const n=auto(side,'Sidebar / '+label,170,'HORIZONTAL',12,14,label===spec.nav?'card':null);n.resize(170,54);n.layoutSizingVertical='FIXED';n.counterAxisAlignItems='CENTER';round(n,12);icon(n,symbol,22);txt(n,label,95,'Body',label===spec.nav?'jade':'text');link(n,to,label,spec.id);}
 const spacer=auto(side,'Sidebar spacer',170);spacer.resize(170,90);spacer.layoutSizingVertical='FIXED';txt(side,'留白，给真正重要的事',170,'Caption');txt(side,'本地账本 · 由你掌握',170,'Small','secondary');
 const detail=auto(split,'Detail',1030,'VERTICAL',0);detail.resize(1030,798);detail.layoutSizingVertical='FIXED';const demo=auto(detail,'Demo banner',1030,'HORIZONTAL',0,0,'soft');demo.resize(1030,30);demo.layoutSizingVertical='FIXED';demo.paddingLeft=26;demo.counterAxisAlignItems='CENTER';txt(demo,'示例账本 · 不含你的真实数据',950,'Small');
 const viewport=auto(detail,'Scroll viewport',1030);viewport.resize(1030,768);viewport.layoutSizingVertical='FIXED';viewport.clipsContent=true;viewport.overflowDirection='VERTICAL';const content=auto(viewport,'Scrollable content',1030,'VERTICAL',22,26);
 for(let i=0;i<spec.body.length;i++){const b=spec.body[i];if(spec.id==='O01'&&b.type==='chart'){const row=auto(content,'Forecast and upcoming',978,'HORIZONTAL',20);bodyNode(row,b,638,spec);bodyNode(row,spec.body[++i],320,spec);}else bodyNode(content,b,978,spec);}
 return content;
}
for(const item of MAC_SPECS){
 const root=await figma.getNodeByIdAsync(MAC.screens[item.id]);if(root.children.length)throw Error('Mac screen already composed '+item.id);changed.push(root.id);const spec=SPECS.find(s=>s.id===item.source);const base=SPECS.find(s=>s.id===item.base)||spec;
 mainWindow(root,base);
 if(item.modal){
  const tint=remember(figma.createRectangle());tint.name='Modal dim';tint.resize(1240,850);tint.fills=[{type:'SOLID',color:{r:.05,g:.10,b:.08},opacity:.22}];root.appendChild(tint);tint.layoutPositioning='ABSOLUTE';tint.x=0;tint.y=0;
  const sheet=auto(root,'Mac sheet / '+spec.title,620,'VERTICAL',0,0,'canvas');sheet.resize(620,720);sheet.layoutSizingVertical='FIXED';sheet.layoutPositioning='ABSOLUTE';sheet.x=310;sheet.y=65;sheet.cornerRadius=16;sheet.clipsContent=true;
  const head=auto(sheet,'Sheet toolbar',620,'HORIZONTAL',12,18,'card');head.resize(620,64);head.layoutSizingVertical='FIXED';head.counterAxisAlignItems='CENTER';actionText(head,'取消',base.id,70,spec.id);const title=txt(head,spec.title,392,'Headline');title.textAlignHorizontal='CENTER';actionText(head,spec.save?spec.save[0]:'完成',base.id,88,spec.id,'jade','RIGHT');
  const viewport=auto(sheet,'Sheet scroll viewport',620);viewport.resize(620,656);viewport.layoutSizingVertical='FIXED';viewport.clipsContent=true;viewport.overflowDirection='VERTICAL';const content=auto(viewport,'Sheet content',620,'VERTICAL',18,22);for(const b of spec.body)bodyNode(content,b,576,spec);
 }
 screenEvidence.push({id:item.id,nodeId:root.id,source:item.source,sharedFlow:spec.caption,dimensions:[root.width,root.height],imageFills:root.findAll(n=>'fills'in n&&Array.isArray(n.fills)&&n.fills.some(p=>p.type==='IMAGE')).length});
}
for(const e of edges){const n=await figma.getNodeByIdAsync(e.nodeId);const to=SCAFFOLD.screens[e.target];if(!to)continue;let sourceRoot=n;while(sourceRoot.parent&&sourceRoot.parent.type!=='PAGE')sourceRoot=sourceRoot.parent;if(sourceRoot.id===to.frameId)continue;await n.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:to.frameId,navigation:'NAVIGATE',transition:null}]}]);}
return {createdNodeIds:created,mutatedNodeIds:changed,screenEvidence,edgeCount:edges.length};
