# WhatsApp Messaging Database: DBMS Project

**Course:** Database Management Systems · **Year:** B.Tech 2nd year · **Team size:** 4
**Database:** PostgreSQL 15 or newer · **Final submission:** Mon 23 Nov 2026
**Topics used:** Data types & constraints · Keys & relationships · Normalization · Query execution plans · Indexing · Query optimization · VACUUM/ANALYZE · Partitioning & sharding

## Files in this folder

| Path | What it is |
|------|------------|
| `README.md` | This project brief |
| `seed_data.zip` | 9 CSV files (120,000 messages): the only input for Phase 2. Unzip it to get `seed_data/` |
| `queries/workload_30.sql` | The 30 queries for Phase 3 (do not edit) |
| `benchmarks/run_benchmark.sh` | Timing script: 3 runs per query, average, raw plans saved |
| `CHECKPOINTS.md` | Checkpoint dates and the files each one needs (DE and AP repos) |

**Getting started:** **clone this repository and push it into your team's DE repo** (the DE repo you submitted in the form); the steps are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Keep the structure shown in [Repository structure](#repository-structure-submit-exactly-this). Unzip `seed_data.zip` inside your project folder, but don't commit the CSV files. Deadlines are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Then begin with Phase 1.

---

## Team details (fill in before you start)

| Role | Name | Enrollment No. | GitHub Username |
|------|------|----------------|-----------------|
| Group Lead | Dhanaya Khaspuri| 2501010140| dhanaya-khaspuri|
| Member 2 | Mahika Garg| 2501010254| mahikagarg247-tech|
| Member 3 | Ishan Bansal| 2501010714| bansalishan07|
| Member 4 | Saumya Madan| 2501010414| saumya-madan|

**Team No.:** __
T0084__ · **Section:** __D__ · **Repository URL:** https://github.com/dhanaya-khaspuri/DE_Project_2026.git

---

## How this project works

| Phase | What you do | You submit | Counts toward | Marks |
|-------|-------------|------------|---------------|------:|
| 1 | Understand the problem statements | `docs/01_problem_understanding.md` | Query Execution | 2 |
| 2 | Work out the database schema **from the seed data** and load it | `sql/01_schema.sql`, `sql/02_load_data.sql`, `docs/02_schema_design.md` | Query Execution | 5 |
| 3 | Run the **30 given SQL queries** and record their execution time | `docs/03_baseline_timings.md`, `benchmarks/results/baseline/` | Query Execution | 3 |
| 4 | Optimize the queries and record the new times | `sql/05_indexes.sql`, `sql/06_optimized_queries.sql`, `docs/04_optimization_report.md`, `benchmarks/results/optimized/` | Code Optimization | 16 |
| 5 | Scalability test on the **large dataset** (given later by faculty) and final report | `docs/05_scalability_report.md`, `benchmarks/results/large/` | Code Optimization | 14 |
| | **Total** | | | **40** |

---

## Phase 1: Problem statements

WhatsApp delivers billions of messages a day. Every user registers with a phone number and may link extra devices (WhatsApp Web / Desktop). Users talk in **direct chats** (two people) and **groups** (with admins, members joining and leaving). A message can be text or media (image, video, audio, document), can **reply** to an earlier message, can be forwarded, edited or deleted. For every recipient the server records when the message was **delivered** (✓✓) and **read** (blue ✓✓). Users also make voice/video calls and can block each other. You have joined the team that owns WhatsApp's message store for India.

The current database was put together quickly by an earlier team. It has **no documented schema** (only data exports survive), and the product teams are complaining:

| # | Problem reported | Team | Related queries |
|---|------------------|------|-----------------|
| P1 | "The **Chats** screen (latest message per chat, unread badges) takes too long to open for active users." | Mobile app | R01, R03 |
| P2 | "**Opening a busy group** and scrolling its history is slow." | Mobile app | R02, R07, W01 |
| P3 | "**Message search** and **message info** (who read it) lag." | Mobile app | R04, R16, R25 |
| P4 | "Registration and contact screens (**phone lookup, last seen, blocked check**) must answer instantly." | Identity / Privacy | R05, R06, R15 |
| P5 | "The delivery service's **pending-receipts** scan and **mark-as-read** updates are slow under load." | Delivery service | R08, W02, W04 |
| P6 | "Group admins asked for a list of **unanswered questions**; the report always comes back **empty**." | Groups | R13 |
| P7 | "Trust & safety wants **spam/forwarding** reports and a fast console." | Trust & Safety | R12, R22, W03 |
| P8 | "Storage costs are rising: find **heavy uploaders and duplicate media**." | Storage | R09, R24 |
| P9 | "Product analytics (DAU, read times, edits/deletes, group health, hourly load) time out, and message volume will grow **20×**." | Product analytics | R10, R14, R17, R19, R20, R21 |
| P10 | "Security and clean-up jobs (stale linked devices, inactive users, missed calls, leaving groups) are slow." | Security / Platform | R11, R18, R23, W05 |

