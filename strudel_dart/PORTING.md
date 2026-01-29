# Strudel Dart Porting Roadmap (Baseline "100% Basic")

This document defines the minimum feature set required to say the Dart/Flutter
port matches Strudel's "basic" functionality and a phased plan to reach it.

## Feature Matrix (Docs vs Dart/Flutter)

Status legend: Yes, Partial, No, N/A.

| Area | Docs page | strudel_dart | flutter_strudel | Notes |
| --- | --- | --- | --- | --- |
| Core patterns + mini notation | /learn/getting-started | Partial | Partial | Core patterns + parser exist; parity gaps remain. |
| Samples (samples, banks, github shortcut) | /learn/samples | Partial | Partial | Hooks exist; Flutter loads default packs. No UI for import folder or soundAlias. |
| Synths (basic, noise, wavetable, ZZFX) | /learn/synths | Partial | Partial | Synth engine exists; parity and UI coverage incomplete. |
| Effects (lpf/hpf, delay/room, etc) | /learn/effects | Partial | Partial | Some filters supported; chain parity incomplete. |
| Visual feedback (punchcard, scope, etc) | /learn/visual-feedback | Partial | Partial | Initial Flutter visuals only; many types missing. |
| MIDI / OSC / MQTT | /learn/input-output | No | No | Planned (Phase 4). |
| Input devices (gamepad) | /learn/input-devices | No | No | Planned (Phase 4). |
| Device motion | /learn/devicemotion | No | No | Planned (Phase 4). |
| Hydra | /learn/hydra | No | No | Web-only in JS. |
| Csound | /learn/csound | No | No | Not implemented. |
| Offline / PWA | /learn/pwa | N/A | N/A | Web app feature; Flutter has separate packaging. |

## Phase 0: Core Semantics Parity (Must-have)

- Pattern semantics: step-join/squeeze/reset/restart edge cases match JS.
- Signal functions: rand/choose/perlin etc match JS signatures and behavior.
- Mini notation parser parity for common patterns and modifiers.
- Controls: attack/decay/sustain/release + ADSR and control aliases.
- REPL: method/function mapping coverage for core patterns and controls.
- Tests: port a subset of core JS tests (pattern/signal/util) to Dart.

Acceptance:
- Core test suite passes for time/pattern equivalence on representative cases.
- All common REPL snippets from web docs run without exceptions.

## Phase 1: Sample Playback Parity (Web + Mobile + Desktop)

- Sample map parsing parity with JS `samples()` loader.
- Alias banks: match Strudel alias mappings.
- Bank + sound resolution: `bank_sound`, `bank:sound`, `sound:n`, etc.
- Legacy fallback mapping for common drum sounds.
- Deterministic sample selection for `n` with list order matching JS.

Acceptance:
- `RolandTR909` / `Dirt-Samples` produce same `n` indices as web.
- Basic drum patterns sound identical for `s("bd sd hh")` and bank usage.

## Phase 2: Soundfont / GM Instruments (Web parity)

- Implement soundfont loading (SF2) or compatible sampled GM pack.
- Map GM names (e.g. `gm_acoustic_bass`) to soundfont instruments.
- Add `soundfonts` loader and REPL exposure.

Acceptance:
- `s("gm_acoustic_bass")` plays a correct GM bass sound.
- Basic GM instruments available and documented.

## Phase 3: Synth/FX Parity (Web parity)

- Port synth parameters and FX chains used in `webaudio/superdough`.
- Implement control routing for FX chains in Dart audio engine.
- Worklet/Kabelsalat equivalent or feature-gated fallback.

Acceptance:
- Common synth patterns from docs sound close to web output.
- FX chains (delay/room/distort) behave consistently.

## Phase 4: I/O + Extensibility

- MIDI, OSC, serial, gamepad (as platform allows).
- Tidal integration and/or compatible pattern bridge.
- Editor integrations if needed.

Acceptance:
- Platform-specific feature matrix documented and stable.

## Priority Checklist (Immediate Next Tasks)

1) Core semantics gaps (pattern.mjs edge cases, stepJoin/retime).
2) Sample map parity and exact list ordering for banks (TR909, Dirt-Samples).
3) Soundfont loader (GM pack) or sample-based fallback mapping.
4) DSP/FX chain support in Flutter audio engine (must be deterministic).
