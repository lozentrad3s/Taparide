import { Composition, continueRender, delayRender } from 'remotion';
import { Ad, AD_DURATION } from './Ad';
import { Pitch, PITCH_DURATION } from './Pitch';
import { fontsReady } from './theme';

const waitForFonts = delayRender('Loading Barlow');
fontsReady.then(() => continueRender(waitForFonts));

export function Root() {
  return (
    <>
      <Composition id="TapARideAd" component={Ad} durationInFrames={AD_DURATION} fps={30} width={1920} height={1080} />
      <Composition id="TapARideAdVertical" component={Ad} durationInFrames={AD_DURATION} fps={30} width={1080} height={1920} />
      <Composition id="TapARidePitch" component={Pitch} durationInFrames={PITCH_DURATION} fps={30} width={1920} height={1080} />
    </>
  );
}
