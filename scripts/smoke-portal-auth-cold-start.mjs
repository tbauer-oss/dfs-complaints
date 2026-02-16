#!/usr/bin/env node
import { Client } from 'pg';

function required(name) {
  const value = String(process.env[name] || '').trim();
  if (!value) throw new Error(`Missing required env: ${name}`);
  return value;
}

async function readSnapshot(client, emailNorm) {
  const { rows } = await client.query(
    `SELECT id, email_norm, password_hash, updated_at
     FROM public.portal_users
     WHERE email_norm = $1
     LIMIT 1`,
    [emailNorm],
  );
  return rows?.[0] || null;
}

async function login(baseUrl, email, password) {
  const response = await fetch(`${baseUrl.replace(/\/$/, '')}/api/portal/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const payload = await response.json().catch(() => ({}));
  return { status: response.status, payload };
}

async function main() {
  const databaseUrl = required('DATABASE_URL');
  const baseUrl = required('PORTAL_BASE_URL');
  const email = required('PORTAL_TEST_EMAIL').toLowerCase();
  const password = required('PORTAL_TEST_PASSWORD');

  const client = new Client({ connectionString: databaseUrl, ssl: { rejectUnauthorized: false } });
  await client.connect();

  try {
    const before = await readSnapshot(client, email);
    if (!before) throw new Error(`User not found in portal_users: ${email}`);

    const loginResult = await login(baseUrl, email, password);
    if (loginResult.status !== 200) {
      throw new Error(`Login failed with status ${loginResult.status}: ${JSON.stringify(loginResult.payload)}`);
    }

    const after = await readSnapshot(client, email);
    if (!after) throw new Error(`User disappeared from portal_users: ${email}`);

    const passwordChanged = String(before.password_hash || '') !== String(after.password_hash || '');
    const updatedAtChanged = String(before.updated_at || '') !== String(after.updated_at || '');

    if (passwordChanged || updatedAtChanged) {
      throw new Error(
        `Guard failed: password_hash/updated_at changed without password endpoint call (passwordChanged=${passwordChanged}, updatedAtChanged=${updatedAtChanged})`,
      );
    }

    console.log('OK: cold-start login did not modify portal_users.password_hash or updated_at');
    console.log(JSON.stringify({
      email_norm: email,
      user_id: before.id,
      updated_at_before: before.updated_at,
      updated_at_after: after.updated_at,
    }, null, 2));
  } finally {
    await client.end();
  }
}

main().catch((err) => {
  console.error('FAILED:', err?.message || err);
  process.exit(1);
});
