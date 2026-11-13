# Submission

- **Name:** Naresh Babu M
- **Date submitted:** 13 November 2026 (update if you submit on a later day)
- **Repository link:** https://github.com/naresh-06-pvt/invoicely-support-lab
- **Total time spent (real time):** <!-- TODO: fill in from your own time log below -->

> Replies below are drafts written on the **exercise clock** (Monday 16 November 2026, Asia/Dubai). The "time" columns in the investigation logs are exercise-clock times; the raw timestamps inside `evidence/` come from my lab containers (13 Nov 2026, UTC) because I reproduced everything on my laptop. Nothing was sent to anyone.

- **Items I fully investigated, and why I chose them:** All five. Items 2, 1, 4 and 3 got a full root cause with evidence. Item 5 is smaller but also has evidence. I worked them in this order: **2 → 1 → 4 → 3 → 5** (production health first, then month-end, then the customer whose invoices are silently stuck, then the rejection with an auditor deadline, then the self-service date problem). See "Prioritisation" at the end.

> How I reproduced things: `make up`, then `make load` (morning traffic) and manual uploads through the portal proxy (`localhost:3000/api/imports`) and the API. Helper scripts I used are in `evidence/scripts/`. The replay tool adds a suffix such as `-G83B` to invoice numbers so it can be run more than once; the three portal uploads for Oasis used the original numbers.

---

## Incident 1 — `inbox/01-oasis-builders-upload-stuck.md`

### Acknowledgement

- **Sent at (exercise clock):** 09:15 (received 09:05)
- **Reply:**

> Subject: RE: URGENT - monthly invoice upload stuck on "Processing"
>
> Dear Rashid,
>
> Thank you for writing, and I'm sorry about the trouble at month-end. I understand that your November file for Oasis Builders Supply sat on "Processing", that you then saw an error page, and that some invoices now say the document number "already exists".
>
> I'm looking at your uploads now. **Please don't upload the file again for the moment.** Another upload can add to the confusion, and I want to be sure which invoices have gone out before we do anything else.
>
> I'll come back to you by **10:30 this morning** with the list of which of your November invoices have been sent and what the safe next step is. If you'd rather talk, I'm available on this email thread and can call you on +971 6 555 0142.
>
> Kind regards,
> Naresh
> Product Support, Invoicely Lite

### Priority and justification

- **Priority:** P2 (handled at the top of the queue until the P1 alert arrived at 09:42)
- **Why:** Invoices are reaching the ASP (some were accepted), so it's not a P1 by the matrix. But a subset can't be issued, the customer cannot upload their normal monthly file at all, and it is month-end close with customers waiting. That business impact puts it at the top of the P2s. I'd raise it to P1 if engineering found the large-file problem affects other customers' normal uploads (it does in principle, see root cause).
- **SLA deadlines I am working to:** first response 10:05 (sent 09:15); next update by 10:30 (promised) and then every 2–4 h; resolution target 17:05 today.

### Investigation log

| Time (exercise clock) | What I checked / did | What I found |
|---|---|---|
| 09:15 | Read the email, `docs/sla-matrix.md`, `docs/architecture.md`. | Hypothesis: "Processing" for minutes + duplicates = slow import + retries. |
| 09:25 | Uploaded the clean Desert Rose sample (12 rows). | Took 2.6 s, i.e. about 0.2 s per row. Normal looks like seconds. |
| 09:30 | Read `importer.go`, `validate.go`, `directory.go`, `asp-mock/main.go`. | Every row calls the participant lookup, one after another. The ASP mock sleeps 200 ms per lookup (`asp-mock/main.go:335`). 600 rows × 0.2 s ≈ 2 min. |
| 09:40 | Uploaded `oasis-builders-nov-2026.xlsx` three times through the portal proxy with 5 s gaps, like Rashid. | Each returned **HTTP 504 "Gateway Timeout" after exactly 60 s**. The proxy timeout is 60 s (`web/app/api/[...path]/route.ts:6`). |
| 09:50 | Queried the DB and api logs. | All three imports kept running after the browser gave up: each took 121.6 s (`import completed ... duration_ms:121572`). |
| 10:00 | Looked at which invoices ended up where. | Upload 1 accepted OBS-2611-001..004 and rejected 005..008 with `AE-BR-09 ... already exists ... status 'Parsed'`. Upload 2 rejected all 8. Upload 3 accepted 005..008. |
| 10:10 | Read `store.ExistingStatus` and `importer.go:87`. | The duplicate check treats any invoice from another import that is not "Rejected" as a duplicate, **including ones still in "Parsed"**. All invoices of an import are inserted as "Parsed" *before* validation starts. So two overlapping uploads of the same file block each other. |
| 10:20 | Checked the ASP side. | Each of the 8 numbers was received **exactly once** (all accepted). No duplicate reached the network. |
| 10:25 | Ruled out: api crash/OOM (restarts 0 at that point, memory 15 MiB), ASP down, bad data in the file (the file validates cleanly, all 8 invoices accepted in the end). | Not the cause. |

Dead end: I first posted to `/api/v1/imports` through the portal and got a 404. The portal route is `/api/imports` (the proxy adds `/v1`). That cost me a few minutes.

### Root cause

- **What happened:** A 600-row file takes about 2 minutes to validate. The portal gives up after 60 s and shows a timeout/error page, but the server keeps processing. Rashid re-uploaded (twice), which started two more imports at the same time. Because invoices from a running import count as "already existing", the overlapping imports rejected each other's invoices with "document number already exists". In the end every invoice was issued once, but he couldn't tell which, and the batch screens showed many red rejections.
- **Where:**
  - `services/api/internal/validate/validate.go:165-172` + `directory/directory.go` (one lookup per row, sequential, same buyer looked up hundreds of times; 1,698 lookups took 343 s in total, mean 0.20 s).
  - `web/app/api/[...path]/route.ts:6` (60 s proxy timeout, shorter than the 121 s import).
  - `services/api/internal/importer/importer.go:87` (invoices inserted as "Parsed" before validation) with `store/store.go:298-307` (`ExistingStatus` counts "Parsed").
