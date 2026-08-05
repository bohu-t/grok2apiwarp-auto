#!/usr/bin/env python3
import json, os, sqlite3, subprocess, tempfile, shutil, time, re, sys, urllib.request, urllib.error
from pathlib import Path

RESIN_CACHE_DB = Path(os.environ.get('RESIN_CACHE_DB', '/vol3/openclaw-workspace-projects/resin-deploy/data/cache/cache.db'))
CONFIG_PATH = Path(os.environ.get('SINGBOX_CONFIG', '/opt/sing-box-bridge/config.json'))
BACKUP_DIR = Path(os.environ.get('BACKUP_DIR', '/vol3/openclaw-backups/resin-singbox-sync'))
BASE_PORT = int(os.environ.get('BASE_PORT', '10801'))
MAX_NODES = int(os.environ.get('MAX_NODES', '300'))
GROK_DB = Path(os.environ.get('GROK_DB', '/var/lib/docker/volumes/grok2api_grok2api-data/_data/backend.db'))
GROK_CONFIG = Path(os.environ.get('GROK_CONFIG', '/vol3/projects/grok2api-go-egress/config.yaml'))
GROK_API_BASE = os.environ.get('GROK_API_BASE', 'http://127.0.0.1:28086/api/admin/v1')
GROK_ADMIN_USERNAME = os.environ.get('GROK2API_ADMIN_USERNAME', '').strip()
GROK_ADMIN_PASSWORD = os.environ.get('GROK2API_ADMIN_PASSWORD', '')
GROK_CONTAINER = os.environ.get('GROK_CONTAINER', 'grok2api')
SINGBOX_CONTAINER = os.environ.get('SINGBOX_CONTAINER', 'sing-box-bridge')
GROK_PROXY_HOST = os.environ.get('GROK_PROXY_HOST', 'sing-box-bridge')
NODE_NAME_PREFIX = os.environ.get('NODE_NAME_PREFIX', 'Resin Bridge')
OLD_PREFIXES = tuple(x.strip() for x in os.environ.get('OLD_NODE_PREFIXES', 'Resin Bridge (sing-box),Resin Bridge').split(',') if x.strip())
SCOPE = os.environ.get('GROK_SCOPE', 'grok_build')
ACCOUNT_CAPACITY = int(os.environ.get('ACCOUNT_CAPACITY', '0'))
SYNC_GROK = os.environ.get('SYNC_GROK', '1').lower() not in ('0','false','no')
DELETE_STALE = os.environ.get('DELETE_STALE', '1').lower() not in ('0','false','no')

def sanitize(s, limit=60):
    s = re.sub(r'\s+', ' ', str(s or '')).strip()
    s = re.sub(r'[\x00-\x1f\x7f]+', '', s)
    return s[:limit] if s else ''

def load_nodes():
    if not RESIN_CACHE_DB.exists():
        raise SystemExit(f'missing resin cache db: {RESIN_CACHE_DB}')
    con = sqlite3.connect(f'file:{RESIN_CACHE_DB}?mode=ro', uri=True)
    con.row_factory = sqlite3.Row
    rows = con.execute('''
      SELECT s.hash, s.raw_options_json, s.created_at_ns,
             COALESCE(d.egress_ip,'') egress_ip,
             COALESCE(d.egress_region,'') region,
             COALESCE(d.failure_count,0) failure_count,
             COALESCE(d.circuit_open_since,0) circuit_open_since,
             COALESCE(d.last_latency_probe_attempt_ns,0) last_latency_probe_attempt_ns,
             COALESCE((SELECT tags_json FROM subscription_nodes sn WHERE sn.node_hash=s.hash AND COALESCE(sn.evicted,0)=0 LIMIT 1),'[]') tags_json
      FROM nodes_static s
      LEFT JOIN nodes_dynamic d ON d.hash=s.hash
      WHERE EXISTS (SELECT 1 FROM subscription_nodes sn WHERE sn.node_hash=s.hash AND COALESCE(sn.evicted,0)=0)
      ORDER BY CASE WHEN COALESCE(d.egress_ip,'') <> '' THEN 0 ELSE 1 END,
               CASE WHEN COALESCE(d.circuit_open_since,0)=0 THEN 0 ELSE 1 END,
               COALESCE(d.failure_count,0) ASC,
               COALESCE(d.last_latency_probe_attempt_ns,0) DESC,
               s.created_at_ns DESC
      LIMIT ?
    ''', (MAX_NODES,)).fetchall()
    con.close()
    nodes=[]
    seen=set()
    for r in rows:
        try:
            outbound=json.loads(r['raw_options_json'])
            if not isinstance(outbound, dict) or not outbound.get('type'):
                continue
            h=r['hash']
            if h in seen: continue
            seen.add(h)
            tags=json.loads(r['tags_json'] or '[]')
            raw_tag=sanitize(tags[0] if tags else outbound.get('tag') or h, 80)
            region=sanitize(r['region'] or '', 20)
            ip=sanitize(r['egress_ip'] or outbound.get('server') or '', 45)
            nodes.append({'hash':h, 'outbound':outbound, 'raw_tag':raw_tag, 'egress_ip':ip, 'region':region})
        except Exception as e:
            print(f'skip invalid node {r["hash"]}: {e}', file=sys.stderr)
    return nodes

