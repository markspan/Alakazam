// Assembles the single self-contained HTML page uihtml loads: the built
// AlakazamTree bundle + its CSS + the MATLAB<->JS bridge glue, all inlined.
// Re-run after `node build.mjs` whenever src/*.js or src/*.css changes.
import fs from 'fs'

const bundle = fs.readFileSync('dist/alakazam-tree.bundle.js', 'utf8')
const css = fs.readFileSync('src/alakazam-tree.css', 'utf8')
const bridge = fs.readFileSync('src/bridge.js', 'utf8')

const html = `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
html, body { margin: 0; padding: 0; height: 100%; overflow: hidden; font-family: sans-serif; font-size: 12px; }
#tree { width: 100%; height: 100%; overflow: auto; box-sizing: border-box; }
${css}
</style>
</head>
<body>
<div id="tree"></div>
<script>
${bundle}
</script>
<script>
${bridge}
</script>
</body>
</html>
`

fs.writeFileSync('dist/alakazam-tree.html', html)
console.log('assembled dist/alakazam-tree.html, ' + html.length + ' bytes')
