import { AbsoluteFill, interpolate, useCurrentFrame } from 'remotion';
import { useEnter, useOrientation } from './ui';

/** Text block + device, side by side (landscape) or stacked (portrait). */
export function Split({ text, device, deviceSide = 'right', textFlex = 1.05 }) {
  const { portrait, u } = useOrientation();
  if (portrait) {
    return (
      <AbsoluteFill style={{ padding: `${150 * u}px ${70 * u}px 0`, alignItems: 'center' }}>
        <div style={{ width: '100%', marginBottom: 40 * u }}>{text}</div>
        <div style={{ flex: 1, display: 'flex', alignItems: 'flex-start', justifyContent: 'center' }}>{device}</div>
      </AbsoluteFill>
    );
  }
  return (
    <AbsoluteFill style={{ flexDirection: deviceSide === 'right' ? 'row' : 'row-reverse', alignItems: 'center', padding: `0 ${130 * u}px`, gap: 90 * u }}>
      <div style={{ flex: textFlex }}>{text}</div>
      <div style={{ flex: 1, display: 'flex', justifyContent: 'center' }}>{device}</div>
    </AbsoluteFill>
  );
}

/** Enters from below with a critically damped spring. */
export function Rise({ children, delay = 0, distance = 140 }) {
  const p = useEnter(delay);
  return <div style={{ transform: `translateY(${(1 - p) * distance}px)`, opacity: p }}>{children}</div>;
}

/** Cross-dissolve between two children at frame `at`. */
export function Crossfade({ a, b, at, len = 14 }) {
  const frame = useCurrentFrame();
  const o = interpolate(frame, [at, at + len], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  return (
    <div style={{ position: 'relative' }}>
      <div style={{ opacity: 1 - o }}>{a}</div>
      <div style={{ position: 'absolute', inset: 0, opacity: o }}>{b}</div>
    </div>
  );
}

/** Shows one of several children by frame windows, cross-dissolving between them. */
export function Sequenced({ items, len = 12 }) {
  const frame = useCurrentFrame();
  return (
    <div style={{ position: 'relative' }}>
      {items.map(({ from, el }, i) => {
        const next = items[i + 1]?.from ?? Infinity;
        const inO = i === 0 ? 1 : interpolate(frame, [from, from + len], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
        const outO = next === Infinity ? 1 : interpolate(frame, [next, next + len], [1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
        const o = Math.min(inO, outO);
        if (o <= 0 && i !== 0) return null; // the first item stays mounted to hold the layout
        return (
          <div key={i} style={{ position: i === 0 ? 'relative' : 'absolute', inset: 0, opacity: o }}>
            {el}
          </div>
        );
      })}
    </div>
  );
}