def node_name(i, n):
    loc = n['region'] or n['egress_ip'] or 'unknown'
    tail = n['raw_tag'] or n['hash'][:8]
    return sanitize(f'{NODE_NAME_PREFIX} {i+1:03d} - {loc} - {tail}', 150)

def build_config(nodes):
    inbounds=[]; outbounds=[]; rules=[]
    for i,n in enumerate(nodes):
        port=BASE_PORT+i
        in_tag=f'resin-in-{i+1:03d}'
        out_tag=f'resin-out-{i+1:03d}'
        ob=dict(n['outbound'])
        ob['tag']=out_tag
        inbounds.append({'type':'socks','tag':in_tag,'listen':'0.0.0.0','listen_port':port})
        outbounds.append(ob)
        rules.append({'inbound':[in_tag],'outbound':out_tag})
    outbounds.append({'type':'direct','tag':'direct'})
    return {'log': {'level': 'info', 'timestamp': True}, 'inbounds': inbounds, 'outbounds': outbounds, 'route': {'rules': rules, 'final': 'direct'}}

def validate_config(config):
    ports=[x.get('listen_port') for x in config.get('inbounds',[])]
    if len(ports) != len(set(ports)):
        raise SystemExit('duplicate sing-box listen ports')
    if not config.get('inbounds'):
        raise SystemExit('empty sing-box inbounds')
    with tempfile.NamedTemporaryFile('w', delete=False, suffix='.json') as f:
        json.dump(config, f, ensure_ascii=False, indent=2)
        tmp=f.name
    container_tmp='/tmp/resin-bridge-candidate.json'
    try:
        subprocess.run(['docker','cp',tmp,f'{SINGBOX_CONTAINER}:{container_tmp}'], check=True, text=True, capture_output=True, timeout=30)
        cp=subprocess.run(['docker','exec',SINGBOX_CONTAINER,'sing-box','check','-c',container_tmp], text=True, capture_output=True, timeout=120)
        if cp.returncode != 0:
            print(cp.stdout + cp.stderr, file=sys.stderr)
            raise SystemExit('sing-box config check failed')
    finally:
        subprocess.run(['docker','exec',SINGBOX_CONTAINER,'rm','-f',container_tmp], text=True, capture_output=True, timeout=30)
        try: os.unlink(tmp)
        except FileNotFoundError: pass

def write_config(config):
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    if CONFIG_PATH.exists():
        backup=BACKUP_DIR / f'config.json.{time.strftime("%Y%m%d-%H%M%S")}'
        shutil.copy2(CONFIG_PATH, backup)
    tmp=CONFIG_PATH.with_name('.config.json.tmp')
    tmp.write_text(json.dumps(config, ensure_ascii=False, indent=2)+'\n')
    os.chmod(tmp, 0o644)
    os.replace(tmp, CONFIG_PATH)

