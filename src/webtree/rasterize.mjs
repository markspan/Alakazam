// Rasterize an SVG icon to a transparent PNG at a fixed pixel width.
//   node rasterize.mjs <in.svg> <out.png> [sizePx=24]
// Keeps the SVG in src/Icons/ as the source of truth; the PNG next to the
// transformation is generated from it so the two never drift.
import { Resvg } from '@resvg/resvg-js';
import fs from 'fs';

const [, , svgPath, pngPath, size = '24'] = process.argv;
const svg = fs.readFileSync(svgPath, 'utf8');
const png = new Resvg(svg, { fitTo: { mode: 'width', value: Number(size) } }).render().asPng();
fs.writeFileSync(pngPath, png);
console.log(`rasterized ${svgPath} -> ${pngPath} (${size}px, ${png.length} bytes)`);
