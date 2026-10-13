import json,sys
from pathlib import Path
p=Path(__file__).parent
f=json.loads((p/'foundation-state.json').read_text());f={k:f[k] for k in ['components','icons','variables','collections','modes','styles']}
sc=json.loads((p/'scaffold-state.json').read_text());sc={k:sc[k] for k in ['wrappers','screens']}
cat=json.loads((p/'catalog.json').read_text());flow=next(x for x in cat['flows'] if x['key']==sys.argv[1]);specs=[s for s in cat['screens'] if s['id'] in flow['screens']]
if len(sys.argv)>2: specs=specs[int(sys.argv[2]):int(sys.argv[3])]
payload='\n'.join('const '+k+'='+json.dumps(v,ensure_ascii=False,separators=(',',':'))+';' for k,v in [('FOUNDATION',f),('SCAFFOLD',sc),('FLOW',flow),('SPECS',specs)])
script=payload+'\n'+(p/'render-flow.js').read_text()
assert len(script)<49500, len(script)
print(script)
