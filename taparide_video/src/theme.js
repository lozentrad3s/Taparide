import { loadFont } from '@remotion/fonts';
import { staticFile } from 'remotion';

// Tap A Ride brand (same tokens as the app: lib/app/theme.dart).
export const colors = {
  ink: '#111814',
  inkSoft: '#34423A',
  muted: '#5B6B62',
  ground: '#F2F6F3',
  surface: '#FFFFFF',
  forest: '#0B5A3A',
  forestDeep: '#06331F',
  forestMid: '#0E6B45',
  leaf: '#4DB52A',
  mint: '#E6F2EA',
  mintStrong: '#CDE6D5',
  amber: '#F5C542',
  red: '#E5484D',
  onForestMuted: '#B9D5C5',
};

export const fonts = { display: 'Barlow', body: 'Barlow', naira: 'Fira Sans' };

const faces = [
  ['Barlow', 'Barlow-Regular.ttf', '400'],
  ['Barlow', 'Barlow-Medium.ttf', '500'],
  ['Barlow', 'Barlow-SemiBold.ttf', '600'],
  ['Barlow', 'Barlow-Bold.ttf', '700'],
  ['Barlow', 'Barlow-ExtraBold.ttf', '800'],
  ['Fira Sans', 'FiraSans-Bold.ttf', '700'],
];
export const fontsReady = Promise.all(faces.map(([family, file, weight]) => loadFont({ family, url: staticFile(`fonts/${file}`), weight })));

// Barlow has no ₦ glyph; fall back to Fira Sans for it (as the app does).
export const family = `${fonts.display}, '${fonts.naira}', sans-serif`;
