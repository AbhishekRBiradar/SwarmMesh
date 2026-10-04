# SwarmMesh product roadmap

## Product and evidence

SwarmMesh is an offline Android distributed-work platform:
choose a workload adapter → start Leader/Workers → approve devices → partition
independent tasks → execute and recover failed work → aggregate a validated
result → compare single-device/swarm runs → inspect or export the outcome.
Inventory/package-label verification is the first evidence-backed adapter. The
platform now also contains mathematical computing examples and a planned model/
LLM-training adapter boundary.

The user reports a successful on-phone **Demo Dataset** run: 20 generated images,
13 expected IDs, 13 unique valid IDs, 2 duplicate occurrences, 2 invalid labels,
3 unreadable images, 1 missing expected ID and 1 unexpected ID. This is functional
demo evidence, not real warehouse performance or a production inventory result.

### Two-phone evidence supplied at 21:16 on 2026-10-03

The user supplied screenshots showing three completed benchmark pairs on 40 demo
images (consistent with two copies of the 20-image dataset), plus one pair's JSON
export, `swarmmesh-1791042390911688-48eb6623.json`.

- Screenshot summary: single-device median **1085.54 ms**, best/worst **932.29 /
  1142.22 ms**; swarm median **1411.56 ms**, best/worst **1102.21 / 1471.97 ms**.
  All three pairs report matching correctness; median ratio **0.77×**, approximately
  **30% longer elapsed time** for the swarm. This repeated result does not support
  a consistent speed improvement, despite the earlier single run at 1.18×.
- Exported pair: Xiaomi 2201116SI Leader completed **29** images, Xiaomi POCO X2
  Worker completed **11**; **0 retries**, **21851 sent / 2932 received bytes**,
  `binary-images-v1`, correctness match true. Single/swarm times are **932.287 /
  1411.561 ms**. The export represents one pair, not the whole three-pair series.
- Counts: 13 unique valid, 17 duplicate occurrences, 4 invalid, 6 unreadable;
  missing `PKG-000013`, unexpected `PKG-999901`.
- The export incorrectly says `isDemo: false` for this known demo test. Inspection
  found that image picking overwrote the user's Demo Dataset choice when Android
  supplied numeric filenames. The picker now preserves explicit on/off choices
  and custom session names. This correction affects future reports; the supplied
  evidence remains unchanged.

This confirms on-phone distributed participation, binary transfer and report
export. It does not exercise fault recovery (there were no retries), isolate the
performance bottleneck or establish real-warehouse performance. Next performance
work should measure scheduling/telemetry/transfer costs and address repeated local
telemetry refresh overhead; measurements must remain comparable and truthful.

Keep inventory claims focused on warehouse inventory, campus equipment audits,
small retail audits, field supply verification and offline business operations.
Package ID verification does not establish medical safety or support treatment
decisions. Mathematical workloads are deterministic demonstrations of the
distributed execution platform, not claims of scientific or financial accuracy.

## Development sequence

**Earlier checkpoint (2026-10-03):** The full suite passed **52 tests** before the
on-phone labeling fix. That fix adds a regression test and passes all **5 report/UI
tests** in `test/session_ui_test.dart`; analyzer is clean and the updated debug APK
builds at `build/app/outputs/flutter-apk/app-debug.apk`.

### Distributed Workbench upgrade — version 1.2.5+9

**Verified checkpoint (2026-10-04):** all **67 tests pass**, `flutter analyze`
reports no issues, and the debug APK builds successfully. Synthetic layout
previews of Command, Workloads and Network were rendered at 390×844; automated
small-screen/reduced-motion checks cover a 320×640 viewport. Physical-device
visual review, networking and performance evaluation remain the next phone checks.

- Confirmed team: three final-year engineering students specializing in AI/ML.
  Competition materials now identify the student category.
- New dark-navy/cyan/gold visual system, Command / Workloads / Network
  navigation, prominent mesh controls and logical live-peer visualization.
- Workload catalog and mathematical adapter: deterministic Monte Carlo π,
  linear-regression sufficient statistics and prime factorization execute over
  the same Leader/Worker protocol, with baseline comparison, contributions,
  retries and application-byte measurements. Inventory remains a separate ready
  adapter; model/LLM training is explicitly planned rather than claimed.
- Mathematical runs now persist in private history and export their aggregate
  result, task results, timings, contributions, retries and application bytes.
- Shared launcher/in-app logo with animated intro, per-session role locking,
  startup no-peer timing and live telemetry display. The app locks access below
  20% battery and unlocks automatically after the device reaches the threshold.
- Startup role selection now routes to separate Leader and Worker workspace
  surfaces. The interface uses black, white and the launcher light-blue accent
  rather than a deep cobalt theme.
- Search/filter report records by issue class or ID/filename/device; original
  record identities remain stable and exports retain all records.
- Visual benchmark verdict and time/contribution bars; phase diagnostics expose
  measured totals/counts/maxima and persist in private history, JSON, CSV and text.
  Concurrent spans are explicitly not additive wall time or network latency.
