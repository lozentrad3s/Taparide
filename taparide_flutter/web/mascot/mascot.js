// Tapi — the Tap A Ride mascot. A green map-pin head (from the logo) on a little car body.
// Moods: idle, wave, think, celebrate, sleep. Set with ?mood=… or postMessage({type:'tapi', mood}).
import * as THREE from 'three';

const params = new URLSearchParams(location.search);
let mood = params.get('mood') || 'idle';
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

// ---------------------------------------------------------------- scene
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, powerPreference: 'low-power' });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(32, 1, 0.1, 50);
camera.position.set(0, 1.15, 6.2);
camera.lookAt(0, 0.95, 0);

scene.add(new THREE.HemisphereLight(0xffffff, 0xcfe6d6, 1.6));
const key = new THREE.DirectionalLight(0xffffff, 2.2);
key.position.set(2.5, 4, 3.5);
scene.add(key);
const rim = new THREE.DirectionalLight(0xb8f0a0, 1.2);
rim.position.set(-3, 2, -2);
scene.add(rim);

// ---------------------------------------------------------------- materials (brand colours)
const leaf = new THREE.MeshStandardMaterial({ color: 0x4db52a, roughness: 0.35, metalness: 0.05 });
const forest = new THREE.MeshStandardMaterial({ color: 0x0b5a3a, roughness: 0.45 });
const ink = new THREE.MeshStandardMaterial({ color: 0x111814, roughness: 0.3 });
const white = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.25 });
const glass = new THREE.MeshStandardMaterial({ color: 0xd9efe1, roughness: 0.1, metalness: 0.1 });
const tyre = new THREE.MeshStandardMaterial({ color: 0x1b2420, roughness: 0.8 });
const blush = new THREE.MeshStandardMaterial({ color: 0xff9aa2, roughness: 0.6, transparent: true, opacity: 0.55 });

const tapi = new THREE.Group();
scene.add(tapi);

// Car body
const body = new THREE.Group();
tapi.add(body);
const chassis = new THREE.Mesh(new THREE.CapsuleGeometry(0.42, 1.25, 8, 24), forest);
chassis.rotation.z = Math.PI / 2;
chassis.scale.set(1, 1, 1.15);
chassis.position.y = 0.42;
body.add(chassis);
const cabin = new THREE.Mesh(new THREE.SphereGeometry(0.5, 32, 24), glass);
cabin.scale.set(1.25, 0.62, 0.95);
cabin.position.set(0.05, 0.72, 0);
body.add(cabin);
const stripe = new THREE.Mesh(new THREE.TorusGeometry(0.43, 0.035, 8, 48, Math.PI), leaf);
stripe.rotation.y = Math.PI / 2;
stripe.position.set(-0.55, 0.42, 0);
body.add(stripe);
const wheels = [];
for (const [x, z] of [[-0.62, 0.42], [0.62, 0.42], [-0.62, -0.42], [0.62, -0.42]]) {
  const w = new THREE.Mesh(new THREE.TorusGeometry(0.17, 0.09, 12, 24), tyre);
  w.position.set(x, 0.17, z);
  body.add(w);
  wheels.push(w);
}
for (const x of [0.98, -0.98]) {
  const lamp = new THREE.Mesh(new THREE.SphereGeometry(0.075, 16, 12), x > 0 ? white : leaf);
  lamp.position.set(x, 0.48, 0.2);
  body.add(lamp);
}

// Pin head (the logo pin): sphere + tapering tip, hollow ring face
const head = new THREE.Group();
head.position.set(0.05, 1.45, 0);
tapi.add(head);
const pinBall = new THREE.Mesh(new THREE.SphereGeometry(0.62, 48, 32), leaf);
head.add(pinBall);
const pinTip = new THREE.Mesh(new THREE.ConeGeometry(0.42, 0.62, 32), leaf);
pinTip.rotation.x = Math.PI;
pinTip.position.y = -0.62;
head.add(pinTip);
const face = new THREE.Mesh(new THREE.CircleGeometry(0.4, 40), white);
face.position.set(0, 0.03, 0.6);
head.add(face);

