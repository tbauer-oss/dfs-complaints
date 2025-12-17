# Internal Chat (DFS Connect+)

## Redis Key Design
- `chat:{contextId}:messages` — List of JSON-serialized message objects (chronological, oldest → newest).
- `chat:{contextId}:meta` — Hash with context metadata (`contextId`, `type`, `reference`, `updatedAt`, `lastMessage`, `lastAuthor`).
- `chat:user:{userId}:contexts` — Set of contexts the user participates in (author or mentioned).
- `chat:user:{userId}:reads` — Hash of last read timestamps per context (ISO-8601).
- `chat:rate:{userId}` — Sliding counter for rate limiting (10 messages / 10s).

Keys are created lazily when the first message or read event is written.

## Message Payload (API)
```json
{
  "id": "8b9c7e0d-5f1b-4c2f-9f1b-9b7d41c3d5c2",
  "contextId": "complaint:R820-25-034",
  "authorId": "jane.doe@dfs-diamon.de",
  "authorName": "Jane Doe",
  "timestamp": "2025-02-20T09:41:22.123Z",
  "type": "user",
  "body": "Bitte @john.doe die CAPA verknüpfen.",
  "mentions": ["john.doe@dfs-diamon.de"],
  "flags": ["todo"]
}
```

## Conversation Entry (API)
```json
{
  "contextId": "audit:AU-2025-02",
  "lastRead": "2025-02-20T09:42:00.000Z",
  "unread": true,
  "meta": {
    "contextId": "audit:AU-2025-02",
    "type": "audit",
    "reference": "AU-2025-02",
    "updatedAt": "2025-02-20T09:44:12.000Z",
    "lastMessage": "Status geändert auf 'In Review'",
    "lastAuthor": "System"
  }
}
```

## API Endpoints
- `GET  /api/admin/chat/:contextId?limit=50&before=<timestamp>` — returns timeline (<=50 messages, `hasMore`, updates lastRead).
- `POST /api/admin/chat/:contextId` — sends a message `{ body, mentions[], flags[] }` with validation, rate limit, and context enrollment.
- `GET  /api/admin/chat/conversations` — returns user contexts with metadata and unread indicator.