**Your job:**
1. Rebuild a correct, well-constrained schema from the data exports (Phase 2).
2. Measure how the 30 most important queries perform today (Phase 3).
3. Make them fast **without changing their results** (Phase 4).
4. Prove the database will survive next year's growth (Phase 5).

**Deliverable for Phase 1** (`docs/01_problem_understanding.md`, at most 1 page):
- For each problem P1–P10, write in your own words what the business needs and which **stakeholder** is affected (end user, group admin, delivery service, storage team, trust & safety, growth/product analytics, security).
- Classify each problem as **customer-facing / real-time** or **reporting / analytics**. This decides your performance targets later.
- List any assumptions you make.

---

## Phase 2: Work out the schema from the seed data

You receive **`seed_data.zip`**. Unzip it to get a folder **`seed_data/`** with 9 CSV files, a real export of the production data:

| File | Rows | What it contains |
|------|-----:|------------------|
| `users.csv` | 30,000 | WhatsApp accounts (identified by phone number) |
| `devices.csv` | 42,000 | Phones and linked devices (Web/Desktop) of each user |
| `chats.csv` | 23,000 | Direct chats and groups |
| `chat_members.csv` | 104,514 | Who is (or was) in each chat |
| `media.csv` | 27,634 | Uploaded media files |
| `messages.csv` | 120,000 | Every message sent from 1 Jan 2025 to 30 Jun 2026 |
| `message_receipts.csv` | 501,590 | Delivery / read status of each message for each recipient |
| `calls.csv` | 25,000 | Voice and video calls |
| `blocked_users.csv` | 4,000 | Who has blocked whom |

The first line of every file is the header (column names). Here are the headers and the first rows of each file:

**users.csv**
```
user_id,phone_e164,display_name,about,is_business,joined_on,last_seen_at,status
1,+919000000001,Vivaan Sharma,Battery about to die,f,2020-09-29,2026-06-18 22:52:57+05:30,ACTIVE
2,+919000000002,Aditya Sharma,,f,2018-10-29,2026-06-30 23:56:14+05:30,ACTIVE
```

**devices.csv**
```
device_id,user_id,device_type,app_version,registered_at,last_active_at
1,1,ANDROID,2.25.7,2020-09-29 00:00:00+05:30,2026-06-18 22:52:57+05:30
2,1,WEB,2.26.8,2021-04-17 00:00:00+05:30,2026-06-17 22:52:57+05:30
```

**chats.csv**
```
chat_id,chat_type,group_name,created_by,created_at
1,DIRECT,,7920,2023-01-02 05:05:29+05:30
2,DIRECT,,15839,2023-01-03 10:10:58+05:30
```

**chat_members.csv**
```
chat_id,user_id,role,joined_at,left_at,is_muted
1,7920,MEMBER,2023-01-02 05:05:29+05:30,,f
1,22649,MEMBER,2023-01-02 08:05:29+05:30,,f
```

**media.csv**
```
media_id,uploader_id,media_type,mime_type,size_bytes,sha256,uploaded_at
1,12289,IMAGE,image/jpeg,1772263,c2bb3ccfff6a5dec63bfc98b37438bd1cbf44fb16376761c797302e8392207aa,2024-12-31 23:59:58+05:30
12,28543,IMAGE,image/jpeg,412674,23de1440cce09d8e54a80d4b6aa3003decdf2be1b4f1e9e0f87ed24a5a5c8247,2025-01-01 01:12:02+05:30
```

**messages.csv**
```
message_id,chat_id,sender_id,sent_at,message_type,body,media_id,reply_to_message_id,is_forwarded,is_deleted,edited_at
1,5561,12289,2025-01-01 00:00:00+05:30,IMAGE,,1,,f,f,
2,20669,24018,2025-01-01 00:06:33+05:30,TEXT,What time is the meeting?,,,f,f,
```

**message_receipts.csv**
```
message_id,user_id,delivered_at,read_at
1,27560,2025-01-01 00:00:59+05:30,2025-01-01 00:10:59+05:30
2,11457,2025-01-01 00:06:35+05:30,2025-01-01 07:56:35+05:30
```

**calls.csv**
```
call_id,chat_id,caller_id,call_type,started_at,answered_at,ended_at,status
1,15998,12892,VIDEO,2025-01-01 00:00:00+05:30,,2025-01-01 00:00:35+05:30,MISSED
2,20825,2634,VOICE,2025-01-01 00:31:26+05:30,2025-01-01 00:31:32+05:30,2025-01-01 01:17:40+05:30,COMPLETED
```

**blocked_users.csv**
```
blocker_id,blocked_id,blocked_at
1,7961,2025-05-18 22:07:07+05:30
5,1573,2026-02-23 21:34:13+05:30
```

