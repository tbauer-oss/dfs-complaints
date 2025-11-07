// /api/rep/assignable-customers.js
export default async function handler(req, res) {
  if (req.method !== 'GET') return res.status(405).end();

  // TODO: hier aus deiner Quelle lesen (DB/KV)
  // Erwartete Felder: email, company?, name?, assigneeEmail?, assigneeName?
  const allCustomers = await loadAllCustomersWithAssignee(); 

  // Minimalvalidierung + sortieren nach Label
  const norm = (x) => ({
    email: String(x.email || '').toLowerCase(),
    company: String(x.company || ''),
    name: String(x.name || ''),
    assigneeEmail: x.assigneeEmail ? String(x.assigneeEmail).toLowerCase() : null,
    assigneeName: x.assigneeName || null,
  });
  const list = allCustomers.map(norm).filter(c => c.email);
  list.sort((a,b) => (a.company||a.name||a.email).localeCompare(b.company||b.name||b.email, 'de', {sensitivity:'base'}));

  res.status(200).json(list);
}
