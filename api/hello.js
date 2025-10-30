export const config = { runtime: 'nodejs22.x' };
export default (req, res) => res.status(200).json({ ok: true, t: Date.now() });
