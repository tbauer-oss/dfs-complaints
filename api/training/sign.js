// /api/training/sign.js – Alias for nested sign route
export const config = { runtime: 'nodejs' };

import handler from './sessions/[id]/participants/[participantId]/sign.js';

export default handler;
