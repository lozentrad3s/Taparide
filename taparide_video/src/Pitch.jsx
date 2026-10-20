// Tap A Ride pitch film (16:9). Facts in the problem section come from the team's
// "Abuja Smart Mobility Platform Concept & Strategy" brief and are cited on screen.
import { linearTiming, springTiming, TransitionSeries } from '@remotion/transitions';
import { fade } from '@remotion/transitions/fade';
import { slide } from '@remotion/transitions/slide';
import { wipe } from '@remotion/transitions/wipe';
import { AbsoluteFill, Audio, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import { Notification } from './Ad';
import { Rise, Sequenced, Split } from './components/layout';
import { Tapi } from './components/Tapi';
import { Body, Browser, Eyebrow, Kinetic, Logo, NetworkBg, Phone, PhotoBg, Pill, Source, Tap, useEnter } from './components/ui';
import { colors, family } from './theme';

const T = 18;
export const PITCH_SCENES = {
  title: 270,
  scale: 240,
  pains: 390,
  gap: 330,
  hub: 330,
  rider: 600,
  join: 330,
  review: 240,
  dashboards: 640,
  ai: 360,
  fcta: 300,
  model: 330,
  roadmap: 360,
  close: 330,
};
export const PITCH_DURATION = Object.values(PITCH_SCENES).reduce((a, b) => a + b, 0) - T * (Object.keys(PITCH_SCENES).length - 1);

// ------------------------------------------------------------------ icons (simple, consistent line icons)
const Icon = ({ name, size = 56, color = '#fff' }) => {
  const p = {
    rider: <><circle cx="12" cy="6.5" r="3.2" /><path d="M5.5 21v-2.5a6.5 6.5 0 0 1 13 0V21" /></>,
    bus: <><rect x="4" y="3.5" width="16" height="14" rx="3" /><path d="M4 11h16M8 21v-3M16 21v-3" /><circle cx="8" cy="14.5" r="0.8" /><circle cx="16" cy="14.5" r="0.8" /></>,
    chart: <><path d="M4 20V4M4 20h16" /><path d="M8 16v-4M12 16V8M16 16v-6" /></>,
    gov: <><path d="M3 10 12 4l9 6" /><path d="M5 10v8M9.5 10v8M14.5 10v8M19 10v8M3 20h18" /></>,
    shield: <path d="M12 3 5 6v6c0 4.4 3 7.6 7 9 4-1.4 7-4.6 7-9V6l-7-3Z" />,
    spark: <path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M18 6l-2.5 2.5M8.5 15.5 6 18" />,
    card: <><rect x="3" y="6" width="18" height="12" rx="2.5" /><path d="M3 10h18" /></>,
  }[name];
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round">
      {p}
    </svg>
  );
};

// ------------------------------------------------------------------ scenes

