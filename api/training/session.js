// /api/training/session.js – Alias for nested training session route
export const config = { runtime: 'nodejs' };

import handler from './sessions/[id].js';

export default handler;
