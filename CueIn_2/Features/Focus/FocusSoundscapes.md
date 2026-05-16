# Focus soundscapes — science, design, and limitations

This document explains **why** CueIn ships simple procedural soundscapes (noise, slow pulses, isochronic-style tones, optional binaural beats) next to the Pomodoro timer, and **how much confidence** the literature supports for each idea. It is **not** medical advice.

## What CueIn implements (v1)

| Preset | What you hear | Primary intent |
|--------|----------------|----------------|
| **Pink veil** | Economical pink-noise approximation (Paul Kellet–style filter stack) | Steady **spectral masking** of distracting highs |
| **Brown depth** | Leaky-integrated “brown-ish” noise | Stronger **low-frequency** masking / warmth |
| **Slow pulse veil** | Pink noise with a slow (~0.12 Hz) amplitude swell | Very gentle **periodic structure** without sharp clicks |
| **Bright pulse (β)** | Soft carrier with ~15 Hz rhythmic emphasis | **Isochronic-style** pulsing (mono; works on speakers) |
| **Binaural β (headphones)** | 200 Hz left, 208 Hz right (8 Hz beat) | Classic **binaural beat** setup (requires headphones) |

All audio is **synthesized in real time** in `FocusSoundscapeEngine` — no licensed music catalog, no streaming dependency.

---

## 1. Auditory masking and “noise colors”

### Idea

Broadband noise can **mask** intermittent office sounds (speech bursts, HVAC swings). “Pink” and “brown” describe different **slopes** of spectral density; different slopes change which distractions are covered and how fatiguing the mask feels.

### Evidence snapshot

- Office and built-environment studies report that **masking sounds** and **signal-to-noise ratio** materially change self-reported disturbance and, in some paradigms, performance on office tasks; exact winners vary by room, task, and level (e.g., masking sound design in open-plan offices — see discussion in building acoustics literature such as *Applied Acoustics* / *Building and Environment* streams).
- A **systematic review** of *moderate broadband noise* and cognitive performance (*Cognition, Technology & Work*, 2023) emphasizes **context dependence**: small effects, task-specific outcomes, and the need to treat “noise helps/hurts” claims carefully — [SpringerLink summary](https://link.springer.com/article/10.1007/s10111-023-00746-2).
- Empirical work on **spectral color** of noise and efficiency/report outcomes exists in occupational-health style samples — e.g., PMC discussion of spectral content and self-rated efficiency — [PMC7986458](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7986458/).

### Practical takeaway for CueIn

Pink/brown presets are best understood as **comfortable maskers** you can tune with the level slider — not a guaranteed productivity drug.

---

## 2. Isochronic tones and rhythmic auditory stimulation

### Idea

**Isochronic tones** are bursts or pulses of sound at a target rate. Popular guides contrast them with binaural beats by noting they can be delivered **monaurally** (one channel) and therefore work without headphones for the *rhythmic* component — see neutral summaries such as [Wikipedia — Isochronic tones](https://en.wikipedia.org/wiki/Isochronic_tones) and comparative explainers (e.g., [Neurosity guide](https://neurosity.co/guides/binaural-beats-vs-isochronic-tones)).

### Evidence snapshot

- Literature reviews often find **more binaural-beat trials than isochronic trials**, and call for higher-quality isochronic studies — e.g., a Scielo review comparing modulation approaches — [Scielo article](https://www.scielo.org.mx/scielo.php?pid=S1665-50442021000600238&script=sci_arttext_plus&tlng=en).
- Mechanistic language (“entrainment”) should be treated cautiously: behavioral nudges can exist even when EEG markers of entrainment are inconsistent across labs.

### What CueIn does *not* claim

CueIn’s “Bright pulse (β)” is a **minimal** carrier + amplitude emphasis inspired by the *family* of isochronic-style stimuli. It is **not** a reproduction of any commercial “functional music” pipeline.

---

## 3. Binaural beats

### Idea

Present **two pure tones** separated by a small **frequency difference** Δf, one to each ear. The listener perceives a beat at Δf. Many studies probe whether Δf in certain bands correlates with mood/attention outcomes.

### Evidence snapshot

- Meta-analytic work reports **small–medium effect sizes** in some cognitive/anxiety-adjacent bundles, with caveats about heterogeneity — e.g., *Psychological Research* meta-analyses ([2018](https://link.springer.com/article/10.1007/s00426-018-1066-8), [2022](https://link.springer.com/article/10.1007/s00426-022-01706-7)).
- EEG/attention paradigms show **mixed mechanistic confirmation** even when behavior shifts — e.g., PubMed-indexed work on attention tasks — [PubMed 34245340](https://pubmed.ncbi.nlm.nih.gov/34245340/).
- A recent parametric exploration in *Scientific Reports* illustrates continued interest in **which parameters** move attention metrics — [Scientific Reports article](https://www.nature.com/articles/s41598-025-88517-z).

### Headphones requirement

True binaural beats require **independent** stimulation of each ear. CueIn labels the preset accordingly.

---

## 4. “Functional music” products (e.g., Brain.fm-style claims)

Some products combine **music** with **slow amplitude modulation** (sometimes linked to ASSR / “neural phase locking” narratives). Public materials describe hypothesis → test pipelines and placebo-controlled comparisons — see vendor white papers and knowledge-base pages such as [Brain.fm science hub](https://www.brain.fm/science) and their cited PDFs (e.g., white paper PDF linked from their domain).

**Important:** vendor materials are **not independent peer review**. They can still be useful as *product hypotheses* and as pointers to what to measure if CueIn later adds richer audio.

---

## 5. Safety and comfort

- Keep **levels sane**; prolonged high SPL listening risks hearing health regardless of signal type.
- If you experience **tinnitus**, **vertigo**, **headaches**, or **anxiety spikes** with pulsed tones, stop using rhythmic presets and prefer pink/brown only — when in doubt, ask a clinician.

---

## 6. Engineering notes (iOS)

- `AVAudioSession` category **playback** with **mixWithOthers** lets CueIn coexist more politely with other audio apps; users can still override in Control Center.
- Background continuation uses the **Audio** background mode (declared in the Xcode target) so short app switches do not necessarily kill the masker — behavior still depends on OS resource policies.

---

## 7. Roadmap ideas

- User-recordable **mix recipes** (noise + pulse depth).
- Optional **short loops** from royalty-free stems (separate licensing work).
- **Live Activities** / richer Now Playing metadata.

When adding new presets, update this document with **stimulus parameters** (frequencies, rates, crest factor) and the **claim level** (“masking comfort” vs “entrainment”) so the UI and science notes stay aligned.
