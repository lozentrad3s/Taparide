// "Why Tap A Ride" — narrated commercial (Gemini TTS voice-over), about 1 min 45 s.
// Scene lengths follow the recorded narration in src/commercial/timing.json.
import { AbsoluteFill, Audio, interpolate, Sequence, spring, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import script from './commercial/script.json';
import timing from './commercial/timing.json';
import { Rise } from './components/layout';
import { Tapi } from './components/Tapi';
import { Body, Browser, Eyebrow, Kinetic, Logo, NetworkBg, Phone, PhotoBg, Pill, useEnter, useOrientation } from './components/ui';
import { colors, family } from './theme';

const FPS = 30;
const PAD = 0.5; // seconds of breathing room after each line
const seconds = (id) => (timing[id] ?? 15) + PAD;
export const COMMERCIAL_SCENES = script.segments.map((s) => ({ ...s, frames: Math.round(seconds(s.id) * FPS) }));
export const COMMERCIAL_DURATION = COMMERCIAL_SCENES.reduce((a, s) => a + s.frames, 0) + FPS; // +1 s hold at the end

/** Fades a scene in and out over 12 frames so cuts feel soft without overlapping the voice. */
function SceneFade({ frames, children }) {
  const f = useCurrentFrame();
  const o = Math.min(interpolate(f, [0, 12], [0, 1], { extrapolateRight: 'clamp' }), interpolate(f, [frames - 12, frames], [1, 0], { extrapolateLeft: 'clamp' }));
  return <AbsoluteFill style={{ opacity: o }}>{children}</AbsoluteFill>;
}

/** Subtitles: the sentence being spoken, timed by its share of the segment's characters. */
function Captions({ text, frames }) {
  const f = useCurrentFrame();
  const { u, portrait } = useOrientation();
  const sentences = text.match(/[^.?!]+[.?!]+/g) || [text];
  const total = sentences.reduce((a, s) => a + s.length, 0);
  const speak = frames - PAD * FPS;
  let start = 0;
  let current = sentences[0];
  for (const s of sentences) {
    const len = (s.length / total) * speak;
    if (f >= start) current = s;
    start += len;
  }
  return (
    <div style={{ position: 'absolute', left: 0, right: 0, bottom: (portrait ? 120 : 54) * u, display: 'flex', justifyContent: 'center', pointerEvents: 'none' }}>
      <div style={{ maxWidth: (portrait ? 960 : 1500) * u, padding: `${10 * u}px ${22 * u}px`, borderRadius: 14 * u, background: 'rgba(6,20,13,0.72)', color: '#fff', fontFamily: family, fontWeight: 600, fontSize: (portrait ? 34 : 32) * u, lineHeight: 1.3, textAlign: 'center' }}>
        {current.trim()}
      </div>
    </div>
  );
}

function SourceNote({ text }) {
  const { u } = useOrientation();
  const p = useEnter(20);
  if (!text) return null;
  return (
    <div style={{ position: 'absolute', right: 40 * u, top: 34 * u, maxWidth: 760 * u, textAlign: 'right', fontFamily: family, fontSize: 17 * u, color: 'rgba(255,255,255,0.62)', opacity: p }}>
      Source: {text}
    </div>
  );
}

function Counter({ to, from = 0, start = 0, dur = 40, format = (v) => Math.round(v).toLocaleString('en-US') }) {
  const f = useCurrentFrame();
  const t = interpolate(f, [start, start + dur], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: (x) => 1 - Math.pow(1 - x, 3) });
  return <>{format(from + (to - from) * t)}</>;
}

// ------------------------------------------------------------------ scenes

