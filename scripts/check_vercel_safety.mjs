import fs from 'fs';

const vercel = JSON.parse(fs.readFileSync('vercel.json', 'utf8'));
const routes = Array.isArray(vercel.routes) ? vercel.routes : [];

const filesystemIndex = routes.findIndex((r) => r && r.handle === 'filesystem');
if (filesystemIndex === -1) {
  console.error('vercel.json: missing {"handle":"filesystem"} route');
  process.exit(1);
}

const trailing = routes.slice(filesystemIndex + 1).filter((r) => r && typeof r === 'object' && 'src' in r);
if (trailing.length > 1 || (trailing.length === 1 && trailing[0].dest !== '/index.html')) {
  console.error('vercel.json: found API routes after handle:filesystem. Move rewrites before filesystem catch-all.');
  process.exit(1);
}

const asText = JSON.stringify(routes);
const forbidden = [
  '/api/gspr/td/[tdId]/overview.js',
  '/api/gspr/td/[tdId]/requirement/[gsprNo].js',
  '/api/gspr/[tdId]/overview.js',
  '/api/gspr/[tdId]/requirement/[gsprNo].js',
];
const hit = forbidden.find((p) => asText.includes(p));
if (hit) {
  console.error(`vercel.json: forbidden route destination still present: ${hit}`);
  process.exit(1);
}

if (fs.existsSync('api/gspr/[tdId]')) {
  console.error('forbidden path exists: api/gspr/[tdId] (conflicts with api/gspr/[regSlug])');
  process.exit(1);
}

console.log('vercel safety checks passed');
