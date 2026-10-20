// "Just tap." — 45-second Tap A Ride commercial. Works in 16:9 and 9:16.
import { linearTiming, springTiming, TransitionSeries } from '@remotion/transitions';
import { fade } from '@remotion/transitions/fade';
import { slide } from '@remotion/transitions/slide';
import { wipe } from '@remotion/transitions/wipe';
import { AbsoluteFill, Audio, interpolate, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import { Tapi } from './components/Tapi';
import { Rise, Split } from './components/layout';
import { Body, Browser, Eyebrow, Kinetic, Logo, NetworkBg, Phone, PhotoBg, Pill, Tap, useEnter, useOrientation } from './components/ui';
import { colors, family } from './theme';

export const AD_SCENES = { questions: 150, reveal: 140, book: 200, pay: 190, tapi: 190, safe: 170, partners: 190, end: 200 };
const T = 15; // transition length
export const AD_DURATION = Object.values(AD_SCENES).reduce((a, b) => a + b, 0) - T * (Object.keys(AD_SCENES).length - 1);

export function Notification({ start, title = 'Time to leave for Wuse', body = 'Your 3:30 PM bus departs soon · 15 min walk' }) {
  const p = useEnter(start, { damping: 18 });
  return (
    <div style={{ position: 'absolute', left: '4%', right: '4%', top: '2.5%', padding: '3.5cqw 4cqw', borderRadius: '6cqw', background: 'rgba(6,51,31,0.96)', boxShadow: '0 20px 40px rgba(0,0,0,0.25)', transform: `translateY(${(p - 1) * 140}%)`, display: 'flex', gap: '3cqw', alignItems: 'center', fontFamily: family }}>
      <div style={{ fontSize: '7cqw' }}>🔔</div>
      <div style={{ minWidth: 0 }}>
        <div style={{ color: '#fff', fontWeight: 800, fontSize: '4.6cqw', whiteSpace: 'nowrap' }}>{title}</div>
        <div style={{ color: colors.onForestMuted, fontWeight: 500, fontSize: '3.6cqw' }}>{body}</div>
      </div>
    </div>
  );
}

function Questions() {
  const { portrait, u } = useOrientation();
  const frame = useCurrentFrame();
  const qs = ["What's the fare today?", "When's the next bus?", 'Is this car safe?'];
  return (
    <AbsoluteFill>
      <PhotoBg src="abuja_expressway.jpg" scrim={0.72} duration={AD_SCENES.questions} />
      <AbsoluteFill style={{ justifyContent: 'center', padding: `0 ${(portrait ? 70 : 140) * u}px` }}>
        <Eyebrow delay={4} color={colors.leaf} size={28 * u}>Abuja, every morning</Eyebrow>
        <div style={{ height: 30 * u }} />
        {qs.map((q, i) => (
          <Kinetic key={q} text={q} size={(portrait ? 96 : 110) * u} color="#fff" delay={14 + i * 28} style={{ marginBottom: 14 * u, opacity: interpolate(frame, [120, 145], [1, 0.0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' }) }} />
        ))}
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

function Reveal() {
  const { portrait, u, width, height } = useOrientation();
  const frame = useCurrentFrame();
  const drive = interpolate(frame, [0, 42], [0, 1], { extrapolateRight: 'clamp', easing: (t) => 1 - Math.pow(1 - t, 3) });
  const size = (portrait ? 760 : 620) * u;
  return (
    <AbsoluteFill>
      <NetworkBg />
      <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center', flexDirection: 'column' }}>
        <Logo white height={(portrait ? 120 : 110) * u} delay={30} />
        <div style={{ width: size, height: size * 0.82 }}>
          <Tapi width={size} height={size * 0.82} mood={frame > 44 ? 'wave' : 'idle'} drive={drive} />
        </div>
        <Kinetic text="Know your fare. Know your ride. Just tap." size={(portrait ? 76 : 72) * u} color="#fff" align="center" delay={56} stagger={4} highlight={['tap']} style={{ maxWidth: (portrait ? 900 : 1500) * u }} />
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

function Book() {
  const { portrait, u } = useOrientation();
  const ph = (portrait ? 960 : 790) * u;
  return (
    <AbsoluteFill>
      <NetworkBg light />
      <Split
        text={
          <>
            <Eyebrow delay={6} color={colors.forest} size={28 * u}>Book in seconds</Eyebrow>
            <div style={{ height: 18 * u }} />
            <Kinetic text="Real routes. Fixed fares." size={(portrait ? 92 : 104) * u} delay={10} highlight={['Fixed', 'fares']} />
            <div style={{ height: 24 * u }} />
            <Body delay={30} size={34 * u}>Search where you're going, pick a departure and see the real road route before you leave.</Body>
          </>
        }
        device={
          <Rise delay={4}>
            <Phone
              height={ph}
              sequence={[
                { src: 'p_home_booked', at: 0, extra: <Tap at={[0.3, 0.37]} start={80} /> },
                { src: 'p_route_details', at: 92 },
              ]}
            />
          </Rise>
        }
      />
    </AbsoluteFill>
  );
}

function Pay() {
  const { portrait, u } = useOrientation();
  const ph = (portrait ? 960 : 790) * u;
  return (
    <AbsoluteFill>
      <NetworkBg light seed={0.3} />
      <Split
        deviceSide="left"
        text={
          <>
            <Eyebrow delay={6} color={colors.forest} size={28 * u}>Tap &amp; pay</Eyebrow>
            <div style={{ height: 18 * u }} />
            <Kinetic text="No cash. No change. No arguments." size={(portrait ? 88 : 100) * u} delay={10} highlight={['No']} />
            <div style={{ height: 24 * u }} />
            <Body delay={34} size={34 * u}>Tap your travel card or show your QR. The fare is the one the operator published, every time.</Body>
            <div style={{ height: 30 * u }} />
            <Pill delay={92} bg={colors.forest} color="#fff" size={32 * u} icon="✓">₦500 paid · Seat S04</Pill>
          </>
        }
        device={
          <Rise delay={4}>
            <Phone
              height={ph}
              sequence={[
                { src: 'p_payment', at: 0, extra: <Tap at={[0.5, 0.955]} start={50} /> },
                { src: 'p_ticket', at: 68 },
              ]}
            />
          </Rise>
        }
      />
    </AbsoluteFill>
  );
}

function TapiScene() {
  const { portrait, u } = useOrientation();
  const frame = useCurrentFrame();
  const ph = (portrait ? 940 : 780) * u;
  const ts = (portrait ? 360 : 330) * u;
  return (
    <AbsoluteFill>
      <NetworkBg seed={0.5} />
      <Split
        text={
          <>
            <div style={{ width: ts, height: ts * 0.8, marginLeft: -40 * u, marginBottom: -10 * u }}>
              <Tapi width={ts} height={ts * 0.8} mood={frame < 70 ? 'think' : 'wave'} look={[0.6, 0]} />
            </div>
            <Kinetic text="Tapi tells you when to leave." size={(portrait ? 88 : 96) * u} color="#fff" delay={8} highlight={['Tapi']} />
            <div style={{ height: 24 * u }} />
            <Body delay={30} size={34 * u} color={colors.onForestMuted}>Your AI ride assistant plans trips, books seats and reminds you before every ride.</Body>
          </>
        }
        device={
          <Rise delay={4}>
            <Phone src="p_assistant" height={ph}>
              <Notification start={95} />
            </Phone>
          </Rise>
        }
      />
    </AbsoluteFill>
  );
}

function Safe() {
  const { portrait, u } = useOrientation();
  const frame = useCurrentFrame();
  const ph = (portrait ? 960 : 790) * u;
  const zoom = interpolate(frame, [20, 80], [1, 1.75], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: (t) => t * t * (3 - 2 * t) });
  return (
    <AbsoluteFill>
      <NetworkBg light seed={0.7} />
      <Split
        deviceSide="left"
        text={
          <>
            <Eyebrow delay={6} color={colors.forest} size={28 * u}>Safe &amp; verified</Eyebrow>
            <div style={{ height: 18 * u }} />
            <Kinetic text="Every vehicle on the FCTA register." size={(portrait ? 88 : 96) * u} delay={10} highlight={['FCTA']} />
            <div style={{ height: 30 * u }} />
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 14 * u }}>
              <Pill delay={40} size={28 * u} icon="✓">Verified operator</Pill>
              <Pill delay={52} size={28 * u} icon="✓">Plate on your ticket</Pill>
              <Pill delay={64} size={28 * u} bg="#FDE8E8" color={colors.red} icon="SOS">Emergency &amp; trip sharing</Pill>
            </div>
          </>
        }
        device={
          <Rise delay={4}>
            <Phone src="p_ticket" height={ph} zoom={zoom} focus={[0.5, 0.82]} />
          </Rise>
        }
      />
    </AbsoluteFill>
  );
}

function Partners() {
  const { portrait, u } = useOrientation();
  const bw = (portrait ? 920 : 1080) * u;
  const ph = (portrait ? 720 : 600) * u;
  const text = (
    <>
      <Eyebrow delay={6} size={28 * u}>Drivers · Operators · Fleet owners · FCTA</Eyebrow>
      <div style={{ height: 18 * u }} />
      <Kinetic text="See every trip. Every naira." size={(portrait ? 92 : 96) * u} color="#fff" delay={10} highlight={['naira.']} />
      <div style={{ height: 22 * u }} />
      <Body delay={30} size={32 * u} color={colors.onForestMuted}>Live fleet maps, earnings per vehicle and an AI analyst for every partner.</Body>
    </>
  );
  const devices = (
    <div style={{ position: 'relative', width: bw, height: bw * 0.66 + ph * 0.35 }}>
      <Rise delay={6}>
        <Browser src="d_operator" width={bw} />
      </Rise>
      <div style={{ position: 'absolute', right: -40 * u, bottom: 0 }}>
        <Rise delay={22}>
          <Phone src="p_driver" height={ph} />
        </Rise>
      </div>
    </div>
  );
  return (
    <AbsoluteFill>
      <NetworkBg seed={0.2} />
      {portrait ? (
        <AbsoluteFill style={{ padding: `${150 * u}px ${70 * u}px`, gap: 60 * u }}>
          <div>{text}</div>
          <div style={{ display: 'flex', justifyContent: 'center' }}>{devices}</div>
        </AbsoluteFill>
      ) : (
        <AbsoluteFill style={{ flexDirection: 'row', alignItems: 'center', padding: `0 ${110 * u}px`, gap: 70 * u }}>
          <div style={{ flex: 0.8 }}>{text}</div>
          <div style={{ flex: 1.2, display: 'flex', justifyContent: 'center' }}>{devices}</div>
        </AbsoluteFill>
      )}
    </AbsoluteFill>
  );
}

function End() {
  const { portrait, u } = useOrientation();
  const size = (portrait ? 700 : 560) * u;
  return (
    <AbsoluteFill>
      <NetworkBg seed={0.9} />
      <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center', flexDirection: 'column' }}>
        <div style={{ width: size, height: size * 0.8 }}>
          <Tapi width={size} height={size * 0.8} mood="celebrate" moodFrom={12} />
        </div>
        <Logo white height={(portrait ? 120 : 104) * u} delay={6} />
        <div style={{ height: 26 * u }} />
        <Kinetic text="Know your fare. Know your ride. Just tap." size={(portrait ? 66 : 64) * u} color="#fff" align="center" delay={18} stagger={3} highlight={['tap.']} style={{ maxWidth: 1400 * u }} />
        <div style={{ height: 36 * u }} />
        <Pill delay={50} bg={colors.leaf} color={colors.forestDeep} size={(portrait ? 40 : 36) * u}>taparide.vercel.app</Pill>
        <div style={{ height: 22 * u }} />
        <Body delay={64} size={26 * u} color={colors.onForestMuted} style={{ textAlign: 'center' }}>Abuja Smart Mobility Platform · Ride • Connect • Go</Body>
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

export function Ad() {
  const { durationInFrames } = useVideoConfig();
  const s = AD_SCENES;
  const t = (kind) =>
    kind === 'slide'
      ? { presentation: slide({ direction: 'from-right' }), timing: springTiming({ config: { damping: 200 }, durationInFrames: T }) }
      : kind === 'wipe'
        ? { presentation: wipe({ direction: 'from-left' }), timing: linearTiming({ durationInFrames: T }) }
        : { presentation: fade(), timing: linearTiming({ durationInFrames: T }) };
  const scenes = [
    [s.questions, <Questions />, 'fade'],
    [s.reveal, <Reveal />, 'slide'],
    [s.book, <Book />, 'slide'],
    [s.pay, <Pay />, 'wipe'],
    [s.tapi, <TapiScene />, 'wipe'],
    [s.safe, <Safe />, 'wipe'],
    [s.partners, <Partners />, 'fade'],
    [s.end, <End />, null],
  ];
  return (
    <AbsoluteFill style={{ background: colors.forestDeep }}>
      <TransitionSeries>
        {scenes.flatMap(([d, el, tr], i) => {
          const items = [<TransitionSeries.Sequence key={`s${i}`} durationInFrames={d}>{el}</TransitionSeries.Sequence>];
          if (tr) items.push(<TransitionSeries.Transition key={`t${i}`} {...t(tr)} />);
          return items;
        })}
      </TransitionSeries>
      <Audio
        src={staticFile('music/ad.wav')}
        volume={(f) => interpolate(f, [0, 20, durationInFrames - 45, durationInFrames], [0, 0.85, 0.85, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })}
      />
    </AbsoluteFill>
  );
}
