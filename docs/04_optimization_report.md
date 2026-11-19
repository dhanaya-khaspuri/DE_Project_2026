# Phase 4: Query Optimization Report

**Course:** Database Management Systems (DBMS)  
**Team Number:** T0084  
**Team Members:** Dhanaya Khaspuri (Lead), Mahika Garg, Ishan Bansal, Saumya Madan  
**Database:** PostgreSQL 18.6 (Apple M4, macOS)  
**Measurement Methodology:** 3 consecutive runs per query via `./benchmarks/run_benchmark.sh`, average reported. Baseline figures come from `docs/03_baseline_timings.md`. Optimized figures marked `~` are estimates from the plan analysis and are to be confirmed with `benchmarks/results/optimized/summary.csv`.  
**Dataset Scale:** `messages` (120,000 rows), `message_receipts` (501,590 rows), `media` (27,634 rows), `devices` (42,000 rows), `chats` / groups (3,000 rows).

---

## 1. Optimization Strategy Overview

Four complementary techniques were applied, chosen by studying the `EXPLAIN (ANALYZE, BUFFERS)` plans from the Phase 3 baseline:

| Technique | Queries fixed | Principle |
|---|---|---|
| Targeted B-Tree indexes | R02, R07, R09, R15, R16, R23, R24 | Avoid full table scans on lookup columns not covered by existing primary keys |
| Partial indexes | R03, R08, R12, R13 | Index only the qualifying subset of rows: tiny size, maximum selectivity |
| Covering indexes (`INCLUDE`) | R01, R06, R09 | Satisfy the query entirely from the index and avoid heap fetches |
| Query rewrite | R10, R13, R18, R19, R22 | Replace non-sargable predicates, `NOT IN`, correlated subqueries and `OFFSET` with set-based, range or keyset patterns |

---

## 2. Per-Query Optimization Detail

### R01: Chats Screen (19.97 ms → ~1.5 ms estimated)

**Problem:** Seq Scan on `chat_members` to find user 965's chats, then a Seq Scan on `messages` inside each `LATERAL`.  
**Fix:** `idx_chat_members_user_active (user_id) WHERE left_at IS NULL` turns the inbox lookup into a tiny index scan. `idx_messages_chat_sent (chat_id, sent_at DESC) INCLUDE (body, ...)` makes each `LATERAL` a 1-row index fetch.

### R03: Badge Counts (7.81 ms → ~0.8 ms estimated)

**Problem:** 501,590-row Seq Scan on `message_receipts` to find `user_id = 965 AND read_at IS NULL`.  
**Fix:** `idx_receipts_user_unread (user_id, message_id) WHERE read_at IS NULL`. This partial index contains only unread rows, so the scan drops from 501k rows to a few hundred.

### R04: Message Search (34.58 ms → ~18 ms estimated)

**Problem:** `ILIKE '%meeting%'` must inspect every message body. A B-Tree cannot answer a leading-wildcard pattern.  
**Fix applied:** restrict the scan to the user's own chats first (`IN (SELECT chat_id FROM chat_members WHERE user_id = 965)`), reducing rows from 120k to the user's subset.  
**Further improvement (planned for CP4):** a `pg_trgm` GIN index on `messages(body)` would remove the full scan entirely.

### R08: Undelivered Receipts (13.16 ms → ~1.2 ms estimated)

**Problem:** Seq Scans on both `messages` and `message_receipts` to find rare undelivered rows.  
**Fix:** `idx_receipts_undelivered (message_id, user_id) WHERE delivered_at IS NULL`. This partial index covers only the ~5,076 undelivered rows.

### R10: Daily Active Senders (7.87 ms → ~3.0 ms estimated)

**Problem:** the filter `sent_at::date BETWEEN ...` applies a cast to the column, so the planner cannot use an index range scan and falls back to a Seq Scan.  
**Fix:** rewrite the filter as a half-open range on the raw column: `sent_at >= '2026-06-01' AND sent_at < '2026-07-01'`, supported by `idx_messages_sent_at (sent_at)`. The result is the same, but the predicate is now index-friendly.

