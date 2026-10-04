# SwarmMesh — iQOO Grand Finale idea-submission draft

Prepared **3 October 2026** for the **Productivity** track. The public site lists
the idea deadline as **5 October 2026, 23:59:59 IST**. Confirm the selected track
and current deadline in the signed-in dashboard before submitting.

**Confirmed team:** three final-year engineering students specializing in AI/ML.
Use the **student** category for all three portal registrations.

This is review copy. An existing SwarmMesh prototype predates the finale; the
guide requires event-window code and prohibits submitting a completed pre-built
app. The disclosure below must accompany any use of this preparation evidence.
The organizer message in section 4 asks how the rule applies to this entry.

## 1. Portal fields

The public form specifies a **5–200-character title**, **50–2,000-character
description**, and a required **PDF/PPT deck (up to 25 MB) or deck link**. Video
and prototype URLs are optional. Only the team leader can submit or update the
idea. The form also asks for proficiency, prior work, team differentiation and
confirmation that pre-existing components are disclosed.

### Idea title

SwarmMesh: Offline Inventory Verification Across Android Phones

Length checked: **63 characters**.

### Description

Copy the four paragraphs below, after confirming the permitted event scope.
Length checked: **1,708 characters**, including blank lines and excluding markers.

<!-- description:start -->
SwarmMesh helps small stockroom and campus equipment-audit teams reconcile stored package-label photos with an expected inventory list, using nearby Android phones on a local Wi-Fi/hotspot network. The report highlights duplicate, missing, unexpected and unreadable labels and records which phone processed each image. Missing means absent from decoded results, not proof that a physical item is lost.

Our pre-existing Flutter/Android research prototype uses on-device ML Kit barcode/QR decoding, approved Leader/Worker connections, binary image batches, battery/thermal-aware scheduling and exportable reports. A two-phone, 40-image generated-data test recorded contributions from both devices. Across three benchmark pairs, median single-phone time was 1085.54 ms versus 1411.56 ms distributed: 0.77x, so we do not claim consistent acceleration or a real warehouse deployment.

For the 48-hour finale, we propose a scoped event-window build: select stored photos and an expected list, decode on an iQOO phone, validate IDs and produce an auditable report; then add one Worker and demonstrate recovery if time permits. We will evaluate correctness against a known manifest and include local-network overhead in performance comparisons. Office Kit will support the phone-led build/demo workflow according to event rules.

Disclosure: the existing prototype and measurements are prior research, not work created during the finale. We seek organizer confirmation on idea reuse, permitted components and whether ML Kit meets the local-model expectation. The current prototype has no local LLM or verified NPU integration. Our contribution is coordinated execution and inventory traceability, not a new decoder.
<!-- description:end -->

### Prior builds & hackathons

> We have developed a Flutter/Android research prototype with local-network
> Leader/Worker execution, on-device ML Kit decoding, resource-aware scheduling,
> recovery logic, saved reports and CSV/JSON/text export. Physical two-phone tests
> demonstrate work on both phones and comparable outputs; automated tests cover
> disconnect, timeout and replacement-Worker paths. Physical three-phone recovery
> and an inventory-user pilot remain to be completed. We applied to the Chennai
> and Hyderabad rounds but were not shortlisted. The existing prototype is
> disclosed as prior work, and we are asking the organizers to confirm the
> permitted scope for a fresh event-window implementation.

Add genuine portfolio links, each person's actual contribution and any real
achievements. Do not describe this repository as published/open-source until
there is a working public link and an appropriate licence.

### What makes you and your team stand out?

> Our preparation combines Android implementation, inspectable distributed-run
> reports and measured evaluation on different phones. We can explain which
> device processed each image, how unfinished work is reassigned, and when
> coordination overhead makes distribution slower. We focus on an understandable
> inventory task and a reproducible result rather than an unverified speed claim.
> Our three-person team consists of final-year AI/ML engineering students. We
> have one laptop and three to four phones for preparation,
> with proposed ownership of runtime/integration, Android UI/phone workflow, and
> evaluation/presentation. We will test the workflow on the event's iQOO devices
> and validate usefulness with inventory users rather than assume demand.

### Android / LLM proficiency

Choose the actual team's experience; the presence of this prototype alone does
not establish any member's proficiency.

- Android options: No Android experience / Basic / Intermediate /
  Expert or shipped apps.