const eyes = [];
for (const x of [-0.14, 0.14]) {
  const eye = new THREE.Group();
  eye.position.set(x, 0.08, 0.62);
  const pupil = new THREE.Mesh(new THREE.SphereGeometry(0.075, 20, 16), ink);
  pupil.scale.z = 0.5;
  const glint = new THREE.Mesh(new THREE.SphereGeometry(0.022, 10, 8), white);
  glint.position.set(0.025, 0.03, 0.035);
  eye.add(pupil, glint);
  head.add(eye);
  eyes.push(eye);
}
const smile = new THREE.Mesh(new THREE.TorusGeometry(0.11, 0.022, 8, 24, Math.PI), ink);
smile.rotation.z = Math.PI;
smile.position.set(0, -0.1, 0.62);
head.add(smile);
for (const x of [-0.27, 0.27]) {
  const cheek = new THREE.Mesh(new THREE.CircleGeometry(0.06, 20), blush);
  cheek.position.set(x, -0.05, 0.615);
  head.add(cheek);
}

// Arm for waving
const arm = new THREE.Group();
arm.position.set(0.6, 1.25, 0.1);
const armMesh = new THREE.Mesh(new THREE.CapsuleGeometry(0.07, 0.38, 6, 12), leaf);
armMesh.position.y = 0.22;
arm.add(armMesh);
const hand = new THREE.Mesh(new THREE.SphereGeometry(0.1, 16, 12), white);
hand.position.y = 0.48;
arm.add(hand);
tapi.add(arm);

// Thinking dots
const dots = new THREE.Group();
for (let i = 0; i < 3; i++) {
  const d = new THREE.Mesh(new THREE.SphereGeometry(0.07, 12, 10), forest);
  d.position.set(-0.22 + i * 0.22, 2.35, 0.2);
  dots.add(d);
}
scene.add(dots);

// Sleep "z"s
const zs = new THREE.Group();
scene.add(zs);

// Confetti
const confetti = [];
const confettiColours = [0x4db52a, 0x0b5a3a, 0xffffff, 0xf5c542, 0xff9aa2];
function burst() {
  for (let i = 0; i < 40; i++) {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(0.08, 0.14), new THREE.MeshBasicMaterial({ color: confettiColours[i % 5], side: THREE.DoubleSide }));
    m.position.set(0, 2, 0);
    m.userData = { v: new THREE.Vector3((Math.random() - 0.5) * 3, 2 + Math.random() * 2.5, (Math.random() - 0.5) * 1.5), spin: Math.random() * 10, life: 1.8 };
    scene.add(m);
    confetti.push(m);
  }
}

// Ground shadow
const shadow = new THREE.Mesh(new THREE.CircleGeometry(1.1, 40), new THREE.MeshBasicMaterial({ color: 0x0b2a1a, transparent: true, opacity: 0.12 }));
shadow.rotation.x = -Math.PI / 2;
shadow.scale.set(1.2, 0.55, 1);
scene.add(shadow);

// ---------------------------------------------------------------- interaction
const pointer = new THREE.Vector2(0, 0);
const look = new THREE.Vector2(0, 0);
addEventListener('pointermove', (e) => {
  pointer.set((e.clientX / innerWidth) * 2 - 1, -((e.clientY / innerHeight) * 2 - 1));
});
// Parent page can forward its pointer so Tapi watches the user across the whole app.
addEventListener('message', (e) => {
  const data = e.data || {};
  if (data.type !== 'tapi') return;
  if (data.pointer) pointer.set(data.pointer[0], data.pointer[1]);
  if (data.mood && data.mood !== mood) setMood(data.mood);
});
renderer.domElement.addEventListener('pointerdown', () => {
  setMood('celebrate');
  setTimeout(() => setMood(params.get('mood') || 'idle'), 1600);
  // Let the host app react (e.g. open the assistant).
  parent?.postMessage({ type: 'tapi-tap' }, location.origin);
});

let moodStart = performance.now();
function setMood(next) {
  mood = next;
  moodStart = performance.now();
  if (next === 'celebrate') burst();
}
setMood(mood);

// ---------------------------------------------------------------- sizing + visibility
function resize() {
  const w = innerWidth, h = innerHeight;
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}
addEventListener('resize', resize);
resize();

let visible = true;
document.addEventListener('visibilitychange', () => { visible = !document.hidden; });

// ---------------------------------------------------------------- animation
const clock = new THREE.Clock();
let nextBlink = 2;
const damp = (current, target, lambda, dt) => current + (target - current) * (1 - Math.exp(-lambda * dt));

