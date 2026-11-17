# Phase 3: Baseline Query Performance & Plan Analysis

**Course:** Database Management Systems (DBMS)  
**Team Number:** T0084  
**Database:** PostgreSQL 18.6 (Apple M4, macOS)  
**Measurement Methodology:** 3 consecutive runs per query using `EXPLAIN (ANALYZE, BUFFERS)` executed via `./benchmarks/run_benchmark.sh`. Writes wrapped in transaction blocks (`BEGIN ... ROLLBACK`).  
**Dataset Scale:** `messages` (120,000 rows), `message_receipts` (501,590 rows), `media` (27,634 rows), `devices` (42,000 rows), `chats` / groups (3,000 rows).

---

## 1. Baseline Benchmark Execution Timings

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| **R01:** Chats screen: user 965's chats with the time and text of the latest message, newest first | READ | 27.161 | 17.003 | 15.733 | 19.966 |
| **R02:** Open a chat: the latest 50 messages of group 22556 | READ | 3.397 | 3.310 | 3.274 | 3.327 |
| **R03:** Badge counts: unread messages per chat for user 965 | READ | 9.600 | 6.901 | 6.931 | 7.811 |
| **R04:** Search: messages containing "meeting" in any chat user 965 belongs to | READ | 34.374 | 34.959 | 34.393 | 34.575 |
| **R05:** Registration: is this phone number already on WhatsApp? | READ | 0.376 | 0.025 | 0.022 | 0.141 |
| **R06:** Contact info: "last seen" of everyone user 965 chats with directly | READ | 2.642 | 2.704 | 2.719 | 2.688 |
| **R07:** Group info screen: current members of group 22556 with their role | READ | 0.651 | 0.113 | 0.114 | 0.293 |
| **R08:** Delivery service: receipts still not delivered for messages sent before 23:00 on 30 Jun 2026 | READ | 12.605 | 13.366 | 13.515 | 13.162 |
| **R09:** Storage team: top 20 users by total media uploaded (GB) | READ | 8.479 | 8.351 | 8.291 | 8.374 |
| **R10:** Growth: daily active senders in June 2026 | READ | 7.886 | 7.741 | 7.993 | 7.873 |
| **R11:** Calls tab: missed calls received by user 965 since 1 Jan 2025 | READ | 5.124 | 4.481 | 4.540 | 4.715 |
| **R12:** Spam detection: users who forwarded 2+ messages on the same day | READ | 5.399 | 5.591 | 5.515 | 5.502 |
| **R13:** Group admins: questions asked in group 20501 that nobody has replied to | READ | 18.336 | 18.674 | 18.651 | 18.554 |
| **R14:** Engagement: 10 groups with the most distinct senders in June 2026 | READ | 6.024 | 5.612 | 5.788 | 5.808 |
| **R15:** Before delivering: has user 3064 blocked user 17793? | READ | 0.029 | 0.024 | 0.025 | 0.026 |
| **R16:** Message info screen: who has read message 119989 and when | READ | 0.080 | 0.061 | 0.071 | 0.071 |
| **R17:** Product analytics: average minutes from sending to reading, per message type (June 2026) | READ | 15.900 | 16.413 | 15.676 | 15.996 |
| **R18:** Clean-up: users not seen since April 2026 who are still in at least one group | READ | 14.443 | 14.693 | 14.585 | 14.574 |
| **R19:** Group health report: for every group, the last message time and messages in June 2026 | READ | 15780.541 | 16107.386 | 15566.144 | **15818.024** |
| **R20:** Capacity planning: messages per hour of the day, by message type | READ | 44.427 | 44.017 | 43.928 | 44.124 |
| **R21:** Product analytics: share of messages edited or deleted, per message type | READ | 12.213 | 12.271 | 12.516 | 12.333 |
| **R22:** Trust & safety console: all messages, newest first, page 4,001 (25 per page) | READ | 8.800 | 8.727 | 8.679 | 8.735 |
| **R23:** Security: linked WEB/DESKTOP devices unused since 1 June 2026 (to auto log out) | READ | 3.501 | 3.214 | 3.142 | 3.286 |
| **R24:** Storage dedup: media files uploaded more than once (same SHA-256) | READ | 5.887 | 6.161 | 6.152 | 6.067 |
| **R25:** Reply thread: walk up the chain of replies starting at message 119989 | READ | 0.060 | 0.056 | 0.058 | 0.058 |
| **W01:** Send a text message in group 22556 | WRITE | 1.162 | 0.481 | 0.464 | 0.702 |
| **W02:** Open chat: mark all of user 965's unread messages in group 22556 as read | WRITE | 3.836 | 3.374 | 3.399 | 3.536 |
| **W03:** "Delete for everyone" on message 119989 | WRITE | 0.150 | 0.121 | 0.120 | 0.130 |
| **W04:** Broadcast: create delivery receipts for 5,000 recipients of a business announcement | WRITE | 26.371 | 27.530 | 26.511 | 26.804 |
| **W05:** User 965 leaves group 20898 | WRITE | 0.192 | 0.149 | 0.141 | 0.161 |
| **Total (sum of all 30)** | | **16059.647** | **16373.508** | **15829.091** | **16087.415** |

---

## 2. Scan Types & Execution Bottleneck Analysis