- LLM options: No LLM experience / Cloud APIs only / Experimented with local LLMs /
  Deployed local LLMs on-device.
- ML Kit barcode decoding is not evidence of deploying a local LLM.

### Supporting links and disclosure

- **Deck:** use [COMPETITION_DECK.html](COMPETITION_DECK.html) as the eight-slide
  draft. Open it in Chrome/Edge, print to **Save as PDF**, select landscape if
  necessary, disable browser headers/footers, and check that the output has eight
  complete slides before uploading. It is a draft, not an already-exported PDF.
- **Video, if provided:** label footage of today's app **pre-existing prototype**.
  Show photo selection, both device contributions, the inventory report and export.
  Explain generated inputs and the measured slowdown; a 60–90-second clip is our
  recommendation, not a published portal limit.
- **Prototype URL, if provided:** link to an accessible repository/demo and identify
  it as prior work. Check reviewer permissions; a local disk path is not a URL.
- **Original-work checkbox:** the form says pre-existing components must be
  disclosed. Disclosure does not by itself override the guide's no-prebuilt rule.

## 2. Proposed team ownership

Assign names based on actual skills before submission; these are proposed roles.

| Owner | Before the deadline | At the event, within the agreed scope |
| --- | --- | --- |
| Member A — integration and team lead | Organizer query; portal/team fields; architecture explanation | Runtime/decoder integration and final submission |
| Member B — Android UX and phone workflow | Deck screenshots; image/list/report usability rehearsal | Phone UI, report flow, installation and Office Kit workflow |
| Member C — evaluation and pitch | Dataset manifest; evidence table; user interview; deck/video | Independent expected results, physical recovery tests, measurements and pitch |

One laptop means one primary integration queue. B and C can prepare inputs, test
phones, inspect reports and rehearse while A builds; rotate laptop use in planned
slots. All three should be able to explain the problem and run the phone demo.
Use Office Kit according to the organizer's actual Green/Red instructions.

## 3. What to review before using this draft

1. All three members are in the same registered student/professional category.
2. The dashboard offers/selects **Productivity** and the text matches that statement.
3. Organizer guidance establishes the event scope and treatment of prior work.
4. Names, portfolio links, proficiency choices and any claimed experience are true.
5. The deck opens for a reviewer, and video/prototype links are accessible if used.
6. After saving, the dashboard shows **Idea submitted** with the correct title and
   attachment. Capture the confirmation and submission time.

## 4. Organizer clarification message — ready to personalize

**To:** sameera@reskilll.com  
**Subject:** Grand Finale direct entry — prior prototype and phone-first rules

> Hello iQOO / Reskilll team,
>
> We are a three-member team preparing a direct Grand Finale idea submission for
> the 5 October deadline. We previously applied to the Chennai and Hyderabad
> rounds but were not shortlisted.
>
> Our idea, SwarmMesh, is an offline Android inventory-verification workflow using
> nearby phones. We already have a research prototype with Flutter, on-device
> ML Kit barcode/QR decoding, local-network job distribution and reports. We will
> disclose this prototype and its measurements as pre-existing work.
>
> The guide says code must be written during the event and a pre-built app cannot
> be submitted. The idea form also asks us to disclose pre-existing components.
> Could you please confirm:
>
> 1. May an unsuccessful city applicant submit this idea directly to the finale?
>    If so, is a fresh event-window implementation of the idea permitted, and
>    which, if any, existing components or reference material may be used?
> 2. For Productivity, does on-device ML Kit barcode decoding meet the local-model
>    expectation, or is another local/open-source model integration required?
>    We currently have no local LLM or verified NPU integration.
> 3. Are three loaner iQOO phones available for our team, and may we run our local
>    Wi-Fi/hotspot multi-phone demonstration? We share one laptop; what are the
>    finale-specific Green/Red and Office Kit requirements?
> 4. What are the finale's final-code submission cutoff, pitch duration and
>    required repo/demo artifacts? Does the published six-part judging rubric
>    apply unchanged to the finale?
>
> We will follow the confirmed rules and clearly distinguish prior research from
> work created during the event. Thank you for helping us scope the entry.
>
> Regards,
> [Team leader name, registered team name and registration email]

This message is prepared, not sent. Full source notes and the preparation
schedule are in [COMPETITION_PLAN.md](COMPETITION_PLAN.md).
