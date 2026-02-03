// api/account/update.js
export { config } from '../account.js';
import accountHandler from '../account.js';

export default function handler(req, res) {
  return accountHandler(req, res);
}
