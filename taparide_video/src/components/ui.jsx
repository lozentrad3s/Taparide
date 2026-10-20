import { AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig, Easing } from 'remotion';
import { colors, family } from '../theme';

export const useOrientation = () => {
  const { width, height } = useVideoConfig();
  return { portrait: height > width, width, height, u: Math.min(width, height) / 1080 };
};

/** Critically damped entrance (no overshoot): Apple-style default. */
export const useEnter = (delay = 0, { damping = 200, durationInFrames } = {}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: frame - delay, fps, config: { damping }, durationInFrames });
};

/** Exit progress 0→1 over the last `len` frames of a sequence of `total` frames. */
export const useExit = (total, len = 12) => {
  const frame = useCurrentFrame();
  return interpolate(frame, [total - len, total], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.in(Easing.cubic) });
};

/** Words rise into place one after another. */
export function Kinetic({ text, size = 96, weight = 800, color = colors.ink, delay = 0, stagger = 3, align = 'left', lineHeight = 1.02, style, highlight = [] }) {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const words = text.split(' ');
  return (
    <div style={{ fontFamily: family, fontSize: size, fontWeight: weight, color, lineHeight, letterSpacing: size > 60 ? '-0.025em' : '-0.01em', textAlign: align, ...style }}>
      {words.map((w, i) => {
        const p = spring({ frame: frame - delay - i * stagger, fps, config: { damping: 200 } });
        const hot = highlight.includes(w.replace(/[.,!?]/g, ''));
        return (
          <span key={i} style={{ display: 'inline-block', whiteSpace: 'pre', overflow: 'hidden', verticalAlign: 'top', paddingBottom: '0.08em' }}>
            <span style={{ display: 'inline-block', transform: `translateY(${(1 - p) * 105}%)`, opacity: p, color: hot ? colors.leaf : undefined }}>
              {w}
              {i < words.length - 1 ? ' ' : ''}
            </span>
          </span>
        );
      })}
    </div>
  );
}

export function Eyebrow({ children, delay = 0, color = colors.leaf, size = 26 }) {
  const p = useEnter(delay);
  return (
    <div style={{ fontFamily: family, fontWeight: 800, fontSize: size, letterSpacing: '0.14em', textTransform: 'uppercase', color, opacity: p, transform: `translateY(${(1 - p) * 16}px)` }}>
      {children}
    </div>
  );
}

export function Body({ children, delay = 0, color = colors.inkSoft, size = 34, style }) {
  const p = useEnter(delay);
  return (
    <div style={{ fontFamily: family, fontWeight: 500, fontSize: size, lineHeight: 1.35, color, opacity: p, transform: `translateY(${(1 - p) * 18}px)`, ...style }}>
      {children}
    </div>
  );
}

/** Small source citation, bottom-left. */
export function Source({ children, light = false }) {
  const p = useEnter(10);
  const { u } = useOrientation();
  return (
    <div style={{ position: 'absolute', left: 60 * u, bottom: 40 * u, fontFamily: family, fontSize: 20 * u, fontWeight: 500, color: light ? 'rgba(255,255,255,0.6)' : colors.muted, opacity: p }}>
      Source: {children}
    </div>
  );
}

export function Pill({ children, delay = 0, bg = colors.mint, color = colors.forest, size = 26, icon }) {
  const p = useEnter(delay, { damping: 14 });
  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: 10, padding: '10px 22px', borderRadius: 999, background: bg, color, fontFamily: family, fontWeight: 700, fontSize: size, transform: `scale(${0.6 + 0.4 * p})`, opacity: Math.min(1, p * 1.5) }}>
      {icon ? <span>{icon}</span> : null}
      {children}
    </div>
  );
}

function StatusBar({ h }) {
  return (
    <div style={{ height: h, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: `0 ${h * 0.75}px`, fontFamily: family, fontWeight: 700, fontSize: h * 0.42, color: colors.ink, background: colors.ground }}>
      <span>9:41</span>
      <span style={{ display: 'flex', alignItems: 'flex-end', gap: h * 0.08 }}>
        {[0.3, 0.45, 0.6, 0.75].map((s) => (
          <span key={s} style={{ width: h * 0.08, height: h * s * 0.5, background: colors.ink, borderRadius: 2 }} />
        ))}
        <span style={{ width: h * 0.55, height: h * 0.27, marginLeft: h * 0.15, border: `${Math.max(1, h * 0.04)}px solid ${colors.ink}`, borderRadius: h * 0.08, padding: 1, display: 'inline-flex' }}>
          <span style={{ width: '78%', background: colors.ink, borderRadius: h * 0.04 }} />
        </span>
      </span>
    </div>
  );
}

