import { createKvRedisCompat } from './kvStore.js';
import { getDatabaseConnectionString } from './db.js';

const NULL_SCAN_RESULT = ['0', []];

function createNullRedis() {
  return {
    __isNullRedis: true,
    async ping() { return 'PONG'; },
    async get() { return null; },
    async set() { return 'OK'; },
    async del() { return 0; },
    async scan() { return NULL_SCAN_RESULT; },
    async keys() { return []; },
  };
}

function hasRequiredStoreEnv() {
  return Boolean(getDatabaseConnectionString());
}

export const redis = hasRequiredStoreEnv() ? createKvRedisCompat() : createNullRedis();
