// /api/diag/kv.js
export const config = { runtime: 'nodejs' };
import { kvStatus } from '../_lib/store.js';

export default async function handler(_req, res){
  res.setHeader('Content-Type','application/json');
  try{
    const s = await kvStatus();
    res.end(JSON.stringify({ ok:true, ...s }));
  }catch(e){
    res.statusCode=500;
    res.end(JSON.stringify({ ok:false, error: e?.message || String(e)}));
  }
}
