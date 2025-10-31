// /api/diag/register-dryrun.js
export const config = { runtime: 'nodejs' };
import { pendingGet, pendingSave } from '../_lib/store.js';
import { send, notifyQM, tpl } from '../_lib/mail.js';
import bcrypt from 'bcryptjs';

export default async function handler(_req,res){
  res.setHeader('Content-Type','application/json');
  try{
    const email = 'dryrun@example.com';
    if (await pendingGet(email)) {
      return res.end(JSON.stringify({ ok:true, note:'already pending' }));
    }
    const pending = {
      email, passhash: await bcrypt.hash('x',10),
      company:'Test GmbH', contact:'Tobias', street:'Ring 1',
      zip:'93339', city:'Riedenburg', country:'DE',
      phone:'', createdAt: Date.now(), status:'pending'
    };
    await pendingSave(pending);
    await Promise.allSettled([
      send(pending.email, tpl.afterRegisterToCustomer(pending.contact,'de')),
      notifyQM(tpl.afterRegisterToQM(pending.email,'de'))
    ]);
    res.end(JSON.stringify({ ok:true }));
  }catch(e){
    res.statusCode=500;
    res.end(JSON.stringify({ ok:false, error:e?.message||String(e)}));
  }
}
