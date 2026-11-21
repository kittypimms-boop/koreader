# Kernel-assisted palm rejection and a home-grown digitizer driver

Planning material for replacing fastnote's userland palm rejection with a Linux
kernel module on the Kobo Libra Colour, and later writing a minimal digitizer
driver. This is the long form of roadmap workstream W5 (hardware-level input).

**Status: planning only. No kernel code exists yet.** Nothing here has been run on
the device. The device kernel version, the module-signing setting and the Elan
chip's real behaviour are unconfirmed; the recon checklist (03) lists the commands
that settle them.

These documents were written in a separate agent workspace. Mentions of skills,
routes, sub-protocols and planners refer to that workspace, not to this repository.
Claims tagged **[V]** were checked against source or a fetched page when written;
**[U]** claims were not. Treat every kernel API detail for kernel 4.9 as **[U]**
until checked against that kernel's headers.

## Reading order

| Doc | What it holds |
|---|---|
| `01_plan_kernel-palm-rejection.md` | The plan, its goal, risks and phase table. Sections 3 and 4 are superseded by 04 for filter mode, the QEMU rig, KUnit and the phase ordering; section 4c (the digitizer driver staircase) still stands. |
| `02_survey_repo-and-device-survey.md` | How palm rejection works in the plugin today and the facts that shape a kernel design. |
| `03_findings_device-recon-checklist.md` | Read-only commands to run on the device. Answer these first. |
| `04_findings_senior-planner-review.md` | How `input_handler.filter()` behaves on 4.9, the frame-lookahead and mute design, the QEMU test rig, KUnit with a pure-C core, the top-10 gaps and the revised phases. The main design document. |
| `05_survey_spec-reading-list-and-fetch-plan.md` | Specs and community docs worth reading, with fetch status. |
| `06_survey_testing-landscape-and-static-analysis.md` | What each test layer can and cannot test, and which static analysis tools fit. |
| `09_survey_page-nav-ux-and-lift-bug-review.md` | The page-navigation design (implemented on this branch) and the ranked hypotheses for the finger-lift jump, which `.agents/notes/finger-lift-jump-diagnosis.md` turns into a capture procedure. |

## Related, elsewhere in this repo

- `.agents/planning/post-v1-roadmap-handoff.md`, workstream W5.
- `.agents/notes/finger-lift-jump-diagnosis.md`: what to capture on the device and how to read it.
- `.agents/notes/canvas-widget-gotchas.md`: the chrome strip, hide and show, and margin page turns.
