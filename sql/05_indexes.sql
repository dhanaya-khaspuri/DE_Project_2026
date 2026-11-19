-- =====================================================================
-- WhatsApp Messaging Database: Phase 3 — Index Creation
-- Course: Database Management Systems (DBMS)
-- Team: T0084 (Dhanaya Khaspuri, Mahika Garg, Ishan Bansal, Saumya Madan)
-- Engine: PostgreSQL 18.6
--
-- Purpose: Add secondary indexes to accelerate the 30-query workload.
--          Run AFTER sql/01_schema.sql and sql/02_load_data.sql.
--          Safe to re-run: each index is created with IF NOT EXISTS.
-- =====================================================================

SET search_path TO whatsapp;

-- =====================================================================
-- messages — the largest and most-scanned table (120,000 rows)
-- =====================================================================

-- R01, R02: fast per-chat timeline lookup (chat_id → sent_at DESC)
-- Covering INCLUDE avoids heap fetch for body and reply_to_message_id.
CREATE INDEX IF NOT EXISTS idx_messages_chat_sent
    ON messages (chat_id, sent_at DESC)
    INCLUDE (message_id, sender_id, message_type, body, reply_to_message_id);

-- R10, R14, R17, R20, R21: sent_at range scans with date casting
-- Storing the extracted date eliminates per-row cast in WHERE / GROUP BY.
CREATE INDEX IF NOT EXISTS idx_messages_sent_date
    ON messages ((sent_at::date));

-- R12: partial index — only forwarded messages (~small fraction)
CREATE INDEX IF NOT EXISTS idx_messages_forwarded_partial
    ON messages (sender_id, (sent_at::date))
    WHERE is_forwarded = TRUE;

-- R13: fix the NULL bug in NOT IN by indexing reply_to_message_id
-- Partial index excludes the vast majority of non-reply rows.
CREATE INDEX IF NOT EXISTS idx_messages_reply_to_partial
    ON messages (reply_to_message_id)
    WHERE reply_to_message_id IS NOT NULL;

-- R18: fast per-sender lookup (used in EXISTS subquery rewrite)
CREATE INDEX IF NOT EXISTS idx_messages_sender
    ON messages (sender_id);

-- R19: covers the two correlated subqueries on chats — max(sent_at)
-- and count(*) for June 2026. Single index replaces 6,000 seq scans.
CREATE INDEX IF NOT EXISTS idx_messages_chat_sent_asc
    ON messages (chat_id, sent_at);

-- W02: UPDATE receipts needs chat_id on messages (join side)
-- idx_messages_chat_sent already covers this — no duplicate needed.

-- =====================================================================
-- message_receipts — largest table (501,590 rows)
-- PK is (message_id, user_id); no index exists on user_id alone.
-- =====================================================================

-- R03: badge counts — WHERE user_id = 965 AND read_at IS NULL
-- Partial index keeps it small (only unread rows).
CREATE INDEX IF NOT EXISTS idx_receipts_user_unread
    ON message_receipts (user_id, message_id)
    WHERE read_at IS NULL;

-- R08: WHERE delivered_at IS NULL — partial index on undelivered
CREATE INDEX IF NOT EXISTS idx_receipts_undelivered
    ON message_receipts (message_id, user_id)
    WHERE delivered_at IS NULL;

-- R17: read_at range join (June 2026) — covering on user side
CREATE INDEX IF NOT EXISTS idx_receipts_read_at
    ON message_receipts (read_at)
    INCLUDE (message_id, user_id)
    WHERE read_at IS NOT NULL;

-- =====================================================================
-- chat_members — R01, R03, R06, R11, R18, W02, W05
-- PK is (chat_id, user_id) — good for chat lookups.
-- Need reverse index for user_id lookups.
-- =====================================================================

-- R01, R03, R06, R18: user_id → chats (inbox, badge, contact info)
-- Partial index: only current members (left_at IS NULL)
CREATE INDEX IF NOT EXISTS idx_chat_members_user_active
    ON chat_members (user_id)
    INCLUDE (chat_id, role)
    WHERE left_at IS NULL;

-- R06: needs chat_type from chats; index on chat_members user side
-- already covered above. Add index to filter DIRECT chats via chats.
-- (chats.chat_type is covered by chats_pkey lookup; no extra index needed)

-- =====================================================================
-- chats — R06, R14, R19
-- =====================================================================

-- R14, R19: filter WHERE chat_type = 'GROUP'
CREATE INDEX IF NOT EXISTS idx_chats_type
    ON chats (chat_type)
    INCLUDE (chat_id, group_name);

-- =====================================================================
-- calls — R11
-- =====================================================================

-- R11: WHERE status = 'MISSED' AND caller_id <> 965 AND started_at >= 2025
CREATE INDEX IF NOT EXISTS idx_calls_chat_status_started
    ON calls (chat_id, status, started_at DESC)
    INCLUDE (call_id, caller_id, call_type);

-- =====================================================================
-- devices — R23
-- =====================================================================

-- R23: WHERE device_type IN ('WEB','DESKTOP') AND last_active_at < '2026-06-01'
CREATE INDEX IF NOT EXISTS idx_devices_type_active
    ON devices (device_type, last_active_at)
    WHERE device_type IN ('WEB', 'DESKTOP');

-- =====================================================================
-- media — R09, R24
-- =====================================================================

-- R09: GROUP BY uploader_id — covering index avoids heap
CREATE INDEX IF NOT EXISTS idx_media_uploader_size
    ON media (uploader_id)
    INCLUDE (size_bytes);

-- R24: GROUP BY sha256 HAVING count(*) > 1
CREATE INDEX IF NOT EXISTS idx_media_sha256
    ON media (sha256)
    INCLUDE (size_bytes);

-- =====================================================================
-- Refresh planner statistics so the new indexes are used immediately
-- =====================================================================
ANALYZE messages;
ANALYZE message_receipts;
ANALYZE chat_members;
ANALYZE chats;
ANALYZE calls;
ANALYZE devices;
ANALYZE media;
