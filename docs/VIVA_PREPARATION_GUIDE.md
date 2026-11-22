# 🎓 DBMS Viva & Defense Preparation Guide (Team T0084)

**Project:** WhatsApp Message Store Database Architecture  
**Database:** PostgreSQL 18.6 · **OS:** macOS (Apple Silicon M4)  
**Team Members:** Dhanaya Khaspuri, Mahika Garg, Ishan Bansal, Saumya Madan

---

## 🌟 Executive Summary of Achievements

- **Overall Speedup:** Total 30-query runtime dropped from **16,087 ms to 151 ms (99.06% reduction / 106× faster)**.
- **Normal Form:** Every relation is proven strictly in **BCNF (Boyce-Codd Normal Form)**.
- **Integrity Constraints:** **20 comprehensive CHECK constraints** enforcing domain invariants and causality rules.
- **Bug Discovery:** Identified and resolved the SQL three-valued logic failure in **R13** (unanswered questions returned 0 rows because `NOT IN` failed on `NULL` replies; fixed via `NOT EXISTS`).
- **R19 Super-Optimization:** Slashing runtime from **15.8 seconds to 6.5 milliseconds (2,434× speedup)** via covering index `idx_messages_chat_sent`.

---

## 🏆 Top 10 High-Probability Viva Questions & Model Answers

### Q1: What normal form is your schema in, and how do you prove it?
**Answer:**  
"Our schema is normalized to **Boyce-Codd Normal Form (BCNF)** across all 9 relations:
1. **1NF:** Every column stores atomic, scalar values (no arrays or repeating groups), with formal primary keys.
2. **2NF:** For single-column PK tables (`users`, `devices`, `chats`, `media`, `messages`, `calls`), partial dependencies cannot exist. For composite PK tables (`chat_members(chat_id, user_id)`, `message_receipts(message_id, user_id)`, `blocked_users(blocker_id, blocked_id)`), non-key attributes depend on the entire composite key.
3. **3NF & BCNF:** In every non-trivial functional dependency $X \to Y$, the determinant $X$ is a superkey (e.g. `user_id` or `phone_e164` in `users`). No non-key attribute determines another non-key attribute (zero transitive dependencies)."

---

### Q2: Why did query R13 return 0 rows in the baseline, and how did you fix it?
**Answer:**  
"Original R13 used:
```sql
AND m.message_id NOT IN (SELECT r.reply_to_message_id FROM messages r)
```
In SQL three-valued logic, `x NOT IN (val1, val2, NULL)` evaluates to `UNKNOWN` because SQL cannot verify if `x` is distinct from an unknown `NULL`. Since 105,090 top-level messages have `reply_to_message_id IS NULL`, the subquery contains `NULL`s, causing the entire `WHERE` clause to evaluate to `UNKNOWN` for every single row.  
**Fix:** We replaced `NOT IN` with `NOT EXISTS`:
```sql
AND NOT EXISTS (SELECT 1 FROM messages r WHERE r.reply_to_message_id = m.message_id)
```
`NOT EXISTS` operates on two-valued existence logic and is completely immune to `NULL`s. It immediately returned the **7 real unanswered questions** in chat 20501."

---

### Q3: Why did R19 take 15.8 seconds in baseline, and how did you achieve a 2,434× speedup?
**Answer:**  
"R19 calculates `max(sent_at)` and June 2026 message counts for every group chat using correlated subqueries:
```sql
SELECT c.chat_id, 
       (SELECT max(m.sent_at) FROM messages m WHERE m.chat_id = c.chat_id),
       (SELECT count(*) FROM messages m WHERE m.chat_id = c.chat_id AND m.sent_at >= '2026-06-01')
FROM chats c WHERE c.chat_type = 'GROUP';
```
In baseline, PostgreSQL had to execute **two full sequential scans** over all 120,000 messages for each of the 3,000 groups ($2 \times 3,000 = 6,000$ table scans, totaling $3.6 \times 10^8$ row inspections).  
**Fix:** We introduced the composite covering index:
```sql
CREATE INDEX idx_messages_chat_sent ON messages (chat_id, sent_at DESC)
INCLUDE (message_id, sender_id, message_type, body, reply_to_message_id);
```
With `chat_id` as the leading equality column and `sent_at DESC` ordered, `max(sent_at)` is resolved in a single $\mathcal{O}(1)$ index probe, and the June count uses an index range scan. Runtime dropped from **15,818 ms to 6.5 ms**."

---

