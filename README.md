# SwarmMesh — Distributed Work Platform

SwarmMesh is an offline, local-network distributed-work platform for Android phones. Nearby devices advertise a `_swarmmesh._tcp` service with Android NSD/mDNS, then exchange independent work units over a WebSocket endpoint. No cloud server is required for the core computation. Inventory verification is one example adapter; the platform is designed for mathematical computing, model-training workloads and other partitionable jobs.

The workload-platform scope, adapter sequence, design requirements and decisions needed for storage/legal pages are recorded in [ROADMAP.md](ROADMAP.md).

## About

SWARM MESH is a local-first distributed work platform for nearby Android
devices. One phone acts as the **Leader** and assigns independent tasks to
approved **Workers** over a local Wi-Fi or hotspot network. Work can continue
without a cloud backend or internet connection.

The project provides a reusable mesh runtime for workload adapters, including
inventory verification and mathematical computing. It includes device
discovery, connection approval, telemetry, workload recovery, measured
contributions, private run history and report export.

### Current status

- Flutter application with Android Leader and Worker workspaces
- Local WebSocket communication with NSD/mDNS discovery
- Inventory image decoding and validation reports
- Monte Carlo π, linear regression and prime-factorization workloads
- JSON, CSV, text and PDF report export
- Automated test suite and debug APK build support

## Working milestone

**Version 1.2.5+9 — focused platform UI checkpoint.** The app now has focused
Command, Workloads and Network views, a workload catalog, mathematical task
execution, a logical live-peer diagram, searchable inventory report records,
visual run comparisons and persisted image-run diagnostics.

Verified on 4 October 2026: **67 tests passing**, clean analyzer, successful debug
APK build. Install the update on each participating phone from Windows CMD:

```bat
adb install -r "D:\swarm_mesh\build\app\outputs\flutter-apk\app-debug.apk"
```

The update preserves app data. Check **About** for `1.2.5 · build 9`, then repeat
the same image benchmark and export its new diagnostics for a measured comparison.

The role screen uses the `SWARM MESH` wordmark with the subtitle **Offline
Distributed Work Platform**. Workspace copy is intentionally concise; detailed
run information remains available in reports and history.

The current build implements the first complete vertical slice of the distributed-work vision:

- **Leader/Worker role selection** in the Flutter UI.
- **Role-specific workspaces**: Leaders see workloads, reports and mesh controls;
  Workers see assigned-work status, device monitoring and network controls.
- **Role lock per app session**: after choosing Leader or Worker, the role stays
  fixed until the app is restarted.
- **Shared device branding**: the Android launcher mark is used in the header and
  animated intro, with the same mark on the Android launch screen.
- **Workload catalog** with mathematical computing and inventory adapters ready;
  model/LLM training is defined as a planned adapter contract.
- **Mathematical workloads** for deterministic Monte Carlo π estimation, linear
  regression over partial sufficient statistics and prime factorization.
- **Mathematical history and reports**: completed runs save privately on the
  Leader and can be reopened or exported as JSON, CSV, text or PDF.
- **Local WebSocket endpoint** on port `4040` on every active phone.
- **NSD service registration and discovery**, including lost-service cleanup and registration cleanup.
- **Permission-gated protocol handshake**: the receiving Leader or Worker must approve or reject a connection request before telemetry, heartbeats or jobs are accepted.
- **Refreshed telemetry exchange** with node ID, model, battery/charging state, logical CPU estimate, initial weight and Android thermal status when available.
- **Measured responsiveness and processing** with correlated heartbeat RTT, previous Worker batch duration and separate rolling per-item timings for image decoding, record validation and mathematical tasks.
- **Heartbeat and connection status** so a Leader can see whether a worker is still reachable.
- **Startup discovery timer**: the Command view reports search time and gives a
  recovery path when no device is found.
- **Live device monitoring**: battery, thermal status and telemetry age refresh
  continuously. Access is locked below 20% battery until the device reaches 20%.
