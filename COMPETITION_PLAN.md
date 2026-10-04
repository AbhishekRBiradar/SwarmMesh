# SwarmMesh — Bengaluru competition preparation

Updated **3 October 2026** from the implementation, user-supplied phone evidence,
dashboard screenshot and official public event pages/assets. Team resources:
**three final-year engineering students specializing in AI/ML, one laptop,
three to four phones**. The user confirmed the all-student team category.

- [SUBMISSION_DRAFT.md](SUBMISSION_DRAFT.md): portal-ready review copy, team roles
  and organizer clarification email.
- [COMPETITION_DECK.html](COMPETITION_DECK.html): eight-slide, browser-printable
  draft; export and inspect a PDF before attaching it to the application.

## 0. Verified event facts and their implications

### Dates, entry and required artifacts

| Item | Public information checked on 3 October | Action for this team |
| --- | --- | --- |
| Event | iQOO Hackathon 2026 Grand Finale, Bengaluru, 9–11 October, advertised as 48 hours | Prepare for the finale, not the 30-hour city format |
| Idea deadline | **5 October 2026, 23:59:59 IST** in the site's public battle configuration; date also shown in the user's dashboard screenshot | Aim to submit by **18:00 IST on 5 October** as an internal buffer |
| Entry route | Direct finale registration is allowed, alongside city qualifiers; ideas are screened | Registration is not shortlisting; confirm treatment of earlier unsuccessful city applications |
| Team | 1–3 members, all students or all working professionals | Confirmed: three final-year AI/ML engineering students; use the student category |
| Finale tracks | Mobility, Community App, Smart Living, Productivity, Developer Tools, Open Innovation | Recommend **Productivity** for inventory reconciliation; verify the selected dashboard statement |
| Idea form | Title 5–200 characters; description 50–2,000; required PDF/PPT deck up to 25 MB or deck link; optional video/prototype URLs | Use the draft and attach a reviewer-accessible deck |
| Submission owner | Only the team leader submits/updates; form includes prior work, proficiency, differentiation and pre-existing-component disclosure | Assign one owner and check the saved confirmation |
| Phone-first | Entry must run and pitch on the iQOO phone; Flutter is accepted | Rehearse actual phone operation and the Office Kit workflow |
| Loaner devices | Public guide says one flagship iQOO loaner per person | Confirm finale availability and local-network permissions; existing measurements are not iQOO benchmarks |

**Source boundary:** the screenshot shows dates, not team completion, selected
track or shortlisting status. Public dashboard JavaScript exposes the form and
public configuration; it does not establish the user's signed-in account state.

### Existing-code rule — resolve before finalizing the event build

The guide says **“code written during the event window”**, **“No shipping a
pre-built product”**, and that carrying in a completed app is not allowed. The
Terms permit pre-event drafting of ideas and attributed third-party libraries,
but require original work created during the Event. They also prohibit work
developed for or submitted to another competition; “Event” includes this series'
city rounds and finale. Do not assume that clause either permits or prohibits
resubmitting this team's earlier city idea without organizer clarification.

