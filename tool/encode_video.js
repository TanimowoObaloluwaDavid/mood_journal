// Encode the CDP screencast frames into a video and a GIF.
//
// GitHub renders animated GIFs in a README but does not autoplay <video>, so the
// GIF is the one that actually shows up when someone opens the repo. The MP4 is
// kept alongside it for anyone who wants the higher-quality version.
//
// Usage:
//   node tool/encode_video.js [--frames <dir>] [--out docs/demo] [--fps 15]

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : args[i + 1];
};

const FRAMES = opt('frames', path.join(process.env.TEMP || '.', 'mood_journal_frames'));
const OUT = opt('out', 'docs/demo');
const FPS = opt('fps', '15');

if (!fs.existsSync(path.join(FRAMES, 'count.txt'))) {
  console.error(`No frames in ${FRAMES}. Run: node tool/capture_web.js --video`);
  process.exit(1);
}

const COUNT = Number(fs.readFileSync(path.join(FRAMES, 'count.txt'), 'utf8').trim());
console.log(`encoding ${COUNT} frames at ${FPS}fps`);

fs.mkdirSync(path.dirname(OUT), { recursive: true });

function ffmpeg(args) {
  const result = spawnSync('ffmpeg', args, { stdio: 'inherit' });
  if (result.status !== 0) {
    console.error(`ffmpeg failed with status ${result.status}`);
    process.exit(result.status || 1);
  }
}

// libx264 rejects odd dimensions, and the capture is 780x1688 at 2x, so scale
// to even numbers explicitly rather than hoping.
const even = 'scale=trunc(iw/2)*2:trunc(ih/2)*2';

const mp4 = `${OUT}.mp4`;
console.log(`-> ${mp4}`);
ffmpeg([
  '-y', '-framerate', FPS, '-i', `${FRAMES}/f%04d.jpg`,
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '23',
  '-pix_fmt', 'yuv420p', '-vf', even, '-movflags', '+faststart',
  mp4,
]);

// A per-frame palette keeps the flat UI colours from banding, and the width
// cap is what stops the GIF weighing several megabytes.
const gif = `${OUT}.gif`;
console.log(`-> ${gif}`);
const palette = path.join(FRAMES, 'palette.png');
ffmpeg([
  '-y', '-framerate', FPS, '-i', `${FRAMES}/f%04d.jpg`,
  '-vf', `${even},scale=340:-1:flags=lanczos,palettegen=stats_mode=diff`,
  palette,
]);
ffmpeg([
  '-y', '-framerate', FPS, '-i', `${FRAMES}/f%04d.jpg`,
  '-i', palette,
  '-lavfi', `${even},scale=340:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3`,
  '-loop', '0', gif,
]);

for (const file of [mp4, gif]) {
  if (fs.existsSync(file)) {
    console.log(`${file}  ${(fs.statSync(file).size / 1024 / 1024).toFixed(2)} MB`);
  }
}