- **Resource-weighted task partitioning** using measured task costs and heartbeat responsiveness, with core-based cold-start estimates and battery/thermal headroom rules.
- **Stored-image inventory workload**: select label images on the Leader, decode QR/barcodes with on-device ML Kit, and send small image batches to approved Workers.
- **Distributed inventory-record validation** for decoded IDs in the form `PKG-000123`.
- **Result aggregation** with valid, duplicate, invalid and unreadable counts.
- **Worker-first fault recovery**: an unfinished batch moves to another eligible Worker on disconnect, timeout, rejection or malformed result. Busy Workers queue the work; the Leader is the fallback when none remains. Earlier completed batches are retained.
- **Correctness comparison**: the same 900-record dataset is processed as a single-device baseline and as a swarm run; elapsed time, throughput and speedup are shown only when both results have the same correctness fingerprint.
- **Measured job traffic**: the benchmark panel shows sent, received and total application bytes, including binary image frames, legacy JSON/base64 messages and failed attempts.
- **Report export and history**: completed inventory Leader reports save automatically in private Android no-backup storage. Reopen/delete them in History and export CSV, JSON, readable text or PDF using the system save picker.
- **Repeated benchmarks**: run three single-device/swarm pairs and view medians, best/worst times, correctness and per-run contributions, bytes and retries. Local-only fallback does not claim a swarm speedup.
- **Manual connection fallback**: the app displays local IPv4 addresses and lets
  the Leader connect to a Worker when automatic discovery fails. The network
  must permit client-to-client connections; manual IP cannot bypass isolation.
- **Report investigation**: search package ID, filename, image ID or device;
  filter needs-review, duplicate, unreadable and retried records. Exports always
  contain the complete report, regardless of the active screen filter.
- **Image-run diagnostics**: inspect measured phase totals, sample counts and
  maximum spans in Run Intelligence; timings also persist in history and all
  export formats. Older reports remain readable with diagnostics unavailable.
- **Worker feedback**: the Worker displays processing/ready state and actual
  batch completion counts; native decoder exceptions return a failed reply so
  the Leader can recover without waiting for the job timeout.

The synthetic text demo remains available for protocol testing. Mathematical
workloads use deterministic task payloads and validated aggregate results. The
inventory adapter uses stored image files, on-device ML Kit barcode/QR decoding
and the same distributed scheduling/recovery layer. An expected-ID `.txt` or
`.csv` file is optional; without it, missing/unexpected checks are not claimed.

## Try it on phones

1. Connect two or more Android phones to the same Wi-Fi network or to one phone's hotspot. Internet access is not needed.
2. Build and install the debug APK on each phone:

   ```bash
   flutter pub get
   flutter build apk --debug
    adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```

3. Open SwarmMesh on each phone.
4. In **Command**, select **WORKER** on the phones that will execute jobs and tap **START WORKER**.
5. In **Command**, select **LEADER** on one phone and tap **START LEADER**.
6. Open **Network** to inspect **DISCOVERED PEERS**. Connection approval prompts appear on every workspace.
7. When a device appears under **CONNECTION PERMISSION**, review its role, model and address, then tap **APPROVE** or **REJECT**. Approval is required on the device receiving the request; both Leader and Worker roles can receive requests. Wait for `CONNECTED` before running a distributed workload.
8. On the Leader, open **Workloads** and choose **Mathematical computing**. Select Monte Carlo π, linear regression or prime factorization, then tap **Run distributed mathematical workload**. The Leader computes a baseline, partitions deterministic tasks across approved Workers, aggregates the answer and shows contributions, bytes, retries and measured comparison.
9. To use the inventory adapter instead, choose **Inventory verification**, tap **SELECT IMAGES** and choose stored label images. Optionally choose an expected-ID `.txt` or `.csv` file.
10. Enter a dataset/session name and mark generated images as **Demo Dataset**. Tap **Run image workload**. The Leader first decodes the same image set locally, then transfers small image batches to approved Workers for local decoding and displays elapsed time, throughput, correctness and speedup.
11. **Run text Demo Dataset** remains available for protocol testing. **Run 3-pair image benchmark** repeats the inventory comparison three times; **Finish current pair, then stop benchmark** cancels remaining pairs.
12. If NSD does not connect, use the hotspot fallback described below.
13. Under **REPORTS & HISTORY**, tap **Open / export report** to inspect inventory results and export them. **History** reopens saved sessions and grouped benchmark summaries. Deleting a saved session removes its private report only, not source images or separately exported files.