/**
 * Phone showing real app screenshots. Give `src` for one screen, or `sequence`
 * ([{ src, at, extra }]) to push from screen to screen like iOS navigation.
 * `zoom`/`focus` push into a region of the current screen.
 */
export function Phone({ src, sequence, height = 860, zoom = 1, focus = [0.5, 0.5], style, shadow = true, children }) {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const w = height * (390 / 844);
  const bezel = height * 0.018;
  const status = height * 0.05;
  const screens = sequence ?? [{ src, at: 0 }];
  const prog = screens.map((s, i) => (i === 0 ? 1 : spring({ frame: frame - s.at, fps, config: { damping: 200 }, durationInFrames: 22 })));
  return (
    <div style={{ position: 'relative', width: w + bezel * 2, height: height + status + bezel * 2, borderRadius: height * 0.075, background: '#0d1411', padding: bezel, boxShadow: shadow ? '0 50px 120px rgba(6,51,31,0.35), 0 12px 30px rgba(0,0,0,0.18)' : 'none', ...style }}>
      <div style={{ position: 'relative', width: w, height: height + status, borderRadius: height * 0.06, overflow: 'hidden', background: colors.ground }}>
        <StatusBar h={status} />
        <div style={{ position: 'relative', width: w, height, overflow: 'hidden', containerType: 'inline-size' }}>
          {screens.map((s, i) => {
            const next = prog[i + 1] ?? 0;
            if (prog[i] <= 0.001 || next >= 0.999) return null;
            const x = (1 - prog[i]) * 100 - next * 28; // incoming from the right, outgoing drifts left
            const current = i === screens.length - 1 || next < 0.5;
            return (
              <div key={i} style={{ position: 'absolute', inset: 0, transform: `translateX(${x}%)`, boxShadow: i > 0 ? '-20px 0 40px rgba(0,0,0,0.12)' : 'none', filter: next > 0 ? `brightness(${1 - next * 0.15})` : 'none' }}>
                <Img src={staticFile(`screens/${s.src}.png`)} style={{ width: '100%', height: '100%', objectFit: 'cover', objectPosition: 'top', transform: current ? `scale(${zoom})` : 'none', transformOrigin: `${focus[0] * 100}% ${focus[1] * 100}%` }} />
                {s.extra}
              </div>
            );
          })}
          {children}
        </div>
      </div>
      <div style={{ position: 'absolute', top: bezel + height * 0.011, left: '50%', width: w * 0.28, height: height * 0.028, marginLeft: -w * 0.14, borderRadius: 99, background: '#0d1411' }} />
    </div>
  );
}

/** Browser window with a real dashboard screenshot. */
export function Browser({ src, width = 1300, zoom = 1, focus = [0.5, 0.5], style, url = 'taparide.vercel.app' }) {
  const h = width * (900 / 1440);
  const bar = width * 0.03;
  return (
    <div style={{ width, borderRadius: width * 0.014, overflow: 'hidden', background: '#fff', boxShadow: '0 50px 120px rgba(6,51,31,0.32), 0 10px 30px rgba(0,0,0,0.16)', ...style }}>
      <div style={{ height: bar, background: '#E9EFEB', display: 'flex', alignItems: 'center', gap: bar * 0.22, padding: `0 ${bar * 0.5}px` }}>
        {['#FF5F57', '#FEBC2E', '#28C840'].map((c) => (
          <div key={c} style={{ width: bar * 0.32, height: bar * 0.32, borderRadius: 99, background: c }} />
        ))}
        <div style={{ marginLeft: bar * 0.6, flex: 1, maxWidth: width * 0.4, height: bar * 0.6, borderRadius: 99, background: '#fff', display: 'flex', alignItems: 'center', paddingLeft: bar * 0.4, fontFamily: family, fontSize: bar * 0.36, color: colors.muted }}>
          🔒 {url}
        </div>
      </div>
      <div style={{ width, height: h, overflow: 'hidden' }}>
        <Img src={staticFile(`screens/${src}.png`)} style={{ width: '100%', height: '100%', objectFit: 'cover', transform: `scale(${zoom})`, transformOrigin: `${focus[0] * 100}% ${focus[1] * 100}%` }} />
      </div>
    </div>
  );
}