Open the files yourself (a spreadsheet, `head`, or `SELECT` after a quick load into a scratch table) and study the data carefully. **Nobody will give you the CREATE TABLE statements.** Working them out *is* the task.

### 2.1 What you must identify (for every table)
1. **Table name and column names.** Use exactly the file names and CSV headers. The 30 queries depend on them.
2. **Data type** of every column. Choose the *right* type, not just `TEXT` everywhere. Think about money, timestamps with a time-zone offset, yes/no columns, small whole numbers, decimals and short codes.
3. **Primary key.** Is it one column, or a combination? (Look closely at `chat_members`, `message_receipts` and `blocked_users`.)
4. **Foreign keys.** Which column points to which table? What should happen **ON DELETE** (CASCADE, RESTRICT or SET NULL), and why?
5. **NOT NULL vs NULL.** Some columns are empty in some rows. Find out **when** and **why**, and decide which columns must never be empty. Why is `group_name` sometimes empty? When are `delivered_at`, `read_at`, `answered_at`, `ended_at`, `left_at`, `media_id`, `body` and `reply_to_message_id` empty, and can a deleted message still have a body?
6. **UNIQUE** columns (natural candidate keys such as emails, phone numbers, codes and handles).
7. **CHECK constraints.** Write at least **12** that the data obeys and the business needs. Look for formats (E.164 phone number, app version, SHA-256 hash), allowed values (chat/message/media/call types, statuses, roles), time order (delivered before read, joined before left, answered before ended), rules tying columns together (group name only for groups, media only for non-text messages, a user cannot block themselves).
8. **Relationships and cardinalities** (1:1, 1:N, M:N). Draw the **ER diagram** (image + Mermaid code).
9. **Normal form.** Show that each table is in 3NF/BCNF (list its functional dependencies). Point out any column that is *derived or redundant* (hint: can the number of chat members, unread counts or a call's duration be derived instead of stored? Is `media.media_type` redundant with `messages.message_type`?) and say whether keeping it is justified.

### 2.2 Rules for your schema
- Create every table in a schema named **`whatsapp`**: `CREATE SCHEMA whatsapp;` and `SET search_path TO whatsapp;`
- In this phase create **only constraints**: PK, FK, UNIQUE, NOT NULL, CHECK. **Do not create any other index yet.** (PostgreSQL automatically indexes PRIMARY KEY and UNIQUE columns; that's allowed. Note which indexes exist.) Your baseline in Phase 3 must reflect a database *without* tuning.
- Your constraints must accept **all** rows of the seed data. If a load fails, either your constraint is wrong or you found a data problem. Explain which in your design doc.

### 2.3 Load the data
Write `sql/02_load_data.sql` using `\copy`, loading tables in the right order (parents before children):

```sql
SET search_path TO whatsapp;
\copy users FROM 'seed_data/users.csv' WITH (FORMAT csv, HEADER true)
-- ... the other tables, in an order that satisfies your foreign keys
ANALYZE;
```

Then verify the row counts match the table above, and run at least **3 integrity checks** of your own (e.g. "every message sender is (or was) a member of that chat", "a reply points to a message in the same chat", "a direct chat has exactly two members"). Paste the results into `docs/02_schema_design.md`.

### Phase 2 deliverables
- `sql/01_schema.sql`: runs top-to-bottom on an empty database without errors
- `sql/02_load_data.sql`: loads all 9 files without errors
- `docs/02_schema_design.md`: data dictionary (table · column · type · constraint · *why*), ER diagram, FDs and normal form per table, integrity-check results, and every data problem you found

---

## Phase 3: Run the 30 queries and record the time

The file **`queries/workload_30.sql`** contains **30 queries**: 25 reads (`R01`–`R25`) and 5 writes (`W01`–`W05`). They're also listed in the [Appendix](#appendix-the-30-queries). **Do not modify them.** If a query fails, your schema doesn't match the seed data; fix the schema, not the query.

### 3.1 How to measure (everyone must use the same method)
- Run each query with `EXPLAIN (ANALYZE, BUFFERS)` and read the **`Execution Time`** at the bottom.
- Run each query **3 times** and record the **average** of the three `Execution Time` values. Keep all three runs in the raw plan file.
- Write queries (`W01`–`W05`) must be measured inside `BEGIN; … ROLLBACK;` so the data does not change.
- Close other heavy applications while measuring, and use the **same laptop** for Phase 3 and Phase 4.

The helper script does all of this for you:
```bash
./benchmarks/run_benchmark.sh <your_database> baseline
# → benchmarks/results/baseline/summary.csv   (avg, median, min, max, scan types)
# → benchmarks/results/baseline/R01.txt …     (full plans of all 3 runs)
```
> ⚠️ One of the 30 queries takes **several seconds** on the seed data. That's intentional. Let it finish, and don't skip it.

### 3.2 Deliverable: the timing table
In `docs/03_baseline_timings.md`, fill this table for **all 30** queries:

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Chats screen: user 965's chats with the time and text of the latest message, newest first | READ | | | | |
| R02: Open a chat: the latest 50 messages of group 22556 | READ | | | | |
| R03: Badge counts: unread messages per chat for user 965 | READ | | | | |
| R04: Search: messages containing "meeting" in any chat user 965 belongs to | READ | | | | |
| R05: Registration: is this phone number already on WhatsApp? | READ | | | | |
| R06: Contact info: "last seen" of everyone user 965 chats with directly | READ | | | | |
| R07: Group info screen: current members of group 22556 with their role | READ | | | | |
| R08: Delivery service: receipts still not delivered for messages sent before 23:00 on 30 Jun 2026 | READ | | | | |
| R09: Storage team: top 20 users by total media uploaded (GB) | READ | | | | |
| R10: Growth: daily active senders in June 2026 | READ | | | | |
| R11: Calls tab: missed calls received by user 965 since 1 Jan 2025 | READ | | | | |
| R12: Spam detection: users who forwarded 2+ messages on the same day | READ | | | | |
| R13: Group admins: questions asked in group 20501 that nobody has replied to | READ | | | | |
| R14: Engagement: 10 groups with the most distinct senders in June 2026 | READ | | | | |
| R15: Before delivering: has user 3064 blocked user 17793? | READ | | | | |
| R16: Message info screen: who has read message 119989 and when | READ | | | | |
| R17: Product analytics: average minutes from sending to reading, per message type (June 2026) | READ | | | | |
| R18: Clean-up: users not seen since April 2026 who are still in at least one group | READ | | | | |
| R19: Group health report: for every group, the last message time and messages in June 2026 | READ | | | | |
| R20: Capacity planning: messages per hour of the day, by message type | READ | | | | |
| R21: Product analytics: share of messages edited or deleted, per message type | READ | | | | |
| R22: Trust & safety console: all messages, newest first, page 4,001 (25 per page) | READ | | | | |
| R23: Security: linked WEB/DESKTOP devices unused since 1 June 2026 (to auto log out) | READ | | | | |
| R24: Storage dedup: media files uploaded more than once (same SHA-256) | READ | | | | |
| R25: Reply thread: walk up the chain of replies starting at message 119989 | READ | | | | |
| W01: Send a text message in group 22556 | WRITE | | | | |
| W02: Open chat: mark all of user 965's unread messages in group 22556 as read | WRITE | | | | |
| W03: "Delete for everyone" on message 119989 | WRITE | | | | |
| W04: Broadcast: create delivery receipts for 5,000 recipients of a business announcement | WRITE | | | | |
| W05: User 965 leaves group 20898 | WRITE | | | | |
| **Total (sum of all 30)** | | | | | |

Below the table, add for each query the **scan type** from the plan (Seq Scan, Index Scan, …) and one line on **why** it is slow or fast.

---

## Phase 4: Optimize the queries

Make the queries faster. **The results must stay the same** (same rows; order matters only where the query has an `ORDER BY`).

### 4.1 Techniques you may use
| Technique | Example |
|-----------|---------|
| B-tree index (single / composite) | the right column **order** matters: equality columns first, then range/sort |
| Partial index | index only the rows a query needs (e.g. a rare status) |
| Covering index | `INCLUDE (...)` so the table is never visited (Index Only Scan) |
| Expression index | index the exact expression used in `WHERE` |
| GIN index | for `ILIKE '%text%'` (extension `pg_trgm`), arrays or full-text search |
| BRIN index | for huge tables stored in time order |
| Query rewrite | sargable date ranges instead of functions on columns; `NOT EXISTS` instead of `NOT IN`; joins instead of correlated subqueries; keyset instead of `OFFSET` pagination; `UNION ALL` instead of `OR` across columns |
| VACUUM / ANALYZE | fresh statistics and visibility maps |
| Summary table / materialized view | for heavy reports that don't need live data (state how it's refreshed) |

**Not allowed:** changing the data, deleting rows, changing PostgreSQL server settings to hide the problem (e.g. huge `work_mem`, `enable_seqscan = off`), or caching results outside the database.

### 4.2 How to work
1. Put every index in `sql/05_indexes.sql`, each with a comment: **which queries it serves and why this type and column order**.
2. Put rewritten queries in `sql/06_optimized_queries.sql`. Copy `queries/workload_30.sql` and change **only** the queries you rewrite, keeping the `-- @R01` markers.
3. **Prove the results are unchanged** for every rewritten query (compare row counts, plus a checksum or an `EXCEPT` query). Put the proof in your report.
4. Benchmark again with the same method:
```bash
./benchmarks/run_benchmark.sh <your_database> optimized 5 sql/06_optimized_queries.sql
```
> 🔎 **Read the results, not just the timings.** At least one of the 30 original queries returns a **wrong answer** because of a subtle SQL rule about NULLs. Find it, explain it, and fix it. This is worth marks.

### 4.3 Deliverable: the optimization table
In `docs/04_optimization_report.md`:

| Query | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
|-------|------------:|---------------------------|----------------------|-----------:|------------:|:------------:|
| R02 | | e.g. Seq Scan on 120k messages | e.g. index on `messages(chat_id, sent_at DESC)` | | e.g. 99.5% (200×) | ✅ |
| … all 30 … | | | | | | |
| **Total** | | | | | | |

Improvement % = (before − after) / before × 100

Also include:
- **Before/after `EXPLAIN` plans** for your 5 biggest improvements
- **Write overhead:** which write queries got **slower** because of your indexes, by how much, and whether that's acceptable
- **Index storage:** the size of each index you created (`pg_relation_size`) compared with its table
- **Queries you could not speed up**, and why (an honest "this query must read most of the table" earns marks)

---

## Phase 5: Scalability report (large dataset round)

Your optimizations worked on 120,000 messages. Next year the business expects **20× the volume**.

By **Thu 19 Nov 2026**, faculty will release **`large_data.zip`**: the same 9 CSV files with about **20× the rows** (≈ 2,400,000 messages, ≈ 10,032,000 message receipts, ≈ 600,000 users, ≈ 460,000 chats). Until then, work on the design part of the report.

### 5.1 What to do with the large dataset
1. Create a new database. Run **your** `01_schema.sql`, load `large_data/` with your load script (change the folder name only), then run **your** `05_indexes.sql` and `ANALYZE`.
2. Run your **optimized** queries (`sql/06_optimized_queries.sql`). **Do not run the original 30 on the large data.** Some of them could run for a very long time.
   - R22 pages with `OFFSET`; if you replaced it with keyset pagination, explain how the "last seen" value is chosen for the large data.
3. Record the times and compare with your Phase 4 results on the seed data.

| Query | Optimized on seed (ms) | Optimized on large (ms) | Growth (large ÷ seed) | Meets target? | If not, what you changed |
|-------|------------------------:|------------------------:|----------------------:|:-------------:|--------------------------|
| R01 | | | | | |
| … all 30 … | | | | | |

### 5.2 Performance targets on the large dataset
| Query group | Queries | Target (average of 3 runs) |
|-------------|---------|----------------:|
| Real-time / user-facing | R01, R02, R03, R05, R06, R07, R15, R16, R25, W01, W02, W03, W05 | **under 5 ms** |
| Interactive search and ops | R04, R08, R11, R13, R22, R23 | **under 250 ms** |
| Reports and analytics | R09, R10, R12, R14, R17, R18, R19, R20, R21, R24 | **under 5,000 ms** |
| Batch jobs | W04 | **under 2,000 ms** |

If a query misses its target, **find out why from the plan and fix it.** A query that was fast on the seed data can become slow on large data for reasons that only appear at scale. Show the before/after plans for every fix.

### 5.3 Deliverable: `docs/05_scalability_report.md`
1. **Results table** (above), with every target met or explained.
2. **Growth analysis.** Group your queries by how their time grew when the data grew 20×:
   - *stayed about the same* (why? e.g. index lookups grow with log n)
   - *grew about 20×* (why? e.g. they read a fixed *share* of the table)
   - *grew more than 20×* (why, and what you did about it)
3. **What broke at scale** and how you fixed it (plans before/after).
4. **Storage:** total database size, table vs index size, on seed and large data.
5. **Architecture for 100×:** explain with numbers from your own measurements:
   - **Partitioning:** which table, by which column (RANGE / LIST / HASH), and why. Write the DDL for `messages`, show partition pruning with `EXPLAIN`, and note the primary-key rule for partitioned tables.
   - **Sharding:** Would you shard messages by chat, by sender, or by recipient? Think about R01 (a user's chat list) and R02 (one chat's history). Which queries become cross-shard, and how would you handle them?
   - **Read replicas and caching:** which of the 30 queries you would send to a replica or cache, and which must hit the primary.
   - **Maintenance:** VACUUM/autovacuum settings for `messages`, archiving old data, refreshing summary tables.
6. **Conclusion:** is your database ready for next year? What are the remaining risks?

---

## Repository structure (submit exactly this)

```
whatsapp-dbms-<team-no>/
├── README.md                          # team table, how to run, headline numbers
├── team.json                          # group lead, members, enrollment numbers
├── docs/
│   ├── 01_problem_understanding.md
│   ├── 02_schema_design.md
│   ├── 03_baseline_timings.md
│   ├── 04_optimization_report.md
│   └── 05_scalability_report.md
├── diagrams/
│   └── er_diagram.png
├── sql/
│   ├── 01_schema.sql
│   ├── 02_load_data.sql
│   ├── 05_indexes.sql
│   ├── 06_optimized_queries.sql
│   └── 08_partitioning.sql
├── queries/
│   └── workload_30.sql                # given; do not edit
└── benchmarks/
    ├── run_benchmark.sh               # given
    └── results/
        ├── baseline/                  # Phase 3: summary.csv + raw plans
        ├── optimized/                 # Phase 4
        └── large/                     # Phase 5
```

`team.json`:
```json
{
  "team_number": "",
  "group_lead": { "name": "", "enrollment_no": "", "github": "" },
  "members": [
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" }
  ],
  "postgres_version": "",
  "laptop_used_for_benchmarks": ""
}
```

**Do not commit the CSV files** (`seed_data/`, `large_data/`); add them to `.gitignore`. They are too large and we already have them.

---

## Timeline

| Due | Work | Checkpoint |
|-----|------|------------|
| Tue 3 Nov 2026 | Clone this repo into your team's DE repo, add members, commit `team.json` | **CP0** Setup |
| Mon 16 Nov 2026 | Phase 1 + Phase 2 (schema, load, ER, data dictionary) | **CP1** Schema loads all seed data with no errors |
| Tue 17 Nov 2026 | Phase 3 (baseline, 3 runs, average) + start Phase 4 | **CP2** Baseline table for all 30 queries committed |
| Thu 19 Nov 2026 | Phase 4 (indexes, rewrites, wrong-result query) | **CP3** Optimization table committed |
| Mon 23 Nov 2026 | Phase 5 on the large dataset + final report | **CP4 Final submission:** last commit on the default branch |
| Wed 25 – Thu 26 Nov 2026 | Individual analysis, in class time | **CP5** Individual analysis |

Full list of files per checkpoint, including the AP repo: [`CHECKPOINTS.md`](CHECKPOINTS.md).

---

### Evaluation (40 marks)

These 40 marks are the DE part of the project: **Query Execution (10)** and **Code Optimization (30)**.
The AP project (20) and your Individual analysis (40) make up the rest of the 100.

| Phase | Criteria | Marks |
|-------|----------|------:|
| | **Query Execution** | **10** |
| 1 | Problems understood, stakeholders and query groups correctly identified | 2 |
| 2 | Correct data types (1), keys and foreign keys with justified delete rules (1), ≥12 meaningful CHECK / NOT NULL / UNIQUE constraints (1), ER diagram + normal-form analysis (1), data loads cleanly + integrity checks (1) | 5 |
| 3 | All 30 queries measured with the required method: 3 runs, average (1), raw plans committed (1), scan type and reason for each query (1) | 3 |
| | **Code Optimization** | **30** |
| 4 | Speed-up achieved with appropriate techniques (6), every index justified (3), results proven unchanged (2), wrong-result query found and explained (2), write overhead and index storage reported (3) | 16 |
| 5 | Large-dataset results with all targets met or explained (4), growth analysis (3), scale-only problems found and fixed (3), partitioning DDL + sharding/replica design backed by your numbers (4) | 14 |
| | **Total** | **40** |

**Integrity rules**
- Every number in your reports must match the raw plan files in `benchmarks/results/`. Copied or invented timings make the whole phase score 0.
- Every member must have commits; the commit history is checked.
- You may use AI tools to learn, but you must be able to explain every index and rewrite in your individual analysis.

---

## Appendix: the 30 queries

These are identical to `queries/workload_30.sql`. Use the file, not copy-paste from this page.

**R01: Chats screen: user 965's chats with the time and text of the latest message, newest first**
```sql
SELECT cm.chat_id, c.chat_type, c.group_name, last_msg.sent_at, last_msg.body
FROM chat_members cm
JOIN chats c ON c.chat_id = cm.chat_id
CROSS JOIN LATERAL (
    SELECT m.sent_at, m.body FROM messages m
    WHERE m.chat_id = cm.chat_id
    ORDER BY m.sent_at DESC
    LIMIT 1
) last_msg
WHERE cm.user_id = 965 AND cm.left_at IS NULL
ORDER BY last_msg.sent_at DESC;
```

**R02: Open a chat: the latest 50 messages of group 22556**
```sql
SELECT message_id, sender_id, sent_at, message_type, body, reply_to_message_id
FROM messages
WHERE chat_id = 22556
ORDER BY sent_at DESC
LIMIT 50;
```

**R03: Badge counts: unread messages per chat for user 965**
```sql
SELECT m.chat_id, count(*) AS unread
FROM message_receipts r
JOIN messages m ON m.message_id = r.message_id
WHERE r.user_id = 965 AND r.read_at IS NULL
GROUP BY m.chat_id
ORDER BY unread DESC;
```

**R04: Search: messages containing "meeting" in any chat user 965 belongs to**
```sql
SELECT m.chat_id, m.message_id, m.sent_at, m.body
FROM messages m
JOIN chat_members cm ON cm.chat_id = m.chat_id AND cm.user_id = 965
WHERE m.body ILIKE '%meeting%'
ORDER BY m.sent_at DESC
LIMIT 20;
```

**R05: Registration: is this phone number already on WhatsApp?**
```sql
SELECT user_id, display_name, status
FROM users
WHERE phone_e164 = '+919000000965';
```

**R06: Contact info: "last seen" of everyone user 965 chats with directly**
```sql
SELECT u.user_id, u.display_name, u.last_seen_at
FROM chat_members me
JOIN chats c         ON c.chat_id = me.chat_id AND c.chat_type = 'DIRECT'
JOIN chat_members other ON other.chat_id = me.chat_id AND other.user_id <> me.user_id
JOIN users u         ON u.user_id = other.user_id
WHERE me.user_id = 965
ORDER BY u.last_seen_at DESC NULLS LAST;
```

**R07: Group info screen: current members of group 22556 with their role**
```sql
SELECT cm.user_id, u.display_name, cm.role, cm.joined_at
FROM chat_members cm
JOIN users u ON u.user_id = cm.user_id
WHERE cm.chat_id = 22556 AND cm.left_at IS NULL
ORDER BY cm.role, u.display_name;
```

**R08: Delivery service: receipts still not delivered for messages sent before 23:00 on 30 Jun 2026**
```sql
SELECT r.message_id, r.user_id, m.sent_at
FROM message_receipts r
JOIN messages m ON m.message_id = r.message_id
WHERE r.delivered_at IS NULL
  AND m.sent_at < '2026-06-30 23:00:00+05:30'
ORDER BY m.sent_at
LIMIT 500;
```

**R09: Storage team: top 20 users by total media uploaded (GB)**
```sql
SELECT uploader_id, count(*) AS files, round(sum(size_bytes) / 1024.0 / 1024 / 1024, 3) AS gb
FROM media
GROUP BY uploader_id
ORDER BY sum(size_bytes) DESC
LIMIT 20;
```

**R10: Growth: daily active senders in June 2026**
```sql
SELECT sent_at::date AS day, count(DISTINCT sender_id) AS active_senders, count(*) AS messages
FROM messages
WHERE sent_at::date BETWEEN '2026-06-01' AND '2026-06-30'
GROUP BY 1
ORDER BY 1;
```

**R11: Calls tab: missed calls received by user 965 since 1 Jan 2025**
```sql
SELECT c.call_id, c.caller_id, c.call_type, c.started_at
FROM calls c
JOIN chat_members cm ON cm.chat_id = c.chat_id AND cm.user_id = 965
WHERE c.status = 'MISSED'
  AND c.caller_id <> 965
  AND EXTRACT(YEAR FROM c.started_at) >= 2025
ORDER BY c.started_at DESC;
```

**R12: Spam detection: users who forwarded 2+ messages on the same day**
```sql
SELECT sender_id, sent_at::date AS day, count(*) AS forwarded
FROM messages
WHERE is_forwarded
GROUP BY sender_id, sent_at::date
HAVING count(*) >= 2
ORDER BY forwarded DESC, sender_id;
```

**R13: Group admins: questions asked in group 20501 that nobody has replied to**
```sql
SELECT m.message_id, m.sender_id, m.sent_at, m.body
FROM messages m
WHERE m.chat_id = 20501
  AND m.body LIKE '%?%'
  AND m.message_id NOT IN (SELECT r.reply_to_message_id FROM messages r);
```

**R14: Engagement: 10 groups with the most distinct senders in June 2026**
```sql
SELECT m.chat_id, c.group_name, count(DISTINCT m.sender_id) AS active_members, count(*) AS messages
FROM messages m
JOIN chats c ON c.chat_id = m.chat_id AND c.chat_type = 'GROUP'
WHERE m.sent_at >= '2026-06-01' AND m.sent_at < '2026-07-01'
GROUP BY m.chat_id, c.group_name
ORDER BY active_members DESC, messages DESC
LIMIT 10;
```

**R15: Before delivering: has user 3064 blocked user 17793?**
```sql
SELECT EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = 3064 AND blocked_id = 17793) AS is_blocked;
```

**R16: Message info screen: who has read message 119989 and when**
```sql
SELECT r.user_id, u.display_name, r.delivered_at, r.read_at
FROM message_receipts r
JOIN users u ON u.user_id = r.user_id
WHERE r.message_id = 119989
ORDER BY r.read_at NULLS LAST;
```

**R17: Product analytics: average minutes from sending to reading, per message type (June 2026)**
```sql
SELECT m.message_type,
       round(avg(EXTRACT(EPOCH FROM (r.read_at - m.sent_at)) / 60), 1) AS avg_minutes_to_read,
       count(*) AS reads
FROM message_receipts r
JOIN messages m ON m.message_id = r.message_id
WHERE r.read_at IS NOT NULL
  AND m.sent_at >= '2026-06-01' AND m.sent_at < '2026-07-01'
GROUP BY m.message_type
ORDER BY avg_minutes_to_read;
```

**R18: Clean-up: users not seen since April 2026 who are still in at least one group**
```sql
SELECT u.user_id, u.display_name, u.last_seen_at
FROM users u
WHERE u.last_seen_at < '2026-04-01'
  AND EXISTS (SELECT 1 FROM chat_members cm JOIN chats c ON c.chat_id = cm.chat_id
              WHERE cm.user_id = u.user_id AND c.chat_type = 'GROUP' AND cm.left_at IS NULL)
ORDER BY u.last_seen_at;
```

**R19: Group health report: for every group, the last message time and messages in June 2026**
```sql
SELECT c.chat_id, c.group_name,
       (SELECT max(m.sent_at) FROM messages m WHERE m.chat_id = c.chat_id) AS last_message_at,
       (SELECT count(*) FROM messages m WHERE m.chat_id = c.chat_id AND m.sent_at >= '2026-06-01') AS june_messages
FROM chats c
WHERE c.chat_type = 'GROUP'
ORDER BY last_message_at DESC NULLS LAST;
```

**R20: Capacity planning: messages per hour of the day, by message type**
```sql
SELECT EXTRACT(HOUR FROM sent_at) AS hour, message_type, count(*) AS messages
FROM messages
GROUP BY 1, 2
ORDER BY 1, 2;
```

**R21: Product analytics: share of messages edited or deleted, per message type**
```sql
SELECT message_type,
       count(*) AS messages,
       round(100.0 * count(*) FILTER (WHERE edited_at IS NOT NULL) / count(*), 2) AS edited_pct,
       round(100.0 * count(*) FILTER (WHERE is_deleted) / count(*), 2) AS deleted_pct
FROM messages
GROUP BY message_type
ORDER BY messages DESC;
```

**R22: Trust & safety console: all messages, newest first, page 4,001 (25 per page)**
```sql
SELECT message_id, chat_id, sender_id, message_type, sent_at
FROM messages
ORDER BY message_id DESC
OFFSET 100000
LIMIT 25;
```

**R23: Security: linked WEB/DESKTOP devices unused since 1 June 2026 (to auto log out)**
```sql
SELECT d.device_id, d.user_id, d.device_type, d.last_active_at
FROM devices d
WHERE d.device_type IN ('WEB', 'DESKTOP')
  AND d.last_active_at < '2026-06-01'
ORDER BY d.last_active_at;
```

**R24: Storage dedup: media files uploaded more than once (same SHA-256)**
```sql
SELECT sha256, count(*) AS copies, sum(size_bytes) AS total_bytes
FROM media
GROUP BY sha256
HAVING count(*) > 1
ORDER BY copies DESC;
```

**R25: Reply thread: walk up the chain of replies starting at message 119989**
```sql
WITH RECURSIVE thread AS (
    SELECT message_id, reply_to_message_id, sender_id, body, 0 AS depth
    FROM messages WHERE message_id = 119989
    UNION ALL
    SELECT m.message_id, m.reply_to_message_id, m.sender_id, m.body, t.depth + 1
    FROM messages m JOIN thread t ON m.message_id = t.reply_to_message_id
)
SELECT * FROM thread ORDER BY depth DESC;
```

**W01: Send a text message in group 22556**
```sql
INSERT INTO messages (message_id, chat_id, sender_id, sent_at, message_type, body)
VALUES (90000001, 22556, 965, '2026-07-01 09:00:00+05:30', 'TEXT', 'Good morning everyone');
```

**W02: Open chat: mark all of user 965's unread messages in group 22556 as read**
```sql
UPDATE message_receipts r
SET read_at = TIMESTAMPTZ '2026-07-01 09:05:00+05:30',
    delivered_at = coalesce(r.delivered_at, TIMESTAMPTZ '2026-07-01 09:05:00+05:30')
FROM messages m
WHERE m.message_id = r.message_id
  AND m.chat_id = 22556
  AND r.user_id = 965
  AND r.read_at IS NULL;
```

**W03: "Delete for everyone" on message 119989**
```sql
UPDATE messages
SET is_deleted = TRUE, body = NULL, media_id = NULL
WHERE message_id = 119989;
```

**W04: Broadcast: create delivery receipts for 5,000 recipients of a business announcement**
```sql
INSERT INTO message_receipts (message_id, user_id)
SELECT 1, g
FROM generate_series(2, 5001) AS g
ON CONFLICT (message_id, user_id) DO NOTHING;
```

**W05: User 965 leaves group 20898**
```sql
UPDATE chat_members
SET left_at = TIMESTAMPTZ '2026-07-01 10:00:00+05:30'
WHERE chat_id = 20898 AND user_id = 965 AND left_at IS NULL;
```
