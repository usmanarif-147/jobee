# 08 — Realtime Chat

## Two responsibilities

The Chat Service owns **all WebSocket connections** for the platform, which means it has two jobs:

1. **Chat** — the user-to-user messaging feature described in this file
2. **General realtime push** — when other services emit events that should appear instantly in a UI (new application badge, "your subscription is about to expire", a new in-app notification), Chat Service consumes those Kafka events and pushes them over the right WebSocket channel

This avoids running a separate "realtime" service. One process owns long-lived connections.

## Who chats with whom

| Pair | Allowed? |
|---|---|
| Super admin ↔ Company | Yes |
| Company ↔ Company | Yes — but **only between subscribed companies** |
| Applicant ↔ Anyone | No (out of scope) |

## What a chat supports

- One-to-one conversations
- Text messages
- File attachments: doc, png, jpg, jpeg, webp, audio, video, csv, md
- Read receipts (who saw what)
- Online presence (who is currently connected)
- Typing indicators

Group chats are out of scope for v1 — explicitly defer.

## Tech choice — Laravel Reverb

Reverb is Laravel's first-party WebSocket server. Reasons:

- Same language as the rest of the backend (PHP)
- Native integration with Laravel broadcasting
- Free, self-hosted
- Handles thousands of connections per node, scales horizontally with Redis pub/sub fan-out

If a single technology hits limits at peak, the migration target is **Centrifugo** or a **Node.js + Socket.IO** service. The chat protocol is abstracted from clients so the backend can swap without breaking apps.

## Architecture

```
   Browser
     │ (WebSocket)
     ▼
 Cloudflare → wss.job-hunter.com → Kong → Chat Service (Reverb)
                                           │
                                           │ Two inputs feeding broadcasts:
                                           │
                                           │  (a) chat messages: written to
                                           │      Chat DB, fanned out via
                                           │      Redis pub/sub to other Reverb pods
                                           │
                                           │  (b) Kafka consumer:
                                           │      consumes notifications.in_app_created,
                                           │      jobs.applications, payments.subscriptions
                                           │      → pushes events to relevant WebSocket
                                           │      channels (bell icons, badges)
```

## Why Redis pub/sub

When Reverb is scaled to multiple instances behind a load balancer, two users in the same conversation may be connected to different instances. Redis pub/sub fans out the message so every instance pushes it to its connected clients.

Same pattern for typing / presence / read-receipt events.

## Persistence

Every message is **written to Postgres** (`chat` schema) before being broadcast. The DB is the source of truth. The WebSocket is just transport.

When a user reconnects:
1. Fetch missed messages from DB since their `last_seen_at`
2. Fetch current online presence from Redis
3. Subscribe to new messages over WebSocket

## File attachments — separate from message text

A message and its file are uploaded separately:

1. **Client → Core API:** `POST /chat/uploads` returns a presigned S3 PUT URL
2. **Client → S3 directly:** uploads file (saves bandwidth on our servers)
3. **Client → Chat API:** `POST /chat/messages` with text + array of attachment IDs
4. Chat service writes the message + attachment links to DB and broadcasts

Attachments are stored in a separate `attachments` table with metadata (filename, mime, size, virus-scan status — see file 13).

## Auth at the WebSocket layer

WebSockets need auth too. Two-step handshake:

1. Browser obtains a short-lived (60-second) chat token from Core API (`POST /chat/token`)
2. Browser opens WebSocket with `?token=...` in the query
3. Reverb verifies the token before accepting the connection
4. Reverb knows the user ID for the duration of the connection

Tokens expire fast so a stolen URL becomes worthless quickly.

## Authorization (who can join which channel)

Reverb supports private channels with auth. When a client tries to subscribe to `private-conversation.{id}`, Reverb calls Core API to check: "Does user X belong to conversation Y?" Only on yes does it allow subscription.

This check is cached in Redis for the duration of the connection — repeated subscription attempts don't hammer the API.

## Channels

| Channel | Type | Purpose |
|---|---|---|
| `private-user.{user_id}` | Private | DM-style notifications to one user |
| `private-conversation.{id}` | Private | All members receive messages |
| `presence-conversation.{id}` | Presence | Member list + online status |

## Scaling

- **One Reverb container** can hold ~10K WebSocket connections — enough for v1
- **Horizontal scaling:** add more Reverb pods behind a load balancer; Redis pub/sub keeps them in sync
- **Sticky sessions:** required (a connection lives on one pod) — Cloudflare / ALB supports this
- **Backpressure:** if a slow recipient can't keep up, drop messages older than N seconds rather than buffering forever

## Failure modes

| Failure | What happens |
|---|---|
| Reverb pod dies | Connections drop; client auto-reconnects with exponential backoff; missed messages fetched from DB |
| Redis dies | Pub/sub stops; same pod can still serve its own users; cross-pod messaging fails until Redis recovers |
| Postgres dies | Writes fail; chat is read-only for the duration |
| Network partition | Client retries; eventually delivers when connectivity returns |

## Why a single Chat Service for both chat AND general realtime

Both jobs need:

- Long-lived WebSocket connections
- Sticky sessions
- Redis pub/sub fan-out across pods
- The same auth handshake

Splitting into "chat-service" and "realtime-service" doubles ops cost without separating any meaningful concern. One service owns the WebSocket layer.

## What to NOT build

- **End-to-end encryption** — moderation needs may require admin access
- **Voice/video calls** — separate concern; consider LiveKit / Twilio if/when added
- **Message editing / deletion** — out of scope
- **Reactions / threads** — out of scope