/** A finger-tap ripple at a point (percent of the parent box). */
export function Tap({ at = [0.5, 0.5], start = 0, color = colors.leaf }) {
  const frame = useCurrentFrame();
  const f = frame - start;
  if (f < 0 || f > 24) return null;
  const p = f / 24;
  return (
    <div style={{ position: 'absolute', left: `${at[0] * 100}%`, top: `${at[1] * 100}%`, width: 0, height: 0 }}>
      <div style={{ position: 'absolute', width: 120, height: 120, left: -60, top: -60, borderRadius: 999, border: `6px solid ${color}`, transform: `scale(${0.2 + p * 0.9})`, opacity: 1 - p }} />
      <div style={{ position: 'absolute', width: 44, height: 44, left: -22, top: -22, borderRadius: 999, background: color, opacity: (1 - p) * 0.7 }} />
    </div>
  );
}

/** Photo background with a slow push-in (Ken Burns) and a brand-tinted scrim. */
export function PhotoBg({ src, from = 1.08, to = 1.18, scrim = 0.6, duration = 150, focus = [0.5, 0.5] }) {
  const frame = useCurrentFrame();
  const s = interpolate(frame, [0, duration], [from, to], { extrapolateRight: 'clamp' });
  return (
    <AbsoluteFill>
      <Img src={staticFile(`photos/${src}`)} style={{ width: '100%', height: '100%', objectFit: 'cover', transform: `scale(${s})`, transformOrigin: `${focus[0] * 100}% ${focus[1] * 100}%` }} />
      <AbsoluteFill style={{ background: `linear-gradient(180deg, rgba(6,51,31,${scrim * 0.55}) 0%, rgba(6,51,31,${scrim}) 100%)` }} />
    </AbsoluteFill>
  );
}

/** Deep-green background with Abuja-like route lines drawing in and vehicles moving along them. */
export function NetworkBg({ light = false, seed = 0, opacity = 1 }) {
  const frame = useCurrentFrame();
  const { width, height } = useVideoConfig();
  const paths = [
    `M -50 ${height * 0.78} C ${width * 0.2} ${height * 0.7}, ${width * 0.35} ${height * 0.86}, ${width * 0.55} ${height * 0.62} S ${width * 0.85} ${height * 0.35}, ${width + 50} ${height * 0.42}`,
    `M ${width * 0.1} -50 C ${width * 0.18} ${height * 0.3}, ${width * 0.42} ${height * 0.35}, ${width * 0.48} ${height * 0.6} S ${width * 0.62} ${height * 0.95}, ${width * 0.7} ${height + 50}`,
    `M -50 ${height * 0.25} C ${width * 0.3} ${height * 0.32}, ${width * 0.5} ${height * 0.12}, ${width * 0.75} ${height * 0.2} S ${width * 0.95} ${height * 0.5}, ${width + 50} ${height * 0.7}`,
  ];
  const stroke = light ? 'rgba(11,90,58,0.10)' : 'rgba(77,181,42,0.16)';
  const dot = light ? 'rgba(11,90,58,0.45)' : 'rgba(77,181,42,0.9)';
  return (
    <AbsoluteFill style={{ background: light ? colors.ground : `radial-gradient(120% 90% at 20% 10%, ${colors.forestMid} 0%, ${colors.forestDeep} 70%)`, opacity }}>
      <svg width={width} height={height} style={{ position: 'absolute', inset: 0 }}>
        {paths.map((d, i) => {
          const draw = interpolate(frame, [i * 8, i * 8 + 60], [1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.out(Easing.cubic) });
          return <path key={i} d={d} fill="none" stroke={stroke} strokeWidth={Math.min(width, height) * 0.012} strokeLinecap="round" pathLength={1} strokeDasharray={1} strokeDashoffset={draw} />;
        })}
      </svg>
      {paths.map((d, i) =>
        [0, 1, 2].map((k) => {
          const t = (frame / 260 + k / 3 + i * 0.17 + seed) % 1;
          const r = Math.min(width, height) * 0.007;
          return (
            <div
              key={`${i}-${k}`}
              style={{ position: 'absolute', left: 0, top: 0, width: r * 2, height: r * 2, borderRadius: 99, background: dot, offsetPath: `path('${d}')`, offsetDistance: `${t * 100}%`, offsetRotate: '0deg' }}
            />
          );
        }),
      )}
    </AbsoluteFill>
  );
}

export function Logo({ white = false, height = 90, delay = 0 }) {
  const p = useEnter(delay);
  return (
    <Img
      src={staticFile(`brand/${white ? 'taparide_logo_white.png' : 'taparide_logo.png'}`)}
      style={{ height, opacity: p, transform: `translateY(${(1 - p) * 20}px)` }}
    />
  );
}
