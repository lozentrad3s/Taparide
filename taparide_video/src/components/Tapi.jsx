// Tapi, the Tap A Ride mascot, ported from the app's three.js mascot (web/mascot/mascot.js)
// to a frame-driven React Three Fiber scene, so every frame renders deterministically.
import { ThreeCanvas } from '@remotion/three';
import { useMemo } from 'react';
import { useCurrentFrame, useVideoConfig } from 'remotion';
import * as THREE from 'three';

const C = {
  leaf: '#4db52a',
  forest: '#0b5a3a',
  ink: '#111814',
  white: '#ffffff',
  glass: '#d9efe1',
  tyre: '#1b2420',
  blush: '#ff9aa2',
};
const CONFETTI = ['#4db52a', '#0b5a3a', '#ffffff', '#f5c542', '#ff9aa2'];

// Small deterministic random so confetti looks the same on every render.
const rand = (i, salt) => {
  const x = Math.sin(i * 127.1 + salt * 311.7) * 43758.5453;
  return x - Math.floor(x);
};

function Body({ wheelSpin }) {
  return (
    <group>
      <mesh position={[0, 0.42, 0]} rotation={[0, 0, Math.PI / 2]} scale={[1, 1, 1.15]}>
        <capsuleGeometry args={[0.42, 1.25, 8, 24]} />
        <meshStandardMaterial color={C.forest} roughness={0.45} />
      </mesh>
      <mesh position={[0.05, 0.72, 0]} scale={[1.25, 0.62, 0.95]}>
        <sphereGeometry args={[0.5, 32, 24]} />
        <meshStandardMaterial color={C.glass} roughness={0.1} metalness={0.1} />
      </mesh>
      <mesh position={[-0.55, 0.42, 0]} rotation={[0, Math.PI / 2, 0]}>
        <torusGeometry args={[0.43, 0.035, 8, 48, Math.PI]} />
        <meshStandardMaterial color={C.leaf} roughness={0.35} />
      </mesh>
      {[[-0.62, 0.42], [0.62, 0.42], [-0.62, -0.42], [0.62, -0.42]].map(([x, z], i) => (
        <mesh key={i} position={[x, 0.17, z]} rotation={[0, 0, wheelSpin]}>
          <torusGeometry args={[0.17, 0.09, 12, 24]} />
          <meshStandardMaterial color={C.tyre} roughness={0.8} />
        </mesh>
      ))}
      {[0.98, -0.98].map((x) => (
        <mesh key={x} position={[x, 0.48, 0.2]}>
          <sphereGeometry args={[0.075, 16, 12]} />
          <meshStandardMaterial color={x > 0 ? C.white : C.leaf} />
        </mesh>
      ))}
    </group>
  );
}

function Head({ look, blink, sleepy, smileScale, tilt }) {
  return (
    <group position={[0.05, 1.45, 0]} rotation={[-look[1] * 0.15, look[0] * 0.35, tilt]}>
      <mesh>
        <sphereGeometry args={[0.62, 48, 32]} />
        <meshStandardMaterial color={C.leaf} roughness={0.35} metalness={0.05} />
      </mesh>
      <mesh position={[0, -0.62, 0]} rotation={[Math.PI, 0, 0]}>
        <coneGeometry args={[0.42, 0.62, 32]} />
        <meshStandardMaterial color={C.leaf} roughness={0.35} metalness={0.05} />
      </mesh>
      <mesh position={[0, 0.03, 0.6]}>
        <circleGeometry args={[0.4, 40]} />
        <meshStandardMaterial color={C.white} roughness={0.25} />
      </mesh>
      {[-0.14, 0.14].map((x) => (
        <group key={x} position={[x, 0.08, 0.62]} scale={[1, sleepy ? 0.12 : blink ? 0.15 : 1, 1]}>
          <mesh position={[look[0] * 0.05, look[1] * 0.04, 0]} scale={[1, 1, 0.5]}>
            <sphereGeometry args={[0.075, 20, 16]} />
            <meshStandardMaterial color={C.ink} roughness={0.3} />
          </mesh>
          <mesh position={[0.025 + look[0] * 0.05, 0.03 + look[1] * 0.04, 0.035]}>
            <sphereGeometry args={[0.022, 10, 8]} />
            <meshStandardMaterial color={C.white} />
          </mesh>
        </group>
      ))}
      <mesh position={[0, -0.1, 0.62]} rotation={[0, 0, Math.PI]} scale={[1, smileScale, 1]}>
        <torusGeometry args={[0.11, 0.022, 8, 24, Math.PI]} />
        <meshStandardMaterial color={C.ink} />
      </mesh>
      {[-0.27, 0.27].map((x) => (
        <mesh key={x} position={[x, -0.05, 0.615]}>
          <circleGeometry args={[0.06, 20]} />
          <meshStandardMaterial color={C.blush} transparent opacity={0.55} />
        </mesh>
      ))}
    </group>
  );
}

