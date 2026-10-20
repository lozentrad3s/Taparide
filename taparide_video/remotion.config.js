import { Config } from '@remotion/cli/config';

Config.setEntryPoint('src/index.js');
Config.setVideoImageFormat('jpeg');
Config.setJpegQuality(92);
// WebGL (Tapi) renders through ANGLE in headless Chrome.
Config.setChromiumOpenGlRenderer('angle');
Config.setConcurrency(4);