**Command** provides role/start controls, a logical peer map, workload activity and
recent reports. **Workloads** owns adapter selection and execution; inventory owns
image input/report controls while mathematical computing owns numerical task controls.
**Network** contains device resources, measured timings, connection tools and logs.
The header's History button is available from every workspace. Topology motion is
decorative activity feedback: node positions do not measure physical location,
and moving dots do not measure packets. Reduced-motion settings stop it.

The same node name is not reused between app launches; the short random node ID also keeps the advertised NSD name within Android/DNS-SD naming limits.

## Generate and install a demo image dataset

A reproducible **Demo Dataset** is included in `sample_images/`. It contains 20 generated PNG images: valid IDs, duplicates, two invalid values, one unexpected value and three blank unreadable images. The expected inventory list is `sample_images/expected_ids.txt`. These demonstrate functionality and must not be presented as real warehouse performance or production inventory evidence.

Regenerate it at any time with:

```bash
dart run tool/generate_demo_qr.dart
```

Copy it to the Leader phone from PowerShell:

```powershell
adb shell mkdir -p /sdcard/Pictures/SwarmMesh
adb shell mkdir -p /sdcard/Download/SwarmMesh
adb push .\\sample_images\\ /sdcard/Pictures/SwarmMesh/
adb push .\\sample_images\\expected_ids.txt /sdcard/Download/SwarmMesh/expected_ids.txt
```

Then select the PNG images with **SELECT IMAGES** and choose `expected_ids.txt` with **EXPECTED LIST**. Only the Leader needs these files; it transfers the image bytes to approved Workers.

## Hotspot fallback process

Use this when a phone can see the hotspot but Android hotspot/AP isolation prevents NSD/mDNS discovery:

1. Start the SwarmMesh service on the Worker and keep it active.
2. On the Worker, read the address shown under **HOTSPOT FALLBACK**. The service port is always `4040`.
3. Start the Leader on the other phone.
4. On the Leader, enter the Worker's IPv4 address, such as `192.168.43.25`, and tap the arrow button. Do not enter `http://` and do not add `:4040`; the app supplies the port.
5. The Worker will show a **CONNECTION PERMISSION** request. Confirm the model, role and address, then tap **APPROVE**.
6. The Leader completes the handshake and the peer changes to `CONNECTED`.

If the address list is empty, both phones may be on different networks, the hotspot may isolate clients, or Android has denied local-network access. Check Wi-Fi/hotspot status and repeat with both apps active. A rejected request or a wrong address does not grant job access.

## Architecture

```text
 Flutter UI / workload catalog
   |
 MeshRuntimeService
   |-- DeviceTelemetryService -> battery, device model, logical CPU count
   |-- MeshDiscoveryService   -> NSD/mDNS registration and browsing
   |-- MathWorkloadEngine     -> deterministic numerical/discrete task adapters
   |-- InventoryImageService -> stored-file QR/barcode decoding with ML Kit
   |-- WebSocket protocol     -> connection_request, approval, hello, heartbeat, job, job_result
   |-- weighted partitioner   -> contiguous chunks with exact coverage
   `-- workload result        -> validated aggregation and device contributions
