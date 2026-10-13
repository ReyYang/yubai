from pathlib import Path
import json,sys
p=Path(__file__).parent;c=json.loads((p/'catalog.json').read_text());mac=json.loads((p/'mac.json').read_text());mapping={'O01':'M01','L01':'M02','P01':'M03','N01':'M04','S01':'M05','L06':'M06','I01':'M07','I05':'M07','P02':'M08','P03':'M08','R04':'M09','R03':'M09','N04':'M10','N05':'M10','S07':'M11','S09':'M11'}
sources=['O01','L01','P01','N01','S01','L06','I05','P03','R04','N04','S07'];bases=sources[:5]+['L01','L01','P01','P01','N01','S01'];items=[{'id':'M'+str(i+1).zfill(2),'source':s,'base':bases[i],'modal':i>=5} for i,s in enumerate(sources)][int(sys.argv[1]):int(sys.argv[2])];needed={v for i in items for v in [i['source'],i['base']]}
print(json.dumps({'mac':mac,'macSpecs':items,'specs':[s for s in c['screens'] if s['id'] in needed],'scaffold':{'screens':{s:{'frameId':mac['screens'][m]} for s,m in mapping.items()}}},ensure_ascii=False,separators=(',',':')))
