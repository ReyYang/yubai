import json,sys
from pathlib import Path
p=Path(__file__).parent
f=json.loads((p/'foundation-state.json').read_text());f={k:f[k] for k in ['components','icons','variables','collections','modes','styles']}
mac=json.loads((p/'mac-state.json').read_text())
mapping={'O01':'M01','L01':'M02','P01':'M03','N01':'M04','S01':'M05','L06':'M06','I01':'M07','I05':'M07','P02':'M08','P03':'M08','R04':'M09','R03':'M09','N04':'M10','N05':'M10','S07':'M11','S09':'M11'}
sc={'screens':{s:{'frameId':mac['screens'][m]} for s,m in mapping.items()}}
src=['O01','L01','P01','N01','S01','L06','I05','P03','R04','N04','S07']
bases=src[:5]+['L01','L01','P01','P01','N01','S01']
ms=[dict(id='M'+str(i+1).zfill(2),source=s,base=bases[i],modal=i>=5) for i,s in enumerate(src)][int(sys.argv[1]):int(sys.argv[2])]
cat=json.loads((p/'catalog.json').read_text());specs=[s for s in cat['screens'] if s['id'] in src]
prefix='\n'.join('const '+k+'='+json.dumps(v,ensure_ascii=False,separators=(',',':'))+';' for k,v in [('FOUNDATION',f),('SCAFFOLD',sc),('MAC',mac),('MAC_SPECS',ms),('SPECS',specs)])
helpers=(p/'render-flow.js').read_text().split('for(const spec of SPECS){')[0].replace("getNodeByIdAsync('0:1')",f"getNodeByIdAsync('{mac['pageId']}')")
script=prefix+'\n'+helpers+'\n'+(p/'render-mac.js').read_text()
assert len(script)<49500,len(script)
print(script)
