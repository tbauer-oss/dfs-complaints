// api/_lib/cors.js
// Centralized CORS helper (re-export from http.js to keep behavior consistent across all routes)
export { setCors, handlePreflight } from './http.js';
