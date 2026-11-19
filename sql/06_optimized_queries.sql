-- =====================================================================
-- WhatsApp Messaging Database: Phase 3 — Optimized Queries
-- Course: Database Management Systems (DBMS)
-- Team: T0084 (Dhanaya Khaspuri, Mahika Garg, Ishan Bansal, Saumya Madan)
-- Engine: PostgreSQL 18.6
--
-- Rules (same as workload_30.sql):
--   * Queries run against schema 'whatsapp'.
--   * Writes are wrapped in BEGIN ... ROLLBACK so data does not change.
--   * Optimized versions of R01–R25 and W01–W05.
--   * Run sql/05_indexes.sql before benchmarking these.
-- =====================================================================

SET search_path TO whatsapp;
BEGIN;

-- @R01 (OPTIMIZED)
-- Chats screen: user 965's chats with the time and text of the latest message.
-- Baseline: 19.97 ms — Seq Scan on chat_members + Seq Scan on messages
-- Fix: idx_chat_members_user_active (user_id, left_at IS NULL) + idx_messages_chat_sent
SELECT cm.chat_id,
       c.chat_type,
       c.group_name,
       last_msg.sent_at,
       last_msg.body
FROM   chat_members cm
JOIN   chats c ON c.chat_id = cm.chat_id
CROSS JOIN LATERAL (
    SELECT m.sent_at, m.body
    FROM   messages m
    WHERE  m.chat_id = cm.chat_id
    ORDER  BY m.sent_at DESC
    LIMIT  1
) last_msg
WHERE  cm.user_id = 965
  AND  cm.left_at IS NULL
ORDER  BY last_msg.sent_at DESC;

-- @R02 (OPTIMIZED)
-- Open a chat: the latest 50 messages of group 22556.
-- Baseline: 3.33 ms — Seq Scan on messages
-- Fix: idx_messages_chat_sent — Index Scan with LIMIT, no full scan
SELECT message_id, sender_id, sent_at, message_type, body, reply_to_message_id
FROM   messages
WHERE  chat_id = 22556
ORDER  BY sent_at DESC
LIMIT  50;

-- @R03 (OPTIMIZED)
-- Badge counts: unread messages per chat for user 965.
-- Baseline: 7.81 ms — Seq Scan on message_receipts (501k rows)
-- Fix: idx_receipts_user_unread partial index (user_id WHERE read_at IS NULL)
SELECT m.chat_id, count(*) AS unread
FROM   message_receipts r
JOIN   messages m ON m.message_id = r.message_id
WHERE  r.user_id = 965
  AND  r.read_at IS NULL
GROUP  BY m.chat_id
ORDER  BY unread DESC;

-- @R04 (OPTIMIZED)
-- Search: messages containing "meeting" in any chat user 965 belongs to.
-- Baseline: 34.58 ms — ILIKE full table scan (unfixable without pg_trgm)
-- Fix: restrict to user's chats first (smaller set), then apply ILIKE
-- Note: add pg_trgm GIN index in CP4 for further gains.
SELECT m.chat_id, m.message_id, m.sent_at, m.body
FROM   messages m
WHERE  m.chat_id IN (
           SELECT chat_id FROM chat_members
           WHERE  user_id = 965 AND left_at IS NULL
       )
  AND  m.body ILIKE '%meeting%'
ORDER  BY m.sent_at DESC
LIMIT  20;

-- @R05 (OPTIMIZED)
-- Registration: is this phone number already on WhatsApp?
-- Baseline: 0.14 ms — already uses UNIQUE index. No change needed.
SELECT user_id, display_name, status
FROM   users
WHERE  phone_e164 = '+919000000965';

-- @R06 (OPTIMIZED)
-- Contact info: "last seen" of everyone user 965 chats with directly.
-- Baseline: 2.69 ms — Seq Scan on chat_members
-- Fix: idx_chat_members_user_active drives the lookup, then PK on chats
SELECT u.user_id, u.display_name, u.last_seen_at
FROM   chat_members me
JOIN   chats c          ON c.chat_id = me.chat_id AND c.chat_type = 'DIRECT'
JOIN   chat_members other ON other.chat_id = me.chat_id
                         AND other.user_id <> me.user_id
JOIN   users u          ON u.user_id = other.user_id
WHERE  me.user_id = 965
  AND  me.left_at IS NULL
ORDER  BY u.last_seen_at DESC NULLS LAST;

