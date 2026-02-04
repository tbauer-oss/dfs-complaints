export const config = { runtime: 'nodejs' };

import { applyInternalCors } from './_utils.js';

export default function handler(req, res) {
  if (applyInternalCors(req, res)) return;
  res.status(404).end();
}
