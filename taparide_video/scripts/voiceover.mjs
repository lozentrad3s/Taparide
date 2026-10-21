// Generates the commercial's voice-over with Gemini text-to-speech, one WAV per segment,
// and writes src/commercial/timing.json (seconds per segment) for the composition.
// The key is read from ../taparide_flutter/.env.local and never printed.
// Usage: node scripts/voiceover.mjs
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const envText = readFileSync(join(root, '..', 'taparide_flutter', '.env.local'), 'utf8');
const key = /^\s*GEMINI_API_KEY\s*=\s*([^\s#]+)/m.exec(envText)?.[1];
if (!key) throw new Error('GEMINI_API_KEY is not set in taparide_flutter/.env.local');

const script = JSON.parse(readFileSync(join(root, 'src', 'commercial', 'script.json'), 'utf8'));
const models = (process.env.TTS_MODEL ? [process.env.TTS_MODEL] : ['gemini-2.5-pro-preview-tts', 'gemini-2.5-flash-preview-tts']);
const out = join(root, 'public', 'voice');
mkdirSync(out, { recursive: true });

function wav(pcm, rate = 24000) {
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVEfmt ', 8);
  h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22); h.writeUInt32LE(rate, 24);
  h.writeUInt32LE(rate * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34); h.write('data', 36); h.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([h, pcm]);
}

async function speak(text) {
  let last = '';
  for (const model of models) {
    const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': key },
      body: JSON.stringify({
        contents: [{ parts: [{ text: `${script.style}\n\n${text}` }] }],
        generationConfig: { responseModalities: ['AUDIO'], speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: script.voice } } } },
      }),
    });
    const j = await r.json().catch(() => ({}));
    const part = j.candidates?.[0]?.content?.parts?.find((p) => p.inlineData);
    if (r.ok && part) {
      const rate = Number(/rate=(\d+)/.exec(part.inlineData.mimeType)?.[1] || 24000);
      return { buf: wav(Buffer.from(part.inlineData.data, 'base64'), rate), rate, model };
    }
    last = `${model}: HTTP ${r.status} ${j.error?.message?.slice(0, 120) || ''}`;
  }
  throw new Error(last);
}

const timingFile = join(root, 'src', 'commercial', 'timing.json');
const timing = existsSync(timingFile) ? JSON.parse(readFileSync(timingFile, 'utf8')) : {};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function speakWithRetry(text) {
  for (let attempt = 0; ; attempt++) {
    try { return await speak(text); } catch (e) {
      if (!/429/.test(e.message) || attempt >= 6) throw e;
      console.log('rate limited; waiting 65s');
      await sleep(65000);
    }
  }
}
for (const seg of script.segments) {
  const existing = join(out, `${seg.id}.wav`);
  if (!process.env.FORCE && existsSync(existing)) {
    // Reuse a clip recorded earlier; its length comes from the WAV header (byte rate at offset 28).
    const b = readFileSync(existing);
    timing[seg.id] = Math.round(((b.length - 44) / b.readUInt32LE(28)) * 100) / 100;
    console.log(`${seg.id}: kept (${timing[seg.id]}s)`);
    continue;
  }
  const { buf, rate, model } = await speakWithRetry(seg.text);
  writeFileSync(join(out, `${seg.id}.wav`), buf);
  const seconds = (buf.length - 44) / (rate * 2);
  timing[seg.id] = Math.round(seconds * 100) / 100;
  console.log(`${seg.id}: ${timing[seg.id]}s (${model})`);
  writeFileSync(timingFile, JSON.stringify(timing, null, 2) + '\n');
}
writeFileSync(join(root, 'src', 'commercial', 'timing.json'), JSON.stringify(timing, null, 2) + '\n');
console.log('total', Object.values(timing).reduce((a, b) => a + b, 0).toFixed(1), 's');