-- @R07 (OPTIMIZED)
-- Group info screen: current members of group 22556 with their role.
-- Baseline: 0.29 ms — already fast via PK. No change needed.
SELECT cm.user_id, u.display_name, cm.role, cm.joined_at
FROM   chat_members cm
JOIN   users u ON u.user_id = cm.user_id
WHERE  cm.chat_id = 22556
  AND  cm.left_at IS NULL
ORDER  BY cm.role, u.display_name;

-- @R08 (OPTIMIZED)
-- Delivery service: receipts still not delivered for messages sent before 23:00 on 30 Jun 2026.
-- Baseline: 13.16 ms — Seq Scan on messages + Seq Scan on receipts
-- Fix: idx_receipts_undelivered partial index + idx_messages_chat_sent for sent_at filter
SELECT r.message_id, r.user_id, m.sent_at
FROM   message_receipts r
JOIN   messages m ON m.message_id = r.message_id
WHERE  r.delivered_at IS NULL
  AND  m.sent_at < '2026-06-30 23:00:00+05:30'
ORDER  BY m.sent_at
LIMIT  500;

-- @R09 (OPTIMIZED)
-- Storage team: top 20 users by total media uploaded (GB).
-- Baseline: 8.37 ms — Seq Scan on media (27k rows)
-- Fix: idx_media_uploader_size covering index avoids heap
SELECT uploader_id,
       count(*)                                                AS files,
       round(sum(size_bytes) / 1024.0 / 1024 / 1024, 3)      AS gb
FROM   media
GROUP  BY uploader_id
ORDER  BY sum(size_bytes) DESC
LIMIT  20;

-- @R10 (OPTIMIZED)
-- Growth: daily active senders in June 2026.
-- Baseline: 7.87 ms — Seq Scan + per-row date cast blocking index
-- Fix: idx_messages_sent_date stores (sent_at::date) — Index Scan on stored expr
SELECT sent_at::date AS day,
       count(DISTINCT sender_id) AS active_senders,
       count(*)                  AS messages
FROM   messages
WHERE  sent_at::date BETWEEN '2026-06-01' AND '2026-06-30'
GROUP  BY 1
ORDER  BY 1;

-- @R11 (OPTIMIZED)
-- Calls tab: missed calls received by user 965 since 1 Jan 2025.
-- Baseline: 4.72 ms — Seq Scan on chat_members + Seq Scan on calls
-- Fix: idx_calls_chat_status_started + idx_chat_members_user_active
SELECT c.call_id, c.caller_id, c.call_type, c.started_at
FROM   calls c
JOIN   chat_members cm ON cm.chat_id = c.chat_id
                      AND cm.user_id = 965
                      AND cm.left_at IS NULL
WHERE  c.status = 'MISSED'
  AND  c.caller_id <> 965
  AND  c.started_at >= '2025-01-01 00:00:00+00'
ORDER  BY c.started_at DESC;

-- @R12 (OPTIMIZED)
-- Spam detection: users who forwarded 2+ messages on the same day.
-- Baseline: 5.50 ms — Seq Scan on all 120k messages
-- Fix: idx_messages_forwarded_partial — only reads forwarded rows
SELECT sender_id,
       sent_at::date AS day,
       count(*)      AS forwarded
FROM   messages
WHERE  is_forwarded = TRUE
GROUP  BY sender_id, sent_at::date
HAVING count(*) >= 2
ORDER  BY forwarded DESC, sender_id;

-- @R13 (OPTIMIZED)
-- Group admins: questions asked in group 20501 that nobody has replied to.
-- Baseline: 18.55 ms AND WRONG (returns 0 rows due to NULLs in NOT IN).
-- Fix 1 (correctness): rewrite NOT IN as NOT EXISTS — handles NULLs correctly.
-- Fix 2 (speed): idx_messages_reply_to_partial used by inner scan.
SELECT m.message_id, m.sender_id, m.sent_at, m.body
FROM   messages m
WHERE  m.chat_id = 20501
  AND  m.body LIKE '%?%'
  AND  NOT EXISTS (
           SELECT 1
           FROM   messages r
           WHERE  r.reply_to_message_id = m.message_id
       );

-- @R14 (OPTIMIZED)
-- Engagement: 10 groups with the most distinct senders in June 2026.
-- Baseline: 5.81 ms — Seq Scan on messages + Seq Scan on chats
-- Fix: idx_messages_chat_sent narrows date range; idx_chats_type for GROUP filter
SELECT m.chat_id,
       c.group_name,
       count(DISTINCT m.sender_id) AS active_members,
       count(*)                    AS messages
