from pathlib import Path
import json,sys
c=json.loads((Path(__file__).parent/'catalog.json').read_text());s=next(s for s in c['screens'] if s['id']==sys.argv[1]);f=next(f for f in c['flows'] if s['id'] in f['screens']);print(json.dumps({'flow':f,'specs':[s]},ensure_ascii=False,separators=(',',':')))
