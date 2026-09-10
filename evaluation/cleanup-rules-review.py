#!/usr/bin/env python3
"""Evaluate the upstream reference rules on the same saved private sample."""
import argparse,ast,importlib.util,json,pathlib,sys,time,urllib.request
p=argparse.ArgumentParser();p.add_argument('--rules',type=pathlib.Path,required=True);p.add_argument('--results',type=pathlib.Path,required=True);a=p.parse_args()
sys.path.insert(0,str(a.rules/'reference/python'));import cleanup
base=json.loads(a.results.read_text());cases=[r for r in base if r['model']=='unchanged']
tree=ast.parse(pathlib.Path('evaluation/cleanup-smoke.py').read_text());prompt=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and isinstance(n.targets[0],ast.Name) and n.targets[0].id=='speako')
result=[]
for c in cases:
 pre=cleanup.filter_transcript(cleanup.apply_vocabulary(c['input'],[]),lang='en')
 start=time.monotonic()
 payload={'model':'hf.co/SpeakoFlow/speakoflow-mini:Q8_0','messages':[{'role':'system','content':prompt},{'role':'user','content':pre}],'stream':False,'think':False,'keep_alive':'5m','options':{'temperature':0,'seed':42,'num_ctx':8192,'num_predict':2048}}
 req=urllib.request.Request('http://127.0.0.1:11434/api/chat',data=json.dumps(payload).encode(),headers={'Content-Type':'application/json'})
 with urllib.request.urlopen(req,timeout=180) as response:r=json.load(response)
 # Emoji and custom replacements intentionally off, matching current preferences.
 output=cleanup.apply_replacements(r['message']['content'],[])
 result.append({'id':c['id'],'input':c['input'],'rules_only':pre,'output':output,'seconds':time.monotonic()-start,'done_reason':r.get('done_reason')})
 (a.results.parent/'rules-results.json').write_text(json.dumps(result,indent=2))
 print(c['id'],'rules_changed',pre!=c['input'],'model_changed',output!=pre,flush=True)