### Q4: What is a Covering Index, and what does the `INCLUDE` clause do?
**Answer:**  
"A covering index stores all columns needed by a query within the index tree itself. The `INCLUDE (...)` clause appends non-search payload columns to the **leaf pages** of the B-Tree without adding them to the intermediate routing levels. This allows PostgreSQL to perform an **Index-Only Scan**, satisfying the query entirely from cache without performing costly heap table fetches."

---

### Q5: What is a Partial Index, and why is it beneficial?
**Answer:**  
"A partial index includes a `WHERE` clause so it only indexes tuples matching a specific condition:
- `idx_message_receipts_user_unread ON message_receipts(user_id) WHERE read_at IS NULL;`
- `idx_message_receipts_undelivered ON message_receipts(...) WHERE delivered_at IS NULL;`

**Benefits:**
1. **Tiny footprint:** `idx_message_receipts_undelivered` is only **488 KB** (1.6% of table size).
2. **Low write overhead:** When a message is delivered or read, only the partial index is updated, avoiding index maintenance on 99% of historical rows."

---

### Q6: Why did you use a GIN Trigram index for query R04 instead of a regular B-Tree?
**Answer:**  
"Query R04 searches for `m.body ILIKE '%meeting%'`. Standard B-Tree indexes only support left-anchored prefix matching (`LIKE 'meeting%'`). A leading wildcard (`'%meeting%'`) cannot use a B-Tree root, forcing a sequential table scan.  
A **GIN Trigram Index (`pg_trgm`)** breaks strings into 3-character sequences (e.g. `mee`, `eet`, `eti`, `tin`, `ing`). During query execution, PostgreSQL looks up the trigrams in the GIN inverted index to pinpoint candidate row pointers directly, accelerating substring search from **34.6 ms to 0.093 ms (371× faster)**."

---

### Q7: What is the PostgreSQL rule regarding Primary Keys on Partitioned Tables?
**Answer:**  
"In PostgreSQL declarative partitioning, **every UNIQUE constraint and PRIMARY KEY on a partitioned table MUST contain all columns of the partition key**.  
Because we partitioned `messages` by `RANGE (sent_at)`, the primary key cannot simply be `(message_id)`. It must be defined as `PRIMARY KEY (message_id, sent_at)`. This ensures that uniqueness can be verified locally within each partition without requiring expensive cross-partition inter-process locks."

---

### Q8: Would you shard WhatsApp messages by `chat_id` or `sender_id`?
**Answer:**  
"We recommend sharding on **`chat_id`**:
1. **Chat History Locality:** The core user action is opening a chat and scrolling history (`R02`). By sharding on `chat_id`, all messages, receipts, and members for that conversation reside on the **same physical shard**.
2. **Write Isolation:** Posting a message (`W01`) and updating receipts (`W02`) remain single-shard ACID transactions.
3. **Cross-Shard Trade-off:** Query `R01` (user inbox list) becomes cross-shard. In production, this is solved by an in-memory Redis Sorted Set (`user:{id}:chats`) that tracks recent chat IDs, which then fetch message snippets concurrently."

---

### Q9: What write overhead did your indexes introduce, and is it acceptable?
**Answer:**  
"We measured all 5 write queries before and after adding indexes:
- `W01` (Insert message): Increased slightly from **0.70 ms to 0.96 ms** (+0.26 ms).
- `W02` (Mark unread as read): Actually sped up **10× (from 3.54 ms down to 0.35 ms)** because locating the unread receipts was dramatically accelerated.
- `W04` (Batch insert 5,000 receipts): Rose from **26.8 ms to 31.3 ms** (+4.5 ms).
All write operations remain well below their strict SLAs (< 5 ms for real-time writes, < 2,000 ms for batch writes)."

---

### Q10: What is a SARGable query, and which queries did you rewrite?
**Answer:**  
"**SARGable** stands for *Search Argument Able*. A query predicate is SARGable if the optimizer can use an index range scan rather than executing a function on every table row:
- **R10:** Original had `WHERE sent_at::date BETWEEN '2026-06-01' AND '2026-06-30'`. Casting `sent_at` to `date` invalidated index range scans. We rewrote it to:
  ```sql
  WHERE sent_at >= '2026-06-01 00:00:00+05:30' AND sent_at < '2026-07-01 00:00:00+05:30'
  ```
  This allowed an Index-Only Scan on `idx_messages_sent_at`, speeding it up from **7.87 ms to 1.49 ms**.
- **R11:** Rewrote `EXTRACT(YEAR FROM started_at) >= 2025` into `started_at >= '2025-01-01 00:00:00+05:30'`."

