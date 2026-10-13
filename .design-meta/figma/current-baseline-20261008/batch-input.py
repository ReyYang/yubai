import json,sys
from pathlib import Path
p=Path(__file__).parent;c=json.loads((p/'catalog.json').read_text());key=sys.argv[1];start=int(sys.argv[2]);end=int(sys.argv[3]);f=next(f for f in c['flows'] if f['key']==key);print(json.dumps({'flow':f,'specs':[s for s in c['screens'] if s['id'] in f['screens'][start:end]]},ensure_ascii=False,separators=(',',':')))
