-- =====================================================================
-- WhatsApp Messaging Database: Phase 2 Data Ingestion Script
-- Course: Database Management Systems (DBMS)
-- Team: T0084
-- =====================================================================

SET search_path TO whatsapp;

-- Ingestion ordered strictly by Foreign Key dependencies (parents before children):
-- 1. users (Root entity)
\copy users FROM 'seed_data/users.csv' WITH (FORMAT csv, HEADER true);

-- 2. devices (Depends on users)
\copy devices FROM 'seed_data/devices.csv' WITH (FORMAT csv, HEADER true);

-- 3. chats (Depends on users for created_by)
\copy chats FROM 'seed_data/chats.csv' WITH (FORMAT csv, HEADER true);

-- 4. chat_members (Depends on chats and users)
\copy chat_members FROM 'seed_data/chat_members.csv' WITH (FORMAT csv, HEADER true);

-- 5. media (Depends on users for uploader_id)
\copy media FROM 'seed_data/media.csv' WITH (FORMAT csv, HEADER true);

-- 6. messages (Depends on chats, users, media, and self-references messages)
\copy messages FROM 'seed_data/messages.csv' WITH (FORMAT csv, HEADER true);

-- 7. message_receipts (Depends on messages and users)
\copy message_receipts FROM 'seed_data/message_receipts.csv' WITH (FORMAT csv, HEADER true);

-- 8. calls (Depends on chats and users)
\copy calls FROM 'seed_data/calls.csv' WITH (FORMAT csv, HEADER true);

-- 9. blocked_users (Depends on users for blocker_id and blocked_id)
\copy blocked_users FROM 'seed_data/blocked_users.csv' WITH (FORMAT csv, HEADER true);

-- Refresh optimizer statistics across the whatsapp schema
ANALYZE;

