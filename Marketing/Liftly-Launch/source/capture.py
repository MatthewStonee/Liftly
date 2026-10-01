"""Capture helper for the installed XcodeBuildMCP CLI. Uses isolated simulator UI."""
import subprocess, sys
CLI=['node','/Users/matthew/.npm/_npx/99336612077b7094/node_modules/xcodebuildmcp/build/cli.js','ui-automation']
SIM=['--simulator-id','CBF71127-E4CE-4B63-BAA9-1E73EB6C55E7']
def run(action,*args):
    r=subprocess.run(CLI+[action]+SIM+list(args),text=True,capture_output=True)
    if r.returncode: raise RuntimeError(r.stdout+r.stderr)
    return r.stdout
state=run('snapshot-ui')
mode,label=sys.argv[1:3]
rows=[r.strip().split('|') for r in state.splitlines() if r.strip().startswith('e') and '|' in r]
rows=[r for r in rows if len(r)>4 and (r[3]==label or r[4]==label or r[-1]==label)]
if len(sys.argv)>3 and mode=='touch': rows=[r for r in rows if r[2]==sys.argv[3]]
if len(rows)!=1: print(state); raise RuntimeError(f'Ambiguous or missing target: {label}')
ref=rows[0][0]
if mode=='touch': print(run('touch','--element-ref',ref,'--down','--up','--delay','0.08'))
elif mode=='type':
    print(run('touch','--element-ref',ref,'--down','--up','--delay','0.08'))
    state=run('snapshot-ui')
    rows=[r.strip().split('|') for r in state.splitlines() if r.strip().startswith('e') and '|' in r]
    rows=[r for r in rows if len(r)>4 and (r[3]==label or r[4]==label or r[-1]==label)]
    if len(rows)!=1: print(state); raise RuntimeError('Text field changed')
    print(run('type-text','--element-ref',rows[0][0],'--text',sys.argv[3],'--replace-existing'))
print(run('snapshot-ui'))
