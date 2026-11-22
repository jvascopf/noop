# WHOOP 4.0 SpO₂ feasibility (personal fork, paused)

Status: **paused on 2026-11-22.** Two bounded probes on one WHOOP 4.0 showed a real two-channel optical
signal, but not the inputs a blood-oxygen estimate needs. Resume only with a reference oximeter.

This note records what was measured so the work does not have to be repeated. It is one strap, one
wearer and a few minutes of data: observations, not validated protocol facts. The protocol pages
([`PROTOCOL_SENSORS.md`](../PROTOCOL_SENSORS.md), [`PROTOCOL_WHOOP4.md`](../PROTOCOL_WHOOP4.md)) remain the
reference for layouts.

## Why the stored data cannot give SpO₂

Pulse oximetry needs, for two wavelengths (red and infrared), both the pulsatile (AC) and the steady
(DC) part of the optical signal, sampled fast enough to see each beat. The ratio
`R = (AC_red / DC_red) / (AC_ir / DC_ir)` is then mapped to a percentage by a calibrated curve.

What a WHOOP 4.0 banks by default (history v24) does not contain that:

- The red/IR scalars at frame offsets 68/70 are stored once a second, but change in steps: one night had
  16 distinct values across 8 hours, and 10 consecutive minutes held one value (488 / 575).
- They carry no pulse waveform, so neither AC component can be recovered.
- `dailyMetric.spo2Pct` therefore stays empty on a 4.0 unless an import supplies it.

## Probe 1: `START_RAW_DATA` (81)

Test Centre → WHOOP 4.0 OPTICAL PROBE → *Run optical probe* (`BLEManager.runOpticalProbe`). It records
15 s untouched, sends 81 `[01]`, records 60 s, sends 82 `[01]`, records 10 s.

- The strap accepted both commands (command response result `0x01`) and emitted an event for each
  (`0x2e` on start, `0x2f` on stop).
- Nothing streamed over BLE during the 60 s. The raw data went to flash instead.
- The next history offload carried two extra record kinds next to the usual 104-byte v24 frames:
  - version 10, declared length 1,924 (the documented IMU block);
  - version 11, declared length 1,928 (the documented optical waveform).
- Only 14 version-11 records (14 s) were stored for the 60 s window.

## Probe 2: R10/R11 realtime (command 63)

*Run guided realtime probe* (`BLEManager.runGuidedOpticalProbe`). It sends 63 `[01]` (the switch the Live
screen uses), then guides the wearer through three phases: strap snug for 90 s, loose for 60 s, then off
the wrist in the air for 30 s. It ends with 63 `[00]`.

- Type-43 frames of 1,932 bytes arrived at about one per second: 97 snug, 65 loose, 11 in the air.
- The strap powered its sensors down a few seconds after leaving the wrist, then started a history sync.

## The R11 optical record

- One record covers about one second. From frame offset 42 there are 100 values with a stride of 4 bytes,
  then a marker value of 262,144.
- The values read as signed 32-bit little-endian (`<i`). Reading them as 24-bit with a separate fourth
  byte breaks on records where that byte is non-zero.
- **Two channels, block-interleaved:** samples 0–49 are channel A and samples 50–99 are channel B.
- Each channel is continuous across records. For A, the step from one record's last sample to the next
  record's first was a median 86, against a normal sample-to-sample step of 133. The step between the two
  channels inside a record was a median 27,661.
- Each channel is therefore about **50 Hz**.
- The optical header (offsets 21–41) was identical in every record of both probes:
  `0d05160d01160d0420000000200305200000002003`.

Per phase (detrended with a 1 s moving mean; AC is the median peak-to-peak per second):

| Phase | Channel A mean | Channel A AC | Channel B mean | Channel B AC | A~B correlation |
|---|---:|---:|---:|---:|---:|
| Snug | −7,588 | 2,020 | 41,776 | 12,690 | 0.86 |
| Loose | 74,118 | 8,611 | 29,328 | 6,211 | 0.94 |
| Air | 159,122 | 246,752 | 150,216 | 237,645 | 0.85 |

- Both channels pulse, and they pulse in phase. That is what two wavelengths seeing the same pulse look
  like.
- In probe 1, at rest, channel B's dominant frequency was 1.0 Hz against a heart rate of 0.96 Hz (57.7 bpm).
- Neither channel behaves as ambient light: both lose the pulse and swing hugely off the skin.

## What blocks an estimate

1. **AC-coupled.** The channel means drift and went negative when snug, matching the documented
   "AC-coupled optical waveform". There is no per-wavelength DC, so `R` cannot be formed from this record
   alone. Whether the v24 red/IR scalars (68/70) are that DC is an open, untested hypothesis.
2. **Unstable channel ratio.** The ratio of the channels' AC standard deviations, over 5 s windows, ranged
   from 0.86 to 11.8 within the snug phase, and from 0.28 to 9.98 within the loose phase. It settled only
   once the arm was still: about 1.0–1.25 at the end of the snug phase. Motion or automatic gain changes
   move it, and the header does not change when they do.
3. **Unknown wavelengths.** Nothing measured here identifies red, infrared or green.
4. **Cost.** The realtime stream is about 2 KB/s. A whole night would keep the strap and the phone
   transmitting; only short periodic samples would be practical.
5. **Calibration and validation.** The curve from `R` to a percentage has to be fitted against a reference
   oximeter on the same nights. Healthy SpO₂ barely moves (about 95–98%), so tracking a varying input, as
   [`AGENTS.md`](../../AGENTS.md) requires for any derived signal, is hard to show.

## If this is resumed

1. **Get a reference.** A ring or fingertip oximeter that exports a whole night with timestamps.
2. **Read the AFE settings.** `GET_AFE_PARAMETERS` (62) is a read. It may expose LED currents and gains,
   which would explain the ratio jumps and could identify the wavelengths.
3. **Test the DC hypothesis.** Compare the v24 68/70 scalars against the R11 channel levels across gain
   changes.
4. **Capture short still windows during sleep.** A few minutes per hour of R11 in deep or light sleep,
   gated on low motion.
5. **Ship it carefully, if at all.** Only after a fit tracks the reference across nights: as
   instrumentation or a default-off Experimental estimate labelled unverified, never feeding recovery or
   illness scoring, with a Kotlin twin.

## Where the tools are

- Both probes live in the Test Centre on a WHOOP 4.0 (card *WHOOP 4.0 OPTICAL PROBE*). Each is
  confirmation-gated and never runs on its own.
- Each writes every BLE notification as `ms phase uuid hex` lines to
  `Documents/optical-probe-<epoch>.txt` or `Documents/optical-probe2-<epoch>.txt` in the app container.
- To analyse a capture:
  1. reassemble frames on characteristic `61080005` (start byte `0xAA`; total length is the u16 at bytes
     1–2 plus 4);
  2. select type-47 version-11 frames (history) or type-43 frames of 1,932 bytes (realtime).