```

The Leader can process a local chunk as well as remote chunks. Workers accept
mathematical task jobs, text-label jobs or image-byte jobs, process them locally,
and return a validated `job_result`. Each adapter owns its task/result contract;
the shared runtime owns approval, scheduling, telemetry, recovery and traffic
measurement.

### Recovery and image transfer

The scheduler commits each successful image batch once. Failed batches become pending and are assigned to another approved, responsive Worker that passes the battery/thermal policy. A busy replacement is queued rather than skipped. A Worker that fails an attempt is excluded for the rest of that run, bounding retries. Local fallback is serialized with the Leader's own work. Contributions are summed by the actual completing node; failed attempts and per-item attempt histories are retained for export.

Updated peers advertise `image-binary-v1` in the approved handshake. Image jobs then use binary WebSocket frames: `SMI1`, a four-byte big-endian header length, a UTF-8 JSON metadata header and the original raw image bytes. Older peers use JSON/base64 automatically. Results remain JSON. No resizing or lossy recompression is applied.

Batches contain at most four images and target at most 8 MiB of source bytes. A single larger image is sent alone, subject to a 32 MiB binary-frame limit and a 64 KiB header limit; images exceeding the transfer limit run locally. Counters and saved reports identify the transport modes actually used. Binary transfer removes base64 expansion, but does not guarantee faster decoding or a net swarm speedup.

### Reports, history and repeated runs

Reports preserve image ID/filename, raw and normalized values, valid/invalid/unreadable state, duplicate occurrences, decode status/reason, per-image processing time, completing device and attempt history. Missing/unexpected checks are labelled **not performed** without an expected list. Attempt processing durations refer to whole batches; they must not be summed once per item. Retry totals count failed remote attempts, while per-item retry counts describe which items were affected.

Completed reports are saved as versioned JSON files in the Leader's Android `noBackupFilesDir/inventory_reports` directory. They persist across app restarts and remain until explicitly deleted, app data is cleared or the app is uninstalled. Source image bytes are never copied into history. Writes use temporary files and rename, and save/load/delete operations are serialized. Unreadable saved files are reported and retained. Save failures remain visible with a retry action; export can still use the in-memory report.

CSV includes item rows and summary rows for timings, devices, contributions, retries, traffic and missing/unexpected IDs. Formula-like spreadsheet text is escaped; JSON retains raw values. Export destinations are chosen through Android's system picker and are outside history retention/deletion controls. The readable format is `.txt`; PDF exports contain the summary and all record rows.

The three-pair benchmark saves each completed pair with a shared group ID. History reconstructs medians and best/worst times after restart, and every pair remains individually exportable. Timing includes processing and report aggregation; the distributed timer also includes scheduling, queuing and transfer. Selection, telemetry refresh before scheduling, history writes and export are outside these timing windows. Runs use a fixed single-then-swarm order; warm-up/order effects are not removed. Speedup is suppressed for correctness mismatch, different inputs or any pair that falls back entirely to the Leader.

### Measured telemetry and scheduling

- Device resources refresh every five seconds while the mesh is active and before a workload/Worker job. Android API 29+ supplies `PowerManager.currentThermalStatus`; unsupported/failed readings are shown as **Unavailable**, not normal. Battery-read failures likewise remain unknown.
- Battery level, charging state and thermal queries are started concurrently;
  stable device-model resolution is reused. Live resource values are not cached
  between refreshes, and thermal/battery exclusion rules still apply per batch.
- Heartbeats carry current telemetry and echo a probe ID. A local monotonic stopwatch measures application round-trip responsiveness (including device/event-loop delays), without relying on clock synchronization. RTT is smoothed with 25% weight on the latest sample and expires after 24 seconds. Old peers without probe support show no measured RTT.
- Workers report `processingMicroseconds` for local batch processing, excluding the socket transfer. Only validated completed results train the scheduler; decode errors and malformed results do not supply timing samples. Older Workers remain compatible and show **not measured** for unavailable timing fields.
- Each node has separate image, text and mathematical timing windows, retaining up to eight batches. The per-item average is total processing time divided by total items in that window, so different batch sizes are comparable. Samples expire after five minutes without a new measurement and are reset when the mesh stops; a reconnected peer starts a fresh window.
- New allocations use inverse estimated per-item cost, with heartbeat RTT amortized over the expected batch size. Unmeasured Workers initially use the Leader's measured baseline scaled by logical-core ratio; cores alone are the fallback when no timing exists. These are scheduling estimates, not device benchmark scores. Different image complexity and transfer bandwidth still limit prediction quality.
- Below 20% known battery, app access and new compute are blocked until the device reaches 20%; charging does not bypass this access gate. From 20–39% battery, eligible work uses three-quarter weight; external power removes that scheduling reduction above the access threshold, but never the thermal pause. **LIGHT** thermal status uses 80% weight and **MODERATE** uses 50%. Unknown battery uses a conservative 75% factor.
- Paused/unresponsive Workers are excluded from new allocations, and eligibility is rechecked before each remote image batch. Recovery tries other eligible Workers first. If the Leader is paused, the benchmark stops with a reason rather than running its required single-device baseline or local fallback. A running native decode is allowed to finish; thermal events do not cancel an in-flight ML Kit call.

The peer panel displays real RTT and previous/rolling task timings with empty/stale states. Live scheduling windows reset when the mesh stops; completed report measurements persist in history. The mesh still uses the trusted-local-network security model.

### Image-run phase diagnostics

Run Intelligence shows single/distributed time bars, actual completed device
contributions and an expandable **Performance diagnostics** panel. Image runs
measure scheduling, batch preparation, device queue wait, local telemetry,
image materialization (file reads/base64 conversion), encoding/socket enqueue,
remote-result wait, local processing and report aggregation. The baseline records
local processing and aggregation. Failed remote waits are included.

Each phase records total microseconds, sample count and maximum span. Concurrent
task spans overlap, so totals are **not additive wall-time percentages**. Remote
wait includes Worker-side telemetry/queueing/decode and reply handling; it is not
isolated network latency. These measurements do not include pre-run refresh,
photo selection, history saving or export. Text-demo and older sessions show
diagnostics as unavailable rather than inventing values.

The telemetry change removes sequential waiting between independent queries; a
net on-phone speed improvement has not yet been measured. Use new exported
profiles to identify the dominant costs before choosing the next optimization.

### Communication measurements

The benchmark's **Sent**, **Received** and **Total** values measure application-message bytes from the Leader's perspective. Sent bytes count complete binary application frames or UTF-8 JSON job messages queued on an open WebSocket; they do not confirm delivery. Received bytes count replies for pending jobs from their assigned Workers, including malformed replies that trigger recovery. Traffic from earlier image batches and failed attempts is retained through reassignment and local fallback.

Counters start at zero for each run. Single-device baselines and local-only runs use zero. Discovery, handshakes, heartbeats, late/duplicate replies, WebSocket/TCP headers and network retransmissions are excluded. These values describe workload communication volume, not network latency or the full on-air byte cost.

## Checks

Run these from the project root:

```bash
flutter analyze
flutter test
flutter build apk --debug
```

The pure inventory tests cover strict protocol JSON, whitespace preservation, duplicate/missing/unexpected IDs, deterministic correctness comparison, resource-weighted partition coverage and invalid resource weights.

Loopback WebSocket runtime tests check measured job bytes, Unicode, binary/legacy negotiation, image batching, per-run reset, busy-Worker reassignment, disconnect/timeout recovery and contribution accounting. Device telemetry, discovery and image decoding are replaced in those tests; on-phone ML Kit and NSD still require the real-device checks below.

Telemetry tests also cover native-channel fallback, old protocol peers, timed heartbeats, automatic resource refresh, Worker processing durations, timing windows, battery/thermal exclusions and measured scheduling weights.

Report/storage tests cover JSON round-trips, CSV quoting, unknown expected-list checks, median calculations, report-only retention, controlled deletion and corrupt-file handling. Widget tests exercise repeated-run controls, export cancellation/failure, history reopening/deletion, small-screen layouts and reduced motion.

Additional checks cover overlapping resource queries with fresh thermal/battery
policy, diagnostic counts through disconnect/fallback, legacy report loading,
diagnostics in all export formats, report filtering with stable record identity,
complete exports while filtered, and navigation at a 320-pixel viewport.

## Known gaps before the final demo

- Full-resolution image transfer can still dominate performance despite binary transport. Resizing/compression and pre-staged compute-only benchmarks remain future evaluation work.
- The scheduler now uses measured processing and RTT, but cold-start core estimates and battery/thermal factors still need validation on real phones. It does not yet model image complexity or transfer bandwidth.
- Hotspot/AP isolation and Android vendor power-management settings can still block NSD or local sockets; the manual address path helps diagnose that case.
- Real-phone NSD, WebSocket round trips and disconnection recovery must be exercised on the target CPH2001/2201116SI devices; local analyzer/tests cannot prove those network behaviors.
- Android's report save picker, private history and repeated benchmarks need a full two-/three-phone acceptance run with real label images.
- The About area includes version, current data-handling facts and open-source notices. Publishable Terms/Privacy/contact information still requires confirmed operator and jurisdiction details.
