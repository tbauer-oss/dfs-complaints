// middleware.js – CORS-Fallback für alle /api/* Routen (inkl. OPTIONS)
import { NextResponse } from 'next/server';

// Prod-Frontend + breite Preview-Whitelist
const PROD_FE = 'https://dfs-complaints-web.vercel.app';
const PREVIEW = /^https:\/\/(?:dfs-complaints|dfs-complaints-web|dfs-customer-complaint)(?:-[a-z0-9-]+)*\.vercel\.app$/i;

function pickAllowOrigin(origin) {
  if (!origin) return PROD_FE;
  if (origin === PROD_FE) return origin;
  if (PREVIEW.test(origin)) return origin;
  return '*'; // Fallback (wird nur ohne credentials akzeptiert)
}

export function middleware(req) {
  const res = NextResponse.next();
  const origin = req.headers.get('origin') || '';
  const allow = pickAllowOrigin(origin);

  res.headers.set('Access-Control-Allow-Origin', allow);
  if (allow !== '*') {
    // nur bei spezifischem Origin: Credentials erlauben
    res.headers.set('Access-Control-Allow-Credentials', 'true');
    res.headers.set('Vary', 'Origin');
  }

  res.headers.set('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.headers.set(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization, X-Admin-Secret, X-Gate, Accept, X-Requested-With'
  );
  res.headers.set('Access-Control-Max-Age', '600');

  // Preflight direkt hier beenden (204) – kommt dann GARANTIERT mit ACAO
  if (req.method === 'OPTIONS') {
    return new NextResponse(null, { status: 204, headers: res.headers });
  }

  return res;
}

export const config = {
  // nur auf API-Routen anwenden (kein Einfluss auf statische Assets / web)
  matcher: ['/api/:path*'],
};
