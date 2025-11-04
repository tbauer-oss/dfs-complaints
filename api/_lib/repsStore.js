// api/_lib/repsStore.js
import { Redis } from '@upstash/redis';

const redis = new Redis({
  url: process.env.UPSTASH_REDIS_REST_URL,
  token: process.env.UPSTASH_REDIS_REST_TOKEN,
});

// Erwartetes Format im Key "reps":
// [
//   { id, firstName, lastName, email, region, customers: ["kunde1@mail", "kunde2@mail", ...] },
//   ...
// ]
export async function getAllRepsWithCustomers() {
  const list = await redis.get('reps');
  if (!Array.isArray(list)) return [];
  return list.map(x => ({
    id: String(x.id ?? x.email ?? ''),
    firstName: String(x.firstName ?? ''),
    lastName : String(x.lastName  ?? ''),
    email    : String(x.email     ?? ''),
    region   : String(x.region    ?? ''),
    customers: Array.isArray(x.customers) ? x.customers.map(e => String(e)) : [],
  }));
}