> **Why not an index on `(sent_at::date)`?** In PostgreSQL, casting `timestamptz` to `date` depends on the session time zone, so it is not `IMMUTABLE` and cannot be used in an index expression. Rewriting the query is the correct fix.

### R12: Spam Detection (5.50 ms → ~0.4 ms estimated)

**Problem:** Seq Scan on 120k messages to find `is_forwarded = TRUE`.  
**Fix:** `idx_messages_forwarded_partial (sender_id, sent_at) WHERE is_forwarded`. This partial index holds only forwarded messages (a small fraction of the table) and supports both the filter and the grouping by sender.

### R13: Unanswered Questions (18.55 ms, returned a WRONG result → ~2.0 ms, CORRECT)

**Problem (correctness):** `NOT IN (SELECT reply_to_message_id FROM messages r)` returns 0 rows because `reply_to_message_id` contains NULLs. With SQL three-valued logic, `x NOT IN (..., NULL, ...)` evaluates to UNKNOWN, which suppresses every row.  
**Fix:** rewritten as `NOT EXISTS (SELECT 1 FROM messages r WHERE r.reply_to_message_id = m.message_id)`, which handles NULLs correctly, and supported by `idx_messages_reply_to_partial`.

### R19: Group Health Report (15,818 ms → ~12 ms estimated)

**Problem:** for each of the 3,000 groups, two correlated subqueries each do a full Seq Scan on 120k messages, which is 6,000 sequential scans.  
**Fix:** replace both with a single `LEFT JOIN` on a `messages ... GROUP BY chat_id` subquery using a `FILTER` clause, with `idx_messages_chat_sent_asc (chat_id, sent_at)` supporting it. One pass over `messages` instead of 6,000.

### R22: Trust & Safety Paging (8.74 ms → ~0.1 ms estimated)

**Problem:** `OFFSET 100000` forces the planner to traverse and discard 100,000 index entries before returning 25 rows.  
**Fix:** keyset (cursor) pagination: `WHERE message_id < :last_seen_id ORDER BY message_id DESC LIMIT 25`. The primary-key index jumps directly to the right position.

---

## 3. Baseline vs Optimized Timings

| Query | Baseline avg (ms) | Optimized avg (ms) | Speedup | Primary technique |
|---|---:|---:|---:|---|
| R01 | 19.97 | ~1.50 | ~13× | Covering index on messages + partial index on chat_members |
| R02 | 3.33 | ~0.40 | ~8.3× | `idx_messages_chat_sent` |
| R03 | 7.81 | ~0.80 | ~9.8× | Partial index on message_receipts |
| R04 | 34.58 | ~18.00 | ~1.9× | Subquery pre-filter (trigram GIN index planned for CP4) |
| R05 | 0.14 | 0.14 | 1× | Already optimal |
| R06 | 2.69 | ~0.60 | ~4.5× | `idx_chat_members_user_active` |
| R07 | 0.29 | 0.29 | 1× | Already optimal |
| R08 | 13.16 | ~1.20 | ~11× | Partial index on undelivered receipts |
| R09 | 8.37 | ~1.00 | ~8.4× | Covering index on media |
| R10 | 7.87 | ~3.00 | ~2.6× | Query rewrite to a date range on `sent_at` + `idx_messages_sent_at` |
| R11 | 4.72 | ~0.80 | ~5.9× | `idx_calls_chat_status_started` |
| R12 | 5.50 | ~0.40 | ~14× | Partial index on forwarded messages |
| R13 | 18.55 | ~2.00 | ~9.3× | Query rewrite (NOT EXISTS) + partial index |
| R14 | 5.81 | ~1.50 | ~3.9× | `idx_messages_chat_sent` + `idx_chats_type` |
| R15 | 0.03 | 0.03 | 1× | Already optimal |
| R16 | 0.07 | 0.07 | 1× | Already optimal |
| R17 | 16.00 | ~2.50 | ~6.4× | Partial covering index on `read_at` |
| R18 | 14.57 | ~2.00 | ~7.3× | Query rewrite + `idx_chat_members_user_active` |
| R19 | 15,818.02 | ~12.00 | ~1,318× | Query rewrite: correlated subqueries → single JOIN |
| R20 | 44.12 | 44.12 | 1× | Full-table aggregate; scan unavoidable |
| R21 | 12.33 | ~10.00 | ~1.2× | FILTER aggregation already close to optimal |
| R22 | 8.74 | ~0.10 | ~87× | Keyset pagination replaces OFFSET |
| R23 | 3.29 | ~0.20 | ~16× | Partial index on WEB/DESKTOP devices |
| R24 | 6.07 | ~0.80 | ~7.6× | `idx_media_sha256` covering index |
| R25 | 0.06 | 0.06 | 1× | Already optimal |
| W01 | 0.70 | 0.70 | 1× | Already optimal |
| W02 | 3.54 | ~0.90 | ~3.9× | `idx_messages_chat_sent` narrows join |
| W03 | 0.13 | 0.13 | 1× | Already optimal |
| W04 | 26.80 | ~24.00 | ~1.1× | Bulk insert limit, structurally bounded |
| W05 | 0.16 | 0.16 | 1× | Already optimal |
| **Total** | **16,087.42** | **~129** | **~124×** | |

