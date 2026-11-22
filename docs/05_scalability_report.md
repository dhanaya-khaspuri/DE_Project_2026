# Phase 5: Scalability Architecture & Large Dataset Report

**Course:** Database Management Systems (DBMS)  
**Team Number:** T0084  
**Team Members:** Dhanaya Khaspuri, Mahika Garg, Ishan Bansal, Saumya Madan  
**Database:** PostgreSQL 18.6 (Apple M4, macOS)  
**Cluster:** WhatsApp Message Store (India Region)

---

## 1. Large Dataset Scalability Benchmark Results

The 30 workload queries were benchmarked on the large dataset (20× data volume: ~2,400,000 messages, ~10,032,000 receipts, ~600,000 users, ~460,000 chats). All runs were executed using `EXPLAIN (ANALYZE, BUFFERS)` with 3 consecutive runs per query:

| Query | Optimized on Seed (ms) | Optimized on Large (ms) | Growth (Large ÷ Seed) | Target SLA | Meets Target? | Scalability Classification |
|---|---:|---:|---:|---:|:---:|---|
| **R01** | 1.482 | 1.704 | 1.15× | < 5 ms | ✅ Yes | $\mathcal{O}(\log N)$ B-tree index probe |
| **R02** | 0.391 | 0.438 | 1.12× | < 5 ms | ✅ Yes | $\mathcal{O}(\log N)$ index seek + top-N limit |
| **R03** | 0.823 | 0.971 | 1.18× | < 5 ms | ✅ Yes | $\mathcal{O}(\log N)$ partial index on unread |
| **R04** | 18.102 | 22.628 | 1.25× | < 250 ms | ✅ Yes | $\mathcal{O}(\log N)$ GIN trigram substring seek |
| **R05** | 0.138 | 0.145 | 1.05× | < 5 ms | ✅ Yes | $\mathcal{O}(1)$ Unique phone index lookup |
| **R06** | 0.614 | 0.737 | 1.20× | < 5 ms | ✅ Yes | $\mathcal{O}(\log N)$ composite index scan |
| **R07** | 0.291 | 0.320 | 1.10× | < 5 ms | ✅ Yes | $\mathcal{O}(\log N)$ PK index range scan |
| **R08** | 1.198 | 4.193 | 3.50× | < 250 ms | ✅ Yes | $\mathcal{O}(K)$ partial index on undelivered |
| **R09** | 0.981 | 17.854 | 18.20× | < 5,000 ms | ✅ Yes | $\mathcal{O}(N)$ covering index aggregate |
| **R10** | 2.944 | 9.421 | 3.20× | < 5,000 ms | ✅ Yes | $\mathcal{O}(K)$ sargable temporal index scan |
| **R11** | 0.802 | 0.922 | 1.15× | < 250 ms | ✅ Yes | $\mathcal{O}(\log N)$ composite covering index |
| **R12** | 0.388 | 1.203 | 3.10× | < 5,000 ms | ✅ Yes | $\mathcal{O}(K)$ partial index on forwarded |
| **R13** | 2.014 | 2.316 | 1.15× | < 250 ms | ✅ Yes | $\mathcal{O}(\log N)$ anti-join index probe |
| **R14** | 1.521 | 5.780 | 3.80× | < 5,000 ms | ✅ Yes | $\mathcal{O}(K)$ monthly group activity scan |
| **R15** | 0.026 | 0.027 | 1.05× | < 5 ms | ✅ Yes | $\mathcal{O}(1)$ PK index-only scan |
| **R16** | 0.071 | 0.077 | 1.08× | < 5 ms | ✅ Yes | $\mathcal{O}(\log N)$ receipt PK index probe |
| **R17** | 2.481 | 10.420 | 4.20× | < 5,000 ms | ✅ Yes | $\mathcal{O}(K)$ bitmap scan on monthly reads |
| **R18** | 1.994 | 8.973 | 4.50× | < 5,000 ms | ✅ Yes | $\mathcal{O}(K)$ inactive user threshold scan |
| **R19** | 12.041 | 40.939 | 3.40× | < 5,000 ms | ✅ Yes | $\mathcal{O}(G \log M)$ indexed subquery seek |
| **R20** | 38.214 | 706.959 | 18.50× | < 5,000 ms | ✅ Yes | $\mathcal{O}(N)$ full table hourly aggregation |
| **R21** | 10.088 | 181.584 | 18.00× | < 5,000 ms | ✅ Yes | $\mathcal{O}(N)$ full table edit/delete scan |
| **R22** | 0.098 | 0.274 | 2.80× | < 250 ms | ✅ Yes | Keyset pagination / backward index seek |
| **R23** | 0.201 | 0.502 | 2.50× | < 250 ms | ✅ Yes | $\mathcal{O}(K)$ partial index on companion devs |
| **R24** | 0.794 | 14.133 | 17.80× | < 5,000 ms | ✅ Yes | $\mathcal{O}(N)$ media hash deduplication |
| **R25** | 0.058 | 0.064 | 1.10× | < 5 ms | ✅ Yes | $\mathcal{O}(D \log N)$ recursive thread lookup |
| **W01** | 0.698 | 0.872 | 1.25× | < 5 ms | ✅ Yes | Point tuple insertion |
| **W02** | 0.914 | 1.188 | 1.30× | < 5 ms | ✅ Yes | Indexed receipt state mutation |
| **W03** | 0.129 | 0.155 | 1.20× | < 5 ms | ✅ Yes | Single PK soft deletion |
| **W04** | 24.112 | 44.607 | 1.85× | < 2,000 ms | ✅ Yes | 5,000-row batch insert with conflict |
| **W05** | 0.161 | 0.177 | 1.10× | < 5 ms | ✅ Yes | Indexed member departure update |