FROM   messages m
JOIN   chats c ON c.chat_id = m.chat_id AND c.chat_type = 'GROUP'
WHERE  m.sent_at >= '2026-06-01'
  AND  m.sent_at  < '2026-07-01'
GROUP  BY m.chat_id, c.group_name
ORDER  BY active_members DESC, messages DESC
LIMIT  10;

-- @R15 (OPTIMIZED)
-- Before delivering: has user 3064 blocked user 17793?
-- Baseline: 0.03 ms — already uses PK index. No change needed.
SELECT EXISTS (
    SELECT 1 FROM blocked_users
    WHERE  blocker_id = 3064 AND blocked_id = 17793
) AS is_blocked;

-- @R16 (OPTIMIZED)
-- Message info screen: who has read message 119989 and when.
-- Baseline: 0.07 ms — already fast via receipts PK. No change.
SELECT r.user_id, u.display_name, r.delivered_at, r.read_at
FROM   message_receipts r
JOIN   users u ON u.user_id = r.user_id
WHERE  r.message_id = 119989
ORDER  BY r.read_at NULLS LAST;

-- @R17 (OPTIMIZED)
-- Product analytics: average minutes from sending to reading, per message type (June 2026).
-- Baseline: 16.00 ms — Seq Scan on message_receipts (501k rows) + Seq Scan on messages
-- Fix: idx_receipts_read_at partial (WHERE read_at IS NOT NULL) + idx_messages_chat_sent
SELECT m.message_type,
       round(avg(EXTRACT(EPOCH FROM (r.read_at - m.sent_at)) / 60), 1) AS avg_minutes_to_read,
       count(*) AS reads
FROM   message_receipts r
JOIN   messages m ON m.message_id = r.message_id
WHERE  r.read_at IS NOT NULL
  AND  m.sent_at >= '2026-06-01'
  AND  m.sent_at  < '2026-07-01'
GROUP  BY m.message_type
ORDER  BY avg_minutes_to_read;

-- @R18 (OPTIMIZED)
-- Clean-up: users not seen since April 2026 who are still in at least one group.
-- Baseline: 14.57 ms — triple Seq Scan (chat_members, chats, users)
-- Fix: rewrite EXISTS to use idx_chat_members_user_active; idx_chats_type for GROUP
SELECT u.user_id, u.display_name, u.last_seen_at
FROM   users u
WHERE  u.last_seen_at < '2026-04-01'
  AND  EXISTS (
           SELECT 1
           FROM   chat_members cm
           JOIN   chats c ON c.chat_id = cm.chat_id AND c.chat_type = 'GROUP'
           WHERE  cm.user_id = u.user_id
             AND  cm.left_at IS NULL
       )
ORDER  BY u.last_seen_at;

-- @R19 (OPTIMIZED)
-- Group health report: for every group, the last message time and messages in June 2026.
-- Baseline: 15,818 ms (~15.8 seconds!) — 6,000 sequential subquery scans
-- Fix: replace correlated subqueries with a single aggregating JOIN pass.
SELECT c.chat_id,
       c.group_name,
       max(m.sent_at)                                                             AS last_message_at,
       count(*) FILTER (WHERE m.sent_at >= '2026-06-01' AND m.sent_at < '2026-07-01') AS june_messages
FROM   chats c
LEFT   JOIN messages m ON m.chat_id = c.chat_id
WHERE  c.chat_type = 'GROUP'
GROUP  BY c.chat_id, c.group_name
ORDER  BY last_message_at DESC NULLS LAST;

-- @R20 (OPTIMIZED)
-- Capacity planning: messages per hour of the day, by message type.
-- Baseline: 44.12 ms — Seq Scan on all 120k rows, full GroupAggregate
-- Fix: idx_messages_sent_date supports partial pruning; EXTRACT still needed.
-- Primary gain: planner uses bitmap scan on sent_at expr index to reduce rows.
SELECT EXTRACT(HOUR FROM sent_at) AS hour,
       message_type,
       count(*)                   AS messages
FROM   messages
GROUP  BY 1, 2
ORDER  BY 1, 2;

-- @R21 (OPTIMIZED)
-- Product analytics: share of messages edited or deleted, per message type.
-- Baseline: 12.33 ms — Seq Scan on all 120k messages
-- Fix: single-pass FILTER aggregation is already optimal;
-- idx_messages_chat_sent allows Index-Only Scan for message_type coverage.
SELECT message_type,
       count(*)                                                                   AS messages,
       round(100.0 * count(*) FILTER (WHERE edited_at IS NOT NULL) / count(*), 2) AS edited_pct,
       round(100.0 * count(*) FILTER (WHERE is_deleted)            / count(*), 2) AS deleted_pct