- Independent resource queries run concurrently, with stable model resolution
  reused. Battery/charging/thermal readings remain fresh at each refresh.
- Worker processing/completion feedback and immediate error replies for decoder
  exceptions. The Leader's existing recovery path handles failed replies.
- Old session schema remains readable; missing diagnostics are shown as unrecorded.

No new physical performance result is established by these changes. Re-run the
same phone/dataset conditions and inspect diagnostic exports. Existing work
continues to be disclosed as pre-event research in competition materials.

| Area | Implemented status |
| --- | --- |
| Measured telemetry | RTT, separate rolling image/text/math timings, battery/charging and Android thermal policy |
| Worker recovery | Worker-first reassignment, queues for busy replacements, retained successful batches, bounded attempts and accurate contribution/retry records |
| Export | CSV, JSON, readable text and PDF, including filenames, outcomes, duplicates, missing/unexpected IDs, times and attempts |
| Session history | Automatic inventory and mathematical report-only saves on the Leader, reopening, grouped benchmark summaries and explicit deletion |
| Transfer | Negotiated raw binary image frames, legacy JSON fallback, byte-aware batches and measured application bytes |
| Benchmarks | Three-pair runner, median and best/worst timings for both paths, correctness gating and individually saved pairs |
| UI | Command/Workloads/Network workspaces, workload catalog, logical live-peer diagram, session naming and Demo Dataset labels, searchable/filterable reports, run comparisons, semantic dark-theme tokens, reduced-motion support and About/open-source notices |
| Diagnostics | Image-run phase totals/counts/maxima preserved in history and CSV/JSON/text; concurrent resource queries retain fresh battery/thermal policy |

Remaining work: physical two-/three-phone validation for multiple adapters, thermal
and fault-recovery testing on target devices, a concrete model/LLM training adapter
with a defined model and checkpoint contract, further visual/UX review, and publishable legal pages after operator
details are confirmed. User-supplied physical inventory benchmark evidence is
recorded above; the agent has not independently driven those phone runs via ADB.

1. **Measured telemetry and scheduling:** automatic heartbeat responsiveness,
   previous Worker processing time, rolling per-item task timing (separate image
   and text workloads), Android thermal state, battery/charging/thermal rules.
2. **Worker reassignment:** retain completed results, return unfinished tasks to
   pending, try another eligible Worker, then use the Leader if none is available.
3. **Report export:** CSV, JSON, readable text and PDF; preserve image filenames,
   decoded IDs, validation/duplicate states, missing/unexpected IDs, contributions,
   processing times and retry details.
4. **Session history and deletion:** dataset name, timestamps, Leader and Worker
   identities, saved reports and reopening/export/deletion. Confirm storage and
   retention choices before implementing persistence.
5. **Large-image transfer:** evaluate resizing/compression while preserving decode
   correctness, binary WebSocket messages and optional pre-staged compute-only
   benchmarks. Per-run job-message UTF-8 byte counters are already implemented;
   these exclude network framing, retransmissions and control traffic.
6. **Repeated benchmarks on two and three phones:** median, best/worst elapsed
   times, communication volume/overhead, Worker contributions, retries and
   correctness match. Keep network-inclusive and compute-only results distinct.
7. **Focused UI redesign:** semantic colors, solid dark surfaces, restrained
   yellow, no unnecessary glow, consistent controls/spacing, legible contrast,
   small-screen layouts, accessible labels and reduced-motion support. Show real
   empty/loading/error/approval/success states. Label generated data **Demo
   Dataset**. Radar motion must communicate discovery. Never invent measurements.
8. **About / Legal:** confirmed Terms, Privacy, open-source notices, app version
   and contact. Consider `/terms` and `/privacy` only if Web is actually supported.
9. **Target-environment validation:** complete workflow using real package-label
   images, Android thermal behavior, NSD/hotspot connections and failed Workers.

Security hardening before production use includes pairing codes/QR, authenticated
messages, Worker identity verification, replay protection, approval expiry,
encrypted transport where required and clear image-transfer privacy information.
Current approval controls participation on trusted local networks; it is not
cryptographic authentication.

## Confirmed storage policy and remaining legal decisions

The user delegated the storage choice. The selected default is automatic **report-only**
history in the Leader's private Android no-backup directory, retained until explicit
deletion, app-data clearing or uninstall. Source image files are not copied into
history. Separately exported files are managed by the user and are not removed when
a saved session is deleted. Save failures are visible and retryable.

Still needed before publishing legal pages:

- Operator/developer name and contact email.
- Country, jurisdiction and any chosen governing law.
- Accounts and payments now or planned.
- Whether images remain exclusively on local devices.
- Confirmation that the implemented storage/retention policy is the policy to publish.
- Planned analytics or crash reporting.
- Minimum user age / intended user group.
- Organization use, personal use, or both.

Current implementation: no cloud backend, accounts, payments, analytics or cookies.
Completed inventory reports are now persisted as private local session files.
Local discovery, device telemetry and image transfer occur between approved local
devices. Workers use temporary files during decoding. Export uses the system save
picker. Update legal text when these facts change; do not invent operator details.
