-- =====================================================================
-- WhatsApp Messaging Database: Phase 2 Database Schema
-- Course: Database Management Systems (DBMS)
-- Team: T0084 (Dhanaya Khaspuri, Mahika Garg, Ishan Bansal, Saumya Madan)
-- Engine: PostgreSQL 15+ (Tested on PostgreSQL 18.6)
--
-- Rules:
-- 1. Tables created in schema 'whatsapp'
-- 2. Constraints only: PK, FK, UNIQUE, NOT NULL, CHECK (>= 12 checks)
-- 3. NO secondary indexes created here (clean baseline for Phase 3)
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS whatsapp;
SET search_path TO whatsapp;

-- Clean drop of existing tables for reproducible execution
DROP TABLE IF EXISTS blocked_users CASCADE;
DROP TABLE IF EXISTS calls CASCADE;
DROP TABLE IF EXISTS message_receipts CASCADE;
DROP TABLE IF EXISTS messages CASCADE;
DROP TABLE IF EXISTS media CASCADE;
DROP TABLE IF EXISTS chat_members CASCADE;
DROP TABLE IF EXISTS chats CASCADE;
DROP TABLE IF EXISTS devices CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- ---------------------------------------------------------------------
-- 1. USERS
-- ---------------------------------------------------------------------
CREATE TABLE users (
    user_id       BIGINT PRIMARY KEY,
    phone_e164    VARCHAR(20) NOT NULL UNIQUE,
    display_name  VARCHAR(255) NOT NULL,
    about         TEXT,
    is_business   BOOLEAN NOT NULL DEFAULT FALSE,
    joined_on     DATE NOT NULL,
    last_seen_at  TIMESTAMPTZ,
    status        VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',

    CONSTRAINT chk_users_phone_format 
        CHECK (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
    CONSTRAINT chk_users_status 
        CHECK (status IN ('ACTIVE', 'BANNED', 'DELETED')),
    CONSTRAINT chk_users_last_seen_order 
        CHECK (last_seen_at IS NULL OR last_seen_at >= (joined_on::timestamptz))
);

-- ---------------------------------------------------------------------
-- 2. DEVICES
-- ---------------------------------------------------------------------
CREATE TABLE devices (
    device_id       BIGINT PRIMARY KEY,
    user_id         BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    device_type     VARCHAR(20) NOT NULL,
    app_version     VARCHAR(30) NOT NULL,
    registered_at   TIMESTAMPTZ NOT NULL,
    last_active_at  TIMESTAMPTZ NOT NULL,

    CONSTRAINT chk_devices_type 
        CHECK (device_type IN ('ANDROID', 'IOS', 'WEB', 'DESKTOP')),
    CONSTRAINT chk_devices_active_order 
        CHECK (last_active_at >= registered_at),
    CONSTRAINT chk_devices_version_format 
        CHECK (app_version ~ '^[0-9]+(\.[0-9]+)+$')
);

-- ---------------------------------------------------------------------
-- 3. CHATS
-- ---------------------------------------------------------------------
CREATE TABLE chats (
    chat_id     BIGINT PRIMARY KEY,
    chat_type   VARCHAR(10) NOT NULL,
    group_name  VARCHAR(255),
    created_by  BIGINT NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    created_at  TIMESTAMPTZ NOT NULL,

    CONSTRAINT chk_chats_type 
        CHECK (chat_type IN ('DIRECT', 'GROUP')),
    CONSTRAINT chk_chats_group_name_coherence 
        CHECK (
            (chat_type = 'DIRECT' AND group_name IS NULL) OR 
            (chat_type = 'GROUP'  AND group_name IS NOT NULL AND length(trim(group_name)) > 0)
        )
);

-- ---------------------------------------------------------------------
-- 4. CHAT_MEMBERS
-- ---------------------------------------------------------------------
CREATE TABLE chat_members (
    chat_id   BIGINT NOT NULL REFERENCES chats(chat_id) ON DELETE CASCADE,
    user_id   BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    role      VARCHAR(20) NOT NULL DEFAULT 'MEMBER',
    joined_at TIMESTAMPTZ NOT NULL,
    left_at   TIMESTAMPTZ,
    is_muted  BOOLEAN NOT NULL DEFAULT FALSE,

    PRIMARY KEY (chat_id, user_id),
    CONSTRAINT chk_chat_members_role 
        CHECK (role IN ('ADMIN', 'MEMBER')),
    CONSTRAINT chk_chat_members_membership_order 
        CHECK (left_at IS NULL OR left_at >= joined_at)
);

-- ---------------------------------------------------------------------
-- 5. MEDIA
-- ---------------------------------------------------------------------
CREATE TABLE media (
    media_id     BIGINT PRIMARY KEY,
    uploader_id  BIGINT NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    media_type   VARCHAR(20) NOT NULL,
    mime_type    VARCHAR(100) NOT NULL,
    size_bytes   BIGINT NOT NULL,
    sha256       CHAR(64) NOT NULL,
    uploaded_at  TIMESTAMPTZ NOT NULL,

    CONSTRAINT chk_media_type 
        CHECK (media_type IN ('IMAGE', 'VIDEO', 'AUDIO', 'DOCUMENT')),
    CONSTRAINT chk_media_positive_size 
        CHECK (size_bytes > 0),
    CONSTRAINT chk_media_sha256_format 
        CHECK (sha256 ~ '^[0-9a-f]{64}$')
);

-- ---------------------------------------------------------------------
-- 6. MESSAGES
-- ---------------------------------------------------------------------
CREATE TABLE messages (
    message_id           BIGINT PRIMARY KEY,
    chat_id              BIGINT NOT NULL REFERENCES chats(chat_id) ON DELETE CASCADE,
    sender_id            BIGINT NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    sent_at              TIMESTAMPTZ NOT NULL,
    message_type         VARCHAR(20) NOT NULL,
    body                 TEXT,
    media_id             BIGINT REFERENCES media(media_id) ON DELETE SET NULL,
    reply_to_message_id  BIGINT REFERENCES messages(message_id) ON DELETE SET NULL,
    is_forwarded         BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted           BOOLEAN NOT NULL DEFAULT FALSE,
    edited_at            TIMESTAMPTZ,

    CONSTRAINT chk_messages_type 
        CHECK (message_type IN ('TEXT', 'IMAGE', 'VIDEO', 'AUDIO', 'DOCUMENT', 'LOCATION')),
    CONSTRAINT chk_messages_edit_order 
        CHECK (edited_at IS NULL OR edited_at >= sent_at),
    CONSTRAINT chk_messages_no_self_reply 
        CHECK (reply_to_message_id IS NULL OR reply_to_message_id <> message_id),
    CONSTRAINT chk_messages_deleted_content_scrubbed 
        CHECK (is_deleted = FALSE OR (body IS NULL AND media_id IS NULL))
);

-- ---------------------------------------------------------------------
-- 7. MESSAGE_RECEIPTS
-- ---------------------------------------------------------------------
CREATE TABLE message_receipts (
    message_id    BIGINT NOT NULL REFERENCES messages(message_id) ON DELETE CASCADE,
    user_id       BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    delivered_at  TIMESTAMPTZ,
    read_at       TIMESTAMPTZ,

    PRIMARY KEY (message_id, user_id),
    CONSTRAINT chk_message_receipts_delivery_order 
        CHECK (delivered_at IS NULL OR read_at IS NULL OR read_at >= delivered_at)
);

-- ---------------------------------------------------------------------
-- 8. CALLS
-- ---------------------------------------------------------------------
CREATE TABLE calls (
    call_id      BIGINT PRIMARY KEY,
    chat_id      BIGINT NOT NULL REFERENCES chats(chat_id) ON DELETE CASCADE,
    caller_id    BIGINT NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    call_type    VARCHAR(20) NOT NULL,
    started_at   TIMESTAMPTZ NOT NULL,
    answered_at  TIMESTAMPTZ,
    ended_at     TIMESTAMPTZ,
    status       VARCHAR(20) NOT NULL,

    CONSTRAINT chk_calls_type 
        CHECK (call_type IN ('VOICE', 'VIDEO')),
    CONSTRAINT chk_calls_status 
        CHECK (status IN ('COMPLETED', 'MISSED', 'REJECTED', 'FAILED')),
    CONSTRAINT chk_calls_time_sequence 
        CHECK (
            (answered_at IS NULL OR answered_at >= started_at) AND
            (ended_at IS NULL OR (ended_at >= started_at AND (answered_at IS NULL OR ended_at >= answered_at)))
        )
);

-- ---------------------------------------------------------------------
-- 9. BLOCKED_USERS
-- ---------------------------------------------------------------------
CREATE TABLE blocked_users (
    blocker_id  BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    blocked_id  BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    blocked_at  TIMESTAMPTZ NOT NULL,

    PRIMARY KEY (blocker_id, blocked_id),
    CONSTRAINT chk_blocked_users_no_self_block 
        CHECK (blocker_id <> blocked_id)
);

