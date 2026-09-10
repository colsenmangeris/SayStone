#!/usr/bin/env python3
"""Read-only local history comparison. Private outputs must stay outside the repo."""
import argparse,ast,difflib,html,json,pathlib,re,sqlite3,time,urllib.request
p=argparse.ArgumentParser();p.add_argument('--output',type=pathlib.Path,required=True);args=p.parse_args()
repo=pathlib.Path(__file__).resolve().parents[1]
if args.output.resolve().is_relative_to(repo): p.error('Private output must be outside the repository')
args.output.mkdir(parents=True,exist_ok=True)
# Reuse exactly the prompts evaluated in the authored suite without executing it.
module=ast.parse((repo/'evaluation/cleanup-smoke.py').read_text())
prompts={n.targets[0].id:ast.literal_eval(n.value) for n in module.body if isinstance(n,ast.Assign) and isinstance(n.targets[0],ast.Name) and n.targets[0].id in ('bit','speako')}
db=pathlib.Path.home()/'Library/Application Support/FluidVoice/TranscriptionHistory.sqlite3'
with sqlite3.connect(db.as_uri()+'?mode=ro',uri=True) as c:
 entries=sorted([json.loads(row[0]) for row in c.execute('SELECT payload FROM history')],key=lambda x:x['timestamp'])
seen=set();cases=[]
for e in entries:
 text=e['rawText'].strip()
 if len(text)<20 or text in seen:continue
 seen.add(text);cases.append({'id':e['id'],'input':text})
cases=cases[-12:]
results=[]
for model,prompt,temp in [('unchanged',None,0),('fluidvoice-bitvoice-eval',prompts['bit'],.2),('hf.co/SpeakoFlow/speakoflow-mini:Q8_0',prompts['speako'],0)]:
 for c in cases:
  start=time.monotonic();out=c['input'];error=None;metrics={}
  try:
   if prompt:
    payload={'model':model,'messages':[{'role':'system','content':prompt},{'role':'user','content':out}],'stream':False,'think':False,'keep_alive':'5m','options':{'temperature':temp,'num_ctx':8192,'num_predict':2048,'seed':42}}
    request=urllib.request.Request('http://127.0.0.1:11434/api/chat',data=json.dumps(payload).encode(),headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(request,timeout=180) as response:r=json.load(response)
    out=r['message']['content'];metrics={k:r.get(k) for k in ['load_duration','total_duration','eval_count','eval_duration','done_reason']}
    if r.get('done_reason')=='length':error='truncated'
  except Exception as exc:error=str(exc);out=''
  row={**c,'model':model,'output':out,'seconds':time.monotonic()-start,'error':error,'metrics':metrics,'unchanged':out==c['input']}
  results.append(row)
  (args.output/'results.json').write_text(json.dumps(results,indent=2))
  print(model,c['id'],round(row['seconds'],2),'unchanged='+str(row['unchanged']),error,flush=True)
parts=['<!doctype html><meta charset="utf-8"><title>SayStone local cleanup review</title><style>body{font:16px system-ui;max-width:1100px;margin:40px auto;padding:20px}article{border-top:1px solid #bbb;padding:20px 0}pre{white-space:pre-wrap}ins{background:#d6f5db}del{background:#ffdada}small{color:#555}</style><h1>SayStone local cleanup review</h1><p>Private, local history sample. This is a text preservation review, not audio ground truth or a representative accuracy benchmark. SpeakoFlow rules layer is not included. First call can include model loading.</p>']
for c in cases:
 parts.append('<article><h2>'+html.escape(c['id'])+'</h2><h3>Unchanged</h3><pre>'+html.escape(c['input'])+'</pre>')
 for r in [r for r in results if r['id']==c['id'] and r['model']!='unchanged']:
  diff=[]
  for op,a,b,x,y in difflib.SequenceMatcher(None,c['input'],r['output'],autojunk=False).get_opcodes():
   if op=='equal':diff.append(html.escape(c['input'][a:b]))
   else:
    if op in ('delete','replace'):diff.append('<del>'+html.escape(c['input'][a:b])+'</del>')
    if op in ('insert','replace'):diff.append('<ins>'+html.escape(r['output'][x:y])+'</ins>')
  parts.append('<h3>'+html.escape(r['model'])+'</h3><small>'+str(round(r['seconds'],2))+' seconds; '+html.escape(str(r['error'] or 'completed'))+'</small><pre>'+''.join(diff)+'</pre>')
 parts.append('</article>')
(args.output/'review.html').write_text('\n'.join(parts))
print('Completed',len(cases),'cases. No reference transcript: no WER or accuracy score calculated.')