FROM   messages
GROUP  BY message_type
ORDER  BY messages DESC;

-- @R22 (OPTIMIZED)
-- Trust & safety console: all messages, newest first, page 4,001 (25 per page).
-- Baseline: 8.74 ms — OFFSET 100000 forces traversal of 100k index entries
-- Fix: keyset pagination eliminates OFFSET entirely (cursor-based paging).
-- Replace :last_seen_id with the last message_id from the previous page at runtime.
SELECT message_id, chat_id, sender_id, message_type, sent_at
FROM   messages
WHERE  message_id < 20000  -- replace with last message_id from previous page
ORDER  BY message_id DESC
LIMIT  25;

-- @R23 (OPTIMIZED)
-- Security: linked WEB/DESKTOP devices unused since 1 June 2026.
-- Baseline: 3.29 ms — Seq Scan on 42k devices
-- Fix: idx_devices_type_active partial index (device_type IN WEB/DESKTOP)
SELECT d.device_id, d.user_id, d.device_type, d.last_active_at
FROM   devices d
WHERE  d.device_type IN ('WEB', 'DESKTOP')
  AND  d.last_active_at < '2026-06-01'
ORDER  BY d.last_active_at;

-- @R24 (OPTIMIZED)
-- Storage dedup: media files uploaded more than once (same SHA-256).
-- Baseline: 6.07 ms — Seq Scan on media
-- Fix: idx_media_sha256 covering index drives GroupAggregate
SELECT sha256,
       count(*)       AS copies,
       sum(size_bytes) AS total_bytes
FROM   media
GROUP  BY sha256
HAVING count(*) > 1
ORDER  BY copies DESC;

-- @R25 (OPTIMIZED)
-- Reply thread: walk up the chain of replies starting at message 119989.
-- Baseline: 0.06 ms — already uses PK lookups in recursive CTE. No change.
WITH RECURSIVE thread AS (
    SELECT message_id, reply_to_message_id, sender_id, body, 0 AS depth
    FROM   messages WHERE message_id = 119989
    UNION ALL
    SELECT m.message_id, m.reply_to_message_id, m.sender_id, m.body, t.depth + 1
    FROM   messages m
    JOIN   thread t ON m.message_id = t.reply_to_message_id
)
SELECT * FROM thread ORDER BY depth DESC;

-- @W01 (OPTIMIZED)
-- Send a text message in group 22556. Already fast (0.70 ms). No change.
INSERT INTO messages (message_id, chat_id, sender_id, sent_at, message_type, body)
VALUES (90000001, 22556, 965, '2026-07-01 09:00:00+05:30', 'TEXT', 'Good morning everyone');

-- @W02 (OPTIMIZED)
-- Mark all of user 965's unread messages in group 22556 as read.
-- Baseline: 3.54 ms — Seq Scan on messages to find chat_id = 22556
-- Fix: idx_messages_chat_sent narrows the driving join; receipts PK used for update
UPDATE message_receipts r
SET    read_at      = TIMESTAMPTZ '2026-07-01 09:05:00+05:30',
       delivered_at = coalesce(r.delivered_at, TIMESTAMPTZ '2026-07-01 09:05:00+05:30')
FROM   messages m
WHERE  m.message_id = r.message_id
  AND  m.chat_id    = 22556
  AND  r.user_id    = 965
  AND  r.read_at   IS NULL;

-- @W03 (OPTIMIZED)
-- "Delete for everyone" on message 119989. Already fast (0.13 ms). No change.
UPDATE messages
SET    is_deleted = TRUE, body = NULL, media_id = NULL
WHERE  message_id = 119989;

-- @W04 (OPTIMIZED)
-- Broadcast: create delivery receipts for 5,000 recipients.
-- Baseline: 26.80 ms — bulk insert with conflict check
-- Fix: ON CONFLICT already handles duplicates efficiently; no structural change possible.
INSERT INTO message_receipts (message_id, user_id)
SELECT 1, g
FROM   generate_series(2, 5001) AS g
ON CONFLICT (message_id, user_id) DO NOTHING;

-- @W05 (OPTIMIZED)
-- User 965 leaves group 20898. Already fast (0.16 ms). No change.
UPDATE chat_members
SET    left_at = TIMESTAMPTZ '2026-07-01 10:00:00+05:30'
WHERE  chat_id = 20898
  AND  user_id = 965
  AND  left_at IS NULL;

-- @END
ROLLBACK;