---

## 4. Index Summary

| Index name | Table | Columns | Type | Benefits |
|---|---|---|---|---|
| `idx_messages_chat_sent` | messages | `(chat_id, sent_at DESC) INCLUDE (body)` | B-Tree, covering | R01, R02, R14, W02 |
| `idx_messages_sent_at` | messages | `(sent_at)` | B-Tree | R10 |
| `idx_messages_forwarded_partial` | messages | `(sender_id, sent_at) WHERE is_forwarded` | Partial | R12 |
| `idx_messages_reply_to_partial` | messages | `(reply_to_message_id) WHERE reply_to_message_id IS NOT NULL` | Partial | R13 |
| `idx_messages_sender` | messages | `(sender_id)` | B-Tree | R18 |
| `idx_messages_chat_sent_asc` | messages | `(chat_id, sent_at)` | B-Tree | R19 |
| `idx_receipts_user_unread` | message_receipts | `(user_id, message_id) WHERE read_at IS NULL` | Partial | R03 |
| `idx_receipts_undelivered` | message_receipts | `(message_id, user_id) WHERE delivered_at IS NULL` | Partial | R08 |
| `idx_receipts_read_at` | message_receipts | `(read_at) INCLUDE (...) WHERE read_at IS NOT NULL` | Partial, covering | R17 |
| `idx_chat_members_user_active` | chat_members | `(user_id) INCLUDE (chat_id) WHERE left_at IS NULL` | Partial, covering | R01, R03, R06, R11, R18 |
| `idx_chats_type` | chats | `(chat_type) INCLUDE (...)` | B-Tree | R14, R18, R19 |
| `idx_calls_chat_status_started` | calls | `(chat_id, status, started_at DESC)` | B-Tree | R11 |
| `idx_devices_type_active` | devices | `(device_type, last_active_at) WHERE device_type IN ('WEB','DESKTOP')` | Partial | R23 |
| `idx_media_uploader_size` | media | `(uploader_id) INCLUDE (size_bytes)` | Covering | R09 |
| `idx_media_sha256` | media | `(sha256) INCLUDE (size_bytes)` | Covering | R24 |

---

## 5. Key Correctness Fix

**R13 returned 0 rows at baseline, a silent data correctness bug.**

The original query used `NOT IN (SELECT reply_to_message_id FROM messages)`. Because `reply_to_message_id` is nullable, the subquery result contains NULLs. SQL evaluates `x NOT IN (..., NULL, ...)` as UNKNOWN (not TRUE), so every row is filtered out.

The fix rewrites it as `NOT EXISTS`, which checks the correlated predicate row by row and treats NULLs as "no match found", returning the correct set of unanswered questions.

---

## 6. Conclusion

The dominant bottleneck was **R19 (15.8 seconds)**, caused by 6,000 correlated subquery executions. A single query rewrite supported by one composite index reduces it to roughly 12 ms, the largest single gain. Combined with partial indexes on `message_receipts` (the largest table) and covering indexes on `messages`, the total workload time drops from about 16,087 ms to about 129 ms, an overall improvement of roughly 124×. The remaining slow items (R04, R20, W04) are bounded by full-table work and are noted for CP4.
