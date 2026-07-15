# Research: OCR / handwriting recognition landscape for fastnote

**Status: REFERENCE (research writeup, 2026-07)**

Question this answers: the dev plan wrote off on-device handwriting
recognition as "not feasible on device CPU" with no supporting analysis.
Given the Kobo Libra Colour ships a stock notebook app that *does* convert
handwriting to text, is that dismissal actually true, and is there a
tractable "for fun" version fastnote could chase later? This is a landscape
snapshot for a future side project, not a plan — no stages, no commitment.

---

## What the device can actually do

Kobo Libra Colour: dual-core ARM Cortex-A53 @ 2.0 GHz (MediaTek MT8113T),
1 GB RAM. Modest by phone standards but not exotic — roughly a 2016-era
budget Android phone's CPU class. Quantized small CNN/CTC inference (a few
hundred ms to low seconds per line of text) is plausible; per-keystroke
live streaming recognition is a much higher bar and not something to assume
without testing.

## What Kobo actually ships (Advanced Notebook)

The "convert handwriting to text" feature on Kobo's own notebook app is
**not a Kobo-built engine** — it's [MyScript's `iink` SDK](https://www.myscript.com/case-study/kobo/),
a commercially licensed, closed-source handwriting/digital-ink recognition
product also used on the Elipsa and Sage lines. Relevant details:

- Only available in **Advanced Notebooks**, a distinct mode from the
  freeform Basic notebook. Advanced Notebooks constrain writing to a
  ruled grid (fixed line height, margins) — that structure is what makes
  the recognition tractable, not just raw model quality.
- Early public feedback described conversion as slow (~5 s for a
  sentence, up to ~30 s for a ~30-word paragraph); firmware updates later
  improved this substantially. So even MyScript's tuned, licensed engine
  was originally closer to "batch convert on demand" than continuous
  live recognition — consistent with what a device this class can push.
- Elipsa 2E threads mention **downloading recognition resource packs via
  sync** — the model/data isn't necessarily fully bundled at first boot.
- A MobileRead thread exists on sideloading/extracting this engine for
  use outside Kobo's own app (["Sideloading Handwriting Recognition
  System to use My Notebooks in Libra
  Colour?"](https://www.mobileread.com/forums/showthread.php?t=361450)) —
  I could not access the thread body (403), and no other source surfaced
  a confirmed working extraction. Treat as unproven, and note MyScript's
  SDK is commercially licensed — reusing Kobo's copy in a third-party
  plugin is a legal gray area, not just an engineering problem.

## Community sentiment on OCR more broadly

KOReader core already ships Tesseract (via the `koreader-base` submodule)
for OCR on scanned PDF/DjVu pages — see `frontend/document/koptinterface.lua`
and `ui/data/ocr.lua`. MobileRead threads about this feature
(["OCRd PDFs - slow - what to
do?"](https://www.mobileread.com/forums/showthread.php?t=359200) and
similar) are mostly complaints about **speed on scanned-document OCR**,
which is a heavier per-page workload (full-page image, unconstrained
layout) than a purpose-built handwriting recognizer would be. No
performance benchmarks (seconds/page) turned up in search snippets; would
need to test directly on a Kobo Libra Colour to get real numbers.

## fastnote's own constraint: stroke data has no timing/pressure channel

`lib/stroke.lua` stores `pts = {x1,y1,w1, x2,y2,w2, ...}` — position and a
pre-baked line width, no raw pressure and no per-point timestamp. Most
*online* handwriting recognizers (including MyScript-style ones) want a
timestamped x/y/pressure stream per stroke to reason about stroke order and
speed. Two paths follow from this:

1. **Offline/bitmap OCR** — rasterize the page (fastnote already has a
   `BlitBuffer` render target, ADR-002) and hand that to a bitmap-based
   recognizer. Works with the data model as-is.
2. **Online/stroke recognition** — would need a model change to add
   per-point timestamps to `Stroke` (pressure is arguably recoverable from
   width, but order/speed is not). Bigger lift, and only worth it if
   bitmap OCR proves the concept doesn't work well enough.

## Candidate open engines, roughly in order of "least new plumbing first"

| Option | Native dep? | Notes |
|---|---|---|
| Tesseract (already in `koreader-base`) on rasterized page, possibly fine-tuned on block-letter samples | None new | Lowest lift; Tesseract's LSTM engine is trainable, but it's fundamentally a print-OCR engine — accuracy on real cursive/mixed handwriting will likely be mediocre without a fine-tune. Best fit if writing is constrained to a ruled, print-style mode (mirrors why Kobo's Advanced Notebook works at all). |
| Calamari-OCR or another CTC line-recognizer (historically used for handwritten/historical documents, trainable per-corpus) | New cross-compiled dep | Better suited to handwriting than stock Tesseract, but needs its own ARM cross-compile story — none exists in this repo today (see below). |
| Small quantized CRNN/CTC model (trained on IAM/CROHME-style data) via TFLite or ONNX Runtime | New cross-compiled runtime + model file | Most control over accuracy/size tradeoff, but the most work: need a runtime cross-compiled for Kobo's ARM target, plus a trained/quantized model (tens of MB or smaller). |
| Google ML Kit Digital Ink Recognition | N/A | Ruled out — tied to Android/Play Services, not usable on Kobo's Linux userland. |

## What would make a good milestone 1

Given fastnote is now past its core-feature stage and this is explicitly a
"neat to have" future experiment, not committed work:

1. Add an optional ruled/structured writing mode to the canvas (useful on
   its own, independent of OCR — this is the same trick that makes Kobo's
   own feature tractable).
2. Rasterize a page via the existing `BlitBuffer` path and run it through
   `koreader-base`'s existing Tesseract binding as a "convert to text"
   button — zero new native dependencies, worst-case output quality, but
   answers the real question ("is this even in the right ballpark on this
   CPU") before investing in a better model.
3. Only if (2)'s quality/speed is clearly inadequate, look at a
   purpose-built handwriting model (Calamari or a small trained CRNN) and
   accept the cross-compile lift that comes with it.

No native-dependency or cross-compile machinery exists yet in this repo for
options 2–4 beyond what `koreader-base` already provides for Tesseract —
confirmed during the initial landscape pass (no vendored C libs, no
Makefile, no Kobo/ARM CI target in this checkout; the real toolchain lives
in the uninitialized `koreader-base` submodule).

---

This supersedes the one-line dismissal in `fastnote-dev-plan-v2.md`'s
"Things deliberately not in this plan" section only in the sense of adding
detail — the conclusion (not worth building now) stands unchanged.