| Query | Dominant Scan Types | Performance Explanation & Diagnosis |
|---|---|---|
| **R01** | `Seq Scan on chat_members`, `Seq Scan on messages` | **Slow (19.97 ms):** Lacks composite index on `chat_members(user_id, left_at)` and `messages(chat_id, sent_at DESC)`. Executes lateral sequential subscans per chat. |
| **R02** | `Seq Scan on messages` | **Moderately Slow (3.33 ms):** Full sequential scan of all 120,000 messages to extract 50 rows for group 22556; will balloon to hundreds of ms on large data. |
| **R03** | `Seq Scan on message_receipts` | **Slow (7.81 ms):** Scans all 501,590 receipts sequentially because the PK is `(message_id, user_id)` and cannot be used for `WHERE user_id = 965`. |
| **R04** | `Seq Scan on messages`, `Seq Scan on chat_members` | **Very Slow (34.58 ms):** Full table scan across 120k messages testing `ILIKE '%meeting%'` via regex string matching without trigram index support. |
| **R05** | `Index Scan using users_phone_e164_key` | **Extremely Fast (0.14 ms):** Utilizes the automatic B-tree index generated by the `UNIQUE` constraint on `phone_e164`. |
| **R06** | `Seq Scan on chat_members`, `Index Scan on chats` | **Slow for Real-Time (2.69 ms):** Finds direct chats via sequential scan on `chat_members` filtering on `user_id = 965`. |
| **R07** | `Index Scan using chat_members_pkey` | **Fast (0.29 ms):** Hits the leading column `chat_id` in composite PK `(chat_id, user_id)`. |
| **R08** | `Seq Scan on messages`, `Seq Scan on message_receipts` | **Slow (13.16 ms):** Joins two unindexed tables sequentially to discover rare undelivered receipts (`delivered_at IS NULL`). |
| **R09** | `Seq Scan on media` | **Slow (8.37 ms):** Reads all 27,634 rows of `media` and computes HashAggregate grouping by `uploader_id`. |
| **R10** | `Seq Scan on messages` | **Slow (7.87 ms):** Computes `sent_at::date` across 120k rows inside `WHERE` clause, preventing index range scan usage. |
| **R11** | `Seq Scan on chat_members`, `Seq Scan on calls` | **Slow (4.72 ms):** Lacks composite index on `calls(chat_id, status, caller_id, started_at)`. |
| **R12** | `Seq Scan on messages` | **Slow (5.50 ms):** Scans entire `messages` table filtering on `is_forwarded = TRUE` followed by date-casting aggregation. |
| **R13** | `Seq Scan on messages` | **Slow (18.55 ms) & WRONG RESULT:** Scans `messages` table twice. Returns **0 rows** because `reply_to_message_id` contains `NULL`s, breaking SQL three-valued logic. |
| **R14** | `Seq Scan on messages`, `Seq Scan on chats` | **Slow (5.81 ms):** Full message scan over date range followed by grouping and joins. |
| **R15** | `Index Only Scan using blocked_users_pkey` | **Extremely Fast (0.03 ms):** Covered entirely by composite primary key index `(blocker_id, blocked_id)`. |
| **R16** | `Index Scan using message_receipts_pkey` | **Fast (0.07 ms):** Leading column `message_id` in PK `(message_id, user_id)` satisfies lookup directly. |
| **R17** | `Seq Scan on message_receipts`, `Seq Scan on messages` | **Slow (16.00 ms):** Full hash join of 501,590 receipts against messages within June 2026 date bounds. |
| **R18** | `Seq Scan on chat_members`, `Seq Scan on chats`, `Seq Scan on users` | **Slow (14.57 ms):** Triple full table scan to evaluate correlated `EXISTS` subquery. |
| **R19** | `Seq Scan on chats`, `Seq Scan on messages` | **Catastrophically Slow (15818.02 ms / ~15.8 sec):** For all 3,000 group chats, it runs **two full sequential scans** across 120,000 messages (6,000 table scans total!). |
| **R20** | `Seq Scan on messages` | **Slow (44.12 ms):** Computes `EXTRACT(HOUR FROM sent_at)` across 120,000 rows followed by high-cardinality grouping. |
| **R21** | `Seq Scan on messages` | **Slow (12.33 ms):** Reads all rows to calculate conditional filters `FILTER (WHERE edited_at IS NOT NULL)`. |
| **R22** | `Index Scan using messages_pkey on messages` | **Slow (8.74 ms):** Uses PK index backward but must traverse and discard 100,000 index tuples due to `OFFSET 100000`. |
| **R23** | `Seq Scan on devices` | **Slow (3.29 ms):** Scans all 42,000 devices filtering by `device_type IN ('WEB', 'DESKTOP')` and timestamp. |
| **R24** | `Seq Scan on media` | **Slow (6.07 ms):** Reads entire `media` table to aggregate on `sha256`. |
| **R25** | `Index Scan using messages_pkey on messages` | **Fast (0.06 ms):** Recursive CTE navigates hierarchy using PK index lookups at each depth level. |
| **W01** | `(no scan)` | **Fast (0.70 ms):** Single tuple insertion with PK validation. |
| **W02** | `Seq Scan on messages`, `Index Scan on receipts` | **Slow for Write (3.54 ms):** Performs sequential scan on `messages` to find messages in chat 22556 before updating receipts. |
| **W03** | `Index Scan using messages_pkey` | **Fast (0.13 ms):** Direct PK update of single record. |
| **W04** | `(no scan)` | **Slow (26.80 ms):** Bulk insertion of 5,000 rows into `message_receipts` with conflict checking. |
| **W05** | `Index Scan using chat_members_pkey` | **Fast (0.16 ms):** Target row found directly via composite PK index. |