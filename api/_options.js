// api/_options.js
import { withCorsHandler } from './_lib/http.js';

export const config = { runtime: 'nodejs' };

function handler(_req, res) {
  res.statusCode = 204;
  res.end();
}

export default withCorsHandler(handler);
