# help

Build tooling for `src/AlakazamHelp.html`, the self-contained `uihtml` page
the app's own Help button opens.

**The built page is not in version control.** It embeds every screenshot as
base64 and runs to about 5 MB, regenerated from `readme.MD`, so committing it
would add a 5 MB diff to history on every README edit. Build it locally with
the steps below. Until you do, the Help button explains that and offers to
open `readme.MD` instead (see `Alakazam.offerReadmeInstead`), so a fresh clone
is never left with a dead button.

Converts the repository's own [`readme.MD`](../../readme.MD) into a single
in-app help page, rather than authoring a second, parallel set of help text
-- the README is already written for the app's own target audience (see its
"Using your own data"/walkthrough sections) and already kept up to date as
features change, so rendering it in-app is the whole point. `build.mjs`:

- uses [marked](https://github.com/markedjs/marked) (MIT licensed) to
  convert the Markdown to HTML **at build time** -- no Markdown parser is
  shipped to the page itself, it is already plain HTML by the time
  `AlakazamHelp.html` exists;
- inlines every `Screenshots/*.jpg` the README references as a base64
  data URI (matching `AlakazamRibbon`'s own self-contained-HTML convention:
  no relative-path resolution once the page is loaded into a `uihtml`
  component);
- gives every `##`/`###` heading a stable slug `id` and builds a table-of-
  contents sidebar from the exact same pass, so the TOC and the rendered
  anchors can never drift apart.

No client-side search box: `uihtml`'s underlying view is a real Chromium
browser, so the standard Ctrl+F "find in page" already works.

## Rebuilding

Once after cloning, and again whenever `readme.MD` or `Screenshots/*.jpg`
changes:

```
cd src/help
npm install
npm run build          # -> dist/AlakazamHelp.html
cp dist/AlakazamHelp.html ../AlakazamHelp.html
```

`node_modules/`, `dist/` and the built `src/AlakazamHelp.html` are all
gitignored, so nothing from this step is committed.

If you ship Alakazam to analysts rather than handing them the repository,
build the page first and include it: they will not have Node, and the Help
button is aimed precisely at people who would never open a README.

## Files

- `build.mjs` -- the whole build: image inlining, Markdown -> HTML, TOC,
  and the page template (CSS lives inline in the template, matching
  `AlakazamRibbon.html`'s own style).
- `package.json` -- the one dependency (`marked`).