SwarmMesh already has substantial code. Disclose the prototype as **prior
research**, ask what reference/reuse is permitted, and distinguish any allowed
event-window implementation from the existing app. Checking the portal's
disclosure box is not an exception to the guide. The email in
[SUBMISSION_DRAFT.md](SUBMISSION_DRAFT.md#4-organizer-clarification-message--ready-to-personalize)
asks these questions without claiming an existing authorization.

### AI/model expectation — public wording needs clarification

The site's general wording says a local or open-source model at the core earns
“brownie points”; the guide's stack paragraph also says that an entry running on
the phone **with a local or open-source model at the core** qualifies. Open
Innovation explicitly includes the model requirement. These do not establish
whether this team's ML Kit-based inventory workflow meets the intended bar.

Current facts: ML Kit handles on-device barcode/QR decoding; scheduling is
rules-based; there is no local LLM or verified Snapdragon NPU integration. Ask
whether ML Kit is sufficient for Productivity. If an additional model is required,
scope a useful, feasible capability with the organizers before promising it.

### Published judging rubric and preparation priorities

This is the **published guide/series rubric**, not a verified idea-screening
formula or a guarantee that finale weights remain unchanged. Terms allow rubrics
to vary by round. The public FAQ describes idea screening using novelty,
technical impact, problem choice, feasible scope and phone-first fit without
numeric weights; its 30-hour wording refers to city battles.

| Published criterion | Weight | Evidence to prepare |
| --- | --- | --- |
| End product quality | 30% | A clear inventory result, usable phone workflow and saved/exported report |
| Novelty and impact | 20% | Explain orchestration/traceability; obtain real workflow feedback and review alternatives |
| HackTracker: creative phone use | 15% | Genuine phone-based development/use and on-device processing; confirm what the tracker measures |
| Technical depth | 15% | Explain batching, measured scheduling, coverage and recovery with actual evidence |
| HackTracker: Office Kit usage | 10% | Use the phone/laptop bridge for useful permitted build, test and presentation tasks |
| Demo and presentation | 10% | Rehearsed phone demo with a comprehensible report and honest measurements |

The two phone/Office Kit categories total **25%**. SwarmMesh's own Worker/job
telemetry is separate from event HackTracker and does not establish those scores.
Rehearse meaningful use; do not generate artificial tracker activity. The guide
mentions a 3–5-minute pitch, but the finale-specific duration remains to confirm.

### Official sources

Checked **3 October 2026**. Public assets were read because these routes return a
generic SPA shell to a non-interactive fetch. Asset hashes may change on redeploy.

- [Finale dashboard](https://iqoo.reskilll.com/dashboard/iqoo-finale) and the user's
  `Screenshot 2026-10-03 215027.png`: deadline date and finale dates.
- [Guide & Rules](https://iqoo.reskilll.com/guide),
  [public guide module](https://iqoo.reskilll.com/assets/Guide-DnnSgl8Q.js): teams,
  direct entry, phone-first format, build rules and rubric.
- [Terms & Conditions](https://iqoo.reskilll.com/terms), marked updated 10 September
  2026; [public terms module](https://iqoo.reskilll.com/assets/TermsAndConditions-CDmNp6P6.js):
  original work, event definition, pre-event ideas and variable evaluation rules.
- [Public site configuration](https://iqoo.reskilll.com/assets/index-C_hxNPZz.js):
  exact deadline `2026-10-05T23:59:59+05:30`, finale tracks/schedule, rubric and FAQ.
- [Public dashboard module](https://iqoo.reskilll.com/assets/BattleDashboard-CfXtAY5v.js)
  and [form constants](https://iqoo.reskilll.com/assets/constants-C1Ds92mA.js):
  form fields, attachments, limits, disclosure and leader-only submission.
- Series contact from the official guide/Terms: **sameera@reskilll.com**.

## 1. The central proposition

**SwarmMesh: offline inventory verification using nearby Android phones.**

One-sentence explanation:

> A team selects stored package-label photos, recruits nearby phones over a local
> network, and receives one report of valid, duplicate, missing and unexpected
> package IDs, with a record of which device processed each image.

Proposed initial user: a small stockroom or campus equipment-audit team that can
provide permission to test. Choose one reachable team and validate the workflow
with them before making claims about demand, time savings or willingness to pay.

The current work starts from **stored images**. Image capture, label placement,
physical counting and identifying unphotographed items are separate operations.
Current inventory validation expects `PKG-` followed by six digits. Production
label formats and expected-list mappings need confirmation with the pilot user.

## 2. What the existing evidence supports

| Claim | Evidence / qualification |
| --- | --- |
| Work executes on two phones | Exported pair: Xiaomi 2201116SI processed 29 images, POCO X2 processed 11 |
| Binary image transfer works | Exported `transports` includes `binary-images-v1` |
| Results agree with local baseline | Exported correctness match; three-pair screenshot reports agreement across runs |
| Audit reports can be exported | Actual JSON supplied by the user includes item results and device contributions |
| Sessions appear in history | User screenshot shows grouped benchmarks and saved reports |
| Recovery logic exists | Automated loopback disconnect, timeout and replacement-Worker tests; physical three-phone recovery demo still required |
| Device/resource awareness exists | Battery, charging, Android thermal readings, RTT and per-workload task timings feed scheduling |
| Core processing has no cloud dependency | Local NSD/WebSocket/ML Kit architecture; rehearse an internet-disconnected local-network demo |
| Speed improvement is conditional | Three-pair 40-image demo: median local 1085.54 ms, swarm 1411.56 ms, ratio 0.77×; swarm took about 30% longer |

The earlier single-run 1.18× result is not the repeated benchmark result. Display
the repeated result when discussing that dataset. No retries occurred in the
exported two-phone run, so it cannot demonstrate recovery.

The demo images are generated test data, not a warehouse pilot. The exported
21:16 report incorrectly had `isDemo: false`; the image-picker reset bug has been
fixed for future runs. Retain original evidence and annotate the correction.

Do not claim a novel barcode decoder, a trained proprietary AI model, Wi-Fi
Direct, Bluetooth mesh, encrypted peer authentication, internet-free pairing in
every network configuration, or guaranteed speedup. The current topology is a
Leader coordinating Workers over a shared Wi-Fi/hotspot network. ML Kit supplies
the barcode/QR decoder; the contribution is its orchestration and audit workflow.

## 3. Prior-research / idea pitch — approximately 90 seconds

This describes the **pre-existing prototype**. For an on-site pitch, identify the
agreed baseline and describe only work actually delivered in the event window.

> Imagine a small stockroom team finishing an inventory check where internet
> access is unreliable. They have package-label photos and an expected list, but
> still need an answer: what is duplicated, missing, unreadable or unexpected?
>
> Our prior research produced SwarmMesh, an Android prototype that turns nearby phones into a local
> inventory-processing team. One phone selects the photos. Approved nearby phones
> decode assigned batches, and the Leader creates a single report that can be
> saved and exported without a cloud processing backend.
>
> The engineering challenge is coordinating different phones reliably. We measure
> responsiveness and processing time, account for battery and thermal conditions,
> and have implemented reassignment of failed batches while retaining completed
> results. Every report records device contributions and attempts.
>
> Our two-phone test completed all 40 demo images with matching single-device and
> distributed results. It also taught us an important constraint: on this small
> dataset, our three-pair median was slower than one phone. We expose that result
> instead of assuming that adding devices always helps.
>
> For the finale we propose a scoped, event-window implementation, subject to
> the organizers' rules on prior work: a usable on-phone inventory report first,
> then shared execution and recovery. We also want to identify when distribution
> is worthwhile and validate the workflow with an actual inventory team. Our
> prior research gives us concrete measurements to inform that proposal.

Adapt length only after confirming the event's allotted time. Replace the
hypothetical opening with an actual observed user problem after pilot interviews.

## 4. Slide outline — eight slides

1. **Problem and user:** one inventory team, its current process, a genuine
   example of a duplicate/missing-ID task. Interview evidence if obtained.
2. **Workflow:** select photos + expected list → approve local phones → decode
   and validate → report/export. Show what the prototype actually handles.
3. **Live product:** screenshots or a short clip of two physical phones and the
   resulting report. Keep the audience focused on the inventory answer.
4. **Technical contribution:** Leader/Workers, binary batches, workload-specific
   timing, battery/thermal policy, retained results and reassignment. Clearly
   identify ML Kit as the decoder dependency.
5. **Correctness and reliability:** known test manifest, duplicate/missing IDs,
   contribution counts and attempts. Distinguish simulated and physical tests.
6. **Measured performance:** same inputs, devices, mode, repetitions and timing
   boundaries. Include slowdowns and variability, plus the optimization target.
7. **Pilot and adoption:** real user feedback, setup time and the next trial.
   Pricing/cost savings are hypotheses until validated; core offline operation
   avoids a cloud-processing requirement but development/support still have costs.
8. **Next milestone and ask:** the concrete technical/pilot milestone, and the
   help sought (for example trial access, technical mentorship or feedback).

Do not invent market-size figures, customer logos, testimonials, savings or event
judging weights. If a slide has no evidence, label it as a hypothesis or plan.

## 5. Live demo script

### Reliable core demonstration

Rehearse to fit a two-minute slot, adjusting to the actual event format:

1. Introduce the prepared **Demo Dataset** and expected inventory list. Show its
   ground-truth counts on one card. Do not imply that generated data is a pilot.
2. Show a Leader and connected Worker on a shared local network. For an offline
   demonstration, use a hotspot/router with no internet uplink and verify that
   configuration during rehearsal. Do not turn off the local network itself.
3. Run the image workload. Show that the two phones contribute, not just that
   they appear in discovery.
4. Open the report: missing ID, duplicate IDs, unreadable images, Worker
   contribution and correctness match. Explain that a missing ID means absent
   from the successfully decoded expected set, not proof of a physically missing box.
5. Export JSON/CSV and open the saved session from History.

Show the repeated-benchmark summary separately so the live demo stays readable.

### Three-phone recovery demonstration — after physical validation

- Use one Leader and two Workers on the same local network.
- Use enough representative images for a Worker batch to remain visibly in
  flight; select the batch size through rehearsal, not artificial sleep/delays.
- Disconnect Worker A while it has unfinished work. Keep the hotspot/router and
  the Leader online locally; avoid making the disconnected phone the hotspot host.
- Show pending work completing on Worker B, completed results from A retained,
  and the final report matching the same input baseline.
- Inspect attempts/contributions to prove reassignment. Disconnecting A after
  its assigned work has finished is not a recovery demonstration.

With only two phones, demonstrate Leader fallback and describe that evidence
accurately. Do not present it as Worker-to-Worker reassignment.

### Rehearsal deliverables

- A tested APK on every phone, fixed app versions and recorded device models.
- A local-network setup checked without internet access.
- Dataset manifest, expected IDs and exported reference results.
- A recorded successful demo as a clearly identified backup, subject to event rules.
- A short troubleshooting path for connection approvals/manual IP access.

## 6. Engineering research priorities and event-scope candidates

These are technical priorities, not a direction to pre-build the competition
entry. Before 5 October, prioritize the application, disclosure and evidence.
Schedule event implementation only within the confirmed rules; the current app
and its measurements remain identified as prior work.

### P0 — measure and reduce avoidable overhead

1. **Implemented in research build 1.2.4+8:** image-run spans for scheduling,
   batch preparation, queue waits, telemetry, file materialization, encoding,
   remote-result wait, local processing and aggregation, with persisted exports.
   Collect actual phone profiles next. Concurrent spans are not additive wall
   time; remote-result wait is not isolated network latency.
2. Independent telemetry queries now run concurrently while retaining fresh
   resource readings. Measure the repeated refresh cost. If material, cache resource
   readings with explicit freshness limits and retain battery/thermal eligibility
   checks, rather than weakening resource policy for a good benchmark number.
3. Evaluate batch sizes and assignment costs with the same image set and build.
   Preserve byte limits, exact coverage and reassignment behavior.
4. Explore a measured local-versus-distributed execution decision. This is a
   proposed improvement; the current scheduler does not implement a complete
   break-even decision. Report local choices as local execution.

### P1 — stronger evaluation

- Compare a release build against itself on both phones; do not compare a debug
  baseline with a release distributed run. Record app version/build and devices.
- Use the same input bytes and expected list for each comparison. Include a small
  generated test set and a permissioned, ground-truthed set of real label photos.
- If time permits, test several sizes, such as 40/200/500 images. Sizes are
  proposed experimental points, not promises of an advantage at larger scale.
- Run at least five measured pairs per condition when practical, with a documented
  warm-up policy. Add alternating/randomized order for a stronger evaluation;
  the current three-pair UI always runs single-device before distributed.
- Keep all results, including failures and slowdowns. Report medians, range,
  correctness, participating devices, bytes, retries and battery/thermal context.
- Explain the timing boundary: the present benchmark excludes photo capture,
  file selection, network setup, approval, report saving and export. Measure those
  separately for an end-to-end user-workflow comparison.
- Compare with a simple offline single-phone scanner/spreadsheet process for
  product value; compare the local and distributed paths for engineering value.

### P2 — reliability and user evidence

- Repeat physical disconnect/reassignment tests. Record the number of trials and
  outcomes; automated test counts alone do not establish on-phone reliability.
- Interview three to five relevant people if accessible. Ask them to describe
  their last audit, error handling, label formats, connectivity and setup burden.
- Observe one consented trial. Record both what helped and what was confusing.
  Use actual feedback to decide whether photo batching and extra phones are useful.
- Polish the session/report flow, readable labels and explanation of slowed-down
  runs. Presentation clarity has more value here than additional decorative UI.

## 7. Judge Q&A

**Why not use one phone?**
One phone is the correct reference and may be the better choice for small jobs.
The two-phone prototype proves shared execution, but our current 40-image median
is slower. We are measuring the conditions in which more compute outweighs
coordination cost. The report workflow must also be useful on one phone.

**Offline scanners already exist. What is your contribution?**
Offline decoding itself is established technology. Our contribution is combining
resource-aware execution across phones, retained-result recovery and a traceable
inventory report in one working prototype. A competitor review is still needed
before making any claim of uniqueness.

**Where is the AI?**
On-device QR/barcode decoding uses ML Kit. SwarmMesh's current scheduler uses
measured timings and explicit rules; it is not a learned model. There is no local
LLM or verified NPU integration. Public wording varies between model bonus points
and a model-at-core qualification; confirm that ML Kit meets the Productivity
expectation rather than assume compliance.

**Does matching the baseline prove correctness?**
It proves agreement between execution modes. Ground-truth labels/expected lists
are needed to assess decoder accuracy independently, because both modes can make
the same decoding mistake.

**Are you faster?**
One earlier run showed 1.18×, while our three-pair 40-image result was 0.77×.
The repeated result currently favors the single phone. We show these measurements
and the exact inputs rather than extrapolating a universal performance claim.

**What if the Worker disconnects?**
The implementation preserves completed batches, queues unfinished batches for an
eligible replacement Worker, then falls back locally if necessary. Automated
tests cover those paths. Present physical recovery evidence only after obtaining it.

**Is it secure?**
The prototype uses approval on a trusted local network. Approval is not encrypted
identity authentication. Pairing/authentication and transport hardening remain
production work; no claim of production security is made.

**Do you need iQOO hardware?**
The prototype is Android-based and existing evidence comes from Xiaomi/POCO
phones. The guide requires the event entry to run and pitch on an iQOO device.
Test the permitted event build on the loaner hardware and report its actual
results. Existing measurements do not imply an iQOO-specific integration.

**Is this a real warehouse deployment?**
Current supplied evidence is from generated demo labels. A permissioned pilot
with real label formats is the next validation step.

## 8. Remaining information needed

From the team:

1. All three are final-year AI/ML engineering students. Member names, actual
   responsibilities and proficiency choices remain to be filled in; verify that
   all three portal registrations use the student category.
2. Selected dashboard statement/track and its full text, plus any form changes.
3. Prior Chennai/Hyderabad application/deck and any feedback already received.
   Past rejection alone does not identify its cause; the Terms say evaluator
   notes/reasons will not be disclosed, so the plan does not depend on obtaining them.
4. Models/Android versions of the additional phones and access to an inventory
   user or permissioned label photos with independently recorded expected results.

From the organizers:

- Prior-idea resubmission and permitted code/reference reuse for this entry.
- ML Kit/local-model expectation for Productivity.
- Finale-specific rubric, pitch duration, final repo/demo cutoff and artifacts.
- Office Kit/Green–Red details, loaner setup, permitted hotspot/local connections
  and whether a shared laptop works with all three loaner phones.

## 9. Three-person hardware and demo arrangement

Use the proposed role split in [SUBMISSION_DRAFT.md](SUBMISSION_DRAFT.md#2-proposed-team-ownership).

| Device | Preparation role | Important detail |
| --- | --- | --- |
| Phone 1 | Leader, image/list selection and report | Keep active throughout the recovery trial |
| Phone 2 | Worker A, deliberately disconnected during unfinished work | Must not be the hotspot host |
| Phone 3 | Worker B, completes reassigned work | Verify its contributions and attempts, not just connected status |
| Optional Phone 4 | Stable hotspot host; mobile-data uplink off for offline rehearsal | Confirm client-to-client reachability on the actual setup |
| Laptop | Build/integration, deck, saved evidence and permitted Office Kit use | Does not perform inventory inference in the current phone-only execution path |

With three phones, the Leader can host the hotspot if that device supports the
required local connections; test it first. Manual IP helps discovery failures but
does not bypass hotspot client isolation. Disconnect Worker A only after work is
in flight, while keeping the network and other devices running.

Keep the generated manifest and the real-label pilot separate. A stable hotspot
plus three connected phones is a setup check; a completed reassignment with exact
coverage and exported attempts is recovery evidence.

## 10. Deadline-driven preparation plan

Dates below use **IST**. Internal targets are planning choices, not official
deadlines. The public finale schedule lists Friday 17:00 check-in and 19:00
kickoff, Saturday 10:00/19:00 and Sunday 09:00 checkpoints, with Sunday's final
submission cutoff and jury start **TBC**. Recheck the organizer's final schedule.

| Date | Team lead / integration | Android / phone UX | Evaluation / pitch | Required outcome |
| --- | --- | --- | --- | --- |
| **3 Oct** | Send organizer query; verify team category and selected track | Review photo-to-report flow and draft deck | Assemble supplied evidence; contact a potential inventory user | Honest application scope and a list of specific outstanding answers |
| **4 Oct** | Review organizer response; establish the permitted event scope | Rehearse existing prototype with clear prior-work labels; capture genuine footage | Review description/deck against problem, novelty, feasibility and phone-first fit | Reviewed draft, usable deck PDF and optional short video |
| **5 Oct, by 18:00** | Submit/update idea and verify saved confirmation | Check attachment access and phone readability | Proofread every claim and preserve submission copy | Confirmed idea submission with buffer before **23:59:59 IST** |
| **6–8 Oct** | If shortlisted, confirm venue/check-in and event build arrangements | Practice permitted Office Kit tasks and local networking | Prepare ground-truth inputs and rehearse the pitch; record any actual user feedback | Ready people, devices and evidence; no pre-built app represented as event work |
| **9 Oct, check-in/kickoff** | Record agreed baseline and start event work at the official clock | Verify iQOO setup and phone-led workflow | Record device models/build settings and checkpoint expectations | Permitted, traceable starting point |
| **9–10 Oct** | Deliver minimal local inventory flow, then one Worker | Integrate usable report/export and phone UX | Test exact coverage and inspectable outcomes at checkpoints | Working core before optional distribution/recovery extensions |
| **11 Oct** | Freeze and submit before the announced cutoff | Keep event demo devices/network ready | Rehearse to the confirmed time; verify links and evidence | Submitted artifacts and an honest on-device demonstration |

### Minimum deliverable, then extensions

For a fresh 48-hour implementation, prioritize **stored-photo/list selection →
on-phone decoding → ID validation → report/export**. Next add one Worker and
traceable contributions. Add a second Worker/recovery only after the core is
stable. Saved-history polish, benchmark instrumentation and scheduler tuning are
secondary to a functioning scoped entry. Incorporate any required model work
before committing to the event scope.

The latest existing APK is available for disclosed research demonstrations at
`build/app/outputs/flutter-apk/app-debug.apk`. It is not evidence of event-window
authorship or permission to use that binary as the competition deliverable.
