# webtree

Build tooling for [`src/WorkSpaceTree.html`](../WorkSpaceTree.html), the
self-contained `uihtml` page `WorkSpaceTree.m` loads for the data-browser
tree. Built once and vendored; end users of Alakazam never need Node/npm.

Wraps [yy-tree](https://github.com/davidfig/tree) (a vanilla-JS
drag-and-drop tree, MIT licensed) with:

- per-node icons (`src/alakazam-tree.js`, `ICONS` map) -- yy-tree has none
  natively;
- a custom right-click context menu (List events / Rename / Recalculate /
  Delete), also not native to yy-tree;
- double-click detection (yy-tree only emits a single `clicked` event);
- drop semantics matching Alakazam's own tree: yy-tree's native drag is a
  *reorder* gesture (insert-as-sibling, mutating its data immediately in
  `_moveData()`), but this tree never actually moves a node -- dropping one
  onto another always means "apply this node's transformation to the one
  it was dropped onto", not "move it here". The visual/data move yy-tree
  performs is always reverted (back to the exact original parent+index)
  and a `nodeDropped` event is sent instead, so MATLAB can build the
  actual new result node(s) itself.
- the MATLAB &lt;-&gt; JS bridge (`src/bridge.js`) on top of `uihtml`'s
  `Data`/`DataChangedFcn`/`HTMLEventReceivedFcn`/`sendEventToMATLAB`
  contract -- see `WorkSpaceTree.m` for the MATLAB side of this contract.

## Rebuilding

```
cd src/webtree
npm install
npm run build          # -> dist/alakazam-tree.bundle.js, dist/alakazam-tree.html
cp dist/alakazam-tree.html ../WorkSpaceTree.html
npm test                # jsdom-based tests: render/click/dblclick/menu/drag
```

`node_modules/` and `dist/` are gitignored; only the final assembled page is
committed, at `src/WorkSpaceTree.html`.

## Files

- `src/alakazam-tree.js` -- the yy-tree wrapper (icons, context menu,
  double-click, always-revert drop).
- `src/alakazam-tree.css` -- styling for the icon/menu additions.
- `src/bridge.js` -- glue between `uihtml`'s JS contract and
  `AlakazamTree.create`.
- `build.mjs` -- esbuild bundle step.
- `assemble.mjs` -- inlines the bundle + CSS + bridge into one
  self-contained HTML file (`uihtml`'s `HTMLSource` is simplest and most
  robust as a single file, with no relative-asset resolution to worry
  about).
- `test_node.mjs` -- jsdom tests. Real pixel-based drag can't be simulated
  (jsdom has no layout engine, so `getBoundingClientRect()` is always
  zero); the drag/revert logic is instead tested by driving the wrapper
  through the exact `move-pending`/`move` event contract verified directly
  in yy-tree's own `input.js` source.