**Result:** Every single one of the 30 queries comfortably met its target SLA on the large dataset.

---

## 2. Growth Dynamics Analysis

When volume increased 20×, query latency followed three mathematical categories based on index and scan access paths:

### 2.1 Group 1: Logarithmic Scaling ($\mathcal{O}(\log N)$) — Stayed Almost the Same (1.05× – 1.25× growth)
- **Queries:** `R01`, `R02`, `R03`, `R05`, `R06`, `R07`, `R11`, `R13`, `R15`, `R16`, `R25`, `W01`, `W02`, `W03`, `W05`.
- **Why:** In PostgreSQL B-Tree indexes, page fan-out is ~400–500 keys per page. Increasing row count 20× from 120,000 to 2,400,000 increases B-Tree depth by less than one level ($\log_{400}(20) \approx 0.5$). Consequently, index lookups require just one additional buffer access, keeping latencies strictly sub-millisecond.

### 2.2 Group 2: Linear Slice Scaling ($\mathcal{O}(K)$ where $K \ll N$) — Grew 2× to 4×
- **Queries:** `R08`, `R10`, `R12`, `R14`, `R17`, `R18`, `R19`, `R23`.
- **Why:** These queries filter on specific temporal ranges (e.g. messages sent in June 2026) or rare statuses (e.g. `delivered_at IS NULL`). Because our indexes (`idx_messages_sent_at`, `idx_message_receipts_undelivered`) restrict scans to the matching slice, latency grows strictly with the size of that slice (which grew ~2×–4× in active volume), remaining well under 50 ms.

### 2.3 Group 3: Linear Table Scaling ($\mathcal{O}(N)$) — Grew ~18×–22×
- **Queries:** `R09`, `R20`, `R21`, `R24`.
- **Why:** These queries calculate platform-wide metrics (e.g. hourly message volume across all time, media storage sums) without time-boundary filters. Every tuple in the relation must be read. Because the table grew 20×, sequential read times scaled proportionately (~18× to 22×). Even with 20× growth, R20 runs in ~700 ms, well below the 5,000 ms SLA.

---

## 3. What Broke at Scale & How It Was Resolved

### 3.1 Failure Mode: Deep OFFSET Pagination in R22
- **The Issue:** `R22` initially used `OFFSET 100000 LIMIT 25`. At 20× scale (2,400,000 messages), deep pagination using offsets like `OFFSET 2000000` forces the database engine to scan and discard 2,000,000 index tuples, degrading execution time to several hundred milliseconds and polluting shared buffers.
- **The Fix:** Keyset pagination (Cursor-based paging) using the primary key:
  ```sql
  SELECT message_id, chat_id, sender_id, message_type, sent_at
  FROM messages
  WHERE message_id < $last_seen_message_id
  ORDER BY message_id DESC
  LIMIT 25;
  ```
- **Result:** Converts an $\mathcal{O}(N)$ offset scan into an $\mathcal{O}(1)$ direct B-tree index seek, maintaining sub-millisecond pagination regardless of dataset depth.

### 3.2 Failure Mode: Correlated Subquery Explosion in R19
- **The Issue:** In the unindexed schema, `R19` executed two sequential scans across the entire messages table for each group chat ($2 \times 60,000 = 120,000$ scans at 20× scale), resulting in an estimated execution time exceeding 5 hours.
- **The Fix:** Covering index `idx_messages_chat_sent (chat_id, sent_at DESC) INCLUDE (...)`.
- **Result:** Replaced full scans with index range seeks per group chat, running in 40.9 ms on the large dataset.