function Hook({ frames }) {
  const { u, portrait } = useOrientation();
  const qs = ['How much is the fare?', 'When will the bus come?', 'Is this car safe?'];
  const at = [Math.round(frames * 0.42), Math.round(frames * 0.58), Math.round(frames * 0.74)];
  return (
    <AbsoluteFill>
      <PhotoBg src="abuja_expressway.jpg" scrim={0.72} duration={frames} />
      <AbsoluteFill style={{ justifyContent: 'center', padding: `0 ${(portrait ? 70 : 140) * u}px` }}>
        <Eyebrow delay={6} size={28 * u}>Abuja, every morning</Eyebrow>
        <div style={{ height: 18 * u }} />
        <div style={{ fontFamily: family, fontWeight: 800, color: '#fff', fontSize: (portrait ? 120 : 150) * u, letterSpacing: '-0.03em', lineHeight: 1 }}>
          <Counter to={4.2} start={10} dur={50} format={(v) => `${v.toFixed(1)} million`} />
        </div>
        <Body delay={30} size={36 * u} color={colors.onForestMuted}>people, three questions</Body>
        <div style={{ height: 30 * u }} />
        {qs.map((q, i) => (
          <Sequence key={q} from={at[i]} layout="none">
            <Kinetic text={q} size={(portrait ? 64 : 70) * u} color="#fff" style={{ marginBottom: 8 * u }} />
          </Sequence>
        ))}
      </AbsoluteFill>
      <SourceNote text={script.segments[0].source} />
    </AbsoluteFill>
  );
}

function Now({ frames }) {
  const { u, portrait } = useOrientation();
  const chips = ['New terminals', 'Electric buses', 'Gas-powered (CNG) buses'];
  return (
    <AbsoluteFill>
      <PhotoBg src="city_gate_aerial.jpg" scrim={0.7} duration={frames} />
      <AbsoluteFill style={{ justifyContent: 'center', padding: `0 ${(portrait ? 70 : 140) * u}px` }}>
        <Eyebrow delay={6} size={28 * u}>Why now</Eyebrow>
        <div style={{ height: 14 * u }} />
        <Kinetic text="One of Africa's fastest-growing capitals." size={(portrait ? 76 : 82) * u} color="#fff" delay={10} />
        <div style={{ height: 24 * u }} />
        <div style={{ display: 'flex', gap: 40 * u, flexWrap: 'wrap', fontFamily: family, color: '#fff' }}>
          <div>
            <div style={{ fontWeight: 800, fontSize: 92 * u, color: colors.leaf, letterSpacing: '-0.03em' }}>
              +<Counter to={190000} start={40} dur={60} />
            </div>
            <div style={{ fontSize: 28 * u, color: colors.onForestMuted }}>new residents a year</div>
          </div>
        </div>
        <div style={{ height: 30 * u }} />
        <div style={{ display: 'flex', gap: 14 * u, flexWrap: 'wrap' }}>
          {chips.map((c, i) => (
            <Pill key={c} delay={Math.round(frames * 0.45) + i * 12} size={30 * u}>{c}</Pill>
          ))}
        </div>
        <div style={{ height: 30 * u }} />
        <Sequence from={Math.round(frames * 0.78)} layout="none">
          <Kinetic text="But the system to run them is missing." size={(portrait ? 56 : 60) * u} color={colors.leaf} />
        </Sequence>
      </AbsoluteFill>
      <SourceNote text={script.segments[1].source} />
    </AbsoluteFill>
  );
}

