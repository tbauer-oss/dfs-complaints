// api/rep/assignable-customers.js
export const config = { runtime: 'nodejs' };

import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';

const KV_URL   = process.env.UPSTASH_REDIS_REST_URL;
const KV_TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN;

function S(v){ return (v ?? '').toString().trim(); }

async function kv(cmd){
  const r = await fetch(KV_URL, {
    method: 'POST',
    headers: { Authorization: `Bearer ${KV_TOKEN}`, 'Content-Type':'application/json' },
    body: JSON.stringify({ cmd }),
  });
  if (!r.ok) throw new Error(`Upstash ${r.status}: ${await r.text()}`);
  return r.json();
}

async function scanAll(pattern, count=1000){
  const keys=[]; let cursor='0';
  do{
    const j = await kv(['SCAN', cursor, 'MATCH', pattern, 'COUNT', String(count)]);
    const res = j?.result || j; // Upstash REST: {result:[cursor,[keys]]}
    cursor = Array.isArray(res) ? (res[0] || '0') : '0';
    const batch = Array.isArray(res) ? (res[1] || []) : [];
    keys.push(...batch);
  } while(cursor !== '0');
  return keys;
}

async function mget(keys){
  if(!keys?.length) return [];
  const j = await kv(['MGET', ...keys]);
  return j?.result ?? [];
}

function isActiveCustomer(u){
  if (!u || typeof u !== 'object') return false;
  const em = S(u.email).toLowerCase();
  if (!em) return false;
  const status  = S(u.status).toLowerCase();
  const revoked = Boolean(u.revoked);
  return (status === '' || status === 'active' || status === 'ok') && !revoked;
}

function labelFor(u){
  const em = S(u.email).toLowerCase();
  const company = S(u.company || u.companyName || u.org);
  const first = S(u.firstName);
  const last  = S(u.lastName);
  const name  = S(u.name || u.contact || `${first} ${last}`.trim());
  return company || (name ? `${name} • ${em}` : em);
}

function parseJsonMaybe(v){
  if (typeof v === 'object' && v !== null) return v;
  try { return JSON.parse(String(v)); } catch { return null; }
}

function emailFromRepOfKey(key){
  // akzeptiert dfs:repOf:mail und dfs:repOfmail
  let k = key.replace(/^dfs:repof:?/i, '');
  try { k = decodeURIComponent(k); } catch {}
  return k.toLowerCase();
}

async function loadAllCustomers(){
  const keys = await scanAll('dfs:user:*');
  const vals = await mget(keys);
  const map = new Map();
  for(const v of vals){
    const u = parseJsonMaybe(v);
    if(!isActiveCustomer(u)) continue;
    const email = S(u.email).toLowerCase();
    map.set(email, { email, _raw: u });
  }
  return Array.from(map.values());
}

async function loadAssignments(){
  // dfs:repOf:<customerEmail> -> rep_#
  const keys = await scanAll('dfs:repOf*');
  const vals = await mget(keys);
  const out = {};
  for (let i=0;i<keys.length;i++){
    const email = emailFromRepOfKey(keys[i]);
    const repId = S(vals[i]).toLowerCase();
    if (email) out[email] = repId || null;
  }
  return out; // { 'kunde@…':'rep_2', … }
}

async function loadRepDirectory(){
  // reps aus dfs:rep:all -> Liste rep_#
  let ids = [];
  try{
    const j = await kv(['GET', 'dfs:rep:all']);
    const raw = j?.result;
    if (Array.isArray(raw)) ids = raw;
    else if (typeof raw === 'string') ids = raw.split(/\s+/).filter(Boolean);
  }catch{}
  // Details aus dfs:reps:<id>
  const keys = ids.map(id => `dfs:reps:${id}`);
  const vals = await mget(keys);
  const dir = {};
  for (let i=0;i<ids.length;i++){
    const obj = parseJsonMaybe(vals[i]) || {};
    dir[ids[i]] = {
      id: ids[i],
      email: S(obj.email).toLowerCase(),
      firstName: S(obj.firstName),
      lastName: S(obj.lastName),
      name: S(`${obj.firstName ?? ''} ${obj.lastName ?? ''}`).trim(),
      active: obj.active !== false,
    };
  }
  return dir; // { rep_2: {email:'carsten…', name:'Carsten Kriete'}, … }
}

export default async function handler(req, res){
  // CORS zuerst
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') return res.status(204).end();

  try{
    if (req.method !== 'GET'){
      return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
    }

    // Auth (wie /api/rep/customers)
    let auth=null; try{ auth = getRepFromAuthHeader(req); }catch{}
    if (!auth) return res.status(401).end(JSON.stringify({ error:'unauthorized' }));

    const wantAll = (req.query?.all || '').toString() === '1';

    // Daten laden
    const [customers, assigned, reps] = await Promise.all([
      loadAllCustomers(),
      loadAssignments(),
      loadRepDirectory(),
    ]);

    // zusammenbauen
    const outAll = customers.map(c=>{
      const u = c._raw || {};
      const email = c.email;
      const company = S(u.company || u.companyName || u.org);
      const first   = S(u.firstName);
      const last    = S(u.lastName);
      const name    = S(u.name || u.contact || `${first} ${last}`.trim()) || email;

      const repId   = assigned[email] || '';
      const repInfo = reps[repId] || null;

      return {
        email,
        company,
        name,
        label: labelFor(u || c),
        assigned: Boolean(repId),
        assignedTo: repId,
        assignedToEmail: repInfo?.email || '',
        assignedToName : repInfo?.name  || '',
      };
    }).sort((a,b)=>a.label.toLowerCase().localeCompare(b.label.toLowerCase(), 'de'));

    if (wantAll){
      // Alle Kunden (zugewiesene markiert)
      return res.status(200).end(JSON.stringify(outAll));
    }

    // Nur freie Kunden
    const free = outAll.filter(x => !x.assigned);
    return res.status(200).end(JSON.stringify(free));
  }catch(e){
    console.error('[rep/assignable-customers] FATAL', e);
    // nie 500 für's FE
    return res.status(200).end(JSON.stringify([]));
  }
}
