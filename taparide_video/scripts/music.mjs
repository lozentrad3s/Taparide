// Generates original, royalty-free music beds for the videos (public/music/*.wav).
// Warm I–V–vi–IV progression (C–G–Am–F) at 100 BPM: pads, bass, a soft arpeggio, light drums.
// Pure synthesis, deterministic, no samples. Replace with licensed music any time.
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SR = 44100;
const BPM = 100;
const BEAT = 60 / BPM;
const BAR = BEAT * 4;
const CHORD_BARS = 2;

const midiHz = (m) => 440 * 2 ** ((m - 69) / 12);
// C, G, Am, F voicings (MIDI) and bass roots
const CHORDS = [
  { pad: [60, 64, 67, 71], root: 36 }, // Cmaj7
  { pad: [59, 62, 67, 74], root: 43 }, // G/B add9 feel
  { pad: [57, 60, 64, 69], root: 45 }, // Am
  { pad: [57, 60, 65, 69], root: 41 }, // F/A -> Fmaj
];

let seed = 1234567;
const noise = () => {
  seed = (seed * 1664525 + 1013904223) >>> 0;
  return seed / 2 ** 31 - 1;
};

function render(seconds, { energy = 1, intro = 2, drums = 1 } = {}) {
  const n = Math.ceil(seconds * SR);
  const L = new Float32Array(n);
  const R = new Float32Array(n);
  const chordLen = BAR * CHORD_BARS;
  const chordAt = (t) => CHORDS[Math.floor(t / chordLen) % CHORDS.length];
  const totalChords = Math.ceil(seconds / chordLen);
  const outroStart = seconds - chordLen * 1.5;

  // ---- pads: per-chord voices with slow attack/release, detuned pair, gentle harmonics
  for (let c = 0; c < totalChords; c++) {
    const start = c * chordLen;
    const chord = CHORDS[c % CHORDS.length];
    const end = Math.min(seconds, start + chordLen + 1.2);
    const s0 = Math.floor(start * SR), s1 = Math.min(n, Math.floor(end * SR));
    chord.pad.forEach((m, vi) => {
      const f = midiHz(m);
      const det = [0.9983, 1.0017];
      let lp = 0;
      for (let i = s0; i < s1; i++) {
        const t = (i - s0) / SR;
        const att = Math.min(1, t / 0.9);
        const rel = t > chordLen ? Math.max(0, 1 - (t - chordLen) / 1.2) : 1;
        let v = 0;
        for (const d of det) {
          const ph = 2 * Math.PI * f * d * t;
          v += Math.sin(ph) + 0.28 * Math.sin(2 * ph) + 0.1 * Math.sin(3 * ph);
        }
        lp += 0.12 * (v - lp); // soften
        const amp = 0.055 * att * rel * (1 + 0.15 * Math.sin(2 * Math.PI * 0.18 * t + vi));
        const pan = 0.5 + (vi - 1.5) * 0.18;
        L[i] += lp * amp * (1 - pan) * 1.4;
        R[i] += lp * amp * pan * 1.4;
      }
    });
  }

  const introEnd = intro * chordLen;
  // ---- bass: root on beat 1 and the "and" of 2, beat 3
  for (let beat = 0; beat * BEAT < seconds; beat += 0.5) {
    const t0 = beat * BEAT;
    if (t0 < introEnd * 0.5 || t0 > outroStart) continue;
    const pos = beat % 4;
    if (![0, 1.5, 2].includes(pos)) continue;
    const f = midiHz(chordAt(t0).root);
    const dur = pos === 1.5 ? 0.35 : 0.7;
    const s0 = Math.floor(t0 * SR), s1 = Math.min(n, s0 + Math.floor(dur * SR));
    for (let i = s0; i < s1; i++) {
      const t = (i - s0) / SR;
      const env = Math.min(1, t / 0.01) * Math.exp(-t * 3.2);
      const v = Math.tanh(1.6 * Math.sin(2 * Math.PI * f * t)) * 0.16 * env * energy;
      L[i] += v;
      R[i] += v;
    }
  }

  // ---- arpeggio: chord tones an octave up, 8th notes, plucky
  const pattern = [0, 1, 2, 3, 2, 1, 2, 3];
  for (let k = 0; k * BEAT * 0.5 < seconds; k++) {
    const t0 = k * BEAT * 0.5;
    if (t0 < introEnd || t0 > outroStart) continue;
    const chord = chordAt(t0);
    const m = chord.pad[pattern[k % pattern.length]] + 12;
    const f = midiHz(m);
    const s0 = Math.floor(t0 * SR), s1 = Math.min(n, s0 + Math.floor(0.45 * SR));
    const pan = k % 2 ? 0.35 : 0.65;
    for (let i = s0; i < s1; i++) {
      const t = (i - s0) / SR;
      const env = Math.min(1, t / 0.004) * Math.exp(-t * 9);
      const ph = 2 * Math.PI * f * t;
      const v = (Math.sin(ph) + 0.35 * Math.sin(2 * ph) * Math.exp(-t * 18)) * 0.045 * env * energy;
      L[i] += v * (1 - pan) * 2;
      R[i] += v * pan * 2;
    }
  }

  // ---- drums: soft kick on each beat, closed hat on off-beats
  if (drums > 0) {
    for (let beat = 0; beat * BEAT < seconds; beat++) {
      const t0 = beat * BEAT;
      if (t0 < introEnd || t0 > outroStart) continue;
      const s0 = Math.floor(t0 * SR), s1 = Math.min(n, s0 + Math.floor(0.3 * SR));
      let phase = 0;
      for (let i = s0; i < s1; i++) {
        const t = (i - s0) / SR;
        const f = 50 + 70 * Math.exp(-t * 30);
        phase += (2 * Math.PI * f) / SR;
        const v = Math.sin(phase) * Math.exp(-t * 11) * 0.22 * drums;
        L[i] += v;
        R[i] += v;
      }
      const h0 = Math.floor((t0 + BEAT / 2) * SR), h1 = Math.min(n, h0 + Math.floor(0.06 * SR));
      let prev = 0;
      for (let i = h0; i < h1; i++) {
        const t = (i - h0) / SR;
        const w = noise();
        const hp = w - prev; // crude high-pass
        prev = w;
        const v = hp * Math.exp(-t * 70) * 0.03 * drums;
        L[i] += v * 0.8;
        R[i] += v * 1.2;
      }
    }
  }

  // ---- master: fades, soft clip, normalise to about -2 dBFS
  const fadeIn = 1.5, fadeOut = 3;
  let peak = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const g = Math.min(1, t / fadeIn) * Math.min(1, (seconds - t) / fadeOut);
    L[i] = Math.tanh(L[i] * 1.2) * g;
    R[i] = Math.tanh(R[i] * 1.2) * g;
    peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
  }
  const norm = 0.8 / (peak || 1);
  const buf = Buffer.alloc(44 + n * 4);
  buf.write('RIFF', 0);
  buf.writeUInt32LE(36 + n * 4, 4);
  buf.write('WAVEfmt ', 8);
  buf.writeUInt32LE(16, 16);
  buf.writeUInt16LE(1, 20);
  buf.writeUInt16LE(2, 22);
  buf.writeUInt32LE(SR, 24);
  buf.writeUInt32LE(SR * 4, 28);
  buf.writeUInt16LE(4, 32);
  buf.writeUInt16LE(16, 34);
  buf.write('data', 36);
  buf.writeUInt32LE(n * 4, 40);
  for (let i = 0; i < n; i++) {
    buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, L[i] * norm)) * 32767), 44 + i * 4);
    buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, R[i] * norm)) * 32767), 46 + i * 4);
  }
  return buf;
}

const out = join(dirname(fileURLToPath(import.meta.url)), '..', 'public', 'music');
mkdirSync(out, { recursive: true });
writeFileSync(join(out, 'ad.wav'), render(46, { energy: 1, intro: 1, drums: 1 }));
writeFileSync(join(out, 'pitch.wav'), render(166, { energy: 0.8, intro: 2, drums: 0.6 }));
writeFileSync(join(out, 'commercial.wav'), render(112, { energy: 0.7, intro: 1, drums: 0.5 }));
console.log('wrote', out);