function Market({ frames }) {
  const { u, portrait } = useOrientation();
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const grow = (delay) => spring({ frame: f - delay, fps, config: { damping: 200 }, durationInFrames: 50 });
  const maxH = (portrait ? 620 : 460) * u;
  const bars = [
    { label: '2025', value: 400, delay: 30 },
    { label: '2031', value: 965, delay: 70 },
  ];
  return (
    <AbsoluteFill>
      <NetworkBg seed={0.3} />
      <AbsoluteFill style={{ flexDirection: portrait ? 'column' : 'row', alignItems: portrait ? 'stretch' : 'center', padding: `${(portrait ? 160 : 0) * u}px ${(portrait ? 70 : 140) * u}px`, gap: 80 * u }}>
        <div style={{ flex: 1 }}>
          <Eyebrow delay={6} size={28 * u}>The market</Eyebrow>
          <div style={{ height: 14 * u }} />
          <Kinetic text="Nigeria's urban mobility market is set to more than double." size={(portrait ? 68 : 72) * u} color="#fff" delay={10} />
          <div style={{ height: 30 * u }} />
          <Sequence from={Math.round(frames * 0.66)} layout="none">
            <div style={{ display: 'flex', gap: 14 * u, flexWrap: 'wrap' }}>
              {['Cash', 'Guesswork', 'Trust'].map((w, i) => (
                <Pill key={w} delay={i * 10} size={34 * u} bg="rgba(255,255,255,0.12)" color="#fff">{w}</Pill>
              ))}
            </div>
            <Body delay={30} size={28 * u} color={colors.onForestMuted} style={{ marginTop: 16 * u }}>is how most daily trips still run</Body>
          </Sequence>
        </div>
        <div style={{ flex: 0.8, display: 'flex', alignItems: 'flex-end', justifyContent: 'center', gap: 70 * u, height: maxH + 120 * u }}>
          {bars.map((b) => {
            const p = grow(b.delay);
            return (
              <div key={b.label} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14 * u, fontFamily: family }}>
                <div style={{ color: '#fff', fontWeight: 800, fontSize: 52 * u, opacity: p }}>${Math.round(b.value * p)}M</div>
                <div style={{ width: 170 * u, height: (b.value / 965) * maxH * p, background: b.label === '2031' ? colors.leaf : 'rgba(255,255,255,0.35)', borderRadius: `${10 * u}px ${10 * u}px 0 0` }} />
                <div style={{ color: colors.onForestMuted, fontWeight: 700, fontSize: 30 * u }}>{b.label}</div>
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
      <SourceNote text={script.segments[2].source} />
    </AbsoluteFill>
  );
}

function Why({ frames }) {
  const { u, portrait } = useOrientation();
  const lines = [
    ['Up to ½ of income', 'spent getting to work'],
    ["Owners can't see", 'what their vehicles earn'],
    ["Government can't see", 'the city move'],
  ];
  return (
    <AbsoluteFill>
      <NetworkBg light seed={0.6} />
      <AbsoluteFill style={{ justifyContent: 'center', padding: `0 ${(portrait ? 70 : 140) * u}px` }}>
        <Eyebrow delay={4} color={colors.forest} size={28 * u}>Why we are building it</Eyebrow>
        <div style={{ height: 26 * u }} />
        <div style={{ display: 'grid', gridTemplateColumns: portrait ? '1fr' : '1fr 1fr 1fr', gap: 26 * u }}>
          {lines.map(([big, small], i) => (
            <Rise key={big} delay={10 + Math.round(frames * 0.16) * i} distance={50}>
              <div style={{ background: '#fff', border: `1px solid ${colors.mintStrong}`, borderRadius: 28 * u, padding: `${30 * u}px ${32 * u}px`, boxShadow: '0 24px 60px rgba(6,51,31,0.10)', fontFamily: family }}>
                <div style={{ fontWeight: 800, fontSize: 50 * u, color: colors.forest, letterSpacing: '-0.02em' }}>{big}</div>
                <div style={{ fontWeight: 500, fontSize: 30 * u, color: colors.inkSoft, marginTop: 6 * u }}>{small}</div>
              </div>
            </Rise>
          ))}
        </div>
        <div style={{ height: 50 * u }} />
        <Sequence from={Math.round(frames * 0.62)} layout="none">
          <Kinetic text="Fair. Safe. Visible." size={(portrait ? 110 : 130) * u} delay={0} stagger={10} highlight={['Visible.']} />
        </Sequence>
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

function Solution({ frames }) {
  const { u, portrait } = useOrientation();
  const f = useCurrentFrame();
  const beats = [
    { title: 'Book & tap to pay', sub: 'Fixed fares, every time', el: (h) => <Phone height={h} sequence={[{ src: 'p_payment', at: 0 }, { src: 'p_ticket', at: 40 }]} /> },
    { title: 'Every vehicle verified', sub: 'On the FCTA register', el: (h) => <Phone height={h} src="p_ticket" zoom={1.7} focus={[0.5, 0.82]} /> },
    { title: 'Every naira visible', sub: 'Drivers, operators, fleet owners', el: (h) => <Browser width={h * 1.45} src="d_operator" /> },
    { title: 'The FCTA sees every route', sub: 'Register, ridership, demand', el: (h) => <Browser width={h * 1.45} src="d_fcta" /> },
    { title: 'Tapi tells you when to leave', sub: 'Your AI ride guide', el: (h) => <Phone height={h} src="p_assistant" /> },
  ];
  const each = frames / beats.length;
  const i = Math.min(beats.length - 1, Math.floor(f / each));
  const local = f - i * each;
  const p = spring({ frame: local, fps: FPS, config: { damping: 200 }, durationInFrames: 18 });
  const b = beats[i];
  const h = (portrait ? 900 : 760) * u;
  return (
    <AbsoluteFill>
      <NetworkBg seed={0.45} />
      <AbsoluteFill style={{ flexDirection: portrait ? 'column' : 'row', alignItems: 'center', justifyContent: 'center', padding: `${(portrait ? 150 : 0) * u}px ${(portrait ? 70 : 130) * u}px`, gap: 70 * u }}>
        <div style={{ flex: portrait ? 'none' : 0.8, width: portrait ? '100%' : undefined }}>
          <Eyebrow delay={4} size={28 * u}>One platform for everyone</Eyebrow>
          <div style={{ height: 16 * u }} />
          <div key={i} style={{ opacity: p, transform: `translateY(${(1 - p) * 30}px)`, fontFamily: family }}>
            <div style={{ fontWeight: 800, fontSize: (portrait ? 80 : 86) * u, color: '#fff', letterSpacing: '-0.03em', lineHeight: 1.02 }}>{b.title}</div>
            <div style={{ fontWeight: 500, fontSize: 34 * u, color: colors.onForestMuted, marginTop: 14 * u }}>{b.sub}</div>
          </div>
          <div style={{ display: 'flex', gap: 10 * u, marginTop: 34 * u }}>
            {beats.map((_, k) => (
              <div key={k} style={{ width: k === i ? 46 * u : 14 * u, height: 14 * u, borderRadius: 99, background: k <= i ? colors.leaf : 'rgba(255,255,255,0.25)' }} />
            ))}
          </div>
        </div>
        <div key={`d${i}`} style={{ flex: portrait ? 'none' : 1.2, display: 'flex', justifyContent: 'center', opacity: p, transform: `scale(${0.94 + 0.06 * p})` }}>{b.el(h)}</div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

function Future({ frames }) {
  const { u, portrait } = useOrientation();
  const size = (portrait ? 640 : 520) * u;
  return (
    <AbsoluteFill>
      <NetworkBg seed={0.9} />
      <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center', flexDirection: 'column', padding: `0 ${70 * u}px` }}>
        <Kinetic text="Connected. Cashless. Smart." size={(portrait ? 80 : 84) * u} color="#fff" align="center" delay={10} stagger={8} highlight={['Smart.']} />
        <div style={{ width: size, height: size * 0.72 }}>
          <Tapi width={size} height={size * 0.72} mood="celebrate" moodFrom={Math.round(frames * 0.45)} />
        </div>
        <Logo white height={(portrait ? 120 : 100) * u} delay={Math.round(frames * 0.35)} />
        <div style={{ height: 22 * u }} />
        <Sequence from={Math.round(frames * 0.55)} layout="none">
          <Kinetic text="Know your fare. Know your ride. Just tap." size={(portrait ? 58 : 60) * u} color="#fff" align="center" stagger={3} highlight={['tap.']} />
        </Sequence>
        <div style={{ height: 26 * u }} />
        <Pill delay={Math.round(frames * 0.7)} bg={colors.leaf} color={colors.forestDeep} size={(portrait ? 38 : 34) * u}>taparide.vercel.app</Pill>
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

const SCENES = { hook: Hook, now: Now, market: Market, why: Why, solution: Solution, future: Future };

export function Commercial() {
  const { durationInFrames } = useVideoConfig();
  let from = 0;
  return (
    <AbsoluteFill style={{ background: colors.forestDeep }}>
      {COMMERCIAL_SCENES.map((s) => {
        const Scene = SCENES[s.id];
        const start = from;
        from += s.frames;
        return (
          <Sequence key={s.id} from={start} durationInFrames={s.id === 'future' ? s.frames + FPS : s.frames}>
            <SceneFade frames={s.id === 'future' ? s.frames + FPS : s.frames}>
              <Scene frames={s.frames} />
            </SceneFade>
            <Captions text={s.text} frames={s.frames} />
            <Audio src={staticFile(`voice/${s.id}.wav`)} />
          </Sequence>
        );
      })}
      {/* Music sits well under the voice (about −16 dB) and swells at the end. */}
      <Audio
        src={staticFile('music/commercial.wav')}
        volume={(f) => interpolate(f, [0, 20, durationInFrames - 160, durationInFrames - 60, durationInFrames], [0, 0.16, 0.16, 0.45, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })}
      />
    </AbsoluteFill>
  );
}
