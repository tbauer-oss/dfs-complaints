# Chat v1 (DFS Connect)

## Key schema
- `chat:v1:user:{uid}` – Hash with display name/avatar for chat participants (read-only for GET routes).
- `chat:v1:user:{uid}:convs` – ZSET of conversation ids ordered by last activity (score = last message timestamp).
- `chat:v1:conv:{convId}:meta` – Hash storing participants, timestamps, and last message metadata.
- `chat:v1:conv:{convId}:msgs` – ZSET of message ids with score = millisecond timestamp.
- `chat:v1:msg:{msgId}` – Hash containing the append-only message payload.

## Legacy issues (root cause)
- The previous chat used ad-hoc context ids and stored per-alias memberships, so every email alias created separate keys and GET calls could register new contexts for each alias.
- Direct messages were not built from a deterministic `minUid:maxUid` pair, so multiple parallel keys appeared for the same two people, fragmenting history and yielding "empty" threads after reloads.