function frame() {
  requestAnimationFrame(frame);
  if (!visible) return;
  const dt = Math.min(clock.getDelta(), 0.05);
  const t = clock.elapsedTime;
  const sinceMood = (performance.now() - moodStart) / 1000;
  const motion = reduceMotion ? 0 : 1;

  // Eyes follow the pointer (critically damped, no overshoot)
  look.x = damp(look.x, pointer.x, 6, dt);
  look.y = damp(look.y, pointer.y, 6, dt);
  for (const eye of eyes) {
    eye.children[0].position.set(look.x * 0.05, look.y * 0.04, 0);
    eye.children[1].position.set(0.025 + look.x * 0.05, 0.03 + look.y * 0.04, 0.035);
  }
  head.rotation.y = damp(head.rotation.y, look.x * 0.35, 4, dt);
  head.rotation.x = damp(head.rotation.x, -look.y * 0.15, 4, dt);

  // Blink
  nextBlink -= dt;
  const blinking = nextBlink < 0.12 && nextBlink > 0;
  const sleepy = mood === 'sleep';
  for (const eye of eyes) eye.scale.y = sleepy ? 0.12 : blinking ? 0.15 : 1;
  if (nextBlink <= 0) nextBlink = 2.5 + Math.random() * 3;

  // Base bob
  let y = Math.sin(t * 2) * 0.04 * motion;
  let armAngle = -0.4;
  let spin = 0;

  if (mood === 'wave') {
    armAngle = -2.3 + Math.sin(t * 9) * 0.45 * motion;
    head.rotation.z = Math.sin(t * 4.5) * 0.08 * motion;
  } else if (mood === 'think') {
    head.rotation.z = damp(head.rotation.z, 0.18, 5, dt);
    armAngle = -2.6;
    eyes.forEach((e) => (e.children[0].position.y = 0.04));
  } else if (mood === 'celebrate') {
    const hop = Math.max(0, Math.sin(Math.min(sinceMood, 1.2) * Math.PI / 0.6));
    y += hop * 0.55 * motion;
    spin = sinceMood < 1.2 ? sinceMood / 1.2 * Math.PI * 2 * motion : 0;
    armAngle = -2.8;
  } else {
    head.rotation.z = damp(head.rotation.z, 0, 5, dt);
  }
  if (sleepy) y = Math.sin(t * 1.2) * 0.02 * motion;

  tapi.position.y = y;
  tapi.rotation.y = spin + Math.sin(t * 0.5) * 0.12 * motion - 0.25;
  arm.rotation.z = damp(arm.rotation.z, armAngle, 10, dt);
  wheels.forEach((w) => (w.rotation.z -= dt * (mood === 'celebrate' ? 8 : 0.6) * motion));
  smile.scale.y = mood === 'celebrate' || mood === 'wave' ? 1.35 : sleepy ? 0.4 : 1;
  shadow.scale.set(1.2 - y * 0.4, 0.55 - y * 0.15, 1);

  // Thinking dots
  dots.visible = mood === 'think';
  dots.children.forEach((d, i) => (d.position.y = 2.35 + Math.max(0, Math.sin(t * 6 - i * 0.7)) * 0.15 * motion));

  // Sleep z's
  zs.visible = sleepy;
  if (sleepy && zs.children.length < 3 && Math.random() < dt * 0.8) {
    const z = new THREE.Mesh(new THREE.TorusGeometry(0.06, 0.018, 6, 16), forest);
    z.position.set(0.5, 2.1, 0.2);
    z.userData.life = 2.5;
    zs.add(z);
  }
  for (const z of [...zs.children]) {
    z.userData.life -= dt;
    z.position.y += dt * 0.35;
    z.position.x += dt * 0.12;
    z.material.opacity = Math.max(0, z.userData.life / 2.5);
    if (z.userData.life <= 0) zs.remove(z);
  }

  // Confetti physics
  for (let i = confetti.length - 1; i >= 0; i--) {
    const c = confetti[i];
    c.userData.v.y -= 6 * dt;
    c.position.addScaledVector(c.userData.v, dt);
    c.rotation.x += c.userData.spin * dt;
    c.rotation.y += c.userData.spin * 0.7 * dt;
    c.userData.life -= dt;
    if (c.userData.life <= 0) {
      scene.remove(c);
      c.geometry.dispose();
      confetti.splice(i, 1);
    }
  }

  renderer.render(scene, camera);
}
frame();

// Tell the host page we're ready (so it can send the current mood).
parent?.postMessage({ type: 'tapi-ready' }, '*');
