// Converts the repository's own README.MD into a single, self-contained
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
//
// THE SAME APPLIES TO ORDINARY LINKS, which is easy to miss because only
// the images look like file references. README.MD is full of relative links
// written for GitHub -- [LICENSE](LICENSE), [`dependencies.md`](dependencies.md),
// [`ClusterStats.m`](src/ClusterStats.m) -- and every one of them is a dead
// link in the help viewer: the page is loaded from src/, so "LICENSE"
// resolves next to it rather than at the repository root, and even where the
// path did resolve, a .md or .m file is not something the component can
// render. They are rewritten below to absolute GitHub URLs, with one
// exception: the LICENSE itself is appended to the page in full. A GPL
// program should be able to show its own licence without a network
// connection, and it is the link an analyst is most likely to click.
import { marked } from 'marked'
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

const here = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(here, '..', '..')
const outDir = path.join(here, 'dist')

// Where a relative link in README.MD is sent instead. Pinned to the default
// branch rather than to whatever produced this build: a release package can
// be opened long after it was cut, and a link into a branch that has since
// moved or been deleted is worse than one pointing at the current default.
const REPO_BLOB = 'https://github.com/markspan/Alakazam/blob/main/'

// The in-page anchor the LICENSE link becomes. Must match the slug that
// slugify() below produces for the appended heading, or the one link this
// whole exercise started from is dead again.
const LICENSE_ANCHOR = 'license-full-text'
const LICENSE_HEADING = 'License (full text)'

// git records the README as "README.MD", and everything in this repository
// now names it that way. The directory is still listed rather than that
// spelling assumed: core.ignorecase is on for Windows checkouts, so a
// working copy can hold readme.MD while the index holds README.MD, and on a
// case-sensitive filesystem -- which is what the release workflow's Linux
// runner uses -- opening the wrong one is a hard failure. Listing costs
// nothing and cannot be wrong.
function findReadme(dir) {
    const match = fs.readdirSync(dir).find(f => f.toLowerCase() === 'readme.md')
    if (!match) {
        throw new Error(`No readme found in ${dir}`)
    }
    return path.join(dir, match)
}

const readmePath = findReadme(repoRoot)

// GitHub's own heading-slug algorithm, reproduced exactly rather than
// approximated: README.MD's internal links are written to work on GitHub, so
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

// Now the ordinary links. Runs AFTER the image pass, and skips anything
// already absolute, so the data: URIs just written above are left alone --
// the negative lookbehind keeps this off image syntax in any case.
//
// A relative href may carry its own fragment (docs/x.md#section); the path
// and the fragment are split so the path is rewritten and the fragment
// survives onto the GitHub URL, where it still means something.
md = md.replace(/(?<!!)\[([^\]]+)\]\(([^)]+)\)/g, (whole, text, href) => {
    if (/^(https?:|data:|mailto:|#)/.test(href)) return whole
    const [target, fragment] = splitFragment(href)
    if (target === 'LICENSE') {
        // Kept in the page rather than sent to GitHub: see the header note.
        return `[${text}](#${LICENSE_ANCHOR})`
    }
    return `[${text}](${REPO_BLOB}${target}${fragment})`
})

function splitFragment(href) {
    const hash = href.indexOf('#')
    if (hash < 0) {
        return [href, '']
    }
    return [href.slice(0, hash), href.slice(hash)]
}

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

// External links open outside the help window. Without this a click
// navigates the uihtml component itself away from the help page, and the
// component has no back button to return with -- the analyst would have to
// close Help and reopen it.
renderer.link = function (token) {
    const text = this.parser.parseInline(token.tokens)
    const title = token.title ? ` title="${token.title}"` : ''
    if (/^https?:\/\//.test(token.href)) {
        return `<a href="${token.href}"${title} target="_blank" rel="noopener noreferrer">${text}</a>`
    }
    return `<a href="${token.href}"${title}>${text}</a>`
}

// The licence, appended verbatim. Fenced rather than rendered as Markdown:
// the GPL is a fixed-layout legal text whose own line breaks and indentation
// carry meaning, and letting a Markdown renderer reflow it (or read its
// numbered clauses as list syntax) would alter the wording as displayed.
const licenseText = fs.readFileSync(path.join(repoRoot, 'LICENSE'), 'utf8')
md += `\n\n## ${LICENSE_HEADING}\n\n\`\`\`text\n${licenseText.replace(/```/g, "'''")}\n\`\`\`\n`

const bodyHtml = marked.parse(md, { renderer })

// The whole point of the LICENSE special case is that its link resolves, so
// a slug drift between LICENSE_ANCHOR and the appended heading is a build
// failure rather than something to discover by clicking.
if (slugify(LICENSE_HEADING) !== LICENSE_ANCHOR) {
    throw new Error(
        `LICENSE_ANCHOR ("${LICENSE_ANCHOR}") does not match the slug of ` +
        `LICENSE_HEADING ("${slugify(LICENSE_HEADING)}") -- the licence link would be dead.`)
}

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
<script>
// A LINK IN A uihtml GOES NOWHERE ON ITS OWN. The component embeds a browser
// with no window of its own to open into, so an ordinary <a> to an http(s)
// address does nothing at all when clicked: no new tab, no navigation, no
// error. Rewriting the relative links above to absolute GitHub URLs is only
// half the job -- without this bridge they are still dead, just dead pointing
// somewhere correct.
//
// setup() is uihtml's own entry point, the same one AlakazamRibbon.html and
// the workspace tree use; Alakazam.onHelp listens for the event.
//
// In-page "#anchor" links are left alone: the table of contents is built from
// them, they are same-document navigation, and they already work.
let alzHelp;
function setup(htmlComponent) {
  alzHelp = htmlComponent;
  document.addEventListener('click', function (e) {
    const a = e.target.closest('a');
    if (!a) { return; }
    const href = a.getAttribute('href') || '';
    if (href.startsWith('#')) { return; }
    e.preventDefault();
    if (alzHelp) { alzHelp.sendEventToMATLAB('openUrl', href); }
  });
}
</script>
</body>
</html>
`

fs.mkdirSync(outDir, { recursive: true })
fs.writeFileSync(path.join(outDir, 'AlakazamHelp.html'), page, 'utf8')
console.log(`Wrote dist/AlakazamHelp.html, ${page.length} bytes, ${toc.length} TOC entries`)
