// /api/training/signature-token.js – Alias for nested signature-token route
export const config = { runtime: 'nodejs' };

import handler from './sessions/[id]/participants/[participantId]/signature-token.js';

export default handler;
