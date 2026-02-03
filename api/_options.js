// api/_options.js
export const config = { runtime: 'nodejs' };

export default function handler(req, res) {
  res.status(204).end();
}