/**
 * @param mood idle | wave | think | celebrate | sleep
 * @param moodFrom frame (relative to the sequence) where the current mood started
 * @param look [x, y] in -1..1, where Tapi looks
 * @param drive 0..1 slide-in progress (Tapi drives in from the left), 1 = parked
 */
export function Tapi({ width, height, mood = 'idle', moodFrom = 0, look = [0, 0], drive = 1, background = null }) {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;
  const since = Math.max(0, (frame - moodFrom) / fps);

  const blink = (t % 3.4) > 3.28;
  const sleepy = mood === 'sleep';
  let y = Math.sin(t * 2) * 0.04;
  let armAngle = -0.4;
  let spin = 0;
  let tilt = 0;
  if (mood === 'wave') {
    armAngle = -2.3 + Math.sin(t * 9) * 0.45;
    tilt = Math.sin(t * 4.5) * 0.08;
  } else if (mood === 'think') {
    tilt = 0.18;
    armAngle = -2.6;
  } else if (mood === 'celebrate') {
    const hop = Math.max(0, Math.sin((Math.min(since, 1.2) * Math.PI) / 0.6));
    y += hop * 0.55;
    spin = since < 1.2 ? (since / 1.2) * Math.PI * 2 : 0;
    armAngle = -2.8;
  }
  if (sleepy) y = Math.sin(t * 1.2) * 0.02;
  const driveX = (1 - drive) * -6;
  const wheelSpin = -t * (mood === 'celebrate' ? 8 : 0.6) - (1 - drive) * 25;
  const smileScale = mood === 'celebrate' || mood === 'wave' ? 1.35 : sleepy ? 0.4 : 1;

  const confetti = useMemo(
    () =>
      Array.from({ length: 46 }, (_, i) => ({
        v: [(rand(i, 1) - 0.5) * 3.2, 2 + rand(i, 2) * 2.6, (rand(i, 3) - 0.5) * 1.5],
        spin: rand(i, 4) * 10,
        color: CONFETTI[i % CONFETTI.length],
      })),
    [],
  );
  const showConfetti = mood === 'celebrate' && since < 1.9;

  return (
    <ThreeCanvas width={Math.round(width)} height={Math.round(height)} gl={{ antialias: true, alpha: true }} camera={{ fov: 32, position: [0, 1.15, 6.2] }} onCreated={({ camera, gl }) => {
      camera.lookAt(0, 0.95, 0);
      gl.outputColorSpace = THREE.SRGBColorSpace;
      gl.toneMapping = THREE.ACESFilmicToneMapping;
      gl.toneMappingExposure = 1.05;
    }}>
      {background ? <color attach="background" args={[background]} /> : null}
      <hemisphereLight args={['#ffffff', '#cfe6d6', 1.6]} />
      <directionalLight position={[2.5, 4, 3.5]} intensity={2.2} />
      <directionalLight position={[-3, 2, -2]} intensity={1.2} color="#b8f0a0" />

      <group position={[driveX, y, 0]} rotation={[0, spin + Math.sin(t * 0.5) * 0.12 - 0.25 + (1 - drive) * 0.6, 0]}>
        <Body wheelSpin={wheelSpin} />
        <Head look={look} blink={blink} sleepy={sleepy} smileScale={smileScale} tilt={tilt} />
        <group position={[0.6, 1.25, 0.1]} rotation={[0, 0, armAngle]}>
          <mesh position={[0, 0.22, 0]}>
            <capsuleGeometry args={[0.07, 0.38, 6, 12]} />
            <meshStandardMaterial color={C.leaf} roughness={0.35} />
          </mesh>
          <mesh position={[0, 0.48, 0]}>
            <sphereGeometry args={[0.1, 16, 12]} />
            <meshStandardMaterial color={C.white} roughness={0.25} />
          </mesh>
        </group>
      </group>

      {mood === 'think'
        ? [0, 1, 2].map((i) => (
            <mesh key={i} position={[-0.22 + i * 0.22, 2.35 + Math.max(0, Math.sin(t * 6 - i * 0.7)) * 0.15, 0.2]}>
              <sphereGeometry args={[0.07, 12, 10]} />
              <meshStandardMaterial color={C.forest} />
            </mesh>
          ))
        : null}

      {showConfetti
        ? confetti.map((c, i) => {
            const s = since;
            return (
              <mesh key={i} position={[c.v[0] * s, 2 + c.v[1] * s - 3 * s * s, c.v[2] * s]} rotation={[c.spin * s, c.spin * 0.7 * s, 0]}>
                <planeGeometry args={[0.08, 0.14]} />
                <meshBasicMaterial color={c.color} side={THREE.DoubleSide} />
              </mesh>
            );
          })
        : null}

      <mesh position={[driveX, 0, 0]} rotation={[-Math.PI / 2, 0, 0]} scale={[1.2 - y * 0.4, 0.55 - y * 0.15, 1]}>
        <circleGeometry args={[1.1, 40]} />
        <meshBasicMaterial color="#0b2a1a" transparent opacity={0.12} />
      </mesh>
    </ThreeCanvas>
  );
}