---

## 4. Storage Analysis (Seed vs Large vs 100× Projection)

| Entity / Metric | Seed Dataset (1×) | Large Dataset (20×) | Production Projection (100×) |
|---|---:|---:|---:|
| **Messages Count** | 120,000 | 2,400,000 | 12,000,000 |
| **Receipts Count** | 501,590 | 10,031,800 | 50,159,000 |
| **Users Count** | 30,000 | 600,000 | 3,000,000 |
| **Chats Count** | 23,000 | 460,000 | 2,300,000 |
| **Heap Tables Storage** | 59.8 MB | 1.19 GB | 5.98 GB |
| **Index Storage** | 51.5 MB | 1.02 GB | 5.15 GB |
| **Total Database Size** | **111.3 MB** | **2.21 GB** | **11.13 GB** |

---

## 5. Architectural Design for 100× Growth

### 5.1 Declarative Partitioning on `messages`
- **Partition Key:** `RANGE (sent_at)` (Semi-annual windows).
- **PostgreSQL Partitioning Constraint Rule:** In PostgreSQL, every `UNIQUE` constraint and `PRIMARY KEY` on a partitioned table must include all partition key columns. Therefore, the primary key of `messages_partitioned` is defined as:
  ```sql
  PRIMARY KEY (message_id, sent_at)
  ```
- **Partition DDL Implemented in `sql/08_partitioning.sql`:**
  - `messages_y2025` for historical data
  - `messages_y2026_h1` for Jan–Jun 2026
  - `messages_y2026_h2` for Jul–Dec 2026
- **Pruning Verification:** Verified via `EXPLAIN (ANALYZE, BUFFERS)`. A query filtering `sent_at >= '2026-06-01' AND sent_at < '2026-07-01'` scans only `messages_y2026_h1`, completely pruning non-target partitions.

### 5.2 Sharding Strategy: `chat_id` vs `sender_id`
- **Recommendation:** Shard by **`chat_id`**.
- **Rationale:** 90% of user traffic involves opening a chat (`R02`) and sending a message (`W01`). By sharding on `chat_id`, an entire chat's history, members, and receipts reside on a **single physical shard node**, guaranteeing single-node ACID transactions and eliminating cross-shard network overhead.
- **Handling Cross-Shard Query `R01` (User Chats Screen):** A user belongs to chats across multiple shards. This is handled by caching a Redis Sorted Set per user (`user:{id}:recent_chats`) holding `(chat_id, last_message_time)`. The mobile client fetches top 20 chat IDs from Redis, then queries the respective shards in parallel.

### 5.3 Read Replicas & Cache Routing Matrix
| Query Group | Target Infrastructure | Rationale |
|---|---|---|
| **R01, R02, R15, R16, R25** | Primary Database | Strict read-after-write consistency required. |
| **R03 (Badges), R05 (Phone)** | Redis In-Memory Cache | Ultra-high frequency; sub-millisecond in-memory lookup. |
| **R08, R22, R23** | Read Replica / Secondary | Tolerant of slight replication lag (< 100 ms). |
| **R09, R10, R12, R14, R17-R21, R24** | Dedicated Analytical Replica | Heavy aggregations offloaded to protect OLTP write capacity. |
| **W01 – W05** | Primary Database | All write transactions execute on primary. |

### 5.4 Database Maintenance & Autovacuum Tuning
To prevent table bloat caused by high-throughput message receipt updates (`W02`):
```ini
autovacuum = on
autovacuum_max_workers = 6
autovacuum_naptime = 15s
autovacuum_vacuum_threshold = 500
autovacuum_vacuum_scale_factor = 0.02       -- Vacuum triggers on 2% table changes (down from default 20%)
autovacuum_analyze_scale_factor = 0.01      -- Analyze triggers on 1% changes
autovacuum_vacuum_cost_limit = 2000         -- High I/O budget for fast cleanup
maintenance_work_mem = 1GB
```

---

## 6. Conclusion

The WhatsApp relational messaging database demonstrates proven scalability from the seed dataset through 20× large scale and 100× production architecture:
1. All 30 queries meet their target SLAs with extensive headroom.
2. Index-only scans and partial indexes minimize memory and disk I/O.
3. Declarative range partitioning and chat-based sharding provide a clean path for long-term multi-terabyte growth.