- **Why it happens:** No caching of lookups per buyer, a synchronous upload request, and a duplicate check that doesn't distinguish "finished" from "in progress".
- **Evidence:** `evidence/01-oasis-db-state.txt`, `evidence/01-oasis-db-state-final.txt`, `evidence/01-oasis-final-state.txt`, `evidence/01-oasis-api-logs.txt`, `evidence/01-oasis-three-uploads-via-portal.txt` (the three 504 responses, transcribed from my terminal) and `evidence/01-oasis-upload.json`, `evidence/00-prometheus-queries.txt` (lookup mean 0.2025 s), `evidence/00-baseline-desert-rose.txt`.
- **Confidence and open questions:** High for the mechanism; I reproduced it end to end. Open: the real production timeout may differ from the lab proxy's 60 s, and I cannot see Rashid's actual production data. The final state in my replay (all 8 issued exactly once) should be re-checked against his real account before I tell him.

### Customer resolution reply OR escalation note

- **Which one and why:** Both. The customer needs an answer now, and there is a product defect (slow validation + overlapping imports rejecting each other) that I can't fix. I escalate to L3 and keep the customer conversation.

**Update to Rashid (sent 10:25, ahead of the 10:30 promise):**

> Subject: RE: URGENT - monthly invoice upload stuck on "Processing"
>
> Dear Rashid,
>
> I've been through your three uploads in detail. Here are answers to your two questions.
>
> **1. Which November invoices have been sent?** All eight invoices, OBS-2611-001 to OBS-2611-008, have been received by the network provider, and each one **exactly once**. Nothing has been issued twice. (Please also check on your side: I'd like you to confirm the same.)
>
> **What you saw:** Your file is bigger than usual (600 lines), so the portal needs about two minutes to check it. The screen gives up waiting after one minute, which is why you saw "Processing" and then an error page, even though we kept working on your file in the background. Your second and third uploads then overlapped with the first, and our system blocked the repeated invoice numbers with the "already exists" message. In this case that message actually stopped duplicates from being issued, so you did the right thing by stopping and asking us.
>
> **2. What to do now?** Nothing more is needed for November. **Please don't upload the file again.** If you see the "already exists" messages in the list of uploads, those are the blocked repeats and can be ignored. Next month, if you can, please send the file once and wait about three minutes; if the screen shows an error, check the batch list before uploading again, and message me.
>
> I've passed the slowness and the overlapping-upload behaviour to our engineering team with all the details, so it doesn't happen to you next month. I'll write again by **15:00 today** to confirm with you that everything matches on your side, and with what engineering plans.
>
> Kind regards,
> Naresh

**Escalation note (L3 Engineering), 10:30:**

```markdown
### Escalation: Large uploads (600 rows) take ~2 min, portal times out at 60 s, and retries make imports reject each other (AE-BR-09)

**Priority:** P2 — month-end close for Oasis Builders; same defect affects any customer with large files.
**Customer / seller:** Oasis Builders Supply LLC, seller id 2
**Reported by / at:** Rashid Al Mansoori (Finance Ops Lead), email, 09:05 Mon 16 Nov
**Affected:** Oasis November file, 8 invoices OBS-2611-001..008, 600 rows. Three overlapping imports (ids start 83d51ac7, 19a07eae, c26605d8). Every invoice was eventually accepted once.

**Symptoms (customer view):**
"Processing" for minutes, then an error page; later "document number already exists" on invoices he did not issue twice.

**Evidence:**
- Payload excerpt: n/a (file is valid; all 8 invoices accepted).
- ASP response / error code: no ASP errors; ASP received each number once.
- Logs: `{service="api"} | json | msg="import completed"` shows duration_ms 121572 / 121640 / 121622 for the three imports. Proxy returned 504 at 60 s ×3.
- Metrics / dashboard: `invoicely_participant_lookup_duration_seconds` mean 0.2025 s, 1,698 lookups = 343 s.
- Database: `SELECT invoice_number, status FROM invoices WHERE seller_id=2 ...` — first import: 001-004 Accepted, 005-008 Rejected (AE-BR-09 "already exists ... status 'Parsed'").

**Steps to reproduce:**
1. `make up`
2. Upload `samples/oasis-builders-nov-2026.xlsx` for seller 2 via `http://localhost:3000/api/imports`.
3. After the 504 (60 s), upload it again twice. Check `invoices` for seller 2.

**What I have already tried / ruled out:**
- API crash/OOM at that time (none), ASP down (no), bad file (no, validates cleanly).

**Suspected cause (with confidence):** High.
- `validate.go:165` one sequential participant lookup per row (200 ms each, same buyers repeated).
- `route.ts:6` 60 s proxy timeout < import time.
- `importer.go:87` + `store.go:298` invoices inserted as Parsed before validation and counted as duplicates by other imports.

**Workaround in place:** Yes — told the customer to upload once and wait; no data repair needed for Oasis.

**Timeline:**
- 09:05 email received · 09:15 acknowledged · 10:25 customer update sent · 10:30 this escalation

**Ask:** (1) Cache participant lookups per id (per import at least), ideally parallelise; (2) make duplicate detection ignore invoices of imports still processing, or serialise imports per seller; (3) either make upload asynchronous (return an import id, UI polls) or raise the proxy timeout above the worst-case import time. Please give me an ETA by 13:00.
**Next customer update due:** 15:00 today
```

### Workaround offered

Upload the file once and wait about three minutes; don't re-upload if the screen times out. For very large files, split the file by invoice (e.g. two files of 300 lines, each taking about a minute) so the portal doesn't time out. I haven't tested the split-file workaround, so I'd mark it as untested to the customer.

### Prevention ideas

Cache participant lookups per buyer; make uploads asynchronous with a visible progress state; per-seller lock or file-hash idempotency so a repeated upload returns the existing import; show "still processing — don't re-upload" in the UI; alert on `import_duration_seconds` p95 above 30 s.

---

## Incident 2 — `inbox/02-alert-api-restarted-marina-bay.md`

### Acknowledgement

- **Sent at (exercise clock):** 09:55 to Priya Nair; 09:47 to support-oncall (alert received 09:42, Priya's forward 09:50)
- **Sent to:** Priya Nair (CSM) and the support-oncall thread; engineering on-call paged at 09:50.
- **Reply:**

> Hi Priya,
>
> Thanks for forwarding. Yes, I believe the alert and the 502s your customers are seeing are the same problem: the Invoicely API restarted several times in the last 15 minutes, and while it restarts, uploads fail with 502 and some invoices don't move on.
>
> I'm treating this as a P1 and I own it. I've paged engineering on-call and I'm confirming exactly which customers' invoices are stuck so I can tell you what to say to customers. For the customers messaging you, the advice for now is: **don't re-upload files; wait for our update**, and anything sitting in "Validated" or "Submitted" will be pushed through by us.
>
> On Marina Bay for Wednesday: I can't give you a yes yet, and I don't want to guess. I'll give you a straight answer, with what we know and what we don't, **before 12:00, in time for your afternoon call**, and updates every 30 minutes until then.
>
> Naresh, Product Support

### Priority and justification

- **Priority:** P1
- **Why:** The api container is restarting repeatedly (critical alert), customers get 502s on upload, and invoices already in the system stop moving (in-memory queue lost), so invoices are not reaching the ASP. Go-live of a customer (Marina Bay) on Wednesday makes it more urgent. The policy says to page engineering on-call as soon as impact is confirmed, without waiting for the root cause.
- **SLA deadlines I am working to:** first response 10:12 for the alert / 10:20 for Priya (sent 09:47/09:55); updates every 30–60 min; resolution target 13:42.

### Investigation log

| Time (exercise clock) | What I checked / did | What I found |
|---|---|---|
| 09:47 | Read the alert. Checked `make ps` / restart counters. | Alert: api restarted 3 times in 15 minutes. |
| 09:50 | Paged engineering on-call (P1 policy). | — |
| 10:00 | Ran `make load` (the morning traffic) and sampled `docker stats` + restart count every ~6 s. | api memory 45 MiB at start → 60 MiB after the first files → climbs to 108 MiB, then **restart**; climbs again to 102 MiB, **restart**; to 125 MiB, **restart**. Three restarts, same as the alert (`evidence/02-load-sampler.txt`). |
| 10:15 | `docker inspect` the container. | `restarts=3` but `OOMKilled=false` and exit code 0 — **misleading**, so I didn't stop there. |
| 10:20 | Looked in the kernel log from a privileged container (`dmesg`). | `Memory cgroup out of memory: Killed process (api) anon-rss:129152kB` and again `125184kB`. The container limit is 128 MiB (`docker-compose.yml:60`). So **the kernel OOM-killed the api**. (`evidence/02-dmesg-oom.txt`) |
| 10:30 | Why does memory only go up? Read `importer.go:95` and `importer/sources.go`. | Every upload is kept in memory (raw file plus the parsed workbook) in `SourceCache`. Nothing ever removes entries (`grep delete` finds nothing). |
| 10:40 | Checked what the restarts left behind. | 15 imports stuck in "Processing", 67 invoices stuck in "Parsed", hundreds in "Submitted". The submit queue is an in-memory channel (`submit.go:60`), so a restart loses all queued invoices and nothing re-queues them on startup. |
| 10:45 | Checked the 502s. | Load generator saw `EOF`, `connection refused` and DNS errors during the restarts, i.e. the 502s Priya describes. |
| 10:50 | Ruled out. | asp-mock: 0 restarts. Postgres healthy. No panic or error line before the restarts. |

Dead end: `docker events` with filters returned nothing, and the `OOMKilled` flag was false. The kernel log was the only place the OOM kills were visible.

### Root cause

- **What happened:** The api process runs out of memory and the kernel kills it, repeatedly, whenever many uploads arrive close together. Each restart drops the in-memory submit queue and any import in progress, leaving invoices stuck in Parsed/Validated/Submitted and giving customers 502s.
- **Where:** `services/api/internal/importer/sources.go` (cache with no eviction) + `importer.go:95` (keeps `Raw` bytes and the whole `excelize` workbook per import); `docker-compose.yml:60-61` (128 MiB limit, same swap limit); `submit/submit.go:60` + `main.go` (queue only in memory, no recovery on startup).
- **Why it happens:** Memory grows with each upload and is never released; 240 uploads in about 80 seconds took the process from 60 MiB to the limit within about 20 seconds.
- **Evidence:** `evidence/02-load-sampler.txt`, `evidence/02-dmesg-oom.txt`, `evidence/02-restart-analysis.txt`, `evidence/02-load-results.txt`, `evidence/02-make-load-output.txt`.
- **Confidence and open questions:** High for the cause (kernel OOM-kill messages plus a cache that only grows). Open: I didn't take a heap profile, so I can't say how much each upload retains; and production sizes/limits may differ from this lab.

### Customer resolution reply OR escalation note

- **Which one and why:** Escalation (P1) to L3 plus updates to Priya. It's a code and infrastructure defect I can't fix myself.

**Escalation note (L3 on-call), 10:50:**

```markdown
### Escalation: API OOM-killed repeatedly under upload load; restarts drop the submit queue and strand invoices

**Priority:** P1 — repeated restarts, 502s on upload, invoices not reaching the ASP; Marina Bay go-live Wed 18 Nov.
**Customer / seller:** Platform-wide (all sellers); first reports from Marina Bay Hospitality (id 3), via Priya Nair.
**Reported by / at:** Grafana alert 09:42; Priya Nair (forwarded) 09:50
**Affected:** api container restarts=3 in 15 min. After my reproduction: 15 imports stuck "Processing", 67 invoices "Parsed", 11 "Validated", 726 "Submitted" with no ASP result across 5 sellers.

**Symptoms (customer view):**
502 Bad Gateway on and off, mostly when uploading; invoices sitting in "Validated"/"Submitted".

**Evidence:**
- Logs: api log stops mid-stream and a new "api starting" appears at 16:23:40, 16:24:10, 16:25:02 (lab clock). No panic line.
- Kernel log: `Memory cgroup out of memory: Killed process (api) anon-rss:129152kB` and `125184kB`.
- Metrics / dashboard: container memory 45 → 60 → 108 MiB → restart, repeated; limit 128 MiB.
- Database: `SELECT status,count(*) FROM invoices GROUP BY 1` → Parsed 67, Submitted 726; `SELECT status,count(*) FROM imports` → Processing 15.

**Steps to reproduce:**
1. `make up`, then `make load` (about 3–4 min) while watching `docker stats` and `docker inspect ... RestartCount`.
2. `dmesg` from a privileged container shows the OOM kills (note `docker inspect` says OOMKilled=false).

**What I have already tried / ruled out:**
- asp-mock (0 restarts), Postgres (healthy), a panic/crash (no log), manual retry of the stuck invoices (only works for Validated/Failed, not Submitted/Parsed).

**Suspected cause (with confidence):** High. `importer/sources.go` caches every uploaded workbook forever (no eviction); limit is 128 MiB (`docker-compose.yml:60`); in-memory submit queue (`submit.go:60`) is lost on restart with no recovery.

**Workaround in place:** No real workaround. Stop-gap suggestion: raise the api memory limit (e.g. 512 MiB) and redeploy; this buys time but does not fix the leak.

**Timeline:**
- 09:42 alert · 09:47 acknowledged · 09:50 paged · 10:20 OOM confirmed · 10:50 this note

**Ask:** (1) Immediately raise the memory limit and redeploy to stop the restarts; (2) fix the cache (evict by size/age or don't cache the workbook); (3) on startup, re-queue invoices in Validated/Submitted older than a few minutes and mark orphaned Processing imports; (4) data repair for stranded invoices (list of ids attached). I need a status by 11:30 and a fix plan I can give Marina Bay before 12:00.
**Next customer update due:** 10:30 and then every 30 minutes.
```

**Update to Priya (10:30, then every 30 min; this is the 11:30 version):**

> Hi Priya,
>
> Here's where we are on the restarts.
>
> **What we know:** The restarts and 502s have one cause. Under busy upload periods the Invoicely API runs out of memory and is shut down by the system. Every restart interrupts uploads that are in progress and drops invoices that were waiting to be sent, which is why some customers have invoices sitting in "Validated" or "Submitted" since about 09:30.
>
> **What we're doing:** Engineering is raising the memory limit now to stop the restarts, and fixing the underlying memory growth. After that we will push the stuck invoices through ourselves.
>
> **What it means for your customers:** Please ask them not to re-upload files for now, so we avoid duplicates. Invoices already visible in the portal will be sent by us.
>
> **Marina Bay:** I can't promise Wednesday until the stop-gap is live and I've seen the system stay up under a busy period. I'll tell you by **12:00** whether we're on track, in time for your call. If you want to give the GM something today: "we found the cause, a fix is in progress, and we'll confirm readiness before Wednesday."
>
> Next update at 12:00 (or sooner when the memory change is live).
> Naresh

### Workaround offered

None that fully works for customers. Advice: don't re-upload; wait for support to re-send stuck invoices. Engineering stop-gap: raise memory limit.

### Prevention ideas

Cap or evict the source cache (or store the original file on disk/object storage and don't keep the parsed workbook); set `GOMEMLIMIT`; durable submit queue (or a startup sweep that re-queues stale Validated/Submitted); an alert on container memory above 80% **before** the kill; a load test with 240 uploads before every go-live; make the dashboard show restarts and OOM kills from the kernel, because `docker inspect` can show `OOMKilled=false`.

---

## Incident 3 — `inbox/03-al-noor-fuel-br-co-15.md`

### Acknowledgement

- **Sent at (exercise clock):** 10:40 (received 10:15)
- **Reply:**

> Dear Fatima,
>
> Thank you for your email, and for the clear description. I understand that some of your November fuel invoices were rejected with the BR-CO-15 message while others from the same file were accepted, and that your auditor wants a written explanation.
>
> I'm investigating now. I'm comparing the accepted and rejected invoices line by line, so I can tell you exactly why these particular ones failed, and whether anything needs changing on your side. **Please don't change your file or re-send these invoices for now.**
>
> I will write to you again by **13:00 today** with what I've found.
>
> Kind regards,
> Naresh, Product Support, Invoicely Lite

### Priority and justification

- **Priority:** P2
- **Why:** A subset of invoices is rejected (3 of 6 in the sample batch), the customer cannot issue them, and an external auditor is reviewing the VAT position, which adds compliance pressure. Not P1: other invoices are reaching the ASP. If it turns out to affect every customer with 3-decimal prices, I would re-prioritise.
- **SLA deadlines I am working to:** first response 11:15 (sent 10:40); update 13:00 (promised), then every 2–4 h; resolution target 08:15 Tue 17 Nov (8 business hours; the clock pauses after 18:00).

### Investigation log

| Time (exercise clock) | What I checked / did | What I found |
|---|---|---|
| 10:40 | Read the email and the ASP rule list (`docs/template-field-guide.md`). | BR-CO-15: total with VAT must equal total without VAT + VAT. |
| 10:50 | Replayed the Al Noor file (`make load`) and listed all 6 invoices with their totals. | 0041, 0043, 0045 accepted; 0042, 0044, 0046 rejected, each by a cent or two (diff −0.01, −0.02, −0.01). |
| 11:05 | Pulled the stored payloads and redid the maths for every line. | Customer data is correct. Line amounts agree with qty × price (the portal's own rule AE-BR-08 passed). |
| 11:15 | Compared accepted and rejected. | Accepted invoices have line amounts that need no rounding (e.g. `4850 × 2.835 = 13749.75` exactly). Rejected invoices have lines such as `3125 × 2.917 = 9115.625` → shown as 9115.63. |
| 11:30 | Read `pint.go` `computeTotals`. | Net and VAT use the **rounded** line amounts (`pint.go:169-170`), but the total with VAT is computed from the **unrounded** `quantity × unitPrice × (1 + rate)` (`pint.go:171`). Rounded and unrounded disagree by a cent or two. |
| 11:40 | Matched it to the ASP's check (`asp-mock/main.go:225`). | It expects total with VAT = net + VAT, in cents. 0044: sent 11,817.57, expected 11,817.59 — exactly the error message. |
| 11:45 | Considered whether it is the customer's file. | No. Prices with 3 decimals are allowed by the template guide ("Fuel ... often use 3 decimals"). |

Dead end: I first suspected the 3-decimal prices were being rejected by AE-BR-08 tolerance. They weren't; AE-BR-08 passed. The failure is later, in the total.

### Root cause

- **What happened:** The portal calculates the invoice total with VAT from unrounded line values, but the net total and VAT from rounded ones. When any line has a half-cent in `quantity × price`, the totals are off by 0.01–0.02 and the ASP's BR-CO-15 check rejects the invoice.
- **Where:** `services/api/internal/pint/pint.go:171` (`gross += l.Quantity * l.UnitPrice * (1 + l.VATRate/100)`), used at `pint.go:184-185`.
- **Why it happens:** Different rounding in the three totals; accepted invoices are those where rounding cancels out or isn't needed.
- **Evidence:** `evidence/03-alnoor-analysis.txt` (per-invoice net, VAT, stored total, and the difference; the ASP message "Got 11817.57, expected 11817.59").
- **Confidence and open questions:** High. Open: I haven't patched and re-run to prove the fix, and I don't know whether other customers with 3-decimal prices are affected (likely, e.g. fuel, anyone with fractional line amounts).

### Customer resolution reply OR escalation note

- **Which one and why:** Escalation (product defect in our calculation; the customer's file is correct and they cannot fix it), plus an update to the customer including the written explanation her auditor asked for.

**Update to Fatima (sent 13:00):**

> Dear Fatima,
>
> I've finished comparing your invoices, and I have a clear answer for you and your auditor.
>
> **1. Why these invoices were rejected and the others weren't.** Your figures are correct. The problem is in how our system adds up the invoice totals, not in your file. For each line, we round the net amount and the VAT to two decimals, as required. But we calculated the final total with VAT from the unrounded numbers. On invoices where a line has a half-fils result (for example 3,125 litres × 2.917 = 9,115.625), those two methods differ by one or two fils, and the network provider's check, BR-CO-15, requires that total with VAT equals the total without VAT plus the VAT, exactly. The invoices that passed were the ones where no rounding was needed. For example, invoice ANF-2611-0044 was sent with 11,817.57 while the total without VAT plus VAT is 11,817.59.
>
> **2. What you need to correct.** Nothing. Please don't change your quantities, prices or amounts, and please don't re-upload these invoices; that would not help and could cause duplicate-number messages.
>
> **3. How and when they can be issued.** The fix is on our side. I've passed it to our engineering team with the exact lines and numbers, and asked for a fix and a date. I can't give you a date until engineering confirms one. I will write to you again by **16:00 today** with their answer. Once fixed, we'll resend the rejected invoices for you with their original numbers, and I'll confirm each one here.
>
> For your auditor: I'm happy to give you a short written statement on company letterhead of this explanation once it's confirmed. Tell me if you'd like it.
>
> I'm sorry for the delay this causes during your VAT review.
>
> Kind regards,
> Naresh

**Escalation note (L3 Engineering), 12:45:**

```markdown
### Escalation: Invoice total with VAT is computed from unrounded lines, causing ASP rejection BR-CO-15 by 0.01–0.02

**Priority:** P2 — a subset of Al Noor invoices cannot be issued; external VAT audit in progress.
**Customer / seller:** Al Noor Fuel & Lubricants LLC, seller id 4
**Reported by / at:** Fatima Khoury (Finance Manager), email, 10:15 Mon 16 Nov
**Affected:** In the reference file 3 of 6 invoices (0042, 0044, 0046). Likely any seller with fractional line amounts.

**Symptoms (customer view):**
Invoices "Rejected by ASP": BR-CO-15 ... Got 11817.57, expected 11817.59.

**Evidence:**
- Payload excerpt: ANF-2611-0044 totals: taxExclusive 11254.84, taxAmount 562.75, taxInclusive 11817.57 (should be 11817.59).
- ASP response / error code: 422, rule BR-CO-15.
- Logs: `{service="asp-mock"} | json | rule="BR-CO-15"`.
- Metrics / dashboard: asp_documents_total outcome=rejected.
- Database: `select invoice_number,status,total_excl_vat,total_vat,total_incl_vat from invoices where seller_id=4` — diffs −0.01/−0.02/−0.01 on rejected ones, 0.00 on accepted.

**Steps to reproduce:**
1. `make up`; `make replay CUSTOMER=al-noor`.
2. Compare `total_incl_vat` to `total_excl_vat + total_vat` per invoice.

**What I have already tried / ruled out:**
- Customer file errors (AE-BR-08 passes), 3-decimal prices as such (allowed by template), ASP rule being wrong (it is correct per BR-CO-15).

**Suspected cause (with confidence):** High. `pint.go:171`: gross is accumulated as `qty*price*(1+rate)` unrounded, while net and VAT are rounded per line.

**Workaround in place:** No safe customer-side workaround.

**Timeline:**
- 10:15 received · 10:40 acknowledged · 12:45 root cause confirmed · 13:00 customer update

**Ask:** Fix to `TaxInclusiveAmount = round2(net) + round2(VAT)` (and `PayableAmount`), add a unit test with 3-decimal prices; add a portal-side BR-CO-15 check before sending to the ASP; then resend the rejected invoices (list of ids attached). Need a date by 15:30.
**Next customer update due:** 16:00 today
```

### Workaround offered

None that I'd recommend: asking the customer to change prices or amounts to make our totals pass would alter her tax documents to suit our bug. Once fixed, we resend the rejected invoices from our side.

### Prevention ideas

Calculate and test totals from rounded amounts only; add a pre-submission check for BR-CO-14/15 so the portal reports the problem before the ASP does; test with realistic fuel data (3-decimal prices); show a plain-language explanation next to ASP rejection codes.

---

## Incident 4 — `inbox/04-bluepeak-sahara-not-received.md`

### Acknowledgement

- **Sent at (exercise clock):** 11:50 (received 11:30)
- **Reply:**

> Hi Daniel,
>
> Thanks for the detailed note, and for holding off on resending, that's exactly right. Please **don't resend the batch yet**.
>
> I understand that your connector got an HTTP 201, the portal shows the 40 Sahara invoices as "Submitted", but many have no ASP reference and Emirates Palm Hospital has only received some of them.
>
> I'm tracing where each of the 40 invoices is, from our portal to the network provider, and I'll tell you which ones were delivered, which weren't, and the safe way to get the rest to the hospital. I'll update you by **13:30**. Sahara's payment run is noted.
>
> Naresh, Product Support, Invoicely Lite

### Priority and justification

- **Priority:** P2 at first; **raised to P1 after the root cause was confirmed** (see log).
- **Why:** At 11:30 it looked like a subset of one customer's invoices (P2), but a payment run is this week. After investigating, the cause is not specific to Sahara: any batch of more than 8 invoices hits the ASP's rate limit, and the 429 replies leave invoices stuck forever in "Submitted" with no retry. In my `make load` run all five peak customers had hundreds of invoices stuck. That means invoices are not reaching the ASP for several customers, which is P1 by the matrix, so I raised it and told Daniel.
- **SLA deadlines I am working to:** P2: first response 12:30 (sent 11:50), update 13:30, resolution 09:30 Tue. After raising to P1: updates every 30–60 min, resolution target 4 h from the re-prioritisation.

### Investigation log

| Time (exercise clock) | What I checked / did | What I found |
|---|---|---|
| 11:50 | Read the email and `docs/architecture.md` (ASP fair-use limit). | The ASP throttles each sender and replies **429** with `Retry-After`; "the document has not been received and should be sent again later". |
| 12:00 | Replayed Sahara (`make load`). Counted statuses for the 40 invoices. | **8 Accepted (with ASP reference), 32 Submitted with no ASP reference.** Same ratio as Daniel's report. |
| 12:10 | Asked the ASP what it holds for Sahara. | `GET /v1/documents?sender=0235:1006453719` → 8 documents, all accepted. The other 32 never arrived. |
| 12:15 | Looked at the ASP log. | 32 × `rate limit exceeded` for Sahara; `senderBurst = 8`, 2 per second (`asp-mock/main.go:36-37`). |
| 12:20 | Looked at what the api did. | It logged `asp response ... status_code:429` and nothing else. In `submit.go:133-155` the `switch` has cases for 200, 422 and the 5xx codes, **but no case for 429**, so the status stays "Submitted". |
| 12:30 | Looked at the invoice history in the DB. | Parsed → Validated → Submitted ("Sent to ASP"), and then nothing. The portal shows it as normal. |
| 12:35 | Tried the portal's "Retry submission" on a stuck invoice. | **409:** "only invoices in status Validated or Failed can be retried (current status: Submitted)". Support and customer have no way to resend them. |
| 12:45 | Checked other sellers. | After the burst test 726 documents were throttled; Desert Rose, Marina Bay, Palm Coast, Zayed each had 170+ invoices stuck in "Submitted" (some also lost by the restarts, Incident 2). |
| 12:50 | Ruled out. | Not lost in the portal (all 40 stored); not rejected (no 422); not an ASP outage; not Daniel's connector (the 201 is correct, because submission is in the background). |

### Root cause

- **What happened:** The api submits invoices to the ASP in parallel (4 workers). The ASP accepts a burst of 8 per sender, then 2 per second, and answers 429 for the rest. The api does not handle 429, so those invoices stay in "Submitted" forever, with no ASP reference, no error and no retry. The portal and the connector's 201 look fine.
- **Where:** `services/api/internal/submit/submit.go:133-155` (missing `case http.StatusTooManyRequests`, no `Retry-After` handling); `submit.go:77-92` (workers fire as fast as they can); `status-lifecycle` allows retry only from Validated/Failed (`httpapi` returns 409 for Submitted).
- **Why it happens:** Any batch bigger than 8 invoices for one seller exceeds the ASP's burst allowance.
- **Evidence:** `evidence/04-sahara-analysis.txt`, `evidence/00-prometheus-queries.txt` (`invoicely_asp_responses_total`: 200 → 8, 429 → 32), `evidence/02-load-results.txt`.
- **Confidence and open questions:** High. Open: whether the real ASP's limits match the documented ones; how many production invoices are already stranded (needs a DB query by engineering). My test re-upload of the Sahara file created 40 new "Validated" invoices only because the replay tool adds a suffix to invoice numbers; in production the same numbers would be blocked as duplicates, so I did not use that as evidence.

### Customer resolution reply OR escalation note

- **Which one and why:** Escalation. It is a code defect, and the stuck invoices can't be repaired through the product (retry returns 409). Plus a customer update.

**Update to Daniel (sent 13:15, after raising to P1):**

> Hi Daniel,
>
> I've found where the missing invoices are, and I have a clear answer.
>
> **Are invoices being lost?** No. All 40 invoices are safely stored with us. Of the 40, **8 reached the network provider and were accepted; the other 32 were never delivered**. The network provider limits how many documents one sender can send at once (about 8 in a burst) and replied "slow down, try again" for the rest. Our system didn't retry those, so they were left showing "Submitted" with no ASP reference, which is why your connector saw a success and Emirates Palm Hospital received only a few. It's a fault on our side, not in your connector, and I'm sorry for that.
>
> **Should you resend?** Please **don't resend the batch**. The 8 that were delivered would be flagged as duplicates, and the portal's "retry" button doesn't work for these 32. I've asked our engineering team to resend the 32 from our side and to fix the cause, and I've marked this as top priority because of Sahara's payment run.
>
> I'll update you at **14:15**, and then every hour until all 40 are confirmed on the hospital's side. If it helps, I can send you the list of the 8 delivered and 32 pending invoice numbers now.
>
> Naresh

**Escalation note (L3 on-call), 13:00:**

```markdown
### Escalation: ASP 429 (rate limit) is not handled — invoices stay "Submitted" forever; no retry path

**Priority:** P1 (raised from P2) — invoices not reaching the ASP for several customers; Sahara payment run this week; Marina Bay go-live Wed.
**Customer / seller:** Sahara Medical Supplies FZE (seller id 5); also affects every seller with batches > 8 invoices.
**Reported by / at:** Daniel Okafor (Bluepeak ERP, for Sahara), email, 11:30 Mon 16 Nov
**Affected:** Sahara batch 1116: 40 invoices — 8 Accepted, 32 Submitted without ASP reference. In my load test: 726 throttled documents; ~170 stuck "Submitted" per seller for 4 other sellers.

**Symptoms (customer view):**
HTTP 201 on upload, "Submitted" in portal, empty ASP reference, buyer didn't receive most invoices.

**Evidence:**
- Payload excerpt: n/a (invoices are valid).
- ASP response / error code: HTTP 429, `Retry-After: 1`, `{"error":"rate_limited"}`.
- Logs: `{service="asp-mock"} | json | msg="rate limit exceeded"` ×32 for sender 0235:1006453719; `{service="api"} | json | status_code=429`.
- Metrics / dashboard: `invoicely_asp_responses_total` 200=8, 429=32; `asp_documents_total{outcome="throttled"}`.
- Database: `select status,count(*) from invoices where import_id=<batch> group by 1` → Accepted 8, Submitted 32; `invoice_events` ends at "Sent to ASP". `POST /v1/invoices/{id}/retry` → 409.

**Steps to reproduce:**
1. `make up`; `make replay CUSTOMER=sahara`.
2. Wait 10 s; count statuses; call `GET :8090/v1/documents?sender=0235:1006453719`.

**What I have already tried / ruled out:**
- Portal retry (409), lost data (all 40 stored), ASP rejection (no 422), connector error (the 201 is correct).

**Suspected cause (with confidence):** High. `submit.go:133-155` has no case for 429; workers send without pacing (`submit.go:77-92`).

**Workaround in place:** No. Need data repair.

**Timeline:**
- 11:30 received · 11:50 acknowledged · 12:35 root cause confirmed · 13:00 raised to P1, this note · 13:15 customer update

**Ask:** (1) Data repair now: set the 32 Sahara invoices (and other stale "Submitted" with no ASP reference) back to Failed/Validated and re-queue, pacing under 2/s; check at the ASP that nothing is delivered twice. (2) Code fix: handle 429 with `Retry-After` and backoff, pace submissions per sender (client-side token bucket 8 burst, 2/s), and allow retry from stale "Submitted". Need ETA for (1) by 14:00.
**Next customer update due:** 14:15, then hourly
```

### Workaround offered

None available to the customer or to support (retry gives 409). Engineering has to repair the 32 invoices. Customer advice: don't resend. I could also suggest to Daniel that, once the fix is live, large batches arrive in slices of 8 or fewer per second, but I haven't tested that and wouldn't promise it.

### Prevention ideas

Handle 429 (and all non-2xx) explicitly with backoff and `Retry-After`; pace per sender; never leave an invoice in "Submitted" without a timeout sweep that moves it to Failed; alert on invoices in "Submitted" older than 5 minutes and on `asp_documents_total{outcome="throttled"}`; allow retry from stale "Submitted"; show the portal's own explanation for stuck states; test with a 40-invoice batch before release.

---

## Incident 5 — `inbox/05-ghaf-cafe-date-error.md`

### Acknowledgement

- **Sent at (exercise clock):** 12:40 (received 12:10)
- **Reply:**

> Dear Hessa,
>
> Thank you for writing, and I'm sorry for the frustration. I can see that your four invoices were all rejected because of the date, and I know your customers are waiting.
>
> Good news: this is very quick to fix, and I can tell you how. I'm checking your file now, and I'll send you the exact steps in the next hour. In the meantime, please don't worry: nothing has been sent to your customers or lost, and the rejected invoices can be uploaded again with the same invoice numbers.
>
> Naresh, Product Support, Invoicely Lite

### Priority and justification

- **Priority:** P3 (the rule says a single user or a self-service fix); I'd treat it as quick because the customer is non-technical and waiting.
- **Why:** One customer, one validation message, product working as documented, and a simple workaround. Not P2: the platform isn't failing. The customer's tone ("system broken") is an emotional signal, not a technical one.
- **SLA deadlines I am working to:** first response 16:10 (sent 12:40); resolution target 3 days, but I aim to solve it today.

### Investigation log

| Time (exercise clock) | What I checked / did | What I found |
|---|---|---|
| 12:40 | Read the email and the Dates section of `docs/template-field-guide.md`. | `13/11/2026` text is rejected with AE-BR-04 by design (ambiguous: 05/11 is 5 Nov or 11 May). |
| 12:50 | Opened the attached workbook's XML. | Every date cell is **text** (`inlineStr`) in `dd/mm/yyyy` form, not a real Excel date. 16 cells (issue date + due date × 8 rows). |
| 13:00 | Uploaded the original file. | All 4 invoices Rejected by portal, AE-BR-04; GTC-120 has 6 errors because it has three rows. |
| 13:10 | Uploaded a copy where only the dates were changed to `YYYY-MM-DD`. | All 4 invoices **Validated**, 0 errors. No other problem was hiding behind the date. |
| 13:15 | Checked the escalation policy. | Product works as documented → do **not** escalate; explain, and raise the message as a suggestion. |

### Root cause

- **What happened:** Hessa typed the dates as text in `dd/mm/yyyy`; the portal only accepts `YYYY-MM-DD` text or real Excel date cells.
- **Where:** `services/api/internal/validate/validate.go:113-119` (AE-BR-04) and `sheet/sheet.go:171-186` (`ParseDate`: ISO text or Excel serial only).
- **Why it happens:** By design, the portal doesn't guess ambiguous day/month order on a tax invoice. The error message tells her the required format but not how to get there in Excel.
- **Evidence:** `evidence/05-ghaf-cell-types.txt` (cell types and values), `evidence/05-ghaf-results.txt` (original: 4 rejected; dates fixed: 4 validated), `evidence/ghaf-cafe-nov-2026-dates-fixed.xlsx`.
- **Confidence and open questions:** High. Open: whether she'd prefer an automatic conversion — a product decision, not for support.

### Customer resolution reply OR escalation note

- **Which one and why:** Customer resolution reply. No escalation: the product is working as documented. I'll raise the message wording as a suggestion only.

> Dear Hessa,
>
> I've looked at your file, and I can help you fix it in a few minutes. Nothing is wrong with your invoices, and 13/11/2026 is a perfectly good date. The portal just needs it written in a particular way.
>
> **What happened:** Your dates are stored in the sheet as plain text like `13/11/2026`. Our portal can only read dates written as `2026-11-13` (year-month-day), or real Excel dates. We don't accept 13/11/2026 because the same text could mean 13 November or, in another country, a different date, and we're not allowed to guess on a tax invoice.
>
> **How to fix it (two columns, about two minutes):**
> 1. In your file, add a new column next to "Invoice issue date". In its first cell type: `=TEXT(DATE(RIGHT(A2,4),MID(A2,4,2),LEFT(A2,2)),"yyyy-mm-dd")` (change A2 to the cell that has your date).
> 2. Copy that formula down for all rows, then copy the new column and paste it back over the old one using **Paste → Values**. Do the same for "Payment due date".
>
> It's easier still if I do it for you: I've attached your file with only the dates changed to the right format, nothing else touched. You can upload that one as it is. I've tested it on our side and all four invoices (GTC-118 to GTC-121) pass the checks.
>
> Next time, you can type the date as `2026-11-13`, or format the column as a date, and it will work.
>
> Could you upload it and tell me if the four invoices show as accepted? I'll check from my side too. I'm sorry for the frustration. If anything looks different, reply and I'll help straight away.
>
> Kind regards,
> Naresh

### Workaround offered

The corrected file (`evidence/ghaf-cafe-nov-2026-dates-fixed.xlsx`) or the formula above.

### Prevention ideas

Make the AE-BR-04 message friendlier and actionable ("Dates must look like 2026-11-13. In Excel select the column → Format Cells → Custom → yyyy-mm-dd"); add data validation and an example row to the downloadable template; consider a documented option to accept `dd/mm/yyyy` as day-first for UAE customers, as a product decision with the compliance team.

---

## Overall

### Prioritisation

The order I worked was **2 → 1 → 4 → 3 → 5**.

- **Incident 1 (09:05) came first in time.** I acknowledged it at 09:15 and started on it, because it was the only open item.
- **Incident 2 (09:42 alert, 09:50 Priya) pre-empted it.** An API that keeps restarting is P1 by the matrix, and it could be the cause of other problems, so I paged on-call and worked it ahead of Oasis. I told Rashid I'd come back by 10:30 so he wasn't left hanging.
- **Incident 4 next, not 3.** Both are P2, but Sahara's invoices were silently stuck with a payment run coming, and I could see the cause was shared with other customers. Al Noor had a clear explanation and no data at risk. I did acknowledge Al Noor within its target.
- **Incident 3 then Incident 5.** Incident 5 is self-service and has a quick fix.
- **I did change my mind once:** Incident 4 started as P2 and I raised it to P1 when I saw that the same unhandled 429 left hundreds of invoices stuck for four other sellers in my load test. I would also now look at Incident 1 and 2 together in a real shift, since the large Oasis files take a lot of memory in the same cache.

### What I would do differently

- Start with a baseline and a quick sweep of the Grafana dashboard for all five before diving in.
- Use scripts from the start; my early shell quoting through PowerShell/WSL wasted time.
- Take Grafana screenshots for the evidence; this write-up uses logs, SQL and Prometheus query output instead of screenshots (**TODO (Naresh): add screenshots of the Grafana dashboard for incidents 2 and 4 if you can**).
- Check the kernel log for OOM kills at the very start of any restart alert; Docker's `OOMKilled` flag was false here.
- Ask L2 for a second opinion on the P1 raise of Incident 4.

### What I learned / what I would need to learn

<!-- TODO (Naresh): replace or extend this section with what YOU actually learned and how. The points below are what the investigation showed; keep only what is true for you. -->

- How UAE e-invoicing works at a high level (PINT AE over Peppol, the 5-corner model, ASP, TRN, ASP rules like BR-CO-15).
- Reading a Grafana/Prometheus/Loki setup and Docker memory limits; kernel OOM kills versus the Docker flag.
- Reading Go service code to find a root cause (missing HTTP 429 case; unrounded total; cache without eviction).
- What I'd study next: Peppol/PINT AE rules in more detail, Go profiling (pprof), and writing good SQL for incident analysis.

### Time log (real time)

<!-- TODO (Naresh): fill in your real dates and times. I can't know them. -->

| Date | From–to | What I worked on |
|---|---|---|
| | | Setup: WSL 2, Docker Desktop, cloning the lab, `make up` |
| | | Reading docs and code |
| | | Investigating incidents 2, 1, 4, 3, 5 |
| | | Writing SUBMISSION.md, reviewing evidence |

### AI usage disclosure

I used **Claude Code (Anthropic, model Claude Sonnet 5.5)** for most of the technical work: installing and starting the lab, reading the documentation and Go code, running the replay commands, SQL queries, Prometheus queries and kernel-log checks, writing the helper scripts in `evidence/scripts/`, and drafting this document, including the customer replies and escalation notes. I did not use other AI tools.

How the output was checked: every root cause above is backed by output captured from the running lab (in `evidence/`), not just by the AI's reading of the code. Two points where the AI's first theory needed correcting by the system: Docker reported `OOMKilled=false`, and only the kernel log showed the OOM kills; and an early test re-upload for Sahara looked like duplicates but was an artefact of the replay tool, so I did not use it as evidence.

<!-- TODO (Naresh): add a sentence on what YOU personally reviewed or re-ran, e.g. "I re-ran make replay CUSTOMER=al-noor and compared the totals myself." Only write what you actually did. -->
