import { withCors } from './http.js';

export function applyAdminCors(req, res) {
  withCors(req, res);
}
