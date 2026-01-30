import { withCors } from './http.js';

export function applyAdminCors(req, res) {
  return withCors(req, res);
}