function Title() {
  const frame = useCurrentFrame();
  const drive = interpolate(frame, [0, 45], [0, 1], { extrapolateRight: 'clamp', easing: (t) => 1 - Math.pow(1 - t, 3) });
  return (
    <AbsoluteFill>
      <NetworkBg />
      <AbsoluteFill style={{ flexDirection: 'row', alignItems: 'center', padding: '0 130px', gap: 40 }}>
        <div style={{ flex: 1.2 }}>
          <Logo white height={110} delay={8} />
          <div style={{ height: 28 }} />
          <Eyebrow delay={20} size={28}>Abuja Smart Mobility Platform</Eyebrow>
          <div style={{ height: 28 }} />
          <Kinetic text="Abuja has the terminals and the buses." size={84} color="#fff" delay={34} />
          <Kinetic text="We are the system that runs them." size={84} color={colors.leaf} delay={70} />
        </div>
        <div style={{ width: 640, height: 560 }}>
          <Tapi width={640} height={560} mood={frame > 48 ? 'wave' : 'idle'} drive={drive} look={[-0.4, 0]} />
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

function Scale() {
  return (
    <AbsoluteFill>
      <PhotoBg src="abuja_taxis.jpg" scrim={0.74} duration={PITCH_SCENES.scale} />
      <AbsoluteFill style={{ justifyContent: 'center', padding: '0 140px' }}>
        <Eyebrow delay={6} size={28}>The problem</Eyebrow>
        <div style={{ height: 24 }} />
        <Kinetic text="4.3 million residents." size={130} color="#fff" delay={14} highlight={['4.3']} />
        <Kinetic text="No structured mass transit." size={96} color="#fff" delay={40} />
        <div style={{ height: 30 }} />
        <Body delay={70} size={36} color={colors.onForestMuted} style={{ maxWidth: 1200 }}>
          Most people depend on informal minibuses, taxis, tricycles and expensive ride-hailing.
        </Body>
      </AbsoluteFill>
      <Source light>Daily Trust, April 2026</Source>
    </AbsoluteFill>
  );
}

function StatCard({ big, line, source, delay }) {
  const p = useEnter(delay);
  return (
    <div style={{ background: '#fff', borderRadius: 32, padding: '38px 40px', boxShadow: '0 24px 60px rgba(6,51,31,0.10)', border: `1px solid ${colors.mintStrong}`, transform: `translateY(${(1 - p) * 60}px)`, opacity: p, display: 'flex', flexDirection: 'column', gap: 14 }}>
      <div style={{ fontFamily: family, fontWeight: 800, fontSize: 62, letterSpacing: '-0.03em', color: colors.forest, lineHeight: 1 }}>{big}</div>
      <div style={{ fontFamily: family, fontWeight: 500, fontSize: 30, color: colors.ink, lineHeight: 1.3 }}>{line}</div>
      <div style={{ fontFamily: family, fontWeight: 500, fontSize: 19, color: colors.muted }}>{source}</div>
    </div>
  );
}

function Pains() {
  return (
    <AbsoluteFill>
      <NetworkBg light />
      <AbsoluteFill style={{ padding: '110px 130px' }}>
        <Eyebrow delay={4} color={colors.forest} size={28}>What commuters face every day</Eyebrow>
        <div style={{ height: 18 }} />
        <Kinetic text="Uncertain, unsafe and expensive." size={84} delay={8} />
        <div style={{ height: 50 }} />
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 32 }}>
          <StatCard delay={40} big="Up to ½ of income" line="spent on the daily commute" source="Daily Trust" />
          <StatCard delay={64} big="Fares jump" line="at peak hours and whenever it rains" source="New National Star · The Trumpet" />
          <StatCard delay={88} big="“One chance”" line="robberies in unpainted cars with fake plates" source="New National Star · The Sun" />
          <StatCard delay={112} big="Stranded at night" line="queues at Berger, Area 1, Nyanya and Kubwa" source="New National Star" />
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

function Gap() {
  const items = [
    ['Idle terminals', 'Modern terminals at Mabushi, Kugbo and the Federal Secretariat have no working buses, routes or schedules.', 'New National Star, Sep 2026'],
    ['New fleets, no shared system', 'Electric buses and the airport shuttle each sell tickets their own way: POS, transfer or cash.', 'Abuja Guide · WithinNigeria'],
    ['No investor trust', 'An owner who buys a vehicle only knows what the driver reports at the end of the day.', 'Team research'],
  ];
  return (
    <AbsoluteFill>
      <PhotoBg src="brt_berger.jpg" scrim={0.8} duration={PITCH_SCENES.gap} />
      <AbsoluteFill style={{ flexDirection: 'row', padding: '0 130px', alignItems: 'center', gap: 80 }}>
        <div style={{ flex: 1 }}>
          <Eyebrow delay={6} size={28}>The gap</Eyebrow>
          <div style={{ height: 20 }} />
          <Kinetic text="The vehicles and terminals exist." size={78} color="#fff" delay={12} />
          <Kinetic text="The system to run them does not." size={78} color={colors.leaf} delay={40} />
        </div>
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 26 }}>
          {items.map(([h, b, s], i) => (
            <Rise key={h} delay={70 + i * 26} distance={50}>
              <div style={{ background: 'rgba(255,255,255,0.08)', border: '1px solid rgba(255,255,255,0.16)', borderRadius: 26, padding: '26px 30px', fontFamily: family }}>
                <div style={{ color: '#fff', fontWeight: 800, fontSize: 34 }}>{h}</div>
                <div style={{ color: colors.onForestMuted, fontWeight: 500, fontSize: 25, lineHeight: 1.35, marginTop: 6 }}>{b}</div>
                <div style={{ color: 'rgba(255,255,255,0.45)', fontSize: 17, marginTop: 8 }}>{s}</div>
              </div>
            </Rise>
          ))}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

function Hub() {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const cx = 960, cy = 610, r = 330;
  const nodes = [
    { icon: 'rider', title: 'Riders', line: 'Book, tap to pay, ride safe', a: -150 },
    { icon: 'bus', title: 'Operators', line: 'Routes, fares, live fleet, revenue', a: -30 },
    { icon: 'chart', title: 'Fleet owners', line: 'Earnings per vehicle', a: 30 },
    { icon: 'gov', title: 'Government (FCTA)', line: 'Verified register, ridership data', a: 150 },
  ];
  const core = spring({ frame: frame - 30, fps, config: { damping: 14 } });
  return (
    <AbsoluteFill>
      <NetworkBg seed={0.4} />
      <AbsoluteFill style={{ alignItems: 'center', paddingTop: 80 }}>
        <Eyebrow delay={4} size={28}>The solution</Eyebrow>
        <div style={{ height: 14 }} />
        <Kinetic text="One platform every operator plugs into." size={70} color="#fff" align="center" delay={8} />
      </AbsoluteFill>
      <svg width={1920} height={1080} style={{ position: 'absolute', inset: 0 }}>
        {nodes.map((n, i) => {
          const rad = (n.a * Math.PI) / 180;
          const x = cx + Math.cos(rad) * r * 1.55, y = cy + Math.sin(rad) * r * 0.62;
          const draw = interpolate(frame, [50 + i * 12, 90 + i * 12], [1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
          return <line key={i} x1={cx} y1={cy} x2={x} y2={y} stroke={colors.leaf} strokeOpacity={0.6} strokeWidth={4} pathLength={1} strokeDasharray={1} strokeDashoffset={draw} />;
        })}
        {nodes.map((n, i) => {
          const rad = (n.a * Math.PI) / 180;
          const x = cx + Math.cos(rad) * r * 1.55, y = cy + Math.sin(rad) * r * 0.62;
          const t = ((frame - 100 - i * 9) / 60) % 1;
          if (frame < 100) return null;
          return <circle key={`p${i}`} cx={cx + (x - cx) * t} cy={cy + (y - cy) * t} r={7} fill="#fff" opacity={0.9} />;
        })}
      </svg>
      <div style={{ position: 'absolute', left: cx - 150, top: cy - 150, width: 300, height: 300, borderRadius: 999, background: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', transform: `scale(${core})`, boxShadow: '0 0 0 18px rgba(77,181,42,0.18), 0 30px 80px rgba(0,0,0,0.35)' }}>
        <Logo height={78} />
      </div>
      {nodes.map((n, i) => {
        const rad = (n.a * Math.PI) / 180;
        const x = cx + Math.cos(rad) * r * 1.55, y = cy + Math.sin(rad) * r * 0.62;
        return (
          <div key={n.title} style={{ position: 'absolute', left: x - 190, top: y - 95, width: 380 }}>
            <Rise delay={70 + i * 14} distance={30}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 18, background: '#0D4A31', border: '1px solid rgba(255,255,255,0.18)', borderRadius: 26, padding: '20px 24px', boxShadow: '0 20px 50px rgba(0,0,0,0.25)' }}>
                <div style={{ width: 76, height: 76, borderRadius: 22, background: colors.leaf, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  <Icon name={n.icon} size={44} color={colors.forestDeep} />
                </div>
                <div style={{ fontFamily: family }}>
                  <div style={{ color: '#fff', fontWeight: 800, fontSize: 30 }}>{n.title}</div>
                  <div style={{ color: colors.onForestMuted, fontWeight: 500, fontSize: 22, lineHeight: 1.3 }}>{n.line}</div>
                </div>
              </div>
            </Rise>
          </div>
        );
      })}
      <AbsoluteFill style={{ justifyContent: 'flex-end', alignItems: 'center', paddingBottom: 70 }}>
        <Body delay={150} size={30} color={colors.onForestMuted}>We don't own vehicles. We are the shared system every provider runs on.</Body>
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

function Rider() {
  const frame = useCurrentFrame();
  const step = 80;
  const steps = [
    ['Search & see the real road route', 'p_route_details'],
    ['Book a seat at the published fare', 'p_payment'],
    ['Tap a card or show a QR to board', 'p_ticket'],
    ['Tapi says when to leave', 'p_assistant'],
    ['Electric cars on demand', 'p_ev'],
    ['Tag Along with verified colleagues', 'p_tag_along'],
    ['Nearby places, live traffic & SOS', 'p_nearby'],
  ];
  const active = Math.min(steps.length - 1, Math.max(0, Math.floor((frame - 20) / step)));
  return (
    <AbsoluteFill>
      <NetworkBg light seed={0.6} />
      <Split
        textFlex={1.15}
        text={
          <>
            <Eyebrow delay={4} color={colors.forest} size={28}>For riders</Eyebrow>
            <div style={{ height: 14 }} />
            <Kinetic text="From tap to seat." size={92} delay={8} />
            <div style={{ height: 36 }} />
            {steps.map(([label], i) => {
              const on = i === active;
              const done = i < active;
              return (
                <Rise key={label} delay={20 + i * 5} distance={30}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 20, padding: '11px 0', fontFamily: family, opacity: on ? 1 : done ? 0.55 : 0.4 }}>
                    <div style={{ width: 46, height: 46, borderRadius: 99, background: on ? colors.forest : done ? colors.leaf : colors.mintStrong, color: '#fff', fontWeight: 800, fontSize: 22, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                      {done ? '✓' : i + 1}
                    </div>
                    <div style={{ fontSize: on ? 38 : 32, fontWeight: on ? 800 : 600, color: colors.ink, letterSpacing: '-0.01em' }}>{label}</div>
                  </div>
                </Rise>
              );
            })}
          </>
        }
        device={
          <Rise delay={6}>
            <Phone
              height={820}
              sequence={steps.map(([, src], i) => ({
                src,
                at: i === 0 ? 0 : 20 + i * step,
                extra:
                  src === 'p_payment' ? <Tap at={[0.5, 0.955]} start={20 + i * step + 50} /> : src === 'p_assistant' ? <Notification start={20 + i * step + 30} /> : null,
              }))}
            />
          </Rise>
        }
      />
    </AbsoluteFill>
  );
}

function ReqCard({ title, items, delay, icon }) {
  return (
    <Rise delay={delay} distance={50}>
      <div style={{ background: 'rgba(255,255,255,0.08)', border: '1px solid rgba(255,255,255,0.16)', borderRadius: 28, padding: '28px 32px', fontFamily: family }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 14 }}>
          <Icon name={icon} size={40} color={colors.leaf} />
          <div style={{ color: '#fff', fontWeight: 800, fontSize: 34 }}>{title}</div>
        </div>
        {items.map((it) => (
          <div key={it} style={{ color: colors.onForestMuted, fontSize: 26, fontWeight: 500, padding: '5px 0', display: 'flex', gap: 12 }}>
            <span style={{ color: colors.leaf, fontWeight: 800 }}>✓</span>
            {it}
          </div>
        ))}
      </div>
    </Rise>
  );
}

function Join() {
  return (
    <AbsoluteFill>
      <NetworkBg seed={0.15} />
      <AbsoluteFill style={{ flexDirection: 'row', alignItems: 'center', padding: '0 120px', gap: 80 }}>
        <Rise delay={6}>
          <Phone src="p_apply" height={790} />
        </Rise>
        <div style={{ flex: 1 }}>
          <Eyebrow delay={6} size={28}>Partner registration</Eyebrow>
          <div style={{ height: 14 }} />
          <Kinetic text="Every partner is verified first." size={74} color="#fff" delay={10} />
          <div style={{ height: 34 }} />
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 26 }}>
            <ReqCard delay={40} icon="rider" title="Private drivers" items={["Verified driver's licence", 'Plate number', 'Original chassis number (VIN)', 'Ownership papers & photo']} />
            <ReqCard delay={60} icon="gov" title="Companies & agencies" items={['Registered business name', 'CAC RC number & TIN', 'Number of vehicles', 'Permits & insurance']} />
          </div>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

function Review() {
  const flow = ['Partner applies', 'AI checks the documents', 'FCTA approves', 'Dashboard goes live'];
  return (
    <AbsoluteFill>
      <NetworkBg light seed={0.25} />
      <AbsoluteFill style={{ padding: '90px 120px', flexDirection: 'column', gap: 40 }}>
        <div style={{ display: 'flex', gap: 18, alignItems: 'center', flexWrap: 'wrap' }}>
          {flow.map((f, i) => (
            <div key={f} style={{ display: 'flex', alignItems: 'center', gap: 18 }}>
              <Pill delay={8 + i * 14} size={30} bg={i === 1 ? colors.forest : colors.mint} color={i === 1 ? '#fff' : colors.forest}>{f}</Pill>
              {i < flow.length - 1 ? <div style={{ fontFamily: family, fontSize: 34, color: colors.forest }}>→</div> : null}
            </div>
          ))}
        </div>
        <div style={{ display: 'flex', gap: 60, alignItems: 'center' }}>
          <Rise delay={30}>
            <Browser src="d_application_review" width={1100} />
          </Rise>
          <div style={{ flex: 1 }}>
            <Kinetic text="AI reads the papers. People decide." size={64} delay={40} />
            <div style={{ height: 20 }} />
            <Body delay={70} size={30}>The AI matches the licence, plate and chassis number against what the applicant typed and flags anything that doesn't match. The FCTA reviewer approves, declines or asks for changes.</Body>
          </div>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

function Dashboards() {
  const frame = useCurrentFrame();
  const parts = [
    { src: 'd_driver', who: 'Drivers', line: 'Go online, complete rides, see what you earned today.', focus: [0.5, 0.42] },
    { src: 'd_operator', who: 'Operators', line: 'Live fleet map, alerts that fix themselves in one tap, revenue by route.', focus: [0.45, 0.6] },
    { src: 'd_fleet', who: 'Fleet owners', line: 'Earnings for every vehicle. The end of under-remittance.', focus: [0.5, 0.45] },
    { src: 'd_admin', who: 'Platform team', line: 'One control centre: every fare, rider, vehicle and partner, and a tap into any dashboard.', focus: [0.62, 0.62] },
  ];
  const each = 160;
  const i = Math.min(parts.length - 1, Math.floor(frame / each));
  const local = frame - i * each;
  const zoom = interpolate(local, [10, each], [1, 1.22], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  return (
    <AbsoluteFill>
      <NetworkBg seed={0.33} />
      <AbsoluteFill style={{ flexDirection: 'row', alignItems: 'center', padding: '0 110px', gap: 70 }}>
        <div style={{ flex: 0.75 }}>
          <Eyebrow delay={4} size={28}>A dashboard for every partner</Eyebrow>
          <div style={{ height: 20 }} />
          <Sequenced
            items={parts.map((p, k) => ({
              from: k * each,
              el: (
                <div>
                  <div style={{ fontFamily: family, fontWeight: 800, fontSize: 92, color: '#fff', letterSpacing: '-0.03em' }}>{p.who}</div>
                  <div style={{ height: 16 }} />
                  <div style={{ fontFamily: family, fontWeight: 500, fontSize: 36, color: colors.onForestMuted, lineHeight: 1.35 }}>{p.line}</div>
                </div>
              ),
            }))}
          />
        </div>
        <div style={{ flex: 1.25 }}>
          <Rise delay={8}>
            <Sequenced items={parts.map((p, k) => ({ from: k * each, el: <Browser src={p.src} width={1080} zoom={k === i ? zoom : 1} focus={p.focus} /> }))} />
          </Rise>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

function Ai() {
  const frame = useCurrentFrame();
  const items = [
    ['Riders', 'Tapi plans trips in plain language, books seats and reminds you when to leave.'],
    ['FCTA', 'Checks partner documents before a person reviews them.'],
    ['Operators', 'An AI analyst reads income, demand hot-spots and live traffic, then says what to do next.'],
  ];
  return (
    <AbsoluteFill>
      <NetworkBg light seed={0.8} />
      <AbsoluteFill style={{ flexDirection: 'row', alignItems: 'center', padding: '0 110px', gap: 60 }}>
        <div style={{ flex: 1.1 }}>
          <Rise delay={6}>
            <Browser src="d_insights" width={1000} zoom={interpolate(frame, [20, 300], [1, 1.12], { extrapolateRight: 'clamp' })} focus={[0.5, 0.2]} />
          </Rise>
        </div>
        <div style={{ flex: 0.9 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{ width: 200, height: 170, marginLeft: -30 }}>
              <Tapi width={200} height={170} mood={frame < 120 ? 'think' : 'celebrate'} moodFrom={120} look={[-0.6, 0]} />
            </div>
            <Eyebrow delay={4} color={colors.forest} size={28}>Smart, not decorative</Eyebrow>
          </div>
          <Kinetic text="AI that saves time and money." size={70} delay={10} />
          <div style={{ height: 26 }} />
          {items.map(([who, what], i) => (
            <Rise key={who} delay={50 + i * 22} distance={40}>
              <div style={{ display: 'flex', gap: 16, padding: '12px 0', fontFamily: family }}>
                <div style={{ minWidth: 150, fontWeight: 800, fontSize: 28, color: colors.forest }}>{who}</div>
                <div style={{ fontWeight: 500, fontSize: 28, color: colors.inkSoft, lineHeight: 1.35 }}>{what}</div>
              </div>
            </Rise>
          ))}
          <div style={{ height: 12 }} />
          <Body delay={130} size={22} color={colors.muted}>Powered by Google Gemini, with Anthropic Claude as backup.</Body>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

function Fcta() {
  return (
    <AbsoluteFill>
      <NetworkBg seed={0.05} />
      <AbsoluteFill style={{ flexDirection: 'row', alignItems: 'center', padding: '0 110px', gap: 70 }}>
        <div style={{ flex: 0.8 }}>
          <Eyebrow delay={4} size={28}>For the FCTA</Eyebrow>
          <div style={{ height: 16 }} />
          <Kinetic text="See the whole city move." size={84} color="#fff" delay={8} />
          <div style={{ height: 30 }} />
          {['A verified-vehicle register that fights “one chance”', 'Ridership by route and by day', 'Demand hot-spots for planning', 'Partner approvals with a full audit trail', 'A digital system to run the idle terminals'].map((l, i) => (
            <Rise key={l} delay={40 + i * 14} distance={30}>
              <div style={{ display: 'flex', gap: 14, padding: '8px 0', fontFamily: family, fontSize: 30, color: '#fff', fontWeight: 600 }}>
                <span style={{ color: colors.leaf }}>✓</span>
                {l}
              </div>
            </Rise>
          ))}
        </div>
        <div style={{ flex: 1.2 }}>
          <Rise delay={8}>
            <Browser src="d_fcta" width={1080} />
          </Rise>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

function Model() {
  const streams = [
    ['Per-ride fee', 'Operators · taken automatically in the payment split'],
    ['Fleet-owner plan', 'Monthly per vehicle · earnings, alerts, driver scorecards'],
    ['Operator software', 'Advanced scheduling, analytics, multiple depots'],
    ['Travel cards', 'One-off card fee'],
    ['Planning data', 'Anonymised ridership reports for the FCTA'],
    ['Employer plans', 'Tag Along circles for office clusters'],
  ];
  return (
    <AbsoluteFill>
      <NetworkBg light seed={0.45} />
      <AbsoluteFill style={{ padding: '100px 130px' }}>
        <Eyebrow delay={4} color={colors.forest} size={28}>Business model</Eyebrow>
        <div style={{ height: 14 }} />
        <Kinetic text="A small fee on every ride. Riders pay the fare, nothing more." size={70} delay={8} highlight={['nothing', 'more.']} />
        <div style={{ height: 50 }} />
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 28 }}>
          {streams.map(([h, b], i) => (
            <Rise key={h} delay={50 + i * 12} distance={40}>
              <div style={{ background: '#fff', border: `1px solid ${colors.mintStrong}`, borderRadius: 28, padding: '30px 32px', boxShadow: '0 18px 44px rgba(6,51,31,0.08)', fontFamily: family, minHeight: 170 }}>
                <div style={{ fontWeight: 800, fontSize: 36, color: colors.forest }}>{h}</div>
                <div style={{ fontWeight: 500, fontSize: 25, color: colors.inkSoft, marginTop: 8, lineHeight: 1.35 }}>{b}</div>
              </div>
            </Rise>
          ))}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

function Roadmap() {
  const frame = useCurrentFrame();
  const stages = [
    ['Now', 'Live platform', 'Rider app, partner portal, FCTA dashboards and AI, on the web and Android.'],
    ['Pilot', 'One real corridor', 'Air Shuttle NG · civil-servant electric buses · a minibus fleet on Lugbe or Kubwa · one office cluster for Tag Along.'],
    ['Scale', 'Validators on buses', 'Tap-card validators, more operators, a licensed wallet partner.'],
    ['Next cities', 'Jos · Kaduna · Enugu', 'Every state running CNG and electric buses needs ticketing and revenue tracking.'],
  ];
  const line = interpolate(frame, [30, 200], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  return (
    <AbsoluteFill>
      <NetworkBg seed={0.7} />
      <AbsoluteFill style={{ padding: '100px 130px' }}>
        <Eyebrow delay={4} size={28}>Roadmap</Eyebrow>
        <div style={{ height: 14 }} />
        <Kinetic text="Abuja first. Then every city with buses to run." size={70} color="#fff" delay={8} />
        <div style={{ position: 'relative', marginTop: 90 }}>
          <div style={{ position: 'absolute', top: 30, left: 30, right: 30, height: 6, background: 'rgba(255,255,255,0.12)', borderRadius: 9 }} />
          <div style={{ position: 'absolute', top: 30, left: 30, width: `calc((100% - 60px) * ${line})`, height: 6, background: colors.leaf, borderRadius: 9 }} />
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 30 }}>
            {stages.map(([when, h, b], i) => (
              <Rise key={when} delay={40 + i * 40} distance={40}>
                <div style={{ fontFamily: family }}>
                  <div style={{ width: 66, height: 66, borderRadius: 99, background: i === 0 ? colors.leaf : colors.forestMid, border: `4px solid ${colors.leaf}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontWeight: 800, fontSize: 26 }}>{i + 1}</div>
                  <div style={{ color: colors.leaf, fontWeight: 800, fontSize: 24, letterSpacing: '0.12em', textTransform: 'uppercase', marginTop: 26 }}>{when}</div>
                  <div style={{ color: '#fff', fontWeight: 800, fontSize: 36, marginTop: 6 }}>{h}</div>
                  <div style={{ color: colors.onForestMuted, fontWeight: 500, fontSize: 24, marginTop: 10, lineHeight: 1.4 }}>{b}</div>
                </div>
              </Rise>
            ))}
          </div>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

function Close() {
  return (
    <AbsoluteFill>
      <NetworkBg seed={0.95} />
      <AbsoluteFill style={{ flexDirection: 'row', alignItems: 'center', padding: '0 130px', gap: 40 }}>
        <div style={{ width: 620, height: 560 }}>
          <Tapi width={620} height={560} mood="celebrate" moodFrom={20} look={[0.5, 0]} />
        </div>
        <div style={{ flex: 1 }}>
          <Logo white height={100} delay={6} />
          <div style={{ height: 30 }} />
          <Kinetic text="Know your fare. Know your ride. Just tap." size={76} color="#fff" delay={16} highlight={['tap.']} />
          <div style={{ height: 40 }} />
          <Body delay={60} size={30} color={colors.onForestMuted}>Partner with us: pilot routes · EV fleets · technology · investment</Body>
          <div style={{ height: 30 }} />
          <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap' }}>
            <Pill delay={80} bg={colors.leaf} color={colors.forestDeep} size={34}>Live demo · taparide.vercel.app</Pill>
          </div>
          <div style={{ height: 30 }} />
          <Body delay={96} size={22} color="rgba(255,255,255,0.55)">Young Innovators Smart Mobility Team · Abuja</Body>
        </div>
      </AbsoluteFill>
      <div style={{ position: 'absolute', right: 40, bottom: 26, fontFamily: family, fontSize: 15, color: 'rgba(255,255,255,0.4)' }}>Photos: Wikimedia Commons contributors (CC BY-SA). Map data © OpenStreetMap contributors.</div>
    </AbsoluteFill>
  );
}

export function Pitch() {
  const { durationInFrames } = useVideoConfig();
  const s = PITCH_SCENES;
  const tr = {
    fade: () => ({ presentation: fade(), timing: linearTiming({ durationInFrames: T }) }),
    slide: () => ({ presentation: slide({ direction: 'from-right' }), timing: springTiming({ config: { damping: 200 }, durationInFrames: T }) }),
    wipe: () => ({ presentation: wipe({ direction: 'from-left' }), timing: linearTiming({ durationInFrames: T }) }),
  };
  const scenes = [
    [s.title, <Title />, 'fade'],
    [s.scale, <Scale />, 'wipe'],
    [s.pains, <Pains />, 'wipe'],
    [s.gap, <Gap />, 'fade'],
    [s.hub, <Hub />, 'fade'],
    [s.rider, <Rider />, 'slide'],
    [s.join, <Join />, 'wipe'],
    [s.review, <Review />, 'wipe'],
    [s.dashboards, <Dashboards />, 'wipe'],
    [s.ai, <Ai />, 'wipe'],
    [s.fcta, <Fcta />, 'wipe'],
    [s.model, <Model />, 'slide'],
    [s.roadmap, <Roadmap />, 'fade'],
    [s.close, <Close />, null],
  ];
  return (
    <AbsoluteFill style={{ background: colors.forestDeep }}>
      <TransitionSeries>
        {scenes.flatMap(([d, el, t], i) => {
          const out = [<TransitionSeries.Sequence key={`s${i}`} durationInFrames={d}>{el}</TransitionSeries.Sequence>];
          if (t) out.push(<TransitionSeries.Transition key={`t${i}`} {...tr[t]()} />);
          return out;
        })}
      </TransitionSeries>
      <Audio
        src={staticFile('music/pitch.wav')}
        volume={(f) => interpolate(f, [0, 30, durationInFrames - 60, durationInFrames], [0, 0.7, 0.7, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })}
      />
    </AbsoluteFill>
  );
}