def restart_container(name):
    subprocess.run(['docker','restart',name], check=True, timeout=90, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def yaml_bootstrap_admin():
    # Avoid external dependency on PyYAML; parse only the small bootstrapAdmin block.
    username='admin'; password=''
    in_block=False
    for line in GROK_CONFIG.read_text().splitlines():
        if re.match(r'^bootstrapAdmin\s*:', line):
            in_block=True; continue
        if in_block and re.match(r'^\S', line):
            break
        if in_block:
            m=re.match(r'^\s*(username|password)\s*:\s*(.*)\s*$', line)
            if m:
                val=m.group(2).strip().strip('"').strip("'")
                if m.group(1)=='username': username=val
                else: password=val
    return username,password

def api_request(path, method='GET', token=None, body=None, timeout=20):
    data=None if body is None else json.dumps(body).encode()
    req=urllib.request.Request(GROK_API_BASE+path, data=data, method=method)
    req.add_header('Content-Type','application/json')
    if token: req.add_header('Authorization','Bearer '+token)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw=r.read().decode(errors='replace')
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raise RuntimeError(f'{method} {path} HTTP {e.code}: {e.read().decode(errors="replace")[:500]}')

def login():
    username,password=(GROK_ADMIN_USERNAME,GROK_ADMIN_PASSWORD) if GROK_ADMIN_PASSWORD else yaml_bootstrap_admin()
    d=api_request('/auth/login','POST',None,{'username':username,'password':password})
    return d['data']['tokens']['accessToken']

def list_bridge_nodes(token):
    # API pagination shape can vary; use DB for discovery because we only need ids/names/proxy configured.
    con=sqlite3.connect(GROK_DB)
    con.row_factory=sqlite3.Row
    rows=con.execute("SELECT id,name,enabled FROM egress_nodes WHERE name LIKE 'Resin Bridge%' ORDER BY name,id").fetchall()
    con.close()
    return [{'id':str(r['id']),'name':r['name'],'enabled':bool(r['enabled'])} for r in rows]

def sync_grok_api(nodes):
    if not SYNC_GROK:
        return {'synced':False,'reason':'disabled'}
    token=login()
    existing=list_bridge_nodes(token)
    by_slot={}
    extras=[]
    # recognize old/new slot names by the first 3-digit number after prefix.
    for row in existing:
        m=re.search(r'Resin Bridge(?: \(sing-box\))?\s+(\d{1,3})\b', row['name'])
        if m:
            slot=int(m.group(1))
            if slot not in by_slot: by_slot[slot]=row
            else: extras.append(row)
        else:
            extras.append(row)
    created=updated=deleted=0
    for i,n in enumerate(nodes):
        slot=i+1
        name=node_name(i,n)
        proxy=f'socks5://{GROK_PROXY_HOST}:{BASE_PORT+i}'
        payload={'name':name,'scope':SCOPE,'enabled':True,'proxyPool':False,'accountCapacity':ACCOUNT_CAPACITY,'proxyURL':proxy,'userAgent':''}
        row=by_slot.get(slot)
        if row:
            api_request(f'/egress-nodes/{row["id"]}','PUT',token,payload)
            updated+=1
        else:
            api_request('/egress-nodes','POST',token,payload)
            created+=1
    stale=[]
    wanted=set(range(1,len(nodes)+1))
    for slot,row in by_slot.items():
        if slot not in wanted: stale.append(row)
    stale += extras
    for row in stale:
        if DELETE_STALE:
            try:
                api_request(f'/egress-nodes/{row["id"]}','DELETE',token)
                deleted+=1
            except Exception as e:
                # Fall back to disabling if bound or protected.
                api_request(f'/egress-nodes/{row["id"]}','PUT',token,{'name':row['name'],'scope':SCOPE,'enabled':False,'clearProxyURL':False,'accountCapacity':ACCOUNT_CAPACITY,'userAgent':''})
        else:
            pass
    return {'synced':True,'updated':updated,'created':created,'deleted_or_disabled_stale':deleted,'wanted':len(nodes),'existing_before':len(existing)}

def main():
    nodes=load_nodes()
    if not nodes: raise SystemExit('no resin nodes found')
    cfg=build_config(nodes)
    validate_config(cfg)
    write_config(cfg)
    restart_container(SINGBOX_CONTAINER)
    grok=sync_grok_api(nodes)
    summary={
        'time':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),
        'resin_nodes':len(nodes),
        'sing_box_ports':f'{BASE_PORT}-{BASE_PORT+len(nodes)-1}',
        'grok':grok,
        'samples':[{'name':node_name(i,n),'port':BASE_PORT+i,'ip':n['egress_ip'],'region':n['region']} for i,n in enumerate(nodes[:10])]
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))

if __name__=='__main__': main()
