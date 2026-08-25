// Converts the repository's own readme.MD into a single, self-contained
// AlakazamHelp.html: this app's own in-app help viewer. The README is
// already written for the app's own target audience (see its own "Using
// your own data"/walkthrough sections) and already kept up to date as
// features change -- rendering it in-app, rather than authoring a second,
// parallel set of help text, is the whole point of this tool. Images are
// inlined as base64 data URIs (matching AlakazamRibbon's own
// self-contained-HTML convention: no relative-path resolution once this
// page is loaded into a uihtml component). Run: npm run build, then
// (matching src/webtree's own manual deploy step) copy dist/AlakazamHelp.html
// to ../AlakazamHelp.html.
import { marked } from 'marked'
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

const here = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(here, '..', '..')
const readmePath = path.join(repoRoot, 'readme.MD')
const outDir = path.join(here, 'dist')

// GitHub's own heading-slug algorithm, reproduced exactly rather than
// approximated: readme.MD's internal links are written to work on GitHub, so
// any slug that differs here silently produces a dead link in the help viewer
// while the same link still works on the web.
//
// The subtle part is that GitHub DELETES punctuation rather than replacing it,
// and only then turns spaces into hyphens. "Frequency analysis (frequency
// tagging / RIFT)" therefore leaves TWO adjacent spaces where " / " was, and
// so slugs to "...-tagging--rift" with a double hyphen. Collapsing runs of
// non-alphanumerics into a single hyphen (the obvious implementation, and the
// one that used to be here) yields a single hyphen instead, which is a
// different id and broke exactly that link.
function slugify(text) {
    return text.toLowerCase()
        .replace(/[^a-z0-9 -]/g, '')
        .replace(/ /g, '-')
}

function inlineImage(relPath) {
    const abs = path.join(repoRoot, relPath)
    const ext = path.extname(abs).slice(1).toLowerCase()
    const mime = ext === 'jpg' ? 'jpeg' : ext
    const bytes = fs.readFileSync(abs)
    return `data:image/${mime};base64,${bytes.toString('base64')}`
}

let md = fs.readFileSync(readmePath, 'utf8')

// Rewrite every ![alt](Screenshots/X.jpg) reference to an embedded data URI
// before handing the text to marked, so the renderer never has to know
// image sources changed at all.
md = md.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, (whole, alt, src) => {
    if (/^https?:\/\//.test(src) || src.startsWith('data:')) return whole
    return `![${alt}](${inlineImage(src)})`
})

// Custom renderer: h2/h3 headings get a stable slug id (so the TOC sidebar
// can link straight to them) and a TOC entry is recorded as a side effect
// of rendering -- simplest way to keep the TOC and the rendered anchors
// from ever drifting apart, since they are built from the exact same pass.
const toc = []
const renderer = new marked.Renderer()
renderer.heading = function (token) {
    const text = this.parser.parseInline(token.tokens)
    const level = token.depth
    if (level === 2 || level === 3) {
        const id = slugify(text.replace(/<[^>]+>/g, ''))
        toc.push({ level, id, text: text.replace(/<[^>]+>/g, '') })
        return `<h${level} id="${id}">${text}</h${level}>\n`
    }
    return `<h${level}>${text}</h${level}>\n`
}

const bodyHtml = marked.parse(md, { renderer })

const tocHtml = toc.map(t =>
    `<a class="toc-${t.level === 2 ? 'h2' : 'h3'}" href="#${t.id}">${t.text}</a>`
).join('\n')

const page = `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
  html, body { margin: 0; padding: 0; height: 100%; font-family: -apple-system, Segoe UI, Arial, sans-serif; color: #222; }
  #shell { display: flex; height: 100%; box-sizing: border-box; }
  #toc { width: 260px; flex: none; overflow-y: auto; background: #f5f6f8; border-right: 1px solid #ddd; padding: 14px 10px; box-sizing: border-box; }
  #toc a { display: block; padding: 4px 8px; border-radius: 4px; color: #2e5c8a; text-decoration: none; font-size: 12.5px; line-height: 1.35; }
  #toc a:hover { background: #e6ecf5; }
  #toc a.toc-h3 { padding-left: 20px; font-size: 11.5px; color: #555; }
  #toc-title { font-weight: bold; color: #333; padding: 4px 8px 10px; font-size: 13px; text-transform: uppercase; letter-spacing: 0.4px; }
  #content { flex: 1; overflow-y: auto; padding: 24px 40px 80px; box-sizing: border-box; max-width: 900px; }
  h1 { color: #2e5c8a; border-bottom: 2px solid #4a7fc9; padding-bottom: 8px; }
  h2 { color: #2e5c8a; margin-top: 2.2em; border-bottom: 1px solid #ddd; padding-bottom: 4px; }
  h3 { color: #345; margin-top: 1.6em; }
  a { color: #4a7fc9; }
  code { background: #eef0f4; padding: 0.1em 0.4em; border-radius: 3px; font-size: 0.9em; }
  pre { background: #eef0f4; padding: 12px 14px; border-radius: 6px; overflow-x: auto; }
  pre code { background: none; padding: 0; }
  img { max-width: 100%; border: 1px solid #ddd; border-radius: 4px; margin: 8px 0; }
  table { border-collapse: collapse; margin: 1em 0; }
  th, td { border: 1px solid #ccc; padding: 4px 10px; text-align: left; }
  th { background: #f0f2f5; }
  blockquote { border-left: 3px solid #4a7fc9; margin: 1em 0; padding: 0.2em 1em; color: #555; background: #f7f8fa; }
</style>
</head>
<body>
<div id="shell">
  <nav id="toc"><div id="toc-title">Contents</div>${tocHtml}</nav>
  <main id="content">${bodyHtml}</main>
</div>
</body>
</html>
`

fs.mkdirSync(outDir, { recursive: true })
fs.writeFileSync(path.join(outDir, 'AlakazamHelp.html'), page, 'utf8')
console.log(`Wrote dist/AlakazamHelp.html, ${page.length} bytes, ${toc.length} TOC entries`)
