# Phase 1: Problem Understanding & Workload Classification

**Course:** Database Management Systems · **Team:** T0084 · **System:** WhatsApp Message Store (India Region)  
**Stakeholders:** Mobile App Users, Group Administrators, Delivery Service, Storage Platform, Trust & Safety, Product/Growth Analytics, Security & Platform Engineering.

---

## 1. Problem Statements Analysis (P1 – P10)

| Problem ID | Stakeholder | Business Requirement & Problem Description | Classification | Target SLA | Related Queries |
|---|---|---|---|---|---|
| **P1** | Mobile App / End Users | **Fast Chats Screen Load:** When users open WhatsApp, their conversation inbox must load instantly showing each chat's latest message snippet, timestamp, and unread badge count. Slowness causes user churn. | Customer-Facing / Real-Time | < 5 ms | `R01`, `R03` |
| **P2** | Mobile App / End Users | **Smooth Group Chat History & Messaging:** Group chats contain active scrolling history. Fetching the latest 50 messages and posting new messages must remain smooth and low-latency regardless of group volume. | Customer-Facing / Real-Time | < 5 ms | `R02`, `R07`, `W01` |
| **P3** | Mobile App / End Users | **Fast Message Search & Read Info:** In-chat text search (e.g., finding "meeting") and inspecting message info (delivery/read timestamps) must respond without UI lag. Thread reply traversal must be instantaneous. | Interactive / Real-Time | < 250 ms (Search) / < 5 ms (Info/Thread) | `R04`, `R16`, `R25` |
| **P4** | Identity & Privacy Teams | **Instant Contact Verification & Privacy Checks:** Contact sync, phone number lookup on registration, fetching "last seen" status, and blocklist verification must execute in sub-millisecond time before message transmission. | Customer-Facing / Real-Time | < 5 ms | `R05`, `R06`, `R15` |
| **P5** | Delivery Engine & Network Edge | **High-Throughput Delivery Receipts & Read State:** Delivery queues poll pending receipts for unsent/undelivered messages, and bulk mark-as-read updates occur when chats open. High concurrency must not bottleneck the message pipeline. | Real-Time Operational / Batch Updates | < 250 ms (Scan) / < 5 ms (Update) / < 2000 ms (Batch W04) | `R08`, `W02`, `W04` |
| **P6** | Group Communities / Admins | **Unanswered Question Reporting:** Group admins need reports of questions posted with no replies. A SQL `NOT IN` anti-pattern with NULLs causes the report to return completely empty, hiding critical community interactions. | Operational Reporting | < 250 ms | `R13` |
| **P7** | Trust & Safety Operations | **Spam Detection & Content Moderation Console:** Trust and Safety analysts monitor accounts forwarding spam (>2 forwards/day), page through recent messages via a moderation console, and execute emergency "delete for everyone". | Operational & Moderation Console | < 250 ms (Paging) / < 5000 ms (Spam Aggregates) | `R12`, `R22`, `W03` |
| **P8** | Storage Platform Engineering | **Storage Cost Optimization & Media Deduplication:** High storage costs necessitate tracking the heaviest media uploaders and identifying identical media files uploaded multiple times via SHA-256 hash collision matching. | Analytical / Cost Reporting | < 5,000 ms | `R09`, `R24` |
| **P9** | Product Management & Growth Analytics | **Platform Metrics & Health Aggregations:** Daily Active Senders (DAU), average delivery-to-read latencies, message edit/delete frequency, hourly activity curves, and group health indicators must run reliably without timeouts. | Analytical Reporting | < 5,000 ms | `R10`, `R14`, `R17`, `R19`, `R20`, `R21` |
| **P10** | Platform Security & Maintenance | **Automated Account & Device Hygiene:** Scheduled background jobs identify stale linked web/desktop sessions (>30 days inactive) for automatic revocation, cleanup inactive accounts still holding group seats, and log missed calls. | Security / Platform Maintenance | < 250 ms (Device cleanup) / < 5,000 ms (User sweep) | `R11`, `R18`, `R23`, `W05` |

---

## 2. Workload Classification Summary

To establish clear engineering performance targets, queries are separated into two distinct execution tiers:

1. **Customer-Facing / Real-Time Tier (`R01-R03`, `R05-R07`, `R15`, `R16`, `R25`, `W01-W03`, `W05`):**
   - High concurrency, user-driven transactions.
   - Must achieve sub-5 ms execution times using strict index lookups (B-Tree, Covering Indexes with `INCLUDE`).
   - Must avoid table scans and high shared buffer hits.

2. **Interactive Search & Operational Tier (`R04`, `R08`, `R11`, `R13`, `R22`, `R23`, `W04`):**
   - Interactive user search, background delivery scans, and moderation tools.
   - Must execute in under 250 ms (or under 2,000 ms for 5,000-row batch inserts in `W04`).

3. **Reporting & Analytics Tier (`R09`, `R10`, `R12`, `R14`, `R17`, `R18`, `R19`, `R20`, `R21`, `R24`):**
   - Large aggregate scans over tens of thousands to millions of rows.
   - SLA target under 5,000 ms, optimized via covering indexes, sargable query rewrites, and partial indexes.

---

## 3. Key Architectural Assumptions

1. **E.164 Phone Formatting:** All phone numbers strictly follow international E.164 format (`+[country code][national number]`, 8 to 15 digits).
2. **Device Architecture:** A user may possess at most one primary mobile device (`ANDROID` or `IOS`) alongside multiple companion linked devices (`WEB` or `DESKTOP`).
3. **Chat Topology:** Direct chats (`DIRECT`) represent 1-on-1 conversations between two distinct users without a group name; Group chats (`GROUP`) require a non-empty `group_name` and have one or more administrators (`ADMIN`).
4. **Temporal Consistency:** Event timestamps strictly adhere to physical causality: `joined_at <= left_at`, `sent_at <= delivered_at <= read_at`, and `started_at <= answered_at <= ended_at`.
5. **Soft Deletions:** Deleting a message for everyone (`is_deleted = TRUE`) purges sensitive content (`body = NULL, media_id = NULL`) while preserving metadata to maintain thread integrity (`reply_to_message_id`).
6. **Seed Data Immutability:** Baseline and Phase 4 benchmarks operate strictly on the certified 120,000-message seed dataset; transaction isolation ensures writes are rolled back.

