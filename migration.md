# Migration: ToolGroup docking, and everything that followed

**Status: complete.** This started as a design note investigating why
MATLAB 2025b/2026a's move away from Java(Swing)-backed figures would break
Alakazam's old `ToolGroup`-docked app shell, and grew into a running log of
the entire shell rewrite (single `uifigure`, `uihtml` ribbon, `uihtml`
workspace tree split into two, tabbed/tiled plots) and the fixes/audit that
followed it. Read top to bottom for the chronological history; the current
architecture is summarised in `README.MD`'s Architecture section and
`PROJECT_STRUCTURE.md`.

The original diagnosis (kept below for the record): MATLAB 2025b/2026a stop
creating Java(Swing)-backed figures; every `figure()` now uses the web/CEF-
rendered uifigure architecture under the hood, which broke Alakazam's old
app shell -- it docked plot windows via the Java-based `ToolGroup` desktop.

## Diagnosis

The whole app window is `matlab.ui.internal.desktop.ToolGroup`
([`src/Alakazam.m:67`](src/Alakazam.m)) -- MathWorks' old undocumented
Java-Swing MDI-desktop API, explicitly adapted from R. Chen's
`showcaseMPCDesigner` ([`src/Alakazam.m:32`](src/Alakazam.m), same "ToolGroup
demo" [`README.MD:149`](README.MD) cites). Every plot dock happens via
`app.ToolGroup.addFigure(newFig)` in
[`src/AlakazamPlotter.m:93`](src/AlakazamPlotter.m), and raising an existing
tab via `app.ToolGroup.showClient(name)`. Under the hood, `addFigure` works
by grabbing the figure's Java Swing peer (`JavaFrame`) and reparenting it
into the ToolGroup's own Swing-based docking desktop
(`com.mathworks.mde.desk.MLDesktop`) -- the same underlying mechanism
[`src/+uiextras/setFigDockGroup.m`](src/+uiextras/setFigDockGroup.m) uses
(that file is vendored but, as far as could be found, never actually
called -- dead code, not the live path).

Once `figure()` stops creating a Swing-backed window, there is no Swing peer
left for `ToolGroup.addFigure` to grab. So the plot figures will not dock via
the current mechanism -- this isn't a flag or compatibility shim, the
foundation the entire app shell stands on is gone. `JavaFrame` already
throws/returns empty on the new figure family, and `ToolGroup`/`MLDesktop`
have no other way to embed a window.

## Options

**A -- migrate the shell to `matlab.ui.container.internal.AppContainer`
(recommended).** MathWorks' own successor to `ToolGroup`, web/CEF-based like
the new figures, and what they migrated their own `ToolGroup`-era apps
(Simulink Data Inspector, System Composer, etc.) to years before this
cutover -- precisely because `ToolGroup`'s Java foundation was already known
to be doomed. It has a documented-in-spirit-if-not-in-public-docs bridge,
`matlab.ui.internal.FigureDocument`, whose entire purpose is embedding a
figure as a dockable document/tab in an AppContainer shell. This keeps every
existing View class (`EpochView`, `AverageView`, `FourierView`, `SignalView`,
`ScalpDistribution` -- all built on classic `axes`/`subplot`/`uicontrol`,
plus EEGLAB's `topoplot` which needs classic graphics) completely untouched;
only the shell (`setupToolGroup`, `plotCurrent`'s dock/show calls,
`setDataBrowser`) changes. Caveat: still an internal, unversioned API --
unconfirmed whether `FigureDocument` already handles the new figure family or
needs adjustment on 2025b/2026a.

**B -- drop true MDI docking, go with independent windows (pragmatic
fallback).** Keep `AlakazamPlotter` producing ordinary top-level figures
exactly as today (zero changes to any View class), and replace "dock into
ToolGroup" with a small home-grown window list: track `app.Figures` (already
done), add a "Windows" list/gallery to the toolstrip to raise a given plot by
name (replacing `showClient`), maybe `movegui`/manual tiling on request.
Loses the single-MDI-window feel but is roughly half a day of work, fully
buildable and testable on R2024b right now, and has zero dependency on
undocumented desktop internals.

**C -- rehost every plot in one `uifigure` with `uitabgroup`/`uiaxes` (not
recommended).** Rejected: too much plotting code is hard-committed to
classic-graphics-only behaviour -- `topoplot`'s direct `patch`/`gca` calls,
`subplot`, floating `uicontrol` sliders positioned in figure-normalized
coordinates (`AverageView`'s tickboxes, `ScalpDistribution`'s slider).
`uiaxes` doesn't reliably support several of these, so this option means
rewriting most view classes, not just the shell.

## Suggested first step

Before committing to A vs. B, a cheap smoke test on a machine that actually
has 2025b/2026a: construct a bare `AppContainer`, wrap a plain `figure` with
a `topoplot` in a `FigureDocument`, and see whether it docks. That single
experiment tells us whether A is viable at all.

## Status

Option A implemented. `Alakazam.m`'s `setupToolGroup`/`ToolGroup` became
`setupAppContainer`/`AppContainer` (`matlab.ui.container.internal.AppContainer`
+ `matlab.ui.internal.FigureDocument`, registered under a `'plots'` document
group); `AlakazamPlotter.plotCurrent` docks each dataset's figure the same
way. The data-browser tree was ported to the same shell in the same pass (it
turned out not to be independent -- see below) via a new `matlab.ui.internal.
FigurePanel` hosting `WorkSpaceTree` (see `webtree/README.md`), replacing
`ToolGroup.setDataBrowser`.

Findings from real R2025b testing (`matlab -batch`, via smoke scripts kept
outside the repo):

- Confirmed via direct construction: `AppContainer`, `registerDocumentGroup`,
  `addTabGroup` (accepts the existing toolstrip `TabGroup`/`Tab` classes
  unchanged), `addDocument`, `addPanel`, `WindowBounds` (replaces
  `setPosition`), `Visible = true` (must be set last, mirroring
  `ToolGroup.open()`), `bringToFront`, `close('force', true)`.
- `FigureDocument.Figure` and `FigurePanel.Figure` are both lazily created,
  `SetAccess = private` (`matlab.ui.internal.divfigure()`) -- not a wrapper
  around a figure you create yourself. Every classic-graphics/figure property
  `AlakazamPlotter` was already setting (`NumberTitle`, `Color`,
  `PaperOrientation`, `Units`, `MenuBar`, `Toolbar`, `DockControls`, ...) is
  still settable on it, as are `axes`/`plot`/`uicontrol`/`patch`.
- **`FigureDocument`/`FigurePanel` figures have `HandleVisibility = 'off'`
  and are never parented under `groot`** -- `findobj(..., "Type", "Figure",
  "Tag", ...)`, the old lookup-by-Tag idiom `plotCurrent`/`overlayAverage`/
  `onTransformation`/`onDeleteNode` all relied on, silently finds nothing.
  Fixed by keying every lookup off the `FigureDocument`'s own `Tag`
  (deterministic: `matlab.lang.makeValidName(eeg.File)`) via
  `AppContainer.hasDocument`/`getDocument`/`closeDocument` (all take
  `(documentGroupTag, tagOrTitle)`, and both arguments must be `string`, not
  `char` -- the internal implementation concatenates them with `+`).
- AppContainer has no `SelectedTab`; that moved onto `TabGroup` itself
  (`tabgroup.SelectedTab = tabHome`, set in `BuildTabGroupAlakazam`).
- The close listener is `WindowStateChanged` (no useful eventdata of its own,
  unlike the old `GroupAction`/`EventType`); check the live
  `AppContainer.WindowState == ...AppWindowState.CLOSED` on the container
  itself instead.
- **Not fully confirmed**: `AppContainer.closeDocument(...)` (used by
  `onDeleteNode` to close a deleted node's open figure) took long enough in a
  headless `matlab -batch` smoke test that it could not be distinguished from
  a hang within a reasonable wait -- everything else in the same test
  (`hasDocument`/`getDocument`/`.Selected`) returned promptly. Plausibly a
  headless/no-window-server limitation of `-batch` specifically (closing a
  CEF-hosted tab may need a real message pump), not a real bug, but this one
  call has not been confirmed working interactively. Worth deliberately
  triggering (right-click a node with an open plot -> Delete) on first
  interactive test.

Everything else (tree add/rename/remove/select, drag-drop reparent vs.
Ctrl-apply-transformation, context-menu dispatch, grand-average node
create/update, figure creation and reuse) was exercised end to end against
the real production code (not reimplemented logic) in a smoke test using a
minimal fake `Alakazam`-like host, with all assertions passing.

Not yet done: a full interactive launch of the real app (`Alakazam()` with
real EEGLAB data) on R2025b -- this is task #7 in the migration tracking.

## Final status: Option A's docking half reverted, confirmed MathWorks bug

The first real interactive launch (2026-07-10, R2026a) surfaced a new
symptom: plots drew without error but never rendered inside their
`FigureDocument` tab -- literal placeholder text reading **"undefined"**
appeared in the content pane instead.

Systematic isolation (bare `AppContainer` + one `DocumentGroup` + one
`FigureDocument`, no tree/toolstrip/EEGLAB) reproduced it identically,
independent of:
- Content type: both classic `axes`/`surf` and `uiaxes`/`uigridlayout` show
  it when hosted in a `FigureDocument`'s divfigure.
- The axes toolbar (`axtoolbar`) and `DockControls` -- neither changes it.
- MATLAB version -- identical across 2025a, 2025b, and 2026a.

The actual rule turned out to be simpler than "AppContainer is broken":
**`uiaxes` only renders correctly inside a genuine `uifigure()`; classic
axes only render correctly inside a genuine classic `figure()`.**
`FigureDocument`'s divfigure is neither, and breaks both -- confirmed by
testing all four combinations (classic axes / `uiaxes` content, plain
`figure()` / plain `uifigure()`, vs. forced through `FigureDocument`) in
isolated repro scripts (kept outside the repo, alongside this file's own
history, for anyone continuing this investigation).

MATLAB R2025a separately introduced a public, documented, default docking
mechanism -- the "Tabbed Figure Container" (see [MathWorks' blog
post](https://blogs.mathworks.com/graphics-and-apps/2025/06/24/introducing-the-tabbed-figure-container/)).
Plain `figure()` calls dock into it automatically, for free, as long as
nothing forces them undocked (setting `Position`, `OuterPosition`, `Resize`,
`WindowState`, `MenuBar`, `Toolbar` or `DockControls` all trigger
auto-undock). Confirmed working cleanly with classic-axes content.

**Resolution**: plots were reverted to classic graphics (`AlakazamPlotter`
creates plain `figure()` windows; `SignalView`/`EpochView`/`AverageView`/
`FourierView` restored to their pre-port classic `axes`/`uipanel`/
`uicontrol` implementations from before this migration -- the port was
purely mechanical, so this was a restore, not a rewrite) and now dock via
the native Tabbed Figure Container instead of `FigureDocument`. `AppContainer`
is kept for the toolstrip + data-browser tree shell only, which was never
affected by this bug. Figure lookup (`overlayAverage`, `onTransformation`,
`onDeleteNode`) reverted from `AppContainer.hasDocument`/`getDocument`/
`closeDocument` back to plain `findobj("Type", "Figure", "Tag", ...)`, since
classic figures are parented under `groot` as usual (unlike
`FigureDocument`'s divfigures, which have `HandleVisibility = 'off'`).

Tradeoff accepted: every plot window now shows MATLAB's default menu bar and
toolbar (hiding them via `MenuBar`/`Toolbar` is exactly what triggers
auto-undock), in exchange for docking that actually works.

This looks like a genuine bug in `matlab.ui.container.internal.AppContainer`
/ `matlab.ui.internal.FigureDocument` -- both explicitly undocumented,
unversioned internal APIs -- not something fixable from this codebase. Worth
filing with MathWorks if anyone revisits true MDI-style docking later; the
isolated repro scripts reproduce it in under 30 lines with zero dependency
on this app.

## Superseding status: single uifigure, AppContainer dropped entirely

The classic-figure/Tabbed-Figure-Container resolution above worked, but
opened plots in a **separate OS window** from Alakazam's own `AppContainer`
(toolstrip + tree) window -- the two are unrelated MATLAB subsystems with no
bridge between them (confirmed: nothing in MathWorks' own description of the
Tabbed Figure Container mentions embedding it in a custom shell). This was
rejected as unacceptable.

Further investigation narrowed the "undefined" bug more precisely: the
workspace tree, hosted via `matlab.ui.internal.FigurePanel`, builds its
divfigure through the *exact same* `matlab.ui.internal.divfigure` factory as
`FigureDocument` (confirmed by reading both classes' source: both call
`matlab.ui.internal.FigureServices.getAppContainerFigureDefaults()` then
`matlab.ui.internal.divfigure(defaultProps{:})`), yet its `uihtml` +
`uigridlayout` content renders perfectly. So the bug is specifically **axes
(classic or `uiaxes`) inside a divfigure** -- not AppContainer content in
general. Separately, a real MathWorks Toolstrip (ribbon) cannot be attached
to anything except `AppContainer` in modern MATLAB; the old undocumented
tricks for attaching one to a classic figure relied on the same Java/Swing
`JavaFrame` machinery that's already confirmed gone.

**Final resolution**: `AppContainer` was dropped entirely. Alakazam is now a
single plain `uifigure` (`Alakazam.setupMainWindow`), laid out with a
top-level `uigridlayout`:
- A control-strip `uitabgroup` (Home / Tools / Grand Average) replaces the
  Toolstrip ribbon, built by `BuildToolbarAlakazam.m` (was
  `BuildTabGroupAlakazam.m`) from the same `Transformations/*.json`
  metadata via the same parsing helpers, just rendered as `uibutton` grids
  in `uipanel`s instead of a Toolstrip `Gallery`.
- The workspace tree (`uihtml`, unchanged) is built directly into a reserved
  `uigridlayout` cell (`Alakazam.TreeGrid`) -- no `FigurePanel` wrapper
  needed at all, since `uihtml` is completely native to a plain `uifigure`.
- Plots are `uitab`s in `Alakazam.PlotsTabGroup`, one per open dataset.
  `SignalView`/`EpochView`/`AverageView`/`FourierView` moved back to their
  post-port `uiaxes`/`uigridlayout` form (the classic-graphics versions from
  the resolution above are no longer used) -- `uiaxes` is completely at home
  in a genuine `uifigure`, since this never goes through
  `AppContainer`/`FigureDocument`/`FigurePanel` at all.

One real subtlety this introduced: `SignalView`'s `WindowScrollWheelFcn` and
`EpochView`/`AverageView`'s `KeyPressFcn` used to be set directly on each
dataset's own figure; with every dataset now a tab on one *shared* figure,
those are figure-wide properties, so each View setting its own would just
overwrite the previous one's handler, breaking wheel/key interaction on
every other open tab. Fixed with a single shared dispatcher
(`Alakazam.dispatchWheel`/`dispatchKey`, wired once in `setupMainWindow`)
that forwards each event to whichever View is on the currently selected
plots tab; `onWheel`/`onKey` became public methods on their View classes so
the dispatcher can call them.

Figure-keyed lookups (`overlayAverage`, `onTransformation`, `onDeleteNode`,
`onSettingsChanged`) moved from `findobj("Type", "Figure", "Tag", ...)` to
`findobj(app.PlotsTabGroup.Children, 'flat', 'Tag', ...)`, since plots are
tabs, not top-level figures, anymore.

## Toolbar restyled as a uihtml ribbon

The single-uifigure rewrite above initially replaced the Toolstrip ribbon
with a plain `uitabgroup` of `uibutton` grids (`BuildToolbarAlakazam.m`),
since a real MathWorks Toolstrip cannot attach to anything but
`AppContainer`. That worked but lost the ribbon's visual polish (icon
galleries, grouped sections).

`uihtml` was already a proven, reliable pattern in this exact app --
`WorkSpaceTree` wraps a full JS tree component (`yy-tree`) inside a plain
`uifigure`-hosted `uihtml`, and was never affected by the `FigureDocument`/
`FigurePanel` "undefined" bug in the first place (it never goes through
`AppContainer` at all). A ribbon is a much simpler case than the tree --
static layout, no drag gestures -- so it's rebuilt as `AlakazamRibbon.m` +
`AlakazamRibbon.html`, mirroring `WorkSpaceTree`'s
`Data`/`DataChanged`/`sendEventToMATLAB`/`HTMLEventReceivedFcn` contract
(see `webtree/src/bridge.js` for the original version of that pattern).
Unlike the tree, this needs no third-party JS library (no drag-and-drop
logic to implement), so `AlakazamRibbon.html` is hand-written directly as a
single self-contained file -- no `webribbon/` folder, no npm/esbuild build
step, unlike `webtree/`.

One correctness pitfall worth recording: `jsonencode` (and `uihtml`'s `Data`
serialization, which uses the same conversion) collapses a scalar or
single-element **struct array** to a bare JSON object rather than a
one-element array -- confirmed empirically (`jsonencode(struct('id','a'))`
and `jsonencode(repmat(struct('id','a'),1,1))` both give `{"id":"a"}`, not
`[{"id":"a"}]`). This would have silently broken the JS side's `.forEach`
calls for any single-item group (the Settings tab item, the Grand Average
item). Fixed by building every list (tabs/groups/items) in
`AlakazamRibbon.m` as a **cell array** of structs instead of a struct array
-- cell arrays always serialize as JSON arrays regardless of element count
(confirmed the same way). `WorkSpaceTree.m`'s own `buildData()` builds
`nodes` as a struct array without this guard; it has likely never been
exercised with exactly one tree node in practice, but carries the same
latent risk if it ever is.

`BuildToolbarAlakazam.m` (and its own predecessor, the Toolstrip-based
`BuildTabGroupAlakazam.m`) no longer exist.

## Plot tab close buttons + a real webtree/ rebuild

`matlab.ui.container.Tab` has no close-button concept at all (checked its
full property list) -- the tab strip is rendered entirely by MATLAB, so no
`uicomponent` can be injected into it. `Alakazam.closeTab(tag)` (closes just
the view, leaving the dataset/tree node untouched) is wired two ways: a
right-click "Close" `uicontextmenu` on each `PlotsTabGroup` tab
(`AlakazamPlotter.plotCurrent`), and a real close-x `uibutton` on each tile
wrapper's handle row (`Alakazam.tileWrapperFor`, which fully controls that
DOM already for click-to-swap reordering).

Node.js became available partway through this session (previously
confirmed absent everywhere on this machine). This let the workspace tree's
modernisation (row styling, selection highlight, icon set) go through
`webtree/`'s actual documented build (`npm install && npm run build`)
instead of hand-syncing `webtree/src/*` with the deployed
`src/WorkSpaceTree.html`. Two things worth recording from reading `yy-tree`'s
real source (`webtree/node_modules/yy-tree/src/`, available once installed):
- `Tree`'s `styles` constructor argument (`nameStyles`/`contentStyles`/
  `expandStyles`/`indicatorStyles`/`selectStyles`) merges with its own
  built-in defaults **shallowly, one whole sub-object at a time**
  (`utils.options()`), not per individual CSS property -- providing e.g. any
  `nameStyles` at all replaces the *entire* default object, including its
  undocumented fixed `width: 100px` (the actual cause of the previous boxy,
  fixed-width node-label look). No need to explicitly null out defaults you
  don't want.
- `yy-tree`'s expand/collapse glyphs (`icons.open`/`icons.closed`) aren't
  exposed through `Tree`'s public options at all. Overridden by importing
  the same underlying module directly (`import { icons } from
  'yy-tree/src/icons.js'`) and mutating its exported object's properties
  before constructing any `Tree` -- esbuild resolves the deep subpath import
  fine (no `exports` field in `yy-tree`'s `package.json` blocking it), and
  since both `alakazam-tree.js` and `yy-tree`'s own `tree.js` end up
  importing the identical module instance once bundled, the mutation
  propagates. An explicitly undocumented reach-in, but into vendored,
  pinned, build-time-only code (see `webtree/README.md`), not a live
  dependency.
- Real row selection highlighting is `alz-row-selected`, Alakazam's own
  class applied to the whole row (`leaf.content`) from both the native-click
  path (`_onClicked`) and the programmatic path (`_selectById`) --
  `yy-tree`'s own `-select` class only ever touches the name span, which is
  why selection previously looked like a barely-different shade of the same
  grey used for the unselected boxy label background.

## Grid/Stack keyboard and wheel dispatch followed the wrong tile

In Grid/Stack (tiled) mode, `Alakazam.dispatchKey`/`dispatchWheel` used to
read `PlotsTabGroup.SelectedTab` directly to find the target view. That
property is only ever updated by selecting a tab in Tabs mode -- clicking
inside a tile's own content in Grid/Stack never touches it (the tabgroup
itself is hidden there, see `setPlotsViewMode`). So arrow-key/wheel
shortcuts always kept acting on whichever tab happened to be selected
*before* switching into tiled mode, never on the tile the user actually
just clicked.

Fixed with an explicit "last activated" tracking: every View class
(`SignalView`, `EpochView`, `AverageView`, `FourierView`) now exposes an
`ActivatedFcn` property, called from its own click/interaction entry points
(axes `ButtonDownFcn`, wheel/slider handlers, checkbox toggles, and -- for
`FourierView`, which is mostly button-driven -- its zoom/pan/trial/channel
buttons too, chained alongside the existing per-channel `showDetail`
`ButtonDownFcn` rather than overwriting it). `AlakazamPlotter` wires each
view's `ActivatedFcn` to `Alakazam.registerTileClick(tab.Tag)`, which sets a
new `LastClickedTag` property; `onTileHandleClicked` also calls it, so
picking a tile's title handle counts too. A new `Alakazam.activeTileTag()`
resolves the dispatch target: `PlotsTabGroup.SelectedTab`'s Tag in Tabs
mode (unambiguous, matches the old behaviour exactly), `LastClickedTag`
otherwise. `dispatchKey`/`dispatchWheel` now look the tab up by that tag
via `findobj` instead of reading `SelectedTab`.

## Tree node icons: per-transformation, plus a real folder icon for roots

The workspace tree previously iconned every non-root node purely by
`EEG.DataType` (`WorkSpaceTree.iconFor`: 'time'/'freq'/'default' -- three
fixed badge SVGs baked into `webtree/src/alakazam-tree.js`'s `ICONS` map).
Every result of every transformation with the same DataType looked
identical, and root nodes used a document-glyph badge (`ICONS.raw`) that
didn't read as "this is a folder/container."

`WorkSpaceTree.iconForResult(EEG, transRoot)` is the new entry point
(replacing `iconFor` at the two node-creation sites that build *result*
nodes: `Alakazam.persistResultNode` and `WorkSpace.treeTraverse`, which
rebuilds the tree from the on-disk cache on load -- both needed the same
lookup so a reopened session shows the same icons). It looks up the
transformation that produced the dataset (`EEG.id`/`EEG.Call`, set in
`persistResultNode`/`onTransformation` to the transformation's own folder
name) via `Transformations/<id>/<id>.json`'s `Icon` field -- the exact PNG
`AlakazamRibbon`'s Tools tab buttons already show -- and returns it as a
base64 data URI. `alakazam-tree.js`'s `_onRender` now renders any
`data:`-prefixed icon string as a real `<img>` scaled to the badge
footprint (16x16, `.alz-icon-img`) instead of looking it up in `ICONS`;
plain key strings ('time'/'freq'/'default'/'raw') still resolve through
`ICONS` exactly as before. When no matching transformation icon exists
(a Grand Average's `id` is a user-chosen name, not a transformation id;
`transRoot` can also be omitted entirely), `iconForResult` falls straight
back to the old `iconFor(DataType)` badge key -- no behaviour change for
those cases.

Root-node icons: no usable modern "folder" icon exists anywhere in the
local MATLAB install to source this from -- `toolbox/matlab/icons/
foldericon.gif` is the only direct hit, and (consistent with the same
finding from the earlier tree-icon-set work) it's a dated Windows-9x-style
bitmap, not something worth scaling into a 16px badge; nothing better
turned up under the toolstrip/web or `resources/currentfolderbrowser`
trees (the latter is just localisation strings, no assets). `ICONS.raw`
(already the icon key every root-import node uses, see
`WorkSpace.loadBVAFile`/`loadSETFile`/`loadMATFile`) was redrawn as a
folder glyph instead -- the same closed-folder-tab silhouette
`AlakazamRibbon`'s "Tabs" view-mode icon already uses (`M2 6h8l2 3h10v11H2z`
in that outline style), recoloured white-on-badge to match the tree's own
icon language rather than copied verbatim in the ribbon's outline style.
`WorkSpace.loadGrandAverages`'s "Grand Averages" node (also `isRoot: true`,
previously the unrelated `'default'` grey-document key) now uses `'raw'`
too, so every root branch gets the same folder look.

## Split the workspace tree in two: data & analyses, and grand averages

Grand averages used to live inside the same `WorkSpace.Tree` as everything
else, nested under an always-present, synthetic "Grand Averages" root node
(`WorkSpace.GrandAveragesNode`) that existed purely as a container -- it
combined several subjects' Averaged results, so it never belonged nested
under any single subject's own branch the way a transformation result does.
Now there are two separate `WorkSpaceTree` instances: `WorkSpace.Tree`
(unchanged name and role, data & analyses) in a new `Alakazam.DataTreePanel`
(top), and `WorkSpace.GrandAveragesTree` in `Alakazam.GrandAveragesTreePanel`
(bottom) -- `Alakazam.TreeGrid` (the same outer cell the tree area always
occupied, so the tree/plots splitter's own math in `dragTreeResize` is
unaffected) became a `[2 1]` grid holding two titled `uipanel`s instead of
one `[1 1]` grid holding one tree directly. Grand averages are now flat,
top-level nodes (`parentId ''`) in their own tree; the container node is
gone entirely, `WorkSpace.GrandAveragesNode` removed.

Both trees wire back to the *same* Alakazam callback methods
(`onSelectionChanged`, `onNodeDoubleClicked`, `onNodeDropped`,
`onContextMenuAction`) -- none of their bodies actually needed to know
which tree raised the event, only the node struct the event already
carries. What did need solving: exactly one of the two `WorkSpaceTree`
instances can have a "selection" at a time in the underlying yy-tree
model, but several call sites (`onRenameNode`, `onDeleteNode`,
`onRecalculateNode`, `onListEvents`, `onTransformation`,
`persistResultNode`) used to just hardcode `this.Workspace.Tree.
SelectedNodes`/`.renameNode(...)`/`.removeNode(...)`/`.addNode(...)` --
with a second tree, an action started from a right-click or a running
transformation on a grand-average node needs to land in
`GrandAveragesTree`, not the unrelated data tree.

Fixed with the same "last interacted with" pattern already used for tile
click-routing (`Alakazam.LastClickedTag`/`registerTileClick`/
`activeTileTag`, see the Grid/Stack dispatch fix above): a new
`WorkSpace.ActiveTree` property, set to whichever tree raised the event.
`CreateTreeComponent` wires each tree's four `*Fcn` callbacks with the
source tree as a second argument -- `@(e) this.Parent.onSelectionChanged(e,
this.Tree)` / `@(e) this.Parent.onSelectionChanged(e, this.GrandAveragesTree)`
-- captured as `this.Tree`/`this.GrandAveragesTree` (WorkSpace properties)
rather than a plain local variable: at the point each `WorkSpaceTree` is
being constructed, its own property assignment (`this.Tree = WorkSpaceTree
(...)`) has not completed yet, so a bare local variable referenced inside
that same statement's anonymous function would be undefined -- a handle
property read is resolved lazily at call time instead, by which point
construction has long finished. Every one of `onSelectionChanged`/
`onNodeDoubleClicked`/`onNodeDropped`/`onContextMenuAction` now sets
`this.Workspace.ActiveTree = sourceTree` as its first line; the five
previously-hardcoded call sites now read/mutate `this.Workspace.
ActiveTree` instead. `saveGrandAverage` is the one exception, hardcoded to
`this.Workspace.GrandAveragesTree` directly rather than `ActiveTree` --
it's only ever reached from the Grand Average tab's own "Define.../
Recalculate" actions, not a generic current-selection flow, so there is
no ambiguity to resolve there.

## AutoEyeICA threw on channels with no scalp location (e.g. EOG)

`AutoEyeICA` ran ICA on the *whole* dataset, then called `TransTools.
EnsureChanlocs` -- which requires every single channel to resolve to a
dipfit standard-10-5 position, throwing outright (naming the channel) if
any doesn't -- purely so ICLabel would have a position for every channel.
An EOG channel (or ECG, or anything else with no real scalp position, which
is the normal case for those) made this throw every time, even though nothing
about ICA or ICLabel actually requires that specific channel to be involved.

`AutoGEDAI` already had the right shape for this problem (see its own
"leadfield-based denoising only works on real scalp EEG channels" section
above): decide eligibility once, run the real processing on just the
eligible channels, splice the rest back into their original slots
afterward, unmodified. `AutoEyeICA` now does the same: `TransTools.
FillChanlocs` (which does NOT require full coverage) fills in whatever
positions it can from dipfit's 10-5 template, `chanlocs.X`/`isnan` then
splits channels into `eegIdx` (positioned -- decomposed) and `otherIdx`
(not -- excluded, e.g. EOG/ECG), `pop_select` reduces to `eegIdx` before
`pop_runica`/`iclabel`/`pop_subcomp` run, and the excluded channels' original
data is copied back into the merged result untouched (ICA never changes the
sample/trial count, so this merge is simpler than AutoGEDAI's -- no epoch-
count-changed bailout needed). `icachansind` is remapped from the reduced
dataset's own local `1..numel(eegIdx)` indices back into the full channel
list (`eegIdx(eegOnly.icachansind)`) so it still correctly names which
channels the kept `icaweights`/`ic_classification` describe. Throws only
when *no* channel has a usable position (nothing to decompose at all) --
same shape as AutoGEDAI's equivalent check.

`TransTools.EnsureChanlocs` (the all-or-nothing wrapper) is now unused --
`AutoEyeICA` was its only caller -- left in place with an updated docstring
rather than deleted outright, in case a future caller genuinely wants that
stricter behaviour.

Verified end-to-end against the real EEGLAB/FastICA/ICLabel stack (not
mocked) with synthetic data: a 6-channel scalp mixture (independent
uniform sources through a random orthogonal mixing matrix -- pure Gaussian
noise has no independent structure for FastICA to find and is not a
realistic test) plus a 7th "HEOG" channel with no 10-5 position. Confirmed
the run no longer throws, channel count/order is unchanged, the HEOG
channel's data comes back byte-identical, `icachansind` excludes it while
`icaweights`/`ic_classification` are still populated for the other six, and
a dataset where *no* channel has a position still throws the expected
"nothing for ICA to decompose" error.

## AutoGEDAI: intermittent "great, then unusable" results from identical runs

Reported symptom: running AutoGEDAI twice on the same dataset with the same
settings sometimes gave a good result, sometimes garbage -- no error, no
visible difference in inputs. `AutoGEDAI.m` itself (channel eligibility,
merge-back, threshold mapping) is deterministic given fixed inputs; traced
the actual cause into the vendored GEDAI plugin it calls (`Documents/MATLAB/
GEDAI/GEDAI-master-1.7/GEDAI.m`, downloaded by `ensureGEDAI` -- not part of
this repo, so it can't be fixed here directly).

`GEDAI.m`'s wavelet-band denoising loop pre-allocates one reduction
accumulator (`wavelet_band_filtered_data = zeros(...)`) shared across three
fallback attempts: parallel (`parfor`), then non-parallel double precision,
then non-parallel single precision, each accumulating band results into it
with `+`. If Parallel is requested and any single band's worker throws (a
transient failure -- the code already anticipates and retries per-band OOM
errors one level in), the whole `parfor` errors out and is caught; MATLAB's
own documentation states a `parfor` reduction variable's value is
**undefined** after a mid-loop error -- it may already hold a partial sum
from whichever bands finished first. The code never resets the accumulator
to zero before the non-parallel fallback runs, which then adds the *full*
band set on top of whatever was already there, silently producing corrupted
(partially double-counted) output with no error surfaced anywhere. This only
manifests when the parallel path hits a transient failure, which is exactly
why it wouldn't reproduce on every run of otherwise-identical settings/data.
A second, unrelated issue in the same file: the wavelet high-pass filtering
step (`if gpuDeviceCount > 0`) silently tries GPU-double -> GPU-single ->
CPU-double -> CPU-single via bare `catch` blocks with no error surfaced and
is not gated by the Parallel option at all, so a machine with a GPU can
silently get different-precision results run to run regardless of that
setting.

Fix (in `AutoGEDAI.m`, since the vendored plugin itself is out of bounds):
`useParallel` now additionally requires `gpuDeviceCount > 0` --
`Parallel: 'yes'` is only actually honoured on a machine with a real GPU;
a GPU-less machine (this dev machine included -- confirmed `gpuDeviceCount
== 0` here, Parallel Computing Toolbox present but no physical GPU) always
runs GEDAI's non-parallel path regardless of the dialog choice, with a
console message explaining the downgrade. `opts.Parallel` itself is still
returned as the user's stated preference (not silently rewritten to 'no'),
so replaying the same settings later on a machine that does have a GPU can
still honour it there. The dialog option itself was considered for removal
outright but kept at the user's request. Reported upstream; revisit once
fixed there.

Verified end-to-end against the real (unmocked) GEDAI plugin with synthetic
data on this GPU-less machine: requesting `Parallel: 'yes'` prints the
downgrade message, actually runs GEDAI's serial per-band path (confirmed via
its own "processing wavelet band = N" progress output, only printed by the
non-parallel code path), completes without error, and `opts.Parallel` comes
back as `'yes'` (the request), not silently downgraded in the returned
settings.

## Full project audit (dead code, duplicated code, stale comments)

Requested directly: audit the whole project for duplicated code ("doublures"),
weird patterns, and comment/docstring accuracy, then bring `README.MD` back
in line with everything above. Surveyed every file under `src/` not already
covered by earlier entries in this log (two parallel Explore agents covered
`src/Transformations/*` and the vendored/support code respectively; the rest
read directly). Findings, split into what was fixed and what was only
flagged:

**Fixed (safe: broken feature, or pure comment/dead-code, no behaviour
change to anything actually reachable):**
- `src/@WorkSpace/load.m` called a bare `uigetfile2('*.wksp')` -- but
  `uigetfile2` only exists inside the `+uiextras` package, so this threw
  "undefined function or variable" outright. "Open WorkSpace" was broken.
  Fixed to `uiextras.uigetfile2(...)`, matching `save.m`'s already-correct
  `uiextras.uiputfile2(...)` call right next to it.
- `Transformations/ArtefactDetect/ArtefactDetect.m`: docstring (`%%
  Rereference the EEG data`) and error identifier (`Alakazam:ReRef`) were
  both copy-pasted from `ReRef.m` verbatim; a UI string typo ("Detaction")
  fixed alongside.
- `Transformations/+TransTools/CreateFilter.m`: the `'stop'` case's `% not
  yet implemented` comment was stale -- the code beneath it is fully
  implemented (`buttord`/`butter('stop')`). Removed the comment and two
  long-dead commented-out `buttord` lines; added a one-line note on why
  `'high'`/`'low'` map to `butter(...,'low')`/`butter(...,'high')`
  respectively (matches the "low cutoff = high-pass" EEG convention
  `IIRFilter.m`'s `LCF`/`HCF` naming already assumes -- almost certainly
  correct, just previously unexplained and landmine-looking).
- `Transformations/Fourier/Fourier.m`: removed dead GPU-experiment remnants
  (`gpuArray`/`gather` comments never actually exercised) and a vestigial
  `%ERROR! norm=1 ...` block that a real per-segment computation inside the
  loop (`norm = vunw/vwin`) already unconditionally overwrites before first
  use -- confirmed dead, not just unreachable in some branch. Docstring
  corrected: it documented `options.Output` values as `'Voltage'`/
  `'VoltageDens'`; the actual valid values (confirmed by opening
  `FourierGui.fig` and reading the real `OutPutRadio` button group's Tags)
  are `'Volt'`/`'Power'`/`'VoltDens'`/`'PowerDens'` -- the *code*'s
  `strcmpi` checks already used the correct short forms, so this was a
  docstring-only bug, not a functional one (the GUI's OK button always
  overwrites `options.Output` from the real selected button's Tag before
  the dialog returns, regardless of what seed value was passed in). Also
  documented that `Complex`/`Normalize`/`Compression`/`CompRes` are
  captured from the dialog but never actually consulted by the transform
  (only `FullSpectrum` is) -- toggling those controls currently has no
  effect; left unimplemented rather than guessing at intended behaviour.
  The inert `options.Output = 'Voltage'` seed default (both here and in
  `FourierGui.m`'s `OpeningFcn`) corrected to `'Volt'` for consistency.
- Verified `src/@cursor/@label/label.m` (nested class folder) is a stale,
  pre-`uiaxes` duplicate of `src/@label/label.m` (top-level) that is also
  completely unreachable: nothing inside `@cursor`'s own methods
  constructs a `label`, and the only real caller (`SignalView.m:493`) sits
  outside `@cursor`'s folder, so MATLAB's class-folder resolution always
  finds the top-level, already-`uiaxes`-fixed copy. Confirmed via `which`/
  grep, not removed (see "Flagged, not fixed" below).
- `README.MD`, `PROJECT_STRUCTURE.md`, `dependencies.md` brought back in
  line with the current architecture (see each file's own diff) --
  "toolstrip gallery" language, the App-Designer-not-Toolstrip requirement,
  the two-tree split, tile view, `AutoEyeICA`/`AutoGEDAI`, GEDAI/FastICA/
  ICLabel as dependencies, and the `+uiextras/+jTree`/`findjobj`/
  `uiinspect` dead-code findings below.

**Flagged, not fixed (real behaviour change, or removal of a whole file --
left for a deliberate follow-up rather than folded into an audit pass):**
- `Transformations/ReRef/ReRef.m`: replay is completely broken -- `opts` is
  hardcoded to `'Init'` regardless of the `init` argument, so dragging a
  ReRef branch onto another dataset always re-runs `pop_reref`'s own
  interactive-equivalent path rather than replaying the originally-chosen
  reference. Breaks the transformation contract every other transform
  follows.
- `Transformations/IIRFilter/IIRFilter.m`: a missing semicolon dumps a full
  data array to the console on one branch; an operator-precedence bug
  computes a variable (`sr`) that turns out to be dead/unused anyway; the
  Polarchannels filtering path hardcodes sample rate `130` instead of
  reading it from the data; one Polarchannels loop uses the *main* EEG
  data's dimensions as its bounds instead of Polarchannels' own (real
  out-of-bounds/mismatch risk if channel counts differ); the low/high-cutoff
  filter block is duplicated near-verbatim four times (EEG channels x2,
  Polarchannels x2) instead of one shared helper.
- `Transformations/SelectData/SelectData.m`: control-flow ordering makes
  `eval(options.Param)` run before the struct-wrapping normalisation that
  follows it, fragile if `options` ever reaches the replay branch without
  `.Param` already set; Polarchannels handling duplicated between the Init
  and replay branches instead of a shared helper.
- `Transformations/+TransTools/SelectWindow.m`: hardcodes every window to a
  fixed 100 samples regardless of `Window_Length`, inconsistent with
  `Fourier.m`'s own percentage-based sizing (`sizeofwin = floor((Window_
  Length/100) * nsamp)`); duplicates the same "window function by name"
  dispatch `Fourier.m` already has instead of sharing one implementation.
- `Transformations/ArtefactDetect/ArtefactDetect.m`: discards an entire
  channel-trial (sets the whole row to NaN) on a single threshold crossing
  anywhere in it, rather than just the offending samples -- likely
  intentional (matches "reject the whole epoch" conventions) but
  undocumented, so flagged rather than assumed.
- Dead files, not removed pending a decision: `src/@cursor/@label/label.m`
  (see above), `src/Icons/*.gif` (three tree-icon `.gif`s with zero
  references anywhere, superseded by the inline-SVG icon sets built this
  session), `src/+uiextras/+jTree/` (the old Java-Swing tree widget
  `WorkSpaceTree` replaced -- only referenced from comments explaining the
  replacement), `findjobj.m`/`findjobj_fast.m`/`uiinspect.m` (zero callers
  anywhere in `src/`, evidently left over from the old `ToolGroup` shell),
  `src/DefaultWorkSpace.wksp` (orphaned, diverged duplicate of the
  repo-root `DefaultWorkspace.wksp` -- the constructor loads the repo-root
  one, and even that only resolves because Windows filesystems are
  case-insensitive: the code asks for `'DefaultWorkSpace.wksp'`, capital
  S, but the file on disk is `DefaultWorkspace.wksp`, lowercase -- would
  fail to load on a case-sensitive filesystem).
- `README.MD`'s `ScreenShot.jpg` is confirmed stale: it shows the old
  MathWorks Toolstrip ribbon, a single undivided data-browser tree, and
  plots docked the old `ToolGroup` way -- none of which match the current
  UI. Needs a fresh screenshot from a running session; not something
  generatable from source alone.

## Follow-up pass: dead code removed, all flagged bugs fixed

Requested directly, following up on the audit above: remove the dead files
it found, and fix every flagged (not-yet-fixed) bug, with two explicit
constraints -- leave `ArtefactDetect.m`'s whole-channel-NaN behaviour alone
(it's a placeholder, not a bug to "fix"), and remove Polarchannels support
entirely rather than fixing its bugs, since it's no longer relevant.

**Removed:**
- `src/@cursor/@label/label.m` (stale, unreachable duplicate of
  `src/@label/label.m`), `src/Icons/*.gif` (three unreferenced icons),
  `src/+uiextras/+jTree/` (the tree widget `WorkSpaceTree` replaced, whole
  subpackage), `src/DefaultWorkSpace.wksp` (orphaned duplicate). The
  repo-root `DefaultWorkspace.wksp` was renamed (`git mv`) to
  `DefaultWorkSpace.wksp`, matching the exact casing `WorkSpace.m`'s
  constructor requests, fixing the latent case-sensitive-filesystem load
  failure noted above.
- `findjobj.m`/`findjobj_fast.m`/`uiinspect.m` turned out to not exist in
  the tree at all -- the previous audit pass's dead-code list (itself
  copied from `dependencies.md`'s own stale entry) was wrong about these
  still being present; `git log --all` shows they were removed in an
  earlier "repo legibility cleanup" commit. Corrected in `dependencies.md`
  and `PROJECT_STRUCTURE.md` rather than "removed" a second time.
- An unrelated accidental modification to `ScreenShot.jpg` (the Read tool
  displaying it as an image appears to have touched/re-encoded the file,
  87KB -> 489KB with no content change intended) was caught via `git
  status`/`git diff --stat` before finishing and reverted with `git
  checkout -- ScreenShot.jpg`.

**Polarchannels removed entirely** (`IIRFilter.m`, `SelectData.m`): this
also resolved every specific bug the audit found in that code, since all of
them lived inside the Polarchannels-only branches --
`IIRFilter.m`'s missing semicolon (console-spamming a full data array),
the `sr = (times(end)- times(1) / length(...))` operator-precedence bug
(the variable was unused regardless), the hardcoded sample rate `130`
instead of the real one, the loop that used the *main* EEG data's
dimensions to bound a loop filtering `Polarchannels.data`, and the
near-verbatim duplication of the whole Low/High-cutoff filter block. What
remained (the real EEG channel filtering) needed no further changes.
`SelectData.m`'s Polarchannels branches (`disp("No effect on
polarchannels")` included) were removed the same way.

**`ReRef.m` replay was completely broken**: `ropts` was hardcoded to
`'Init'` regardless of the `init` argument, and `EEG = pop_reref(EEG);`
only ever captured one output, discarding the command-history string a
replay would need -- so a dragged ReRef branch always re-ran EEGLAB's own
interactive-equivalent path instead of replaying the originally-chosen
reference, and the `init` parameter was accepted but never read at all.
Rewritten to follow the same `Name(input, opts)` / `'Init'` vs replay
pattern every other transformation (and the README's own worked example)
already uses -- `[EEG, opts] = pop_reref(EEG)` on the interactive path,
`eval(opts.Param)` on replay, with the same `~isstruct(opts)` defensive
normalisation `SelectData.m` has. Verified against the real `pop_reref`:
replaying a captured average-reference command actually changes the data
and sets `EEG.ref` correctly (previously it would have silently reopened
the interactive dialog instead).

**`SelectData.m`'s eval-before-normalise ordering** fixed: the
`if ~isstruct(options)` struct-wrapping now runs before `eval(options.
Param)`, not after, so a bare (non-struct) captured value reaching the
replay branch no longer risks erroring on `options.Param` before it's
guaranteed to exist. In the current Alakazam.m-mediated flow this was
always latent, not actually reachable (`Alakazam.onTransformation` already
wraps a bare captured value in `struct('Param', ...)` before ever storing
it), but the fix makes the function safe to call directly too.

**`SelectWindow.m`'s hardcoded-100-samples "inconsistency" with
Fourier.m**, on closer inspection, is not the bug it first looked like:
tracing through the concatenation math (`prev(1:end/2)` + a
`Window_Length`-sized flat run + `prev(end/2:end)`, then plotted against a
length-normalised x-axis) shows the *proportion* SelectWindow.m's preview
shows already tracks `Window_Length` correctly, just via a different
(fixed-edge-sample-count, variable-total-length) mechanism than Fourier.m's
own (`sizeofwin` scaled directly off `Window_Length`) -- changing the
numeric behaviour without being able to see the actual rendered preview
risked breaking something that works, so left alone (now with a comment
explaining the mechanism, since it isn't obvious from the code alone). What
*was* a real, safe-to-fix duplication: both files independently listed the
same 10 window types via a cascading `if strcmpi(...)` chain, a
maintenance hazard (add a window type to one and the other silently falls
behind). Extracted into a new shared `TransTools.WindowByName(type, n)`,
used by both `Fourier.m` (sized to the loaded signal, as before) and
`SelectWindow.m` (sized to the fixed 100-sample preview shape, as before).
Verified byte-identical output against calling each window function
(`hanning`, `hamming`, ...) directly for every type, including the
unrecognised-type fallback.

All of the above verified with `checkcode` (clean, aside from one
pre-existing, unrelated bracket-usage style warning in `IIRFilter.m` line 8
that predates this pass) and functional smoke tests where a real EEGLAB/
MATLAB code path was exercisable headlessly.

## README rewrite: EEG-only scope, corrected claims, added references

Requested directly: rewrite `README.MD` to be concise and technical (not
marketing copy) for a cognitive-science audience, link `bin_language.md`,
verify the "Broad format support" and transformation-library claims against
what actually exists, cite every toolkit actually used, and drop all
HRV/peripheral-physiology framing -- the project is EEG-only now.

**"Broad format support" was wrong.** `WorkSpace.open` (`open.m`) only ever
scans for `*.mat`, `*.vhdr`, and `*.set` -- confirmed against the three real
loaders (`loadMATFile`/`loadBVAFile`/`loadSETFile`). The README claimed XDF,
VU-AMS EDF, CARSPAN, Cortrium C3 and TMSi Poly5 too; `dependencies.md`
already said otherwise ("the app now reads only BrainVision files ... and
previously-saved `.mat` datasets") but the README was never brought in line
with that note. Corrected to the three real formats; also fixed
`loadMATFile.m`'s own docstring along the way (copy-pasted from
`loadBVAFile.m`, claimed to be "the eeglab function reading Brainvision
files" -- it's a plain `load('EEG')`, not an EEGLAB reader at all).

**The transformation-library description was stale**, listing "Poincare /
HRV metrics, EMG, ICG/PEP, and respiration" -- none of which correspond to
anything in `src/Transformations/` (confirmed against all 11 folders'
`.json` manifests). Leftover from before the project narrowed to EEG only;
`ScalpDistribution.m`'s own docstring already documents this transition
accurately ("now removed from development, still on main) PoinCare
transformation" -- left as-is, it's correct history, not a stale comment).
Replaced with the real, current library (`IIRFilter`, `ReRef`, `SelectData`,
`DefineBins`, `Baseline`, `Average`, `ArtefactDetect`, `AutoEyeICA`,
`AutoGEDAI`, `Fourier`, `ScalpDistribution`), each described from what its
code actually does, not its (sometimes terser or stale) `.json` blurb.

**Caught one conflation while drafting**: an early version of the rewrite
credited `Average` with "grand averages" -- but grand averaging (combining
several subjects) is a separate mechanism (`GrandAverage.m`/
`GrandAverageDialog.m`, its own ribbon tab, no `.json` manifest, not
discovered as a transformation plugin at all), confirmed by reading
`Average.m` in full: it only ever averages one dataset's own epoched
trials (optionally per-bin, including bin-difference/interaction
contrasts). Fixed in all three places it had leaked into (the Key features
bullet, the Transformations table row, and the ERPLAB reference).

**Overview and Key features rewritten** to drop the peripheral-physiology
framing entirely (ECG/HRV, ICG/PEP, respiration, blood pressure,
electrodermal activity) and the "interbeat intervals" mention in the Fast
plotting section, generalised to "events and marked artefacts" -- the
underlying overlay code (`SignalView.drawIbiMarkers`, reading
`EEG.IBIevent`) still exists and still works if that field happens to be
present, so it wasn't touched, just no longer given top billing in
EEG-focused documentation.

**References**: added citations for every toolkit actually used --
ERPLAB (methodological model for `DefineBins`/`Average`/`GrandAverage`, not
a runtime dependency), GEDAI, ICLabel, FastICA, EEGLAB itself, GUI Layout
Toolbox, and mlapptools -- plus a link to
[`bin_language.md`](src/Transformations/DefineBins/bin_language.md) from
the `DefineBins` table row. `dependencies.md`'s Ledalab/MoBILAB entries
(zero references anywhere in `src/`, leftover from the same
broader-physiology-scope era) dropped with an explanatory note rather than
silently deleted.

`ScreenShot.jpg` is still the stale pre-migration one flagged in the audit
above; the user will supply a fresh one separately.

## Workspace persistence: MAT/prefs -> JSON, for two different files

Requested directly: "the workspace file" (`.wksp`) should be JSON, not
MATLAB's `.mat` format. Led to a second, related question once the user
learned `AlakazamSettings` persists via `setpref`/`getpref` (MATLAB's own
opaque per-user preferences store, not a file you can open/diff/back up) --
they wanted that as a plain JSON file too. Two genuinely separate stores,
same underlying ask; converted both.

**`.wksp` session files** (`WorkSpace.save`/`load`, and the app's own
`DefaultWorkSpace.wksp` at the repo root, read by `WorkSpace.m`'s
constructor): were literally `save(...)`'d MAT files wearing a `.wksp`
extension. `save.m`/`load.m` now `jsonencode`/`jsondecode` a plain
`{RawDirectory, CacheDirectory, ExportsDirectory}` object instead (still
through `toStoredPath`/`fromStoredPath` for the `~`-portable-path
encoding, unchanged) -- the `.wksp` extension itself is kept (it's a
meaningful, already-established file-picker filter, matching what the
user asked: JSON *format*, not necessarily a `.json` *extension*).
`save.m` also gained a guard for a cancelled save dialog (`Name == 0`),
matching the guard `load.m` already had -- the original had none, and
would have errored trying to save to a nonexistent path.

The repo's own `DefaultWorkSpace.wksp` was converted in place (loaded via
the old `'-mat'` form one last time, re-written as JSON with the exact
same three directory values, verified byte-for-byte against the original
via a headless round-trip before commit-worthy).

**`AlakazamSettings`** (`Group`/`PrefKey` -> `setpref`/`getpref`): replaced
with a `SettingsFile` constant (`fullfile(prefdir, 'AlakazamSettings.json')`
-- same per-user MATLAB-managed directory `setpref` already used
conceptually, just a plain readable file instead of the opaque prefs
store) and `jsonencode`/`jsondecode` in `save()`/`refresh()`. The
existing "no stored value yet -> schema defaults" merge behaviour
(`buildValues`) needed no changes -- it already treated the stored side as
an arbitrary struct, and `jsondecode` produces exactly that.

**Breaking, deliberately**: neither conversion reads the old format as a
fallback. An existing `.wksp` file saved before this change, or settings
already stored via the old `setpref`, will not load -- per this project's
own stated approach (change the code, don't add compatibility shims), and
because both are cheap for the user to redo (Save WorkSpace again; Settings
dialog reopens at schema defaults until Save is pressed once).

**Also fixed in passing**: `PROJECT_STRUCTURE.md` claimed `AlakazamSettings`
persists to `~/workspace.json` -- traced this to cross-contamination from
the *spectHR* project's own CLAUDE.md (which really does describe that
filename, for a different project entirely) leaking into a description I
wrote in an earlier pass of this file, since both projects' context are
present in the same session. `AlakazamSettings.m`'s own docstring (line 5,
"mirroring the spectHR settings layout") shows the confusion wasn't
groundless -- the *design* is deliberately modelled on spectHR's, just not
under spectHR's exact filename. Corrected to the real path.

Verified end-to-end: the real `WorkSpace` class (not a reimplementation)
constructed against the actual repo-root `DefaultWorkSpace.wksp`, confirmed
it read real directory values; a manual save/load round-trip (the
`uiextras.uiputfile2`/`uigetfile2` calls inside `save.m`/`load.m` are
interactive dialogs, not headlessly callable, so this replicates their
exact internal logic) confirmed byte-for-byte directory fidelity through
`toStoredPath -> JSON -> fromStoredPath`, and confirmed the file on disk is
real JSON text, not a MAT binary wearing a `.wksp` extension.
`AlakazamSettings`: set a real schema value, saved, forced a fresh
singleton via `reload()`, confirmed the value survived and the on-disk
file is genuine JSON; deleted the file and confirmed a fresh instance falls
back to schema defaults (the first-run case). No leftover test artifacts
on disk afterward (checked before and after against the real
`prefdir()/AlakazamSettings.json` path, since there's no way to redirect a
`Constant` property to a temp location for the test).

## TransformSettings: per-transformation options remembered per workspace

Proposed as an exploratory question ("when a user changes a transformation's
setting, should it become the new default, saved/loaded with the
workspace?"), answered with a recommendation (start with `DefineBins` --
it already half-does this via a machine-wide `setpref`, not workspace-
scoped -- prove the mechanism there before rolling out further), then
built on "your call".

**The missing piece**: transformations are invoked via a bare `feval(
transformId, EEG)` (`Alakazam.onTransformation`) -- the transformation
function itself has no reference back to `WorkSpace` or `Alakazam`, so it
had no way to ask "what does the current workspace remember for me?" at
all. `AlakazamSettings` already solved an analogous problem (global static
access from anywhere, no object reference needed) for machine-wide
settings; `src/TransformSettings.m` is the same lazy-singleton `get`/`set`
shape, but deliberately *not* machine-wide -- it's supposed to answer "what
does *this* workspace remember", so switching workspaces should show
different stored options, unlike `AlakazamSettings`.

**Design**: `TransformSettings.get(transformId)` / `.set(transformId,
opts)`, keyed by transform id (a dynamic struct fieldname -- always a valid
MATLAB identifier, since it's a transformation's own folder/entry-function
name). No fixed schema, unlike `AlakazamSettings`: each transformation's
stored value is whatever struct shape it chooses (DefineBins stores
`{script, epochStart, epochStop}`; a future transform might store a flat
`settingsdlg`-shaped struct). Three more static entry points thread it
through the workspace lifecycle: `reset()` (a brand-new/fresh workspace),
`loadFrom(values)` (populate from a loaded `.wksp` file's own
`TransformSettings` field, tolerating an old-format file with no such field
by resetting instead of erroring), and `allValues()` (for `WorkSpace.save`
to serialise). Wired into exactly three places: `WorkSpace.m`'s constructor
(both the default-workspace-on-startup path and the explicit-directories
path reset/seed it), `load.m` (`loadFrom` before `open()`), and `save.m`
(`allValues()` folded into the same JSON object the directories already
serialise into -- one more field, no new file).

**`DefineBins.m` migrated** off its own `setpref('Alakazam',
'DefineBinsScript', ...)` / `setpref('Alakazam', 'DefineBinsEpoch', ...)`
pair (machine-wide, survived across every workspace indiscriminately) onto
`TransformSettings.get/set('DefineBins', ...)`, preserving an original,
deliberate asymmetry rather than "simplifying" it away: the epoch bounds
are remembered as soon as the dialog closes (in `promptForScript`, before
the script is even parsed), but the script text is only remembered *after*
`parseSpec` succeeds (back in the main function) -- so a typo elsewhere in
an otherwise-fine script never overwrites a previously-good remembered
script, but does not lose the (separately valid) epoch bounds either. Both
writes read-modify-write the *same* stored struct rather than blindly
overwriting it, so setting one field can never clobber the other.

**Not done in this pass** (deliberately, matching how `TransformSettings`
was scoped from the start -- "start with `DefineBins`, prove the mechanism,
roll out to the rest afterward"): the other ~10 transformations still seed
their dialogs from hardcoded literals every time. Each would need the same
small edit `DefineBins.m` got (read `TransformSettings.get(id)` as the
dialog's seed if present, `TransformSettings.set(id, opts)` after a
successful interactive run) -- mechanical, but real work per file, held
back until this pilot is confirmed to feel right in actual use.

Verified: a fresh workspace seeds `DefineBins`' built-in template and
default epoch bounds; the real (non-dialog) script-mode replay path
confirmed to *not* write to `TransformSettings` (only a genuine interactive
run should); remembering a script and remembering epoch bounds confirmed
not to clobber each other in the same stored struct; a full JSON
round-trip (mirroring `WorkSpace.save`/`load`'s own mechanism exactly)
confirmed both survive. A separate end-to-end test built a real `WorkSpace`
object, stored settings for *two different* transformations
(`DefineBins` and a hypothetical `AutoGEDAI` entry), saved through
`save.m`'s exact body, reset `TransformSettings` to prove nothing survived
in memory, then loaded through `load.m`'s exact body and confirmed both
transformations' settings came back correctly and independently.

## Toolbox availability check (Signal Processing, Statistics and Machine Learning)

The user pointed out Alakazam also needs the Signal Processing Toolbox and
the Statistics and Machine Learning Toolbox, and asked for this to be
documented in the README and checked at startup, informing the user if
either is missing.

Signal Processing Toolbox usage is real and confirmed by grep: `filtfilt`,
`butter`, `buttord` in `TransTools/CreateFilter.m` and
`Transformations/IIRFilter/IIRFilter.m`, and the taper-window functions
(`hanning`, `hamming`, `bartlett`, `blackmanharris`, `bohmanwin`,
`nuttallwin`, `parzenwin`, `rectwin`, `triang`) in
`TransTools/WindowByName.m`. An extensive grep for common Statistics and
Machine Learning Toolbox function names across `src/` found no direct hits
-- the dependency, if real, is transitive through EEGLAB or its plugins,
not visible in Alakazam's own code. Trusted the user's explicit statement
regardless (project owner, and toolbox boundaries aren't always visible
from this repo alone).

Added `EEGLabEnvironment.ensureToolboxes()`, called from the existing
`ensure()` alongside `ensureEEGLab()`/`ensurePlugins()`. Unlike EEGLAB
itself (offered as a one-click download) or the EEGLAB plugins (installed
via `plugin_askinstall`/`installFromZip`), a MATLAB toolbox cannot be
silently installed here -- it needs a licence and MATLAB's own Add-On
Explorer -- so this check only informs, never installs: it probes each
toolbox via a representative function (`butter` for Signal Processing,
`pca` for Statistics and Machine Learning, mirroring the existing
`Plugins` registry's `which(probeFcn)` pattern) and, if anything is
missing, shows one consolidated `warndlg` naming every missing toolbox and
why Alakazam needs it, then lets startup continue -- matching the existing
"plugin/FastICA failures warn rather than abort" philosophy rather than
EEGLAB's hard-fail treatment, since the user asked to "inform," not block.

Verified on this dev machine, which turned out to have exactly one of the
two toolboxes installed (Signal Processing present, Statistics and Machine
Learning absent) -- a genuine, convenient real-world test of both branches
of the detection logic without needing to fake anything: `which('butter')`
resolved, `which('pca')` did not, and the missing-toolbox message built
correctly for the absent one only.

`README.MD`'s Getting started section now lists both toolboxes in the
Requirements line (with what each is used for) and notes the startup
check. `PROJECT_STRUCTURE.md`'s `EEGLabEnvironment` row updated to mention
the toolbox check alongside the existing plugin-install description.

## TransformSettings rolled out beyond DefineBins

Following up on the pilot, the user asked to roll `TransformSettings` out
to the other transformations, the same way `DefineBins` already works.

Went through every transformation folder and checked whether it actually
had Alakazam-side hardcoded dialog defaults to remember:

- **`ArtefactDetect`, `AutoEyeICA`, `Baseline`**: straightforward -- each
  builds a `uiextras.settingsdlg` call with literal numeric defaults.
  `TransformSettings.get(id)` now seeds those literals (falling back to
  the original hardcoded values the first time), and the dialog's result
  is written back via `TransformSettings.set(id, ...)`.
- **`AutoGEDAI`**: same idea, but four of its eight fields are
  `settingsdlg` popups (cell-array choices, e.g. `{'auto','auto+','auto-'}`),
  which default to whichever entry is *first* in the list -- including the
  existing `hasParallelToolbox`-based reordering of the Parallel choice.
  Added a small `putFirst(choices, value)` local helper that moves a
  remembered value to the front of its own choice list (leaving the list
  unchanged if the value isn't a member, e.g. a stale `Parallel` value from
  a workspace saved on a different machine), so every field's remembered
  choice becomes the popup default without losing any of the other
  selectable choices.
- **`Fourier`**: `FourierGui(options)` already accepted an options struct
  as a seed, but reading `FourierGui_OpeningFcn` closely showed it only
  stores the passed-in struct into `handles.options` -- it never pushes
  those values onto the actual visible controls (the radio button groups,
  checkboxes, edit boxes). So a seeded options struct was silently a no-op
  for every field a callback subsequently overwrites from the *control's*
  own state (Resolution, Output, Complex, FullSpectrum, Normalize,
  Interval, ResVal) -- only the untouched fields (Window, Window_Length,
  Compression, CompRes, Name) actually carried through. Fixed by adding a
  `syncControlsFromOptions(handles)` local function, called once from the
  opening function, that sets each control from `handles.options` the
  same way `OK_Button_Callback` reads it back out (button-group
  `SelectedObject` found by child `Tag` for Resolution/Output, checkbox
  `Value` for Complex/FullSpectrum/Normalize, edit-box `String` for
  Interval/ResVal) -- without this fix, wiring `TransformSettings` into
  `Fourier.m` alone would have remembered settings that never visibly
  affected the reopened dialog. `Fourier.m` itself merges
  `TransformSettings.get('Fourier')` field-by-field onto its hardcoded
  defaults struct (so a stored value predating a newer schema field still
  falls back to that field's literal default) before calling `FourierGui`,
  then saves the result back.

**Deliberately left unwired**, each for a concrete reason rather than time
pressure:
- **`Average`**: `opts` is accepted but never actually used by the
  algorithm at all -- there is nothing to remember.
- **`IIRFilter`**: its dialog is `IIRFilterApp.mlapp`, a binary App
  Designer container, not a plain `.m` file -- there is no safe way to
  hand-edit its control defaults the way `FourierGui.m`'s plain-text
  GUIDE callbacks could be. Would need reopening the file in MATLAB's own
  App Designer.
- **`ReRef`, `SelectData`**: both delegate entirely to EEGLAB's own
  interactive dialogs (`pop_reref`, `pop_select`) via `pop_*(EEG)` with no
  seed argument -- there is no Alakazam-side default to seed in the first
  place.
- **`ScalpDistribution`**: a pure-plot transformation (see its own
  docstring) with no options dialog at all -- confirmed unchanged, per
  the earlier explicit instruction to leave this file alone; it needed no
  edit here regardless, since there was nothing to wire.

Verified headlessly (the dialogs themselves block on `uiwait`, so as with
`DefineBins`, this replicates each transformation's exact surrounding
logic against a real `TransformSettings` store rather than driving the
GUI): store/retrieve for `ArtefactDetect`, `AutoEyeICA`, `Baseline`;
`AutoGEDAI`'s `putFirst` reordering (including the "value not a member"
no-op case) and all eight of its fields round-tripping; `Fourier`'s
field-by-field merge onto its hardcoded defaults with a partial stored
struct (confirming an unset field keeps its literal default rather than
going missing); and a single JSON round-trip (mirroring
`WorkSpace.save`/`load`'s own mechanism) carrying all five transformations'
settings at once. `FourierGui.m`'s new `syncControlsFromOptions` itself
could not be exercised this way (it only runs inside the blocking, visible
dialog) -- its correctness rests on mirroring `OK_Button_Callback`'s own
Tag/Value/String reads exactly, not on a runtime test; recommend
confirming visually on the next interactive run that reopening Fourier
shows the previously-chosen Resolution/Output/window/etc.

`checkcode` clean on all six touched files (`ArtefactDetect.m`,
`AutoEyeICA.m`, `AutoGEDAI.m`, `Baseline.m`, `Fourier.m`, `FourierGui.m`)
-- the "input argument might be unused" notes `checkcode` reports on
`FourierGui.m` are pre-existing GUIDE-callback boilerplate (`hObject`,
`eventdata` on every callback), confirmed by running `checkcode` against
the pre-session base revision, not anything from this change.

## Fixed: a freshly opened continuous plot could look wrong until zoomed

The user reported a recurring problem: right after running a transformation,
the newly opened plot sometimes "doesn't look like EEG" -- but zooming in
and back out fixes it. Correctly guessed this was related to the
MinMaxPyramid decimation carrying over something stale, and asked for it
to be tracked down.

Root cause, confirmed empirically (not just by inspection): `SignalView`
samples its axes' real pixel width (`AxWidthPx`, read from
`this.Axes.Position`) during construction, to decide how many min/max
buckets to decimate the visible window into. `AlakazamPlotter.plotCurrent`
built the view *before* selecting its new tab (`app.PlotsTabGroup.
SelectedTab = newTab` ran only after `plotContinuous`/`plotEpoched`
returned) -- and a `uitab`'s content reports a stale placeholder size
while it is not the group's `SelectedTab`, confirmed directly: a bare
`uiaxes` inside an unselected tab reported `Position = [10 10 400 300]`
regardless of the real container size, even after `drawnow`, and only
picked up its true size once that tab actually became selected. So the
very first decimation `SignalView` computes uses a placeholder ~400px
width instead of the real one (often ~900px+), producing a visibly wrong
envelope -- too few buckets for the true window, i.e. an aliased-looking
plot. The very next user interaction (zoom or pan slider) calls `redraw()`
again, by which point the tab *is* selected and the width is correct, so
the plot self-corrects -- exactly matching "zooming a bit in/out restores
the correct view."

This is specific to `SignalView` (continuous data): `EpochView`,
`AverageView` and `FourierView` were checked and none of them sample axes
pixel width the same way, so none of them share this bug.

Fixed in `AlakazamPlotter.plotCurrent`: after selecting the new tab and
calling `refreshPlotsView()` (which also retiles into `TileGrid` when in
Grid/Stack mode -- the tiled case has the identical problem, since a tab's
content is reparented into its tile only inside `retile()`, likewise after
the view was already constructed), one more `drawnow` + `view.redraw()`
runs once the view is genuinely in its final visible location, whether
that is the now-selected tab (Tabs mode) or its tile (Grid/Stack mode).
`SignalView.m` itself is untouched -- its own constructor still does its
existing pre-layout/post-layout double redraw, which remains correct and
useful for the normal case where a tab is already selected when its
content is built (e.g. it's the very first tab opened).

Verified two ways:
1. Directly reproduced the underlying MATLAB behaviour: a `uiaxes` inside
   a not-yet-selected `uitab` reports a placeholder `Position` regardless
   of the real container size, confirmed correct only once selected.
2. Built a real `SignalView` inside a not-yet-selected tab (mirroring the
   old, buggy construction order) on a genuinely visible `uifigure`
   (an *invisible* test figure was tried first and did NOT reproduce the
   bug -- MATLAB resolves full layout eagerly when nothing is actually
   being rendered on screen at all, so the repro needs a visible window,
   matching the real app): confirmed `AxWidthPx` reads the placeholder
   value (400) while hidden, then confirmed it reads the true value (894,
   matching the figure's real width) after selecting the tab and calling
   the same trailing redraw the fix now adds.

`checkcode` clean on `AlakazamPlotter.m`.

## Friendly transformation-error dialog

The user pasted a real failure: clicking Baseline on a continuous (not yet
segmented) dataset produced a working but terse message ("Problem in
Baseline: Data not Segmented") *and* a full raw MATLAB stack trace dumped
to the command window on top of it, and asked for "another great, overly
friendly and informative error/warning system."

Root cause of the stack-trace spam: `Alakazam.onTransformation`'s catch
block already called `warndlg(ME.message, "Error in transformation")` --
so the user WAS being told -- but then `rethrow(ME)` right after, which is
what actually produced the scary console dump (an uncaught error inside a
uihtml-ribbon callback chain prints its full stack trace via
`appdesservices...executeUserCallback`). There is nothing above
`onTransformation` in that call chain that does anything useful with a
rethrown error -- it is the top of the ribbon's callback dispatch -- so
rethrowing served no purpose beyond the noise.

Fixed:
- `onTransformation` no longer rethrows; the dialog is now the only, and
  sufficient, way the user is told what happened.
- Replaced the plain `warndlg` with a new `Alakazam.showTransformationError
  (transformId, ME)`, using `uialert(this.MainFigure, ...)` (matching this
  session's earlier shell rewrite towards a single modern uifigure, and the
  precedent `GrandAverageDialog`/`DefineBins` already set for `uialert` on
  their own dialogs) with a warning icon and a title naming the
  transformation. Every Alakazam-authored guard clause writes "Problem in
  &lt;Transform&gt;: ..."; that prefix is stripped before display since the
  dialog's own title already names the transform. For an error that is
  *not* an `Alakazam:...` identifier (an unguarded native MATLAB error,
  e.g. a transformation with no explicit data-format check that just
  crashes on a shape mismatch), a generic hint is appended: this is almost
  always still a data-format mismatch in practice, so the same general
  "this step needs segmented / averaged / frequency-domain data" nudge a
  proper guard clause would have given is shown anyway, rather than a bare
  MATLAB error string with no context at all.
- `transformId` is now computed before the `try` block (was inside it),
  purely so it is always defined in the `catch` block -- previously an
  error before that line would have left `transformId` undefined,
  crashing the handler itself.
- Improved the two weakest guard messages the user actually hit --
  `Average.m` and `Baseline.m`'s "Data not Segmented" / "Trials not
  specified" / "No Correct Data Supplied" checks -- to explain what is
  needed and what to do (e.g. "Segment it first (e.g. with DefineBins),
  then run Baseline on the segmented result"), matching the tone the
  already-good guard messages elsewhere (`AutoEyeICA`, `AutoGEDAI`,
  `ScalpDistribution`) already use. Left every other transformation's
  existing messages alone -- most were already this descriptive; the
  central dialog now presents whatever they say more calmly regardless.

Deliberately did not add new precondition/data-format guards to
transformations that don't have one today (`Fourier`, `IIRFilter`,
`ReRef`, `SelectData`, ...) -- auditing every transformation's valid input
shapes is a much larger effort than what was asked, and the new central
handler already gives a reasonable, friendly experience for *any* error
any of them throws, guarded or not, via the native-error hint above.

Verified: reproduced the user's exact scenario (`Baseline` on a 2D
`CONTINUOUS` dataset) and confirmed the improved message text; replicated
`showTransformationError`'s own prefix-stripping and message-construction
logic against that real exception (confirmed the prefix is fully
stripped, and that an `Alakazam:...`-identified error does NOT get the
generic native-error hint appended, while a plain `MATLAB:...`-identified
exception does); and smoke-tested that `uialert` itself renders without
error given the constructed message, in a real (visible; an offscreen one
was tried first and `uialert` refused it outright with "Figure handle
'Visible' value must be 'on'") `uifigure`. `checkcode` clean on
`Alakazam.m`, `Average.m`, `Baseline.m`.

## Tree splitter and a hand-drawn Grand Average icon

Two requests: a resizable divider between the two workspace trees (like
the existing tree/plots divider), and a proper hand-drawn icon for the
ribbon's "Define Grand Average..." button.

**Tree splitter**: `TreeGrid` (Alakazam.m's setupMainWindow) was a 2-row
uigridlayout (`RowHeight = {'2x', '1x'}`, `RowSpacing = 4`) with no way to
adjust the split at runtime. Changed to 3 rows -- `DataTreePanel` |
splitter | `GrandAveragesTreePanel` -- with `RowSpacing = 0` (the splitter
row itself now provides the visual gap, the same reasoning the
tree/plots splitter's `MainGrid` already uses with `ColumnSpacing = 0`).
The splitter is a thin (3px) `uipanel` with the exact same hand-rolled
drag pattern as the existing tree/plots divider
(`beginTreeResize`/`dragTreeResize`/`endTreeResize`): a plain
`uigridlayout` has no built-in resizable divider, so
`beginTreesSplitResize` wires `MainFigure.WindowButtonMotionFcn`/
`WindowButtonUpFcn` on mouse-down, `dragTreesSplitResize` live-resizes
`TreeGrid.RowHeight{1}` (pixels) to track the mouse (row 3, Grand
Averages, stays `'1x'` and fills the remainder), clamped so neither panel
can be dragged to nothing, and `endTreesSplitResize` stops tracking on
mouse-up.

Verified headlessly: built the same 3-row structure directly, confirmed
`Data & Analyses` gets more height than `Grand Averages` under the
default 2x/1x split, replicated `dragTreesSplitResize`'s clamp math at the
top/bottom/mid-drag positions (`WindowButtonMotionFcn` callbacks can't be
driven headlessly), and confirmed setting `RowHeight{1}` actually resizes
the panel on screen. Getting real (non-placeholder) `Position` values out
of a freshly built, deeply nested `uigridlayout` tree needed more settling
time than a single `drawnow` here (a `pause` plus a second `drawnow`,
occasionally with a 1px figure-size nudge to force a relayout pass) --
consistent with the same "layout needs to actually settle" lesson the
SignalView initial-width fix uncovered earlier this session, just a
deeper case of it.

**Grand Average ribbon icon**: `grandAverageItems` was still using a
borrowed MathWorks toolstrip PNG (`control_app_24.png`, a generic "app"
icon, resolved via `iconRoot = fullfile(matlabroot, 'toolbox', 'matlab',
'toolstrip', 'web')`) -- the same category of mismatch `workspaceItems`
and `viewItems` were already fixed for earlier this session. Replaced with
a hand-drawn inline SVG matching the ribbon's own style (24x24 viewBox,
`#4a7fc9` stroke, `fill="none"`): three thin mini-waveforms (individual
subjects' averages) converging into one bold waveform (the grand
average) -- the icon depicts the feature itself. `iconRoot` and the
`grandAverageItems(this, iconRoot)` parameter were both dead once nothing
else used them, so removed; `encodeIcon` itself stays (still used for each
transformation's own bundled PNG icon in `transformationGroups`).

Verified: rendered the SVG standalone to check it reads cleanly at both
24px and larger sizes; a headless test built a real `AlakazamRibbon`,
confirmed the Grand Average tab's icon is a well-formed base64 SVG data
URI (not an empty/broken `encodeIcon` fallback), decodes to valid SVG
matching the 24x24/`#4a7fc9` convention, and contains no leftover
reference to `control_app_24`. `checkcode` clean on `Alakazam.m` and
`AlakazamRibbon.m`.

## Hand-drawn icons for every transformation

Following the Grand Average icon, the user liked the style enough to ask
for the same treatment for every transformation in the Tools tab.

Confirmed first (by actually looking at a few) that every transformation's
existing `<Name>.png` was the same kind of mismatched, generic clip-art
already fixed elsewhere in the ribbon this session (workspaceItems,
viewItems, settingsItems, grandAverageItems) -- e.g. `ArtefactDetect.png`
was an unrelated padlock-ish glyph, `Average.png` three vertical sliders,
`DefineBins.png` a generic gear/refresh combo. All 11 are `24x24` RGBA
PNGs (confirmed via `imfinfo`/`imread`), referenced by each
`Transformations/<Name>/<Name>.json` manifest's `Icon` field, and read by
**two** independent consumers that both already existed and needed no
code changes: `AlakazamRibbon.transformationGroups` (via `encodeIcon`,
the Tools tab) and `WorkSpaceTree.iconForResult` (the same PNG, scaled
down, for that transformation's result nodes in the tree) -- this
directly confirms the earlier answer to "if I create a new Transformation,
will the new icon match?": yes, both places read the one manifest-referenced
file automatically, so this was a pure asset swap, no `.m` edits needed
beyond what Grand Average's own change already made.

One motif per transformation, matching the ribbon's own convention
(`#4a7fc9` stroke, `fill="none"`, minimal line art), literal where the
domain gives an obvious visual and abstract-but-consistent otherwise:
`ArtefactDetect` (dashed threshold lines, a signal spike breaking one,
flagged with a dot), `AutoEyeICA` (an eye with a removal slash),
`AutoGEDAI` (a clean wave with a sparkle -- denoising, not literal
filtering, to read differently from IIRFilter), `Average` (two faint
overlapping trial traces collapsing into one bold trace -- deliberately
distinct from Grand Average's converging-funnel motif, since Average
combines one subject's trials and Grand Average combines several
subjects' averages), `Baseline` (a shaded baseline window plus a dashed
zero-reference line), `DefineBins` (a timeline split by two dividers into
three event-bearing bins), `Fourier` (a time-domain wave, an arrow, and a
small spectrum bar chart), `IIRFilter` (a funnel: a noisy wave entering
the wide end, a smooth curve leaving the narrow end), `ReRef` (four
electrode nodes with dashed lines to one bold central reference node),
`ScalpDistribution` (a head with ears/nose and concentric topomap
contours, matching real topoplot conventions), `SelectData` (three
channel-row lines under a dashed selection marquee).

Rendering pipeline: designed each as an SVG (same coordinate/style
convention as the ribbon's other inline icons), then rasterized to a real
24x24 RGBA PNG via a headless browser canvas (`drawImage` a 4x-supersampled
render down to 24x24 for antialiasing, `canvas.toDataURL('image/png')`) --
this reuses the browser's actual, correct SVG renderer rather than
reimplementing stroke/cap/join rendering by hand in MATLAB. `file://` and
`data:` URL navigation are both blocked in this environment's browser
tool, so the HTML/JS doing the rendering was served over a throwaway local
`python -m http.server` in the scratchpad instead.

Caught a real transcription bug this way: hand-copying the browser's
returned base64 JSON blob into a file introduced a single silently-flipped
byte in `ReRef.png` specifically (same length, different bytes -- not
caught by eye, only by MATLAB's own PNG reader raising `IDAT: CRC error`).
Re-fetched that one icon's data fresh from the still-open browser tab and
rewrote just that file rather than trusting the hand-copy again. Learned
from this: re-verified every one of the 11 files afterward with a real
decode (`imread`, which checks the CRC), not just a visual glance, since a
subtly wrong-but-still-valid-looking icon would not have been caught by
eye at 24x24 either.

Verified: all 11 files decode cleanly (`imfinfo`/`imread`, valid CRC,
24x24 RGBA); a real `AlakazamRibbon` build confirmed every one of the 11
transformation icons flows through as a well-formed base64 PNG data URI
in the Tools tab. Rendered a labelled review grid of all 11 at a larger
size for a visual sanity check before finishing.

## webtree/ moved under src/, and a src/Icons/ source directory

Two housekeeping requests: move `webtree/` (previously at the repo root)
into `src/`, and save the hand-drawn icons' actual SVG source somewhere
persistent instead of only as inline string literals in `AlakazamRibbon.m`
or, for the transformation icons, only as already-rasterized PNGs with no
source ever kept at all.

**`webtree/` -> `src/webtree/`**: `git mv webtree src/webtree` (the
untracked `node_modules/`/`dist/` moved along with it as a normal
filesystem rename). Updated every reference: `.gitignore`'s two
`webtree/node_modules/`/`webtree/dist/` lines needed the `src/` prefix too
-- git's gitignore patterns containing a slash are anchored to the
`.gitignore`'s own directory, so the old patterns silently stopped
matching anything once the folder moved a level deeper (confirmed: `git
status` showed them as newly untracked `??` entries rather than properly
ignored, until fixed). Also updated `src/webtree/README.md`'s relative
link and `cd`/`cp` instructions, `PROJECT_STRUCTURE.md`, `dependencies.md`,
and the doc-comment mentions in `AlakazamRibbon.m` and `WorkSpaceTree.m`.
`migration.md`'s own historical entries were left as-is (a dated log of
what was true when written, not living documentation).

Actually verified the move works, not just that the paths read correctly:
Node.js turned out to be installed on this machine after all (an earlier
session's plan-mode note claiming none was available was itself stale or
specific to a different environment) -- ran the real `npm install && npm
run build && npm test` from the new `src/webtree/` location. The freshly
built `dist/alakazam-tree.html` came out byte-identical to the committed
`src/WorkSpaceTree.html` once line endings were normalised (the only
difference was LF vs. the checked-out file's CRLF, the same benign
autocrlf effect noted elsewhere in this file), and the full jsdom test
suite (render/click/double-click/context-menu/drag/Ctrl-revert) passed
unchanged.

**`src/Icons/`**: added one `.svg` file per hand-drawn ribbon icon -- the
9 ribbon-chrome ones (`OpenWorkspace`, `SaveWorkspace`, `EditWorkspace`,
`ClearWorkspace`, `Settings`, `ViewTabs`, `ViewGrid`, `ViewStack`,
`GrandAverage`) and the 11 transformation ones. The transformation icons'
*rasterized* PNG (`Transformations/<Name>/<Name>.png`) stays the actual
runtime artifact -- `WorkSpaceTree.iconForResult` needs a raster image for
tree-node icons, and nothing auto-regenerates a PNG from an edited `.svg`
-- so `src/Icons/<Name>.svg` there is documentation/source only, not wired
to anything; regenerate the PNG by hand (the same browser-canvas
rasterization pipeline used to create them) after editing the SVG.

For the 9 ribbon-chrome icons, rather than leaving them ALSO merely
duplicated (the file existing separately from the string still embedded
in `AlakazamRibbon.m`, free to drift out of sync), refactored
`workspaceItems`/`settingsItems`/`viewItems`/`grandAverageItems` to read
the `.svg` file directly at construction time via a new `encodeSvgFile`
method -- the SVG counterpart of the existing `encodeIcon(pngPath)`, which
already reads a transformation's PNG from disk the same way. `buildTabsData`
now resolves `iconsDir` once (`fullfile(fileparts(mfilename('fullpath')),
'Icons')`) and threads it through. `encodeSvgIcon` (raw-markup ->
data-URI) is unchanged and still used directly by `encodeSvgFile`; nothing
about the ribbon's own `AlakazamRibbon.html` page changed -- it is still a
single self-contained page with every icon inlined as a data URI in the
one `Data` payload sent to it, only the MATLAB-side *source* of that
markup moved from a literal string to a sibling file.

Verified: all 20 `.svg` files exist and are well-formed (start with
`<svg`, use the established `viewBox="0 0 24 24"` convention); a real
`AlakazamRibbon` build confirmed all 9 ribbon-chrome icons still load
correctly as base64 SVG data URIs; and, to prove there is no drift risk
left at all, decoded the ribbon's rendered Settings icon back out of its
data URI and confirmed it is byte-for-byte identical to
`src/Icons/Settings.svg` on disk. `checkcode` clean on `AlakazamRibbon.m`.

Aside: partway through this, `R2024b`'s `matlab.exe` turned out to be
missing from this machine (only `R2026a`'s was found, both still listed
under `Program Files\MATLAB\`) -- switched the remaining `checkcode`/test
runs in this session to `R2026a` rather than trying to diagnose or repair
the `R2024b` install, since that is a machine/licensing concern outside
this codebase's scope. Worth the user's own attention if `R2024b` is still
the intended development version.

## Fixed: cryptic crash on a fresh MATLAB install where EEGLAB was never run

The user uninstalled R2024b (staying on R2026a, now the sole/intended
development version) and hit this on `startAlakazam` on that fresh setup:

```
Warning: Could not install EEGLAB plugin 'bva-io': Undefined function 'plugin_askinstall' ...
Warning: Could not install EEGLAB plugin 'ICLabel': Undefined function 'plugin_askinstall' ...
Warning: Could not install EEGLAB plugin 'dipfit': Undefined function 'plugin_askinstall' ...
...
Error using pop_loadset ... Unrecognized function or variable 'pop_loadset'.
Error in WorkSpace/loadSETFile (line 42)
Error in Alakazam (line 514)
```

Root cause: `EEGLabEnvironment.ensureEEGLab()` only checked `~isempty(which
('eeglab'))` -- but having `eeglab.m` on the path is not the same as EEGLAB
being *initialized*. EEGLAB adds its own subfolders and every plugin's
functions (`pop_loadset`, `plugin_askinstall`, ...) to the path only when
`eeglab()` itself actually runs. The fresh-*install* branch already handled
this correctly (it calls `eeglab;` right after downloading), but a machine
where EEGLAB was already on the path some other way (carried over from a
previous MATLAB install, added by a `startup.m`, ...) and simply never had
`eeglab` run in the current session hit the early-return branch instead,
which skipped straight past initialization. The failure then surfaced twice,
increasingly crypt­ically and increasingly far from the real cause: first as
harmless-looking plugin-install warnings, then as a hard, uncaught crash
deep inside `WorkSpace.loadSETFile` that took down the whole app
construction.

Reproduced live: this development machine turned out to be in exactly that
state right now (`which('eeglab')` resolves, `which('pop_loadset')` and
`which('plugin_askinstall')` do not) -- a genuine, no-mocking-needed
repro rather than a synthetic one.

Fixed by adding `EEGLabEnvironment.ensureEEGLabInitialized()`, called from
`ensureEEGLab()`'s early-return branch (found-on-path case only; the
fresh-install branch remains unchanged since it was already correct).
Probes for `pop_loadset` specifically (the exact function the user's own
crash named, and unambiguously EEGLAB-runtime-only); if missing, shows a
blocking dialog explaining that EEGLAB has never been run this session and
telling the user to run `eeglab` once and start Alakazam again, then throws
a specific `Alakazam:eeglabNotInitialized` error -- a hard stop, matching
EEGLAB-entirely-missing's existing fatal treatment rather than the
plugins/toolboxes' soft-warn-and-continue one, since an uninitialized
EEGLAB breaks nearly everything downstream (as the user's own crash showed)
rather than disabling one optional feature.

Deliberately did not have Alakazam call `eeglab('nogui')` itself to
silently self-heal, even though that would have been just as easy and
would have let startup succeed outright -- the user specifically asked for
the user to be informed and told to run it themselves, not for a silent
auto-fix.

Verified against the real broken state on this machine (not a mock):
confirmed the precondition directly (`which` results above), called the
real `EEGLabEnvironment.ensure()` (a timer auto-dismissed the blocking
dialog so the test could run unattended) and confirmed it now throws
`Alakazam:eeglabNotInitialized` with the "run eeglab once" guidance instead
of silently continuing into the later crash, then ran `eeglab('nogui')` and
confirmed that resolves it (`pop_loadset` becomes defined) -- exactly the
fix path a user follows. `checkcode` clean on `EEGLabEnvironment.m`.

Aside: this also incidentally initialized EEGLAB for real on this
development machine (plugins ICLabel/bva-io/dipfit/etc. now loaded), simply
as a side effect of the verification test itself running `eeglab('nogui')`.

## FourierView rewritten to single-channel + arrow-key navigation

The user wanted the Fourier (frequency-domain) view to behave like the
raw/average time-domain views: one plot per electrode, stepped through with
the up/down arrow keys, rather than a grid of every channel at once with
click-to-drill-into-detail.

Rewrote `FourierView.m` around the same interaction model
`EpochView`/`AverageView` already use: a single persistent axes, built once
in the constructor and only ever redrawn in place (`redraw()`, mirroring
their own method name), showing one channel's spectrum (with the existing
band shading) at a time. Up/down arrows step the channel; left/right step
the trial for multi-trial data -- the same split `EpochView` already uses
(up/down = channel, left/right = trial), a closer structural match than
`AverageView`'s up/down-only scheme since Fourier data has a genuine trial
dimension the same shape as Epoch's (channels x freqs/time x trials), not
Average's (channels x time, no trial axis). The existing zoom/pan and
trial-step buttons stayed, just retargeted from `this.Axes(1)` (an array,
in the old grid-of-subplots design) to a single `this.Axes` handle.

Building the axes once and never deleting/rebuilding it let the entire
`captureSlot`/`buildOuterGrid`/`TitleLabel`/`Mode` rebuild-tracking
machinery be deleted outright: that existed only to let `drawGrid`/
`showDetail` figure out *where* to rebuild `this.Grid` from scratch on
every mode switch (it could have been reparented into a tile-grid cell by
Alakazam's own Grid/Stack view mode by then). With no more rebuild-from-
scratch, `this.Grid` is simply constructed once and Alakazam's tile system
reparents that one stable handle around exactly the way it already does for
`EpochView`/`AverageView` (`Alakazam.tileWrapperFor` just grabs
`tab.Children(1)` generically, untouched by this change).

Found and fixed a real, separate gap while researching this (confirmed via
an Explore agent before touching anything): `Alakazam.dispatchKey`'s
`viewName` loop only ever checked `["EpochView", "AverageView"]` --
`FourierView.onKey` was never wired into keyboard dispatch at all, not even
before this rewrite (it wasn't "working before and broken by the
redesign," it plainly wasn't called from outside the class already). Added
`"FourierView"` to that loop, without which the new arrow-key navigation
would have been dead code. Also fixed the now-stale `retile()` comment
that compared its own tile rows/cols math to `FourierView.drawGrid`'s
identical formula -- `drawGrid` no longer exists.

Verified: `checkcode` clean on `FourierView.m` and `Alakazam.m`. Built a
real `FourierView` against synthetic multi-channel, multi-trial
frequency-domain data and confirmed: a single-axes (not array) view drawn
on construction; up/down arrows step and correctly clamp the channel at
both ends; left/right arrows step and clamp the trial; an unrelated key is
a no-op; the title reflects the current channel's label and trial; the
view is discoverable via the same `getappdata(tab, "FourierView")` key
`dispatchKey` looks up; and, directly in the committed source, that
`dispatchKey`'s `viewName` loop now actually includes `"FourierView"`.

## Fixed: IIRFilter crashed when ticking a checkbox ("Matrix dimensions must agree")

The user hit this after upgrading to R2026a, running IIRFilter on a real
dataset and enabling the Low Cutoff checkbox:

```
Unrecognized field name "CEF".   (x3-4, repeated)
Error using  /
Matrix dimensions must agree.
Error in TransTools.CreateFilter (line 11)
    [n, Wn] = buttord(((1/lsL)*freq)/nyq,(lsL*freq)/nyq,10,att);
Error in IIRFilterApp/UpDatePlot (line 109)
Error in IIRFilterApp/LCEnabledChanged (line 300)
```

Root cause, confirmed with the user's own real dataset (`Data/EEG/
12_P3_corrected_elist.set`), not a synthetic repro -- a genuine race
condition, not a data problem (`EEG.srate` for this file is a perfectly
ordinary scalar, 256):

`IIRFilterApp.startupFcn` called `app.GetGuiWinToMakeModal()` *first*,
before setting `app.SampleRate`/`app.ChannelLabels`/building the table.
`GetGuiWinToMakeModal` calls `mlapptools.waitForFigureReady`, which digs
into an undocumented internal MATLAB figure structure to get a native
window handle (used only so the dialog can be pinned "always on top") --
and on R2026a that structure no longer has whatever field mlapptools
expects ("Unrecognized field name 'CEF'"), so it throws, gets caught, and
retries after `pause(0.5)`, in an unbounded `while true` loop.

`pause()` yields control back to MATLAB's event queue -- and the dialog is
already fully visible and interactive at that point (`createComponents`
builds and shows the figure *before* `runStartupFcn` even starts). So a
checkbox click made while `GetGuiWinToMakeModal` is still retrying gets
dispatched immediately, calling `UpDatePlot()` with `app.SampleRate` still
`[]` (never assigned yet). `nyq = []/2 = []`, and `scalar / []` is exactly
what MATLAB's `/` throws "Matrix dimensions must agree" on (confirmed
directly: `5/[]` errors the same way; verified in this session before
touching any code). How fast `GetGuiWinToMakeModal` succeeds is
nondeterministic (0.5s in one test run here, ~1.5s in the user's own log),
which is exactly why the bug was intermittent and tied to *how quickly*
the user ticked the box.

The user confirmed the trigger directly ("I think it happens when i
enable a tickbox. This triggers the redraw of the filter response"),
which matched the diagnosis exactly.

Fixed inside `IIRFilterApp.mlapp` (a binary App Designer `.mlapp`, edited
by unzipping the OPC/ZIP container, patching the embedded MATLAB source in
`matlab/document.xml`'s CDATA section as plain text, and re-zipping --
`appdesigner/appModel.mat`, the visual-layout model App Designer's own
editor reads, was left untouched and unaffected; MATLAB's runtime
execution of `IIRFilterApp(...)` uses the CDATA source directly, verified
by actually running the patched app before replacing the original file):

- `startupFcn` reordered: `app.SampleRate`/`ChannelLabels`/the preview
  table/the initial `UpDatePlot()` now happen first, synchronously, before
  anything that can yield control back to the event queue.
  `GetGuiWinToMakeModal()` moved to the very end, as a best-effort,
  non-blocking step -- by the time it can possibly be interrupted by a
  user click, `app.SampleRate` is already set, so the race window is
  closed regardless of how long (or whether) mlapptools ever succeeds.
- `GetGuiWinToMakeModal` itself capped at 10 attempts (~3s) instead of
  retrying forever, returning `[]` if it never succeeds. An unbounded
  retry loop on a genuinely-broken-on-this-MATLAB-release introspection
  call is a latent hang waiting to happen even after the ordering fix,
  since `TransTools.CheckOptions` calls it a *second* time (see below).
- `TransTools/CheckOptions.m`: `Gui.GetGuiWinToMakeModal()`'s result can
  now legitimately come back empty, so `win.setAlwaysOnTop(true)` is
  guarded behind `~isempty(win)` -- without this, a plain .m-file fix
  alone would have just traded one crash for another
  (`[].setAlwaysOnTop(true)`).

Verified against the real dataset end to end: `app.SampleRate` is set
immediately on construction (before, it depended on how fast
`GetGuiWinToMakeModal` happened to resolve); enabling Low Cutoff, High
Cutoff and Notch each call `UpDatePlot()` without crashing (the user's
exact reported action, for all three filter sections, not just the one
they happened to hit); `GetGuiWinToMakeModal` returns promptly (bounded,
not hanging); and `CheckOptions.m`'s new guard is confirmed load-bearing
by directly reproducing what `[].setAlwaysOnTop(true)` would have thrown.
`checkcode` clean on `CheckOptions.m` (its one pre-existing `eval` note is
the already-documented, deliberate exception for the GUI-command-string
pattern -- confirmed unchanged from before this edit, not introduced by
it).

## mlapptools removed from IIRFilter entirely

Following the race-condition fix, the user asked directly: do we still
need mlapptools, and is there a better way to wait for the dialog and
read its settings? Checked rather than assumed, then implemented once
confirmed.

**Do we still need it?** No. Grepped the app's full source: mlapptools
was used for exactly one thing -- `GetGuiWinToMakeModal()` calling
`mlapptools.waitForFigureReady` to get a native window handle purely to
call `win.setAlwaysOnTop(true)` (plus a commented-out, already-dead
`unlockUIFig` call). `TransTools/CheckOptions.m` is the only other file
touching this protocol, and it has exactly one consumer (`IIRFilter.m`),
so nothing else in the codebase depends on the shape of this contract.

**Is there a better way?** Yes, verified directly in R2026a before
committing to anything:
- `uifigure` has a native `WindowStyle` property that accepts
  `'alwaysontop'` directly -- a documented, version-stable one-line
  replacement for the entire `GetGuiWinToMakeModal` retry-loop dance.
- `uiwait(fig)` / `uiresume(fig)` is the standard, MathWorks-documented
  App Designer pattern for a modal-style dialog that blocks its caller
  until done and then returns a value -- more idiomatic than, and (see
  below) more correct than, the previous custom `Finished` boolean
  property polled via `waitfor(Gui, 'Finished')`.

Implemented (same proven mechanism as the earlier race fix: unzip the
`.mlapp` OPC container, patch the embedded MATLAB source in `matlab/
document.xml`'s CDATA as plain text, re-zip, verify by actually running
it against the real dataset before overwriting the tracked file):

- `IIRFilterApp.mlapp`: removed the `GUIWIN`/`Finished` properties and the
  `GetGuiWinToMakeModal` method entirely. Added `GetMainFigure(app)`
  (returns `app.IIRFilterUIFigure`) -- the method `CheckOptions.m` now
  calls, keeping the same "apps used this way implement a small expected
  method set" convention `GetValues()` already established, rather than
  reaching into a hardcoded internal property name. `createComponents`
  now sets `app.IIRFilterUIFigure.WindowStyle = 'alwaysontop';` once,
  declaratively, alongside its other figure setup. `OKButtonPressed` calls
  `uiresume(app.IIRFilterUIFigure)` instead of setting `Finished`.
- `CancelButtonPushed` also switched to `uiresume(app.IIRFilterUIFigure)`
  -- and its old `app.delete()` was *removed*, not just replaced. This
  fixes a real, latent bug found while doing this: Cancel used to delete
  the app (and its figure/components) immediately, before
  `TransTools.CheckOptions` got a chance to call `Gui.GetValues()` and
  `delete(Gui)` afterward -- calling a method on an already-deleted handle
  errors in MATLAB. Cancel now behaves symmetrically to OK (signal done,
  let the caller read values and clean up), the same fix `uiwait`/
  `uiresume`'s own semantics naturally invited.
- `TransTools/CheckOptions.m`: the `GetGuiWinToMakeModal`/
  `setAlwaysOnTop`/`waitfor(Gui,'Finished')` block replaced with
  `uiwait(Gui.GetMainFigure()); options = Gui.GetValues(); delete(Gui);`.
- Deleted `src/Transformations/IIRFilter/mlapptools.m`,
  `mlapptools_LICENSE.md`, and `WidgetID.m` (mlapptools' own only helper
  class, otherwise unused anywhere) -- confirmed via a full `src/` grep
  that nothing else referenced any of the three. `PROJECT_STRUCTURE.md`
  and `dependencies.md` updated to match (the latter also fixed a second,
  unrelated stale claim spotted in passing: `+uiextras/+jTree` was still
  described as present-but-dead, when it was actually deleted outright
  earlier this session).

Verified end to end against the real dataset (`Data/EEG/
12_P3_corrected_elist.set`) in four stages: structural checks (WindowStyle
is `alwaysontop`, the old properties/method are gone, `GetMainFigure`
works); the OK path (a `timer` clicks OK while the main thread is blocked
in `uiwait`, confirming it unblocks promptly and `GetValues()` afterward
reflects the edited checkbox/frequency); the Cancel path (same timer
trick, confirming `uiwait` unblocks *and* -- the actual bug fix --
`GetValues()` no longer errors afterward, since the app is no longer
deleted out from under the caller); and the full real `TransTools.
CheckOptions` round trip, the exact code path `IIRFilter.m` uses.
`checkcode` clean on `CheckOptions.m` and `Alakazam.m` (the one remaining
note on `CheckOptions.m`, about its `eval`, is the already-documented,
deliberate exception for the GUI-command-string dispatch pattern).

## ScalpDistribution: up to 3 bins per row, live time label while dragging

Two requests: lay out bins 3-to-a-row (was a near-square grid via
`ceil(sqrt(n))`, e.g. a 2x2 grid for 4 bins) instead of one wide row that
keeps growing, and make the "t = ... ms" label track the slider live while
dragging rather than only updating on release.

**Layout**: `nCols = ceil(sqrt(nBins))` replaced with `nCols = min(3,
nBins)` (rows still `ceil(nBins / nCols)`) -- 1-3 bins stay a single row,
4+ wraps after every 3rd. Confirmed end to end with a real 5-bin dataset:
5 topoplot axes land at exactly 3 distinct column positions (3 in the
first row, 2 in the second), not the old formula's 3x2 grid coincidentally
looking similar for that particular count -- verified the two formulas
actually diverge (e.g. 4 bins: old gives a 2x2 square, new gives 3+1).

**Live label during drag**: `ScalpDistribution` deliberately uses a
classic `figure`/`uicontrol` slider, not `uifigure`/`uislider`, because
`topoplot` draws with legacy low-level graphics that need a classic axes
(see the file's own docstring) -- so `uislider`'s `ValueChangingFcn`
(what `SignalView`/`EpochView`/etc. use for exactly this kind of live
feedback) isn't available here. A classic `uicontrol` slider's `Callback`
only fires on mouse-up; dragging never calls it. Confirmed directly
before relying on it: the slider's underlying `Value` property *does*
update continuously during a drag even though `Callback` doesn't fire, so
`addlistener(slider, 'Value', 'PostSet', ...)` reacts live to every drag
tick -- the standard, still-current, non-Java way to do this (no
`findjobj`/Swing digging, matching this session's broader move away from
that).

Split the old single `redraw(t)` into `updateLabel(t)` (just the text,
now wired to the `PostSet` listener, firing on every drag tick) and
`redraw(t)` (label + the actual per-bin `topoplot` recompute, still wired
to `Callback`, firing only on release) -- recomputing every bin's
topoplot on every drag tick would be far too slow to feel live, so only
the cheap part runs during the drag itself. The listener handle is kept
alive by the same nested-function closure that already keeps `ax`/
`timeLabel` alive for the life of the figure (the slider's `Callback`
being a nested-function handle is what keeps that whole workspace alive
in the first place).

Verified: the nCols/nRows formula by hand for 1-7 bins; a real 5-bin
dataset (built from the same real dataset's own channels, so
`posChanlocs` resolves against the real dipfit template, not a mock)
actually lays out as 3 distinct columns; setting the slider's `Value`
programmatically (which does not invoke `Callback`, exactly like a live
drag tick before mouse-up) updates the label immediately while leaving
every topoplot axes' children count unchanged (proving the expensive
redraw does *not* fire during drag); then manually firing the `Callback`
(simulating mouse-up) confirms the topoplots *do* redraw with real
content at that point. `checkcode` clean.

## ScalpDistribution follow-up: colorbar removed, heads update live too

Immediate follow-up to the previous entry, after actually seeing it in
use: the hand-placed colorbar (fixed at x=0.93) now sits behind the
rightmost head once a 3-per-row layout is common (any nBins >= 3, since
the last change), because the plot columns' own width formula
(`cellW = 1/nCols`) was never adjusted to leave room for it -- for
`nCols = 3`, the third column's right edge (~0.98) already overlapped the
colorbar's position. The user pointed out MATLAB's own axes toolbar
already offers a colorbar/colormap affordance, making the hand-placed one
redundant anyway, so the fix was to delete it rather than reposition it:
removed the `colorbar(ax(1), ...)` call entirely, and with it, the
now-unnecessary right-margin reservation -- plot columns are back to
using the full figure width (`cellW = 1/nCols` again).

Also asked for, in the same message: let the topoplots themselves --
not just the "t = ..." label -- update live while dragging. The
previous entry deliberately split cheap (label) from expensive (topoplot
recompute) specifically to avoid this, worried about drag-tick lag; the
user tried it and wants the live heads anyway. Simplified: the `Value`
`PostSet` listener now calls the same full `redraw(t)` the old
mouse-up-only `Callback` used to (label text + every bin's `topoplot`
recompute), and the `Callback` was removed outright rather than kept
redundantly alongside it -- `PostSet` already fires for the slider's
final value on release too, so a separate release-only handler no longer
does anything a drag tick hasn't already done. `updateLabel` and `redraw`
were merged back into one function, since nothing calls just the label
part anymore.

Verified: no `colorbar` object exists anywhere in the figure after the
change, and the rightmost head's axes now extends to the (previously
reserved-away) right edge of the figure; the slider has no `Callback` set
at all; and -- the actual point of the request -- a numeric fingerprint of
one axes' plotted `CData`/`ZData` (child count/position alone don't
change between redraws of the same layout, so a real data comparison was
needed) differs before and after a simulated drag tick (`Value` set
programmatically, which invokes `PostSet` but not `Callback`, exactly
mirroring a live drag before mouse-up), confirming the heads themselves,
not just the label, now redraw live. The synthetic test dataset itself
needed a fix along the way: it originally collapsed every timepoint to a
single per-channel mean (so every instant looked identical, defeating the
very check this test needed to make) -- switched to genuinely
time-varying data cropped from the real recording. `checkcode` clean.

## ScalpDistribution: fixed the rightmost head shrinking when a colorbar is added

Immediate follow-up: the user reported that adding a colorbar (via
MATLAB's own axes toolbar, per the previous entry's "just take it out,
it's part of the interface of matlab now") draws that head noticeably
smaller than its siblings.

Root cause, confirmed directly rather than assumed: `topoplot`'s axes has
`PositionConstraint = 'outerposition'`-like behaviour -- adding a colorbar
to it shrinks the axes' actual `Position` (not just an outer margin) to
make room, confirmed by measuring the head's own plotted data extent
before/after (`[0.9851 0.9664]` both times, completely unchanged) against
its `Position` width (`0.30` -> `0.2454`, an 18% shrink). The head is not
redrawn smaller in data terms; its containing box just gets squeezed,
which is what makes it *look* smaller on screen.

Two things tried and confirmed **not** to work before landing on the fix:
- Setting `ax.PositionConstraint = 'innerposition'` before adding the
  colorbar: for a plain `subplot`+`imagesc` axes this prevents the shrink
  entirely (confirmed), but for a `subplot`+`topoplot` axes it does
  nothing -- MATLAB's subplot-grid position manager overrides it
  regardless (confirmed directly, same shrink either way).
- `addlistener(ax, 'Position', 'PostSet', ...)` to catch and immediately
  undo the shrink: confirmed the listener **never fires** when `colorbar`
  changes `Position` -- it goes through some internal path that does not
  raise a normal property-set notification at all (a bare `set`, e.g. a
  slider's `Value`, does fire `PostSet` reliably; `colorbar`'s internal
  resize does not).

What does work, confirmed directly: restoring `Position` to its original
value *after the fact* sticks -- `colorbar` does not fight back a second
time once its own resize has already happened. So the fix is a
lightweight polling `timer` (`ExecutionMode: 'fixedRate'`, 0.5s period)
that checks every head's `Position` against the layout position recorded
right after the grid was built, and restores it if anything (typically a
user-added colorbar) has changed it. Stopped and deleted via the figure's
own `DeleteFcn` so it does not keep running after the plot window is
closed.

Since colorbars are no longer reserved-for internally (removed entirely
last entry), the plot columns had grown to use the *full* figure width --
leaving no room for a colorbar the user might still add via the native
UI. Reinstated a modest margin (`plotAreaWidth = 0.95`, versus the ~0.90
the original hand-placed colorbar used) so a colorbar added to the
rightmost head, once its axes is restored to full size, has somewhere to
render without being clipped at the figure edge -- confirmed directly
that it lands in that margin (or the small existing gap between interior
cells) without overlapping the now-unshrunk head.

Verified end to end (twice, to rule out a one-off timing fluke, since a
polling-timer fix is inherently timing-sensitive): built a real 3-bin
figure, added a colorbar to the rightmost head exactly as the user would,
waited past two timer periods, and confirmed its `Position` is restored
to the original layout slot; confirmed the colorbar itself is not clipped
past the figure edge and does not overlap the restored head's own box;
confirmed all three heads remain identically sized; and confirmed normal
drag/redraw still works correctly afterward (the position-restore
mechanism does not interfere with `redraw`'s own repeated
`cla`/`topoplot` calls on every drag tick). `checkcode` clean.

## Tree drag-and-drop: removed the move/reparent gesture, drop always applies the branch

The tree previously had two drop behaviours depending on whether Ctrl was
held during the drop: no Ctrl left yy-tree's own reparent in place (moved
the branch to the new parent), Ctrl held reverted the move and instead
applied the dropped branch's transformations to the target
(`Alakazam.evaluateDroppedBranch`). The user reported the no-Ctrl case was
unwanted ("I can move a branch now. I do not want that.") and asked for
the apply-transformation behaviour unconditionally: drag a branch onto
another node, and the transformations get replayed onto that node.

Removed the move/reparent gesture entirely rather than just defaulting it
off, across all three layers of the drop contract:

- `src/webtree/src/alakazam-tree.js` (`AlakazamTree`): dropped the
  `_ctrlDown` field and its three `keydown`/`keyup`/`blur` window
  listeners. `_onMove` now unconditionally reverts the move yy-tree just
  performed (splices the node back to its pre-drag parent/index, exactly
  as the old Ctrl-held branch did) and emits a plain
  `{type:'nodeDropped', sourceId, targetId}` -- no `reparented` field at
  all, since there is now only one behaviour.
- `src/WorkSpaceTree.m` (`handleDropped`): dropped the
  `if d.reparented ... end` mirroring block (nothing to mirror any more,
  the JS side never moves a node) and the `Reparented` field on the
  struct passed to `NodeDroppedFcn`.
- `src/Alakazam.m` (`onNodeDropped`): dropped the `if ~eventData.Reparented`
  conditional -- `evaluateDroppedBranch` is now called unconditionally.
  This needed a **new** guard that the old conditional had implicitly
  covered: `eventData.Target` can be `[]` for a drop onto empty space/root
  (no dataset to apply the branch to), and `evaluateDroppedBranch`
  unconditionally dereferences `targetNode.UserData`, so
  `onNodeDropped` now returns early when `isempty(eventData.Target)`, in
  addition to the existing root-source guard.

`src/webtree/test_node.mjs`'s drag-simulation tests were rewritten to
match: the old "5a: no Ctrl, real reparent, mutation stands" case (the
only one that previously expected the move to stick) became "the move is
always reverted, even for a plain top-level-onto-top-level drop"; the
former Ctrl-held cases (5b/5c) kept their revert-to-original-parent
assertions but dropped all Ctrl framing and the `reparented` field from
the expected event JSON.

Verified: `cd src/webtree && npm run build && npm test` (jsdom drag
simulation, all cases pass, dist copied to `src/WorkSpaceTree.html`);
`checkcode` clean on `WorkSpaceTree.m`/`Alakazam.m`; a headless functional
test (constructing a real `WorkSpaceTree` and driving it through its own
`Component.HTMLEventReceivedFcn`, exactly as the JS bridge does, since
`onEvent`/`handleDropped`/`nodeStruct` are private -- mirroring the
standalone-algorithm-replication pattern used elsewhere in this session
for `onNodeDropped`'s own guard logic, since constructing a full `Alakazam`
needs EEGLAB) confirms: `handleDropped` forwards a `Reparented`-free
Source/Target struct and yields `Target = []` for an empty `targetId`;
`onNodeDropped`'s guard ignores a root-source drop, ignores an empty-target
drop (the new case), and unconditionally reaches `evaluateDroppedBranch`
for a normal node-onto-node drop.

## Tree drag-and-drop: cursor feedback while a drag is in progress

Immediate follow-up to the above: the browser's native drag cursor still
read as a "move" cursor while dragging a branch, which is misleading now
that a drop never moves anything (it applies the branch's transformations
to the target). `src/webtree/src/alakazam-tree.js`'s `_onMovePending`/
`_onMove` now toggle an `alz-dragging` class on `<html>` for the duration
of the drag; `alakazam-tree.css` adds `html.alz-dragging, html.alz-dragging
* { cursor: copy !important; }`.

Two things confirmed directly rather than assumed, both against
`node_modules/yy-tree/src/input.js`:
- The class has to go on `<html>` (or another ancestor covering the whole
  page), not just the dragged row: yy-tree's `Input._pickup()` reparents
  the dragged element to `document.body` and positions it absolutely under
  the pointer, so the pointer spends the whole drag over *other* rows/
  whitespace, not the dragged node itself.
- `!important` is required: `TREE_STYLES` already sets inline
  `cursor: pointer` on every row's name/content spans, which would
  otherwise win over an inherited, non-`!important` cursor value.
- `move-pending` and `move` are a reliable start/end pair with no
  cancel/escape path -- `Input._up()` always emits `move` once the drag
  threshold (`_moving`) has been crossed, including on `mouseleave`, so
  the class is guaranteed to come back off.

Verified: `cd src/webtree && npm run build && npm test`; a new jsdom test
drives `move-pending` then `move` directly and asserts
`document.documentElement.classList.contains('alz-dragging')` is `false`
before the drag, `true` after `move-pending`, and `false` again after
`move`. `dist/alakazam-tree.html` copied to `src/WorkSpaceTree.html`.

## Fixed: Clear WorkSpace opened a stray figure window and looked hung

The user reported that "Clear WorkSpace" opens a figure window and the app
"does not come back." Root cause, confirmed directly:
[`src/@WorkSpace/rawclear.m`](src/@WorkSpace/rawclear.m) is leftover
classic-figure-era code -- `set(gcf,'Pointer','watch')` before the
delete/recreate, `set(gcf,'Pointer','arrow')` after. `gcf` only tracks
classic figures, not this app's `uifigure` shell, so calling it with none
open **silently creates a brand-new blank classic figure** rather than
erroring or resolving to `MainFigure`. Confirmed empirically: a headless
`uifigure` exists, `findall(0,'Type','figure')` reports 1 (the uifigure
itself is `Type=='figure'` too), then `set(gcf,'Pointer','watch')` bumps
that count to 2 -- a real new window, popped up on top of/stealing focus
from `MainFigure`, which is what read as "the program does not come
back" (it hadn't hung; the blank stray figure was just occluding/focus-
stealing the real app window).

Fixed to use `this.Parent.MainFigure` (the `WorkSpace`'s own reference to
the owning `Alakazam` app) directly instead of `gcf`, and wrapped the
pointer-restore in `onCleanup` rather than a plain trailing `set(...)` --
the old code left the watch cursor stuck forever (and the stray figure
open) if `rmdir`/`mkdir`/`open(this)` threw partway through; `onCleanup`
restores the pointer even on that path.

Verified: `checkcode` clean; a headless functional test (constructing a
real `uifigure` as a stand-in `MainFigure`, driving `rawclear.m`'s
"Yes, delete!" body directly -- `questdlg` itself would block headlessly,
and `open(this)` needs a full `WorkSpace`/`Tree`, both out of scope for
this focused test) confirms no additional classic figure appears
(`findall(0,'Type','figure')` count unchanged, counting `MainFigure`
itself as the baseline) and the pointer is restored to `'arrow'`
afterward; separately confirmed the *old* `gcf`-based code, run against
the same harness, does reproduce the stray-figure bump (1 -> 2), so this
test would have caught the regression.

## Tree drag-and-drop: busy cursor while MATLAB computes, live drop-target highlight

Two follow-up requests on the drag-and-drop redesign: (1) the cursor
doesn't change while MATLAB is off running `evaluateDroppedBranch`
("the drop is being calculated") -- wanted an animated hourglass-style
busy indicator; (2) while dragging, the row list collapses around the
insertion point (expected, fine), but there's no clear indication of
*which* node is the "DROPBRANCH" -- the one that will actually receive the
dropped branch's transformations.

**Busy cursor.** `src/webtree/src/alakazam-tree.js`'s `_onMove` now adds
an `alz-busy` class to `<html>` the instant it sends `nodeDropped`
(alongside removing `alz-dragging`); `alakazam-tree.css` adds
`html.alz-busy, html.alz-busy * { cursor: wait !important; }`. `cursor:
wait` rather than a custom animated-cursor image: on this app's target
platform (Windows), the browser renders it as the OS's own animated busy
indicator, whereas `cursor: url(...)` pointing at an animated GIF/cursor
resource generally does not animate across browsers -- the OS-native
route gets the "animated hourglass" the user asked for without an asset.

Clearing it is the hard part: the only MATLAB->JS signal available is a
fresh `Component.Data` push (observed via `bridge.js`'s `DataChanged`
listener), and `Alakazam.onNodeDropped`'s existing guards (root source,
empty target) returned *before* ever reaching `evaluateDroppedBranch`/
`persistResultNode`'s own push -- so an ignored drop, or a thrown
transformation error, would have left the busy cursor stuck forever.
Fixed with the same `onCleanup` technique as the rawclear.m fix above:
`onNodeDropped` now does `notifyDone = onCleanup(@()
sourceTree.notifyDropHandled());` right after setting `ActiveTree`, so a
push happens when the callback returns by *any* path -- success, an
ignored drop, or an error unwinding the stack. `WorkSpaceTree` gained
`notifyDropHandled()` (a thin public wrapper around the existing private
`push()`) and a `PushSeq` counter stamped into every pushed payload as a
`seq` field, so consecutive pushes can never look identical to `Data`'s
change-detection even when nothing about the node set actually changed
(e.g. two ignored drops in a row) -- belt-and-suspenders alongside the
`onCleanup` guarantee itself.

**Live drop-target highlight.** yy-tree's own visual feedback during a
drag is just a thin horizontal insertion-line indicator -- easy to lose
track of once the row list collapses around it, exactly the user's
complaint. There's no per-frame hook from yy-tree for "what would this
drop onto right now," so `_onDragPointerMove` (a `document`-level
`mousemove` listener, registered so it always runs *after* yy-tree's own
`document.body`-level listener, since bubble-phase dispatch reaches
`document` after `body` regardless of registration order) reads yy-tree's
internal state directly (vendored, pinned code, same justification as the
existing icon-override reach-in): confirmed in
`node_modules/yy-tree/src/input.js` that `Input._up()` always does
`indicator.parentNode.insertBefore(this._target, indicator)` then
`_moveData()` reads `this._target.parentNode.data` as the resolved new
parent -- meaning the indicator's *current* `parentNode`, at any moment
mid-drag, already tells us exactly what dropping right now would resolve
to (a rendered leaf element, whose own `.data` is the prospective target,
or the tree's root container for a no-target drop). `_setDropTargetHighlight`
applies a new `alz-drop-target` class (dashed outline + light tint,
distinct from the solid-blue click-selection highlight so the two don't
visually fight) to that leaf, clearing the previous one -- mirroring the
existing `_applySelectionHighlight` pattern. Cleared on drop
(`_onMove`) and guarded against ever highlighting the dragged node itself.

Verified: `cd src/webtree && npm run build && npm test`. Real pixel-based
hit-testing can't be simulated in jsdom (no layout engine), so the new
drop-target tests drive `_onDragPointerMove` directly against a manually
repositioned indicator element (exactly mirroring what `Input._move()`
would have just done to it) rather than dispatching real `mousemove`
events -- confirmed: highlights the node the indicator is parented under,
clears for a root/no-target position, never highlights the dragged node
itself, and clears once the drop completes. The busy-cursor test confirms
`alz-busy` turns on the instant a drop is sent (clearing it is
`bridge.js`'s job, not part of the bundle `test_node.mjs` exercises --
`bridge.js` is 3 lines, reviewed by hand). `dist/alakazam-tree.html`
copied to `src/WorkSpaceTree.html`. `checkcode` clean on
`WorkSpaceTree.m`/`Alakazam.m`. A new headless MATLAB functional test
(driving `onNodeDropped`'s exact guard/`onCleanup` structure against a
real `WorkSpaceTree`, `evaluateDroppedBranch` stood in by a stub function)
confirms `notifyDropHandled` fires exactly once for every outcome: a
root-source drop, an empty-target drop, a thrown error (propagates as
expected *and* still notifies, proving `onCleanup` runs on the
error-unwind path), and the normal successful case.

## Fixed: deleting a branch crashed on the next click ("Unable to find file or directory")

The user reported that right-click -> Delete on a branch throws
`Error using load: Unable to find file or directory ".../
Baseline11195207.mat"` out of `Alakazam/onSelectionChanged`, immediately
after deleting a node. Root cause: `WorkSpaceTree.removeNode(id)` only
ever removed the *one* node it was given from `this.Nodes` -- its own
docstring said as much ("callers remove descendant nodes explicitly first
if the whole branch is going"), but `Alakazam.onDeleteNode` never actually
did that. It deletes descendant *files* recursively (`rmdir(childDir,
"s")`) and closes their open tabs/tiles, but calls `removeNode` exactly
once, for the top node the user right-clicked.

That left every descendant still sitting in `this.Nodes` with a
`parentId` pointing at an id that no longer existed. `setNodes`
(`src/webtree/src/alakazam-tree.js`) treats an unresolvable `parentId` as
"top-level" (`const parent = n.parentId != null ? byId.get(n.parentId) :
null; if (parent) {...} else { this._root.children.push(data) }`) -- so a
deleted branch's children resurfaced as brand-new *root* nodes in the
tree, still fully clickable, while their backing `.mat` files had already
been deleted out from under them by the recursive `rmdir`. Clicking one
(as the user did, right after the delete) crashed `onSelectionChanged`'s
`load(eventData.UserData, "EEG")`.

Fixed at the `WorkSpaceTree` layer, not the `Alakazam.onDeleteNode` call
site: `removeNode` now walks `parentId` links via a new private
`branchIds(id)` helper (id plus every descendant, `Nodes` being a flat
map rather than a real tree) and removes the whole branch -- and clears
`SelectedId` if it pointed at any of them -- in one `push()`. No change
needed in `Alakazam.m`: `onDeleteNode`'s single `removeNode(node.Id)`
call now does the right thing automatically, and its own file/tab/tile
cleanup already walked the same `childDir` recursively, so the two stay
in lockstep.

Verified: `checkcode` clean. A headless functional test (building a real
`WorkSpaceTree` reproducing the exact reported shape --
`corrected_elist` -> `DefineBins11195205` -> `Baseline11195207`, selected,
plus an unrelated sibling branch -- constructing a full `Alakazam` needs
EEGLAB, and the bug was purely in the JS-facing `Nodes` bookkeeping, no
disk access involved) confirms: deleting the middle node removes both it
and its descendant from the pushed `Data`; the unrelated sibling branch
and the shared root are untouched; no remaining node's `parentId` still
references the deleted id (the exact condition that used to resurface
orphans as new roots); and the selection is cleared since the selected
node was removed.

## Fixed: dragging out of the tree fired a drop instead of cancelling

The user reported that a drop also fires just from the cursor leaving the
tree area entirely -- not something that should count as a drop at all.
Root cause: yy-tree's `Input` (`node_modules/yy-tree/src/input.js`)
registers `document.body.addEventListener('mouseleave', e =>
this._up(e))` right alongside its `mouseup`/`touchend` listeners, and
`_up()` treats a `mouseleave` exactly like a real mouse-button release --
it finalizes the move (`_moveData()`, emits `'move'`) with no separate
"cancelled" concept. Since `_onMove` already unconditionally sent
`nodeDropped` whenever `'move'` fired, simply carrying the pointer off the
edge of the tree's own uihtml page (into the ribbon, the plots area, even
just past the window edge) was enough to apply whatever branch was being
dragged onto whatever node the drop indicator happened to be resting on.
uihtml renders in its own embedded document, with no "pointer left the
whole app" signal of its own -- `mouseleave` on that document's `body` is
the only place this is observable at all.

Fixed by intercepting it one layer up, in `alakazam-tree.js`'s
`AlakazamTree` constructor: a `document.body` `'mouseleave'` listener is
registered *before* `new Tree(...)` (which is what constructs `Input` and
registers *its* `mouseleave` listener). Listeners on the same element for
the same event fire in registration order, so this one always runs first,
setting `this._pointerLeftDuringDrag = true` if a drag was in progress at
that moment (checked via `this._pending`, already used for the same
purpose elsewhere) -- and since `_up()`'s subsequent, synchronous
`'move'` emission happens later in that same call stack, `_onMove` can
read the flag reliably every time. `_onMove` now branches on it: the data-
graph revert (undoing yy-tree's own `_moveData()`) and cursor-class
cleanup still run unconditionally as before, but if the flag is set,
`_onMove` returns before setting `alz-busy` or sending `nodeDropped` --
the drag is simply abandoned, and the dragged row snaps back to its
original tree position via the same revert-then-`update()` path an
ordinary reverted drop already used. `_onMovePending`'s own comment
("there is no cancel/escape path") no longer applied and was corrected.

Verified: `cd src/webtree && npm run build && npm test`. Two new jsdom
tests dispatch a real `mouseleave` DOM event on `document.body` (exercising
the actual listener wiring, not just calling internal methods) mid-drag
and confirm no `nodeDropped` event is sent and `alz-busy` never turns on
(while `alz-dragging` still correctly turns off); a second test confirms a
stray `mouseleave` firing with *no* drag in progress doesn't wrongly
poison a later, real drag. `dist/alakazam-tree.html` copied to
`src/WorkSpaceTree.html`. No MATLAB-side change needed -- the bug and its
fix are entirely within the JS drag-gesture layer.

## Fixed: the mouseleave-cancel fix above broke normal overlay drops

Immediate regression from the previous entry: the user reported they
could no longer drop one Averaged dataset onto another to overlay their
plots (`Alakazam.overlayAverage`, via `evaluateDroppedBranch`'s
`isOverlayableAverage` special case) -- a genuine, ordinary tree-node-
onto-tree-node drag, never intended to leave the tree's own bounds at
all. The previous fix's blanket "any `mouseleave` mid-drag cancels" was
too eager: dragging toward a row near a (possibly narrow, e.g. the split
"Data & Analyses"/"Grand Averages" panels) tree panel's edge is exactly
the kind of drag most likely to graze past the exact pixel boundary for
an instant from ordinary mouse imprecision -- and that innocent overshoot
was now silently aborting an otherwise completely normal, intended drop.

Replaced the instant-cancel with a short grace period. The constructor's
early `mouseleave` listener (registered before `new Tree(...)`/`Input`,
so it always runs first and can `stopImmediatePropagation()` to keep
Input's own listener from ever seeing the event at all -- unchanged from
the previous fix) now, instead of just flagging the leave, arms a
`setTimeout(() => this._cancelDrag(), LEAVE_GRACE_MS)` (250ms). A
matching early `mouseenter` listener clears that timer. If the pointer
comes back within the grace window, **nothing else needs to happen**:
because the `mouseleave` was intercepted before Input ever processed it,
Input's own internal drag state (`_target`/`_moving`, the floating ghost
row, the indicator) was never touched in the first place, so the drag
simply continues exactly as if the momentary excursion never happened --
Input's own `mousemove`/`mouseup` listeners pick up right where they left
off. Only if the timer actually fires (no re-entry in time) does the new
`_cancelDrag()` manually unwind the drag: remove the floating ghost row
and indicator, null out `Input._target`/`_moving` directly (reaching into
those private fields the same way `_onDragPointerMove` already reaches
into `Input._indicator`), then call `this._tree.update()` -- since the
data graph was never mutated in this path (that only ever happens inside
`Input._moveData()`, which never ran), a plain rebuild-from-data is
enough to make the dragged row reappear exactly where it started, no
revert-then-restore dance needed.

`_onMove` (the real-drop path) is otherwise back to its pre-previous-
entry form -- no more `cancelled` flag or early return, since a genuine
`'move'` event now always represents an actual completed drop (the
mouseleave-triggered case is fully absorbed by the interceptor before
Input can ever emit it).

Verified: `cd src/webtree && npm run build && npm test`. The previous
entry's two tests (which drove the drag purely through the wrapper's own
`emit('move-pending'/'move')` shortcut) were replaced with four that
drive a **real** `Input` pickup instead (`down()` + `move()` past the
threshold, using the file's own existing low-level test helpers) --
necessary because the emit shortcut only ever fires this wrapper's own
event handlers, never touching `Input._target`/`_moving`/the indicator at
all, so it couldn't actually exercise `_cancelDrag`'s interaction with
real `Input` state. The four: (1) a real `mouseleave` mid-drag is
intercepted before `Input._up()` can run (`Input._target`/`_moving`
remain set, no event sent yet); (2) letting the grace period lapse with
no re-entry cancels cleanly (`Input` state cleared by `_cancelDrag`
itself, no event ever sent, the node provably still under its original
parent); (3) a `mouseenter` partway through the grace period keeps the
exact same drag alive, and a subsequent real `mouseup` completes it
normally (`nodeDropped` sent, busy cursor on); (4) a stray
`mouseleave`/`mouseenter` pair with no drag in progress is a no-op.
`dist/alakazam-tree.html` copied to `src/WorkSpaceTree.html`. No
MATLAB-side change needed.

## Tree rows: tighter vertical spacing

User feedback: the vertical gap between tree rows read as too loose.
`alakazam-tree.js`'s `TREE_STYLES` stacks two separate vertical paddings
per row -- `nameStyles.padding` (the name span) sits inside
`contentStyles.padding` (the whole-row flex container) -- so both
contributed to the gap. Tightened `nameStyles.padding` from `'3px 6px'`
to `'1px 6px'` and `contentStyles.padding` from `'2px 4px'` to `'1px 4px'`
(horizontal padding untouched), trimming 6px of vertical space per row
(3px off the top, 3px off the bottom) on top of the existing 1px
`.yy-tree-leaf` row-to-row margin, left as is. Verified: `cd src/webtree
&& npm run build && npm test` (a pure styling change; no behavioural test
needed, existing suite still green). `dist/alakazam-tree.html` copied to
`src/WorkSpaceTree.html`.

## Grand Average persistence: investigated, not reproducible

The user reported grand averages don't survive an Alakazam restart --
suspected the Grand Averages tree fails to rediscover
`CacheDirectory/GrandAverages/*.mat` on reopen. Investigated thoroughly
before touching any code (`WorkSpace.open`/`loadGrandAverages`/
`Alakazam.saveGrandAverage` all read correctly on inspection) and then
verified empirically against the user's own real default workspace,
including their real pre-existing grand average file
(`Data/Cache/GrandAverages/d.mat`): a headless `WorkSpace`-only test, a
single-process `startAlakazam()` -> `delete()` -> `startAlakazam()`
round trip, and -- the most faithful reproduction possible -- **two
fully independent MATLAB processes** (the first creates and saves a
brand-new grand average and exits completely; the second is a genuinely
cold `startAlakazam()` in a brand-new process, sharing nothing but the
files on disk) all correctly rediscover every grand average, old and
newly-created alike. No code defect found or changed. Test artifacts
were cleaned out of the real `Data/Cache/GrandAverages/` folder
afterward, leaving only the user's own `d.mat`. The user separately
reported the problem seems to no longer reproduce on their end.

## Removed the last ECG remnant: SignalView's IBI-marker overlay

The user confirmed the app is strictly EEG-only now (no more ECG/HRV
traces) and asked for any remaining ECG/MEG code to be found and removed.
Audited the whole `src/` tree first: no MEG code exists anywhere, and no
beat-detection/R-peak-producing pipeline exists in this repo at all --
`EEG.IBIevent` was only ever *read*, never produced, by anything here (a
holdover from an earlier multi-modal-physiology era of the tool). The
only real remnant was `SignalView.m`'s interbeat-interval marker overlay
and its one small support file:

- `src/SignalView.m`: removed `drawIbiMarkers` entirely (drew
  colour-coded, AAMI-beat-class-coloured, draggable cursors at each
  `eeg.IBIevent{i}.RTopTime`), the `IbiColors` constant (AAMI beat-class
  colour dictionary: N/L/S/T/1/2/i), the `MaxIBIs` constructor option
  (never actually passed by either `AlakazamPlotter.plotContinuous` call
  site, so always inert in practice), the `'ibi'`-tag cleanup line and
  `drawIbiMarkers` call in `drawOverlays`, and the `IbiEvents` field +
  `eeg.IBIevent` read in `parseOverlays`. `drawPointEvents`/
  `drawAreaEvents` (the generic EEGLAB stimulus-marker/artifact-window
  overlays -- not ECG-specific despite sharing `parseOverlays`'s
  `eeg.event` parsing with the removed code) are untouched, since they
  read `eeg.event`, a different field, and every EEG dataset uses them.
  Also reworded the file's "clean replacement for the old Tools.plotECG"
  / "Ported from plotECG" attribution comments (class docstring, the
  zoom-mapping comment, both `autoStack*` docstrings) to drop the
  ECG-specific naming while keeping the actual technical content.
- `src/+uiextras/delCursor.m`: deleted outright. Its only live statement
  was a generic `delete(vl)`; the rest was already-commented-out
  `EEG.IBIevent.RTopTime/ibis/RTopVal`-mutating code. Its only caller was
  `drawIbiMarkers`'s cursor-delete callback (`drawPointEvents`'s own
  cursors pass `[]` for this callback, so never called it) -- fully
  orphaned once `drawIbiMarkers` is gone.
- `src/@cursor/cursor.m` and `src/@label/label.m` deliberately **not**
  touched: both are generic draggable-marker/area helper classes with no
  ECG-specific content, still load-bearing for `drawPointEvents`/
  `drawAreaEvents`'s ordinary EEG event overlays.
- Cosmetic-only, non-functional wording cleanup: `AlakazamPlotter.m`'s
  "IBI/event overlays" comment, `PROJECT_STRUCTURE.md`'s "replaces the
  removed Tools.plotECG" row, and `ScalpDistribution.m`'s
  "PoinCare"-comparison comments (`PoinCare` was a since-fully-deleted
  Poincaré-plot HRV transformation; no `PoinCare.m` exists anywhere in
  the repo, confirmed by search) -- all reworded to drop the ECG/HRV
  tool references while keeping the actual explanation. Left the `EOG/
  ECG` mentions in `EnsureChanlocs.m`/`FillChanlocs.m`/`AutoEyeICA.m`/
  `AutoGEDAI.m`/`ScalpDistribution.m` as-is: these are generic
  "a channel with no scalp position" handling that names ECG only as an
  illustrative example (a real EEG cap commonly carries a spare ECG
  channel for cardiac-artifact ICA-component identification) -- not ECG
  *support*, and removing the example would make the comments less
  useful, not more accurate.

Verified: `checkcode` clean on `SignalView.m`, `AlakazamPlotter.m`,
`ScalpDistribution.m`. A functional test against a real EEGLAB dataset
(`12_P3_corrected_elist.set`) confirms `SignalView` still constructs and
redraws correctly, `IbiColors`/`drawIbiMarkers` no longer exist on the
class, `Overlay` no longer carries an `IbiEvents` field, no `'ibi'`-tagged
graphics object is ever produced, and the generic `eeg.event`-driven
overlay path still runs without error.

## Fixed: point-event markers had silently stopped drawing at all

Found while checking that ECG removal (previous entry) hadn't disturbed
the generic EEG event overlays: the user separately noticed real
`AlakazamPlotter` plots weren't showing event markers at all. Root
cause, confirmed against a real EEGLAB dataset
(`12_P3_corrected_elist.set`): `SignalView.parseOverlays`'s point-event
line, `overlay.EventTime = eeg.times(latency(isPoint))`, indexes
`eeg.times` directly with raw EEGLAB event latencies -- which are
fractional sample positions (e.g. `745.75`), not integers. MATLAB throws
`Array indices must be positive integers or logical values` on that,
silently swallowed by `parseOverlays`'s own `try/catch` ("leave overlays
empty if the event structure is malformed"), so `EventTime` came back
empty for every real dataset with sub-sample-precision latencies --
`drawPointEvents` then had nothing to draw, with no visible error
anywhere. The sibling `AreaTime` line two lines below already had the
right fix in place (`eeg.times(max(1, floor(latency(isArea))))`);
`EventTime` was just missing the equivalent clamp-and-round. Fixed to
`eeg.times(max(1, round(latency(isPoint))))` (round rather than
`AreaTime`'s floor, since a point marker's own position benefits from
nearest-sample accuracy rather than truncation to a window-start
boundary). This bug predates the ECG-removal work above and is unrelated
to it -- `parseOverlays`'s event-parsing block was carried over verbatim
in that change.

Also raised `MaxEvents` (the density cap bounding how many point-event
cursors a single window may show before `drawPointEvents` bails out
entirely rather than flooding the axes) from 30 to 100, since 30 proved
too easily exceeded on real recordings with dense stimulus/response
markers -- e.g. `12_P3_corrected_elist.set`'s zoomed-out view alone has
403.

Verified: `checkcode` clean on `SignalView.m`. Confirmed directly against
the real dataset that `latency(1) = 745.75` reproduces the exact
swallowed exception; after the fix, `parseOverlays` returns all 403
`EventTime` values instead of `[]`, and a manually-constructed `cursor()`
call with real overlay data succeeds and renders. Full end-to-end
verification through `SignalView.redraw()`'s own zoom/scroll-driven
window math was inconclusive in this headless environment specifically
(a `uifigure('Visible','off')` never lays out, so `AxWidthPx`/`AxWidthCm`
stay at their construction-time placeholder values, the same known
"stale axes width" gotcha `AlakazamPlotter.plotCurrent`'s `drawnow`
already works around for the *first* redraw elsewhere -- see the
SignalView-initial-view-width entry earlier in this file) -- not a
defect in the fix itself, just a limitation of driving zoom/pan math
without a real, visible, laid-out figure. Recommend an interactive
sanity check (open a continuous dataset, confirm event markers now
appear while scrolling) to fully close this out.

## Fixed: a tree with exactly one node rendered totally blank

The user reported the Grand Averages tree was "totally empty" after a
full MATLAB restart, alongside repeated "HTMLSource may be referencing
unsupported functionality or may have a JavaScript error" console
warnings -- while the Data & Analyses tree (the sibling `WorkSpaceTree`
right above it) rendered fine. A first attempt to reproduce via a fresh
`startAlakazam()` and reading `Component.Data` directly in MATLAB
appeared to show the grand average ("tester", the user's real, only
saved grand average) present and correct -- which was the wrong layer to
check, and gave a false "works for me."

Root cause, found by dumping the *exact* JSON MATLAB actually sends
(`jsonencode(app.Workspace.GrandAveragesTree.Component.Data)`) rather
than trusting the MATLAB-side struct: `WorkSpaceTree.buildData()` built
`nodes` as a MATLAB struct array, and `jsonencode` (the same machinery
`uihtml`'s `Data` marshaling is built on) collapses a **1x1** struct
array to a bare JSON object instead of a single-element array --
confirmed directly: `jsonencode(repmat(struct('a',1),1,1))` gives
`{"a":1}`, not `[{"a":1}]`; 2+ elements and 0 elements both serialize
correctly, only exactly 1 does not. `alakazam-tree.js`'s `setNodes` does
`for (const n of nodes)`, and confirmed directly against the real
bundled JS that this throws `"nodes is not iterable"` on a bare object --
uncaught, surfacing as exactly the vague "may have a JavaScript error"
warning MATLAB reported, and leaving the tree completely unrendered
(the exception fires before any node is processed). This reproduces for
*any* tree with exactly one node -- most commonly the Grand Averages
tree, since it is entirely plausible to have saved only one grand
average, while the Data & Analyses tree almost always has several nodes
(every raw import plus its whole analysis chain) and so essentially
never hits the collapse.

Fixed by building `nodes` as a **cell** array instead of a struct array
(confirmed: `jsonencode({struct('a',1)})` gives `[{"a":1}]`, reliably an
array regardless of count) -- sidesteps the struct-array collapse
entirely rather than special-casing `count == 1`. Assigned into the data
struct as `struct('nodes', {nodes}, ...)` (double-wrapped, not
`struct('nodes', nodes, ...)`): `struct()`'s own cell-value convention
otherwise treats an unwrapped cell array as "one struct element per
cell" (broadcasting into a struct *array*), which is the opposite of
what is needed here -- a scalar `data` struct whose one `nodes` field
holds the whole cell array intact.

Verified: `checkcode` clean. Confirmed directly against the real,
previously-affected data (`jsonencode` of a real, fresh
`startAlakazam()`'s `GrandAveragesTree.Component.Data` with the user's
actual one saved grand average, `tester.mat`) that `nodes` now starts
with `[`, a real array. Reproduced the JS-side crash directly against
the real bundled `alakazam-tree.js` with the exact pre-fix bare-object
payload (`"nodes is not iterable"`), and confirmed the fixed one-element
array payload renders correctly (`icons.length === 1`) -- both the
failure and the fix are demonstrated against the real code, not
inferred. A new headless MATLAB test
(`test_workspacetree_single_node_array.m`) builds a real `WorkSpaceTree`
and checks the raw `jsonencode`'d shape of `Component.Data` at 0, 1, and
2 nodes, asserting `nodes` always starts with `[` -- the JSON *text*
itself, since `jsondecode` collapses a genuine one-element array back to
a scalar struct too, so a decoded round-trip can't tell a real
single-element array apart from the bug it's meant to catch.

## Surfacing JS-side tree render failures as a real, readable warning

Immediate follow-up, prompted by the diagnosis cost of the bug above:
the only visible symptom on the MATLAB side was a vague, generic
"HTMLSource may be referencing unsupported functionality or may have a
JavaScript error" console warning, with no message, no stack trace, and
no indication of which tree or what actually went wrong -- because
`uihtml`'s JS runs inside its own embedded CEF browser process, and a
JS exception there has no language-level bridge back into MATLAB. It
just dies in that browser's own (invisible from MATLAB) devtools
console unless something explicitly reports it back.

`src/webtree/src/bridge.js`'s `applyData` (previously bare, no
try/catch around `tree.setNodes(...)`) now wraps that call: on an
exception, it `console.error`s the real error (in case devtools ever is
attached) and, more importantly, sends a new `renderError` event back to
MATLAB via `sendEventToMATLAB('renderError', {message, stack})` --
`String(e.message)`/`String(e.stack)`, so it survives the MATLAB<->JS
JSON bridge as plain text regardless of `Error` object serialization
quirks. `WorkSpaceTree.m` gained a matching `RenderErrorFcn` callback
property (alongside the existing `SelectionChangedFcn`/`NodeDroppedFcn`/
etc. family) and an `onEvent` case dispatching to it with
`struct('Message', d.message, 'Stack', d.stack)`. `WorkSpace.
CreateTreeComponent.m` wires both trees' `RenderErrorFcn` to a new
`Alakazam.onTreeRenderError(this, eventData, sourceTree)`, which names
which of the two trees failed (`Workspace.GrandAveragesTree` vs. the
data tree, compared via `isequal(sourceTree, ...)`) and prints the real
message and stack via `warning('Alakazam:treeRenderError', ...)` -- a
warning rather than a dialog, since this always indicates an actual bug
in `src/webtree`, not something the analyst did wrong or can act on
beyond reporting it.

Verified end to end against the real bundled JS, not just individual
pieces in isolation: fed `bridge.js`'s real `setup()` function the exact
bare-object payload that caused the original bug and confirmed it now
sends a `renderError` event carrying the real message
(`"nodes is not iterable"`) and a real stack trace naming `setNodes`,
rather than silently failing. A new headless MATLAB test
(`test_tree_render_error_surfaced.m`) drives a real `WorkSpaceTree`
through its actual `HTMLEventReceivedFcn` with that exact payload,
confirms `RenderErrorFcn` receives the real message and stack, and
confirms a replica of `onTreeRenderError`'s own warning formatting
produces readable, specific output naming the tree and the error --
composed together, this closes the loop from "silent blank tree with a
useless warning" to "a specific, actionable MATLAB warning naming
exactly what broke." `checkcode` clean on `WorkSpaceTree.m`,
`Alakazam.m`, `@WorkSpace/CreateTreeComponent.m`. `dist/alakazam-tree.html`
copied to `src/WorkSpaceTree.html`; the existing `test_node.mjs` suite
(which bundles only `alakazam-tree.js`, not `bridge.js`) still passes
unchanged.

## Export: Grand Averages to an R-compatible CSV

First real export capability in the app (`dependencies.md`'s own
gap-analysis audit had flagged that `ExportsDirectory` was a configured-
but-unused setting -- nothing anywhere ever wrote into it). Added a
"Export Grand Averages..." button to the ribbon's Grand Average tab,
right alongside the existing "Define Grand Average...", with a new
hand-drawn icon (`src/Icons/ExportGrandAverages.svg`, matching the rest
of the icon set: 24x24 viewBox, `#4a7fc9` stroke, `fill="none"` -- a
small data table with an arrow breaking out of it, for "tabular data
leaving the app").

**Scope: bulk, not per-node.** One button exports *every* Grand Average
currently in `Workspace.GrandAveragesTree` into a single CSV, rather than
requiring a tree selection first -- the simplest possible UI for "get
everything I've computed into R", and the long/tidy output format (below)
already carries a `grand_average` column to filter/facet by on the R
side, so a combined file loses nothing a per-file export would have kept.

**Format**: long/tidy, not a wide channel x time matrix -- one row per
(grand average x bin x channel x time point), columns `grand_average,
bin, channel, time_ms, amplitude, sem, n_subjects`. This is what R's
`read.csv()` + `ggplot2`/`dplyr` expect directly with no reshape needed
(`ggplot(df, aes(time_ms, amplitude, colour = bin)) + geom_line() +
facet_wrap(~channel)`). `n_subjects` (constant per grand average) is
written as `NA` when unknown; an individual `NaN` amplitude/sem sample
is left as literal `NaN` text rather than forced to `NA`, since forcing
it would break the vectorized numeric write for what is the exception
case, not the rule -- confirmed R's own `as.numeric()`/`read.csv()`
parse `"NaN"` into R's own `NaN` correctly either way (`is.na(NaN)` is
`TRUE` in R), so both spellings resolve to "missing" on the R side.

**New files/methods**:
- `src/exportGrandAveragesCSV.m` -- the actual writer, a plain function
  (not a method) taking a `WorkSpaceTree.allNodes()`-shaped struct array
  and a target path, kept separate from `Alakazam.m` the same way
  `GrandAverage.m` (computation) is already kept separate from
  `Alakazam.saveGrandAverage` (UI orchestration). Writes one `fprintf`
  call per (grand average x bin x channel) -- the row-constant text
  fields (grand average name, bin label, channel label, n_subjects) are
  baked into that call's format string as literal text (`%%`-escaped
  around the numeric placeholders that do cycle), and the whole time
  series is written in one shot via `fprintf`'s normal numeric-matrix
  cycling -- not one `fprintf` per row, which would mean hundreds of
  thousands of calls for a realistic dataset. Confirmed fast in practice:
  23,808 rows (31 channels x 256 samples x 3 bins, the user's own real
  `tester.mat`) exported in 0.14s.
- `WorkSpaceTree.allNodes()` -- new public accessor returning every
  current node in the same `struct(Id,Name,UserData,IsRoot)` shape
  `SelectedNodes`/`addNode` already use. Added rather than having
  `Alakazam.m` reach into `Component.Data` directly, since `Alakazam.m`
  never does that anywhere else -- every other tree read goes through a
  proper `WorkSpaceTree` accessor, and this keeps it that way.
- `Alakazam.onExportGrandAverages` -- ribbon dispatch target
  (`onRibbonAction`'s new `'exportGrandAverages'` case): guards against
  zero grand averages (`msgbox`, not silently exporting an empty file),
  prompts via `uiputfile` defaulting into `Workspace.ExportsDirectory`,
  wraps the actual write in the same watch-cursor/`onCleanup` pattern
  `rawclear.m` already established this session, and reports success/
  failure via `msgbox`/`warndlg` matching `onDefineGrandAverage`'s own
  existing error-handling convention.

Verified: `checkcode` clean on `AlakazamRibbon.m`, `Alakazam.m`,
`WorkSpaceTree.m`, `exportGrandAveragesCSV.m`. Ran the exporter directly
against the user's real `tester.mat` grand average and confirmed: row
count exactly matches `nChan x nSamples x nBins`; the file round-trips
cleanly through `readtable` with every column inferring the expected
type (text for `grand_average`/`bin`/`channel`, numeric for the rest) --
exactly what R's `read.csv()` would also infer. Ran the full path a
second time through a real `startAlakazam()` instance
(`Workspace.GrandAveragesTree.allNodes()` -> `exportGrandAveragesCSV`),
confirming the real, live tree enumeration and exporter work together
correctly, not just in isolation. Confirmed the ribbon itself actually
exposes the new button: dumped `AlakazamRibbon`'s real `Component.Data`
JSON and found `exportGrandAverages` present with the correct label,
tooltip, and a properly base64-encoded `data:image/svg+xml` icon.
`uiputfile`'s own interactive dialog cannot be driven headlessly, so the
save-path-selection step itself was not exercised end-to-end; everything
around it (guard, exporter, tree enumeration, ribbon wiring) was.

## New transformation: TimeFrequency (wavelet ERSP plots, Plots section)

A new pure-plot transformation, `src/Transformations/TimeFrequency/`,
added to the ribbon's existing "Plots" group (alongside
`ScalpDistribution`). Computes an event-related spectral perturbation
(ERSP) heatmap per bin: complex Morlet wavelet convolution against every
trial in a bin, variable wavelet cycles growing linearly with frequency
(EEGLAB `newtimef`'s own time/frequency-resolution tradeoff -- few cycles
at low frequencies for temporal precision, more at high frequencies for
spectral precision), single-trial power averaged across a bin's trials,
then dB-baseline-corrected against a user-set pre-stimulus window. One
tile per bin (up to 3 per row, matching `ScalpDistribution`'s own tiling),
a shared symmetric colour scale across every bin so they stay visually
comparable, and a hand-built diverging blue/white/red colormap centred on
0 dB (MATLAB ships no built-in diverging colormap). Every channel x bin
is computed once up front with a progress bar; Up/Down arrow keys then
just re-slice the already-computed array and redraw -- instant, rather
than re-running the wavelet convolution live on every channel step (which
would be multi-second-per-keypress, unlike this app's other keyboard-
driven views).

**New files**:
- `src/Transformations/TimeFrequency/TimeFrequency.m` -- the
  transformation entry point: validates `DataFormat == 'EPOCHED'` and a
  non-empty `bindesc` (time-frequency power needs individual trials, not
  an already-averaged ERP), a `uiextras.settingsdlg` options dialog
  (frequency range, wavelet cycles, baseline window) remembered
  per-workspace via `TransformSettings` (matching `Baseline.m`'s
  pattern), builds the tiled `uifigure`/`uiaxes` heatmap grid, and owns
  the arrow-key channel-stepping.
- `src/Transformations/+TransTools/ComputeErsp.m` -- the actual wavelet
  computation, pulled out of `TimeFrequency.m` into the existing
  `+TransTools` shared-helper package (alongside `CreateFilter.m`/
  `WindowByName.m`) specifically so it can be called and verified
  directly, without going through `TimeFrequency.m`'s own blocking
  options dialog. One shared `nfft` (sized for the widest/lowest-
  frequency wavelet) lets each trial's FFT be computed once and reused
  across every frequency's wavelet multiplication. A bin with no matched
  trials leaves its slice of the output as `NaN` rather than erroring.
- `src/Transformations/TimeFrequency/TimeFrequency.json`,
  `TimeFrequency.png` (24x24 RGBA icon, built directly as a MATLAB pixel
  array via `imwrite(..., 'Alpha', ...)` rather than rasterized from SVG
  -- no SVG rasterization tool, e.g. `rsvg-convert`/`inkscape`/`magick`/
  `cairosvg`, is available on this machine), and `src/Icons/
  TimeFrequency.svg` (hand-drawn SVG design source, matching the PNG's
  exact grid/opacity layout, added per the user's specific request for
  an SVG version alongside the PNG -- following the existing
  `Fourier.svg`/`Average.svg`/etc. source-alongside-runtime-PNG
  convention).

**API pitfalls caught while building this** (both fixed before this was
considered done, not left as latent bugs): `TransTools.progressbar` has
no output argument and uses `persistent` internal state (a first draft
wrongly assumed a handle-returning API, `h = progressbar(0, 'title')`,
matching neither the real signature nor `Fourier.m`'s actual usage); and
a bin with zero matched trials has to still call `TransTools.progressbar`
in its skip branch, not just advance the internal counter, or a dataset
whose *last* bin happens to be empty would never send the
`fractiondone==1` call that auto-closes the popup.

**MATLAB subfunctions aren't independently testable**: the ERSP
computation started as a local function inside `TimeFrequency.m`, then
had to be extracted to `+TransTools/ComputeErsp.m` once it became clear a
local function can't be called from an external test script without
going through the file's own blocking dialog -- this is the concrete
reason `ComputeErsp.m` exists as a separate file rather than staying
inline.

Verified: `checkcode` clean on both `TimeFrequency.m` and
`ComputeErsp.m`. Built a synthetic epoched dataset (40 trials, 3
channels, two bins) with a real, randomly-phased 10 Hz sinusoidal burst
injected into one bin only during a post-stimulus window (200-600 ms),
absent from the pre-stimulus baseline and from the second, deliberately
empty bin. `TransTools.ComputeErsp` correctly reported +26.9 dB at ~10 Hz
during the burst window vs. +0.5 dB outside it and +0.4 dB at a
far-off (~31 Hz) frequency during the same window -- confirming the
wavelet convolution, trial-averaging, and baseline correction are all
correct together, and that the result is properly time- and frequency-
specific, not just generally noisy. The empty second bin came back
entirely `NaN` with no crash. Separately confirmed ribbon discovery:
constructed a real `AlakazamRibbon` against the actual
`src/Transformations` folder and dumped its `Component.Data`, confirming
`TimeFrequency` is grouped into the "Plots" ribbon section alongside
`ScalpDistribution` with a correctly base64-encoded PNG icon. Confirmed
`TimeFrequency.png`'s format (24x24, truecolor+alpha, 24-bit) exactly
matches an existing icon (`Average.png`) via `imfinfo`. Not yet
exercised: the actual UI (options dialog, heatmap rendering, arrow-key
stepping) through a live `startAlakazam()` session -- `uiextras.
settingsdlg` blocks on user input and can't be driven headlessly, so this
still needs a manual interactive check.

## TimeFrequency: converted from a pure plot to a persisted, tree-node result

Follow-up to the above: TimeFrequency (and, in spirit, ScalpDistribution --
see the next section) started as a "pure plot" transformation (see
`Alakazam.onTransformation`'s `ishandle(result.EEG)` short-circuit): it
returned a graphics handle, so nothing was persisted or added to the tree,
matching `ScalpDistribution`'s existing precedent. On request, TimeFrequency
is now a normal, persisted transformation instead -- it gets a tree node
under the epoched dataset it was run on, and opens in its own tab in
`PlotsTabGroup`, the same way `Average`/`Fourier` results do.

**Signature change**: `[pfigure, ropts] = TimeFrequency(input, ~)` ->
`[EEG, opts] = TimeFrequency(varargin)`, matching `Fourier.m`'s own
1-or-2-arg contract exactly (`TimeFrequency(input)` pops the options
dialog and stores the choice in `TransformSettings`; `TimeFrequency(input,
opts)` replays with a stored options struct and no dialog -- the form used
when a branch bearing this transformation is dragged onto another
dataset). All the validation and the `TransTools.ComputeErsp` call are
unchanged; the returned `EEG` is `input` carried forward (`.data`,
`.chanlocs`, `.bindesc`, etc. all untouched and still meaningful) plus two
new fields, `.ersp` and `.freqs`, that the new view draws from -- `.data`
itself is deliberately left alone rather than overwritten, since TimeFrequency
computes a derived visualization, not a reshape of the same signal (unlike
`Average`, which does replace `.data`).

**New file**: `src/TimeFrequencyView.m` -- a new View class (the app's
fifth: `EpochView`/`AverageView`/`FourierView`/`SignalView` were the only
family members before this, and none of them draw a multi-tile grid, so
this establishes that pattern for the first time). Follows the existing
View contract exactly: `(fig, eeg)` constructor building into the given
uitab directly (no owned `uifigure` of its own, unlike the transformation's
previous pure-plot incarnation), a public `redraw()`, a public `onKey`
handling up/down arrow channel-stepping, and the `ActivatedFcn`/
`notifyActivated()` boilerplate every other View class carries. Internally
it is the previous pure-plot version's own tile-grid/heatmap/colormap code,
relocated wholesale from a standalone `uifigure` into `uigridlayout`/
`uiaxes` children of the tab.

**Dispatch**: `AlakazamPlotter.plotEpoched` checks `eeg.id` (stamped by
`Alakazam.persistResultNode` to the transformation's own id, and -- unlike
`.DataFormat`/`.DataType` -- unique enough to identify "this specific
transformation's result needs a dedicated view") before falling through to
the existing `DataFormat`/`DataType` routing: a TimeFrequency result is
still `DataFormat = "EPOCHED"` with `trials > 1`, so without this check it
would silently fall into `EpochView`, which cannot draw an ERSP heatmap.
Added `"TimeFrequencyView"` to `Alakazam.dispatchKey`'s hardcoded view-name
list too, or its arrow-key channel-stepping would never receive events.

**A real bug caught by testing, not just checkcode**: `uilabel.Layout.
Column = [1 nCols]` throws ("must be ... a 1x2 increasing array") when
`nCols == 1` (a single-bin dataset) -- `[1 1]` is not strictly increasing.
This exact pattern existed unchanged in the pre-conversion `TimeFrequency.m`
too, but was never actually exercised with a single-bin dataset by any
earlier test in this project (every prior functional test used 2+ bins).
Fixed in `TimeFrequencyView`'s constructor: set the label's `Layout.Column`
to a plain scalar `1` when `nCols == 1`, the `[1 nCols]` range only when
`nCols > 1`.

Verified: `checkcode` clean on `TimeFrequency.m`, `TimeFrequencyView.m`,
`AlakazamPlotter.m`, `Alakazam.m`. A full headless functional test built a
minimal stand-in "app" (just the `PlotsTabGroup`/`MainFigure`/
`registerTileClick`/`refreshPlotsView` surface `AlakazamPlotter.plotCurrent`
actually touches) and drove the real, unmodified `AlakazamPlotter` +
`TimeFrequencyView` classes end to end: confirmed the 2-arg replay form
returns a real, correctly-shaped struct (not a handle); confirmed
`plotCurrent` creates exactly one tab, tagged with the result's own file
path (the tab-reuse/close/tile key every other transformation relies on);
confirmed it dispatches specifically to `TimeFrequencyView` and *not* also
to `EpochView`/`AverageView`/`FourierView`; exercised up/down arrow-key
channel stepping including edge clamping, and confirmed the redrawn tile's
`CData` actually matches the newly-selected channel's ERSP slice (not just
that `redraw()` ran without erroring); confirmed a second `plotCurrent()`
call for the same result file reuses the existing tab rather than
duplicating it. Separately re-tested with a 4-bin dataset (2x3 tile grid,
wrapping rows) to regression-guard the `Layout.Column` fix's `nCols > 1`
branch. Not yet exercised: the real interactive UI end to end (options
dialog, drag-and-drop replay onto a sibling dataset, right-click tab
close, Grid/Stack tiling) through a live `startAlakazam()` session.

## TimeFrequency: two user-reported bugs, both fixed

Two real bugs reported after the conversion above, both fixed in
`TimeFrequencyView.m`/`TransTools/ComputeErsp.m`:

**Axes not tightly bound to the data's real range.** `imagesc(ax, x, y,
C)` sets `XData`/`YData` but does not itself constrain `XLim`/`YLim` to
those vectors' extent -- axes default to "auto" limits, which MATLAB
rounds out to the next "nice" tick value (e.g. a 1000 ms epoch spanning
-200 to 800 ms was shown with an axis running -400 to 800 ms; 0-40 Hz
shown as 0-45 Hz). Fixed by pinning each tile's axes explicitly:
`xlim(ax, [eeg.times(1), eeg.times(end)]); ylim(ax, [eeg.freqs(1),
eeg.freqs(end)]);`, right after the `imagesc` call in
`TimeFrequencyView`'s constructor.

**A difference/combo bin ("Effect = bin2 - bin1") rendered as a solid,
meaningless block.** Root cause: `DefineBins.m` leaves `bindesc(b).trials
= []` for a combination bin (it has no trials of its own -- see
`DefineBins.m:701`, `binRecord`), so `ComputeErsp`'s existing
empty-trials guard left its whole `ersp(:,:,:,b)` slice as `NaN`. NaN
pixels render using the colormap's edge colour rather than a distinct
"missing" colour, which is exactly what looked like "a full, massive
blue block" (the diverging colormap's low end). `Average.m` already has
the right pattern for this exact kind of bin (`Average.m:81-143`):
resolve combo bins in dependency order, computing each as the
coefficient-weighted sum of the bins its `.combo` struct array
references. Ported the same scheme into `ComputeErsp.m`: after computing
every ordinary (non-combo) bin's ERSP as before, a second pass walks
combo bins in dependency order (repeating until every one resolves or a
pass makes no further progress, so a combo-of-a-combo, e.g. an
interaction effect, still works) and sets `ersp(:,:,:,b) = sum(coeff_t *
ersp(:,:,:,refPos_t))`. This is a legitimate operation specifically
because ERSP is already in dB (log-power): a signed sum of dB values
across bins is exactly the standard ERSP contrast/difference map
convention, the same reasoning that lets `Average.m` sum plain voltage
averages (linear to begin with) for the same kind of bin. The
progress-bar's `total` denominator now only counts non-combo bins (the
combo pass itself is cheap arithmetic, not wavelet convolution, so it
needs no progress reporting of its own); guarded the pathological
all-combo-bins case (`total` would otherwise be `0/0`) by flooring
`total` at 1 and force-closing the popup if no ordinary bin ever ran.

Verified: extended the headless test suite with a 3-bin synthetic
dataset (two ordinary bins with disjoint trial subsets, plus a genuine
`DefineBins`-shaped combo bin -- `.combo = struct('coeff', {1,-1}, 'bin',
{2,1}, ...)`, referencing the other two bins **by their `.index` field,
not array position**, matching `DefineBins.m`'s real convention).
Confirmed the difference bin's ERSP is no longer `NaN`/constant, and is
**exactly** bin 2's ERSP minus bin 1's ERSP element-for-element (max
absolute difference < 1e-9), not merely "some now-plausible numbers".
Confirmed the two ordinary bins are still computed normally (the
`isCombo` filtering did not accidentally skip real bins). Separately
confirmed every tile's `XLim`/`YLim` after construction exactly equals
`[eeg.times(1) eeg.times(end)]`/`[eeg.freqs(1) eeg.freqs(end)]` for a
deliberately "non-round" epoch window (-200 to 800 ms), not MATLAB's
auto-rounded bounds. Re-ran every previous TimeFrequency test (the 10 Hz
burst-detection test and the full tree/tab/`AlakazamPlotter` end-to-end
test) to confirm neither fix regressed anything already verified;
`checkcode` clean on both changed files.

**Follow-up**: every tile shares the same frequency range, one shared
colour scale, and one shared colorbar already, so repeating the
frequency-axis ticks/label on every single tile was pure clutter. Only
the leftmost tile in each row (`col == 1`) now shows `ylabel(ax,
"Frequency (Hz)")`; every other tile has `ax.YAxis.Visible = "off"`
(hides the ruler -- ticks, tick labels, axis label -- but not the
plotted data itself). Verified directly against a 5-bin (2-row, `nCols =
3`) grid: bins 1 and 4 (column 1 of each row) have `YAxis.Visible ==
"on"`, every other bin has it `"off"`.

## ScalpDistribution: initially NOT converted -- a real topoplot/uiaxes conflict (superseded, see below)

Attempted the same conversion for `ScalpDistribution` (also requested), but
hit a genuine, confirmed architectural blocker before writing any
conversion code: `ScalpDistribution.m`'s own existing comments already flag
that EEGLAB's `topoplot` needs a classic figure (`gca`/`gcf`, direct legacy
patch calls), which is why it currently opens its own classic `figure()`
rather than a `uifigure` -- `PlotsTabGroup`'s tabs, however, are
`uifigure`-family only.

Tested directly (not just inferred from the comment) whether that
constraint still holds in this MATLAB version: `uicontrol` and `axes(...)`
targeting a `uiaxes` inside a `uitab` both now run without error (an
apparent relaxation in recent MATLAB versions of what used to be a hard
block) -- but `topoplot` itself, called that way, silently draws **zero
graphics children** into the target `uiaxes` rather than actually
rendering the scalp map, and `axes(uiaxesHandle)` turned out to still
create/switch to a brand-new separate classic axes elsewhere rather than
truly making the `uiaxes` current. So the failure mode moved from "throws
an error" to "silently renders nothing" -- arguably worse, since it would
not be caught by casual testing. `ScalpDistribution` therefore still opens
its own classic-figure pure plot, unconverted, pending a decision on how to
resolve this (see the conversation for the options discussed: hand-rolling
a `uiaxes`-compatible scalp-topography renderer without `topoplot`, versus
a lighter-weight compromise).

## Tree drag threshold: a click with slight cursor movement was registered as a drag

Reported: "clicking a tree branch, then moving the cursor while clicking,
gets registered as a drag." Root cause: two compounding bugs in the
vendored `yy-tree` dependency (`src/webtree/node_modules/yy-tree`, pulled
in at build time, not part of this repo's own source), confirmed directly
against its real source rather than assumed:

1. `Input._checkThreshold` (`yy-tree/src/input.js`) computes the mouse-move
   distance since mousedown but only checks its **truthiness**, never
   actually compares it against any threshold -- so literally any cursor
   movement at all, even a single pixel of ordinary mouse jitter during a
   click, immediately starts a drag.
2. The `threshold` constructor option `yy-tree`'s own JSDoc documents
   (`@param {number} [options.threshold=10] number of pixels to move to
   start a drag`) is a dead option: `defaults.js` declares it and `Tree`'s
   constructor accepts it into `this._options`, but `Tree` never exposes it
   via a getter (unlike every *other* documented option -- `move`,
   `select`, `holdTime`, etc. all have one) and nothing in the library ever
   reads it back. So even fixing bug 1 to compare against `tree.threshold`
   compares against `undefined`, which is never `> anything` -- confirmed
   empirically (a debug script showed `tree._tree.threshold === undefined`
   even after passing `threshold: 10` in the constructor options) before
   settling on a fix, not assumed.

**Fix** (`src/webtree/src/alakazam-tree.js`): patched as a runtime instance
override, `this._tree._input._checkThreshold = function (e) {...}`, right
after `new Tree(...)` in the constructor -- not a source edit, since
`yy-tree` is a vendored npm dependency, not part of this file. Compares the
real Euclidean distance against a new local constant,
`DRAG_THRESHOLD_PX = 10`, defined in this file rather than trying to read
back `tree.threshold`/`tree._options.threshold` (the latter would work,
since `_options` does hold the value, but reaching into a documented-as-
private, `_`-prefixed field of a third-party library for a value it never
itself honours is worse than just owning the constant outright). Logic is
otherwise identical to the original `_checkThreshold`.

**Node.js is actually available in this environment** (`v24.18.0`,
confirmed via `node --version`), contrary to an earlier, now-stale note in
this project (`src/webtree/README.md`/an earlier planning doc claimed no
Node install existed anywhere on the machine). This fix was therefore
built and verified the *right* way -- edit `alakazam-tree.js`, run the real
`npm run build` (`esbuild` -> `assemble.mjs`), and copy the real output
over `src/WorkSpaceTree.html` -- rather than hand-syncing the two files by
inspection, eliminating any risk of manual transcription drift. (A first
attempt at this fix *was* hand-synced into `WorkSpaceTree.html` before
Node was confirmed available; diffing it against the first real build
afterwards showed it was byte-identical modulo line endings, but it also
carried forward the exact same "compares against `tree.threshold`, which
is `undefined`" mistake the real build's own test run then caught -- see
below. That hand-edit was fully superseded by the real, tested build
before landing.)

**Caught by the project's own test suite, not manual inspection**: the
existing `src/webtree/test_node.mjs` regression suite (also run via a real
`node test_node.mjs`, previously believed to need Node too) already had
two `down(x, 10, 10); move(15, 15)` calls meant to simulate crossing the
drag threshold, with a comment explicitly acknowledging they relied on the
*old, buggy* "any movement at all" behaviour ("any non-zero movement
crosses yy-tree's threshold check"). Distance from (10,10) to (15,15) is
~7.07px -- comfortably *under* the new, correctly-enforced 10px threshold
-- so fixing the bug correctly broke these two pre-existing tests
(`AssertionError: sanity: dragging cursor should be on mid-drag`), which is
exactly what should happen to a test that was unknowingly depending on the
bug. Updated both to `move(30, 30)` (~28px, clearly past threshold) and
corrected their comments. Added a new dedicated regression test for the
actual reported bug: mousedown, a small `move(13, 12)` (~3.6px, well under
threshold), then mouseup on a *different* node (so as not to disturb the
adjacent double-click test's own timing-sensitive state) -- asserts
`_moving` never became true and the interaction still produces exactly one
`nodeClicked` event, not a drag.

Verified: `node src/webtree/test_node.mjs` -- the full suite (render/
click/double-click/context-menu, drop-always-reverts logic, drag-cursor/
busy-cursor/drop-target-highlight toggling, the mouseleave-mid-drag grace-
period state machine, and the new sub-threshold-jitter test) passes
against the real, freshly-built bundle. Confirmed genuine real drags (a
deliberate move well past 10px) still work correctly throughout -- this
was not a blanket "never drag" fix, only a "don't drag on tiny, accidental
movement" fix. `src/WorkSpaceTree.html` was regenerated by the real build
pipeline (`npm run build` in `src/webtree/`), not hand-edited.

## ScalpDistribution: converted after all -- ported topoplot() instead of calling it

Follow-up to the section above: asked to revisit this specifically ("we
have the sources...") -- since EEGLAB's `topoplot.m` is plain, readable
MATLAB source (not a compiled/mex black box), the actual fix was to port
its core algorithm to a new `TransTools.DrawScalpMap.m`, targeting an
explicit axes handle throughout (`surface(ax,...)`, `contour(ax,...)`,
`patch(ax,...)`, `plot(ax,...)`) instead of `topoplot`'s own implicit
`gca`/`gcf` state, rather than trying to coerce `topoplot()` itself into
working inside a `uiaxes`.

**Scope**: `DrawScalpMap` is a restricted port, not a general
reimplementation of every `topoplot` option -- only the exact code path
`ScalpDistribution.m`'s own call used (`STYLE='both'`, `SHADING='flat'`,
`ELECTRODES='on'`, `EMARKER='.'`, `headrad=rmax=0.5`, `CONVHULL` off, no
`EMARKER2CHANS`/grid/colorbar): interpolate electrode values onto a 67x67
grid via `griddata(...,'v4')` (a pure computation, no graphics dependency
at all, hence no porting needed there), mask outside the head circle,
draw the colour-filled surface + 6 contour lines, a masking ring to hide
the jagged grid boundary, the cartoon head/nose/ears outline (fixed
geometry, ported verbatim from `topoplot.m`'s own hand-drawn `EarX`/`EarY`
point arrays), and electrode marker dots.

**A real, non-obvious coordinate bug caught only by testing against the
actual template data, not documentation**: `topoplot.m`'s own help text
states "0 deg. points to the nose," which was the natural first
assumption for the pol2cart-based coordinate swap `DrawScalpMap` needed
(`[px,py]=pol2cart(theta,radius)`, plotted as `(py,px)`). Verified this
directly against the real `Dipfit1005File` standard 10-5 template (not
assumed) and found it does **not** hold for that template's raw
`chanlocs.theta`: frontal/occipital electrodes (Fpz, Fz, Oz) landed on the
*horizontal* axis, not vertical. Root cause: `topoplot.m` **always**
re-derives `Th`/`Rd` via a second `readlocs(loc_file)` call internally
(`topoplot.m:692-694`), even when already given a struct with `.theta`/
`.radius` set -- so a template's raw `.theta`/`.radius` fields are not
necessarily what `topoplot()` would actually plot with. Fixed by calling
the identical `readlocs(chanlocs)` inside `DrawScalpMap` too (using its
`Th`/`Rd`/`indices` outputs, reordering/subsetting `values` to match
`indices` exactly as `topoplot.m` does with its own `Values(indices)`),
rather than trusting the raw struct fields or a theoretical convention
from the help text.

**Verified against the real `topoplot()`, not an independent guess**:
built a real 6-channel test set (Fpz/Fz/Cz/Oz/T7/T8, resolved against the
real 10-5 template), ran the actual `topoplot(values, chanlocs,
'electrodes','labelpoint')` in a classic figure, and read back its own
drawn electrode-marker `Line` object's `XData`/`YData` directly (not the
accompanying text labels -- `topoplot.m:1554` deliberately offsets each
label's text position by `+0.01` horizontally for on-screen readability,
which is a red herring for marker-position comparison and cost one
debugging round-trip before being traced to that exact line). Compared
against `DrawScalpMap`'s own drawn marker positions for the identical
input: **exact match to floating-point precision (error 0.00000) on
every one of the 6 electrodes.**

**Conversion** (mirroring the same pattern as `TimeFrequency.m`/
`TimeFrequencyView.m`): `ScalpDistribution.m` is now `[EEG, opts] =
ScalpDistribution(input, opts)` (matching `Average.m`'s minimal-options
pattern -- it never had a real dialog). It resolves scalp positions once
(the expensive template lookup) and computes one shared, symmetric colour
scale across the *whole* dataset (every bin, every instant -- not just
whichever bins happen to be ticked at transform-time, so the scale stays
stable regardless of later tick changes), stamping `.ScalpChanlocs`/
`.ScalpHasPos`/`.ScalpMapLimit` onto the result. All drawing -- including
the actual live, cheap-enough-to-redo-per-frame `griddata` interpolation
-- moved into the new `ScalpDistributionView` (`src/ScalpDistributionView.m`),
the app's 6th View class: a tile grid (up to 3 per row, wrapping, the
`Layout.Column` `[1 1]`-rejection fix from `TimeFrequencyView` reused
here directly) plus a `uislider` (uifigure-native -- its
`ValueChangingFcn` fires continuously during the drag itself, the
uifigure-native equivalent of the previous classic-`uicontrol`-slider's
`PostSet`-listener trick, and arguably simpler; no more `positionGuard`
timer either, since `DrawScalpMap`'s `uiaxes` don't suffer the
colorbar-shrinks-my-axes quirk `topoplot`'s classic axes did).

**A layering fix required by the conversion itself**: the "only draw bins
ticked in the sibling AverageView tab" logic used to run *inside* the
transformation function, where `EEG.File` still pointed at the parent
Average dataset (before `Alakazam.persistResultNode` overwrites it with
this result's own new cache path). Moving that lookup into the View (the
only place with access to sibling tabs at all) broke it silently at
first, since by the time the View runs, `eeg.File` is already this
result's *own* file, not the parent's -- the AverageView sibling tab is
tagged with the parent's file, so the lookup never found it. Fixed by
having `ScalpDistribution.m` stash the parent's file explicitly as
`EEG.ScalpSourceFile = input.File` before returning (captured while
`input.File` still is the parent), with `ScalpDistributionView` looking
up siblings by that field instead of `eeg.File`. Also softened the
"every bin unticked" case from a hard error (the pure-plot version's own
behaviour) to a fallback showing every bin -- appropriate now that this
is a real, persisted, reopenable result rather than a one-shot plot.

Verified end-to-end: a real 2-bin synthetic Averaged dataset (6 real
10-5-labelled channels) run through `ScalpDistribution`, confirmed the
result carries resolved positions/map limit; drove the real, unmodified
`AlakazamPlotter` + `ScalpDistributionView` (same minimal stand-in "app"
technique as the `TimeFrequency` tests) and confirmed it dispatches to
`ScalpDistributionView` specifically (not `AverageView`, the collision
this id-check guards against, since a `ScalpDistribution` result is still
`DataFormat="AVERAGED"`/`trials==1`); confirmed the no-sibling-tab
fallback draws every bin with the correct shared `CLim`; confirmed
`redraw()` updates every tile and the time label without error; built a
*real* `AverageView` as a sibling tab, unticked one bin by driving its
actual `uicheckbox` (`Value` + firing its real `ValueChangedFcn`, not
reaching into the private `Visible` property directly), and confirmed a
freshly-constructed `ScalpDistributionView` correctly draws only the
still-ticked bin. Re-ran every `TimeFrequency` test afterward to confirm
the shared `AlakazamPlotter.plotEpoched` edit didn't regress anything
already verified there. `checkcode` clean on
`ScalpDistribution.m`/`ScalpDistributionView.m`/`DrawScalpMap.m`/
`AlakazamPlotter.m`. Confirmed via a real `AlakazamRibbon` instance that
`ScalpDistribution` is still correctly discovered in the "Plots" ribbon
group alongside `TimeFrequency` after the conversion. Not yet exercised:
the real interactive UI (slider drag feel, tile click-to-activate in
Grid/Stack mode) through a live `startAlakazam()` session.

## ScalpDistribution: three follow-up fixes (orientation, slider labels, colorbar)

Reported after the conversion above: "frontal electrodes are plotted on
the right ear -- the Oz-Cz-Fpz line should point up," the slider's tick
labels showed raw fractions, and the tile grid had no colorbar at all.

**Rotation.** The unrotated coordinates `DrawScalpMap.m` computes
(verified exactly against real `topoplot()` output, see the section
above) put the template's anterior-posterior line on the horizontal axis
for `Dipfit1005File`'s `standard_1005.elc` template, not vertical --
anatomically valid (it is exactly what real `topoplot()` itself draws for
this template) but not the conventional "nose up" cartoon-head
orientation most EEG viewers expect. Rotated 90 degrees clockwise on
request: `[a,b] = pol2cart(theta,radius)` (topoplot's own raw values,
unchanged) then `horiz = a; vert = -b;` (previously `[px,py] =
pol2cart(...)`, plotted directly as `(py,px)` with no rotation) -- the
standard clockwise-rotation identity for a screen point `(h,v) -> (v,
-h)`. Applied consistently everywhere `px`/`py` were previously used:
the interpolation grid's sample/query coordinates, the `griddata` call,
and the electrode marker plot. Verified two ways: (1) the existing
exact-match-against-real-`topoplot()` test now compares against the
*rotated* ground truth (`expected = [truthY(i), -truthX(i)]`) and still
matches to floating-point precision on all 6 test electrodes; (2) a new,
directly-readable anatomical assertion confirms Fpz lands well above
centre, Oz well below, T7 well left, T8 well right.

**Slider tick labels.** `uislider`'s own default `MajorTicks`/
`MajorTickLabels` are 5 raw, evenly-spaced fractions of `Limits` --
ugly whenever the time range's endpoints are not themselves round
numbers. Fixed in `ScalpDistributionView`'s constructor: `MajorTicks` is
now `round(linspace(times(1), times(end), 5))` and `MajorTickLabels` a
matching `sprintf('%.0f', ...)` per tick, both set explicitly rather than
relying on uislider's defaults.

**Single shared colorbar.** Every tile in the grid always carries the
same `CLim` (`DrawScalpMap` is always called with this dataset's one
`ScalpMapLimit`), so one colorbar describes every tile at once -- added
via `colorbar(this.Axes(min(nCols, nBins)))`, the exact same
last-tile-of-the-first-row placement convention `TimeFrequencyView`
already uses, labelled `"Amplitude (\muV)"` to match `AverageView`'s own
y-axis wording.

Verified: extended `test_scalpdistribution.m` with direct checks that
`Slider.MajorTicks` exactly equals the expected 5 rounded values,
`Slider.MajorTickLabels` are whole numbers with no decimal point and read
back exactly as expected via `str2double`, and `findobj(fig, 'Type',
'colorbar')` finds exactly one. Re-ran the full `ScalpDistribution` and
`TimeFrequency` test suites afterward -- all still pass. `checkcode`
clean on `DrawScalpMap.m` and `ScalpDistributionView.m`.

## Shared colorbar was shrinking its target tile -- fixed in both grid views

Reported: "the rightmost head now is plotted smaller." Root cause:
`colorbar(this.Axes(min(nCols, nBins)))` attaches the colorbar directly
to one real tile's axes, and MATLAB narrows that axes' own `Position` to
make room for it -- confirmed directly (not assumed) with a minimal
`uigridlayout` + two `uiaxes` test: the colorbar's target axes'
`InnerPosition` width shrank by ~17% the moment `colorbar(ax)` was
called, even with no aspect-ratio constraint at all. `ScalpDistributionView`
made this far more visible than `TimeFrequencyView`: `DrawScalpMap.m`
calls `axis(ax, 'square')` (matching `topoplot()`'s own behaviour), so
narrowing that tile's width to fit the colorbar also shrinks its *height*
to preserve the square aspect -- the exact same underlying mechanism the
pre-conversion classic-figure version's own `positionGuard` timer used to
fight (see its own comment, still in `migration.md`'s earlier
`ScalpDistribution` section) -- but this time triggered by our own
colorbar, not a user-added one, and inescapable rather than intermittent
without a similar counter-measure. `TimeFrequencyView`'s `imagesc` tiles
have no such constraint, so the same shrink there is real but subtler
(width-only, no visible height change) -- checked directly and confirmed
it was never actually fixed there either, despite being asked about "the
trick from TimeFrequency": no such trick currently exists in that file.

**Fix, applied to both views identically**: don't attach the colorbar to
any real tile at all. Reserve an extra, narrow (56px) trailing grid
column, create a dedicated `uiaxes` there with `Visible = "off"` and its
`CLim` set to the shared scale (`ScalpMapLimit` / the constant `climAbs`
computed over the whole `ersp` tensor), and attach the colorbar to that
invisible axes instead (`colorbar(colorbarAxes)`). Verified directly with
the same minimal reproduction: every real tile's `InnerPosition` is then
completely unaffected, to the pixel, by the colorbar's presence. The
hidden axes' `Layout.Row` spans every tile row (`[1, nRows]`, or a plain
scalar `1` when `nRows == 1` -- same `[1 1]`-rejection guard as
elsewhere) so the colorbar has the full grid height to draw across, not
just one row's worth.

Verified: added a direct size-parity check to both
`test_scalpdistribution.m` and `test_timefrequency_fixes.m` (both already
build multi-tile datasets) -- every tile's `InnerPosition` width/height,
read after a real `drawnow`, now matches every other tile's exactly, for
both views. Re-ran the full regression suite (`TimeFrequency`,
`ScalpDistribution`, `DrawScalpMap` orientation) afterward -- all still
pass. `checkcode` clean on `ScalpDistributionView.m`, `TimeFrequencyView.m`,
`DrawScalpMap.m`.

## ScalpDistribution slider: round-5 range and no minor-tick clutter

Reported: "the slider does not need all the micro steps plotted below it
(they should be reachable though...), and it's also not pretty-printed
yet -- round the upper and lower values to the closest 5 or 0."

**"Micro steps."** `uislider.MinorTicksMode` defaults to `"auto"`, which
densely auto-generates an unlabelled minor tick mark roughly every `Step`
(default `1`) between major ticks -- on a several-hundred-ms range that
is a wall of clutter with no individually-readable meaning. Confirmed
directly this is invisible when only inspecting the `MinorTicks`
property headless (it stays `[]` until something actually triggers
`"auto"` to materialise it), which is why it wasn't caught by the
previous round's testing -- the property value itself doesn't reveal
what `"auto"` mode will render. Fixed by locking `MinorTicksMode =
"manual"` with `MinorTicks = []`: this only suppresses the *visual* tick
marks, it does not touch `Step`/`Value` at all, so every point in
between remains exactly as reachable by dragging as before -- verified
directly by setting `Slider.Value` to an arbitrary non-tick fractional
value (`-33.5`) and confirming it's accepted unchanged.

**Round-to-5 range.** The slider's own end-to-end range
(`eeg.times(1)`/`eeg.times(end)`) is rarely a round number (wherever the
nearest sample happens to land), and `Limits` drives both the draggable
range and, via `MajorTicks`, the printed tick labels -- so both were
inconsistently un-pretty at the very ends even after the previous
`MajorTicks` rounding fix. Fixed by rounding `Limits` itself to the
nearest 5 (`roundTo5 = @(t) round(t/5)*5`) before constructing the
slider, then deriving `MajorTicks` from the already-rounded `Limits`
rather than the raw `eeg.times` bounds. A rounded endpoint landing a few
ms past the true data edge is harmless: `redraw()` always maps whatever
`Value` the slider lands on to the nearest real sample in `eeg.times`
(its own `min(abs(eeg.times-t))` lookup), so it simply clamps to the
nearest real edge sample rather than erroring or leaving a gap.

Verified: extended `test_scalpdistribution.m`'s synthetic dataset to use
deliberately non-round-5 endpoints (`times(1) = -197`, `times(end) =
803`, previously exact multiples of 5 by coincidence and so never
actually exercising this rounding) and confirmed `Slider.Limits` reads
back exactly `[-195, 805]`; confirmed `MajorTicks`/`MajorTickLabels` are
derived from those rounded `Limits`, not the raw times bounds; confirmed
`MinorTicksMode == "manual"` and `MinorTicks` is empty; confirmed setting
`Slider.Value` to an arbitrary fractional value not on any tick still
succeeds, proving hiding the minor ticks did not restrict reachability.
Re-ran the full regression suite (`TimeFrequency`, `ScalpDistribution`,
`DrawScalpMap` orientation) afterward -- all still pass. `checkcode`
clean on `ScalpDistributionView.m`.

## Two more hand-crafted tree icons: subject dataset and Grand Average

Reported: the tree's Grand Average and subject-dataset (raw import) node
icons "are colourful, but deviant from our handcrafted set."

Traced both to `src/webtree/src/alakazam-tree.js`'s `ICONS` map (the
tree's own small, hand-drawn icon family -- `raw`/`time`/`freq`/`default`,
each a flat-coloured rounded-square badge with a simple white glyph, the
established style since the tree's icon set was last redrawn). Neither
node type actually had its own dedicated icon: a freshly-imported subject
dataset's root node already used `raw` (a generic folder+document glyph,
not anything specific to "this is one subject's recording"), and a Grand
Average's root node just borrowed whichever of `time`/`freq` a plain
per-subject `Average` result would also get (`WorkSpaceTree.iconFor(EEG.
DataType)`, in both `Alakazam.saveGrandAverage`'s fresh-creation path and
`WorkSpace.loadGrandAverages`'s rebuild-from-disk path) -- a stale
comment in `alakazam-tree.js` itself even still described `raw` as
"doubling as... the 'Grand Averages' branch" icon, evidence this was
never actually a considered, dedicated choice to begin with, just
whatever was already at hand when those two code paths were written.

**`raw` redesigned in place** (same key, same 3 call sites --
`WorkSpace.loadBVAFile`/`loadMATFile`/`loadSETFile` -- untouched, they
already meant exactly "a subject's own freshly-imported root node"):
kept the amber badge colour, replaced the folder+document glyph with a
simple person silhouette (a circle head + shoulder arc, the same
filled-white-shape-on-badge technique `raw`'s old glyph already used),
since that root node represents one subject's own recording, not a
generic file.

**New `grandAverage` key added**: a small "three source nodes merging
into one" glyph (three white dots connected by lines converging to one
larger dot) on a new violet badge (`#8e5fc9`, distinct from every
existing badge colour), directly representing "several combined into a
group result" rather than reusing a time/frequency-domain badge that
says nothing about it being a *combination* at all. Wired into both
places that used to borrow `time`/`freq`: `Alakazam.saveGrandAverage`
and `WorkSpace.loadGrandAverages` now pass the literal `'grandAverage'`
unconditionally, regardless of the underlying data's time/frequency
domain (a Grand Average is its own concept either way, not two different
badges depending on domain).

Icon lookup itself needed no changes to support a new key --
`alakazam-tree.js`'s `_onRender` already does a plain `ICONS[data.icon]
|| ICONS.default` dictionary lookup with no fixed enum to extend, and
`WorkSpaceTree.addNode` already stores whatever icon string it's given
verbatim (`char(icon)`, no validation against a fixed set) -- so both new
keys are simple, low-risk additions riding on already-generic,
already-tested plumbing.

Verified: extended `src/webtree/test_node.mjs` with a sixth test node
using `icon: 'grandAverage'` and confirmed its rendered icon HTML
contains the new badge's own `#8e5fc9` fill (i.e. it is genuinely using
the new dedicated icon, not silently falling back to `ICONS.default`).
Ran the real build pipeline (`npm run build` in `src/webtree/`) and
`npm test` (`node test_node.mjs`) -- the full existing suite (render/
click/double-click/context-menu, drop-always-reverts, drag-cursor/
busy-cursor/drop-target-highlight, the mouseleave grace-period state
machine, the sub-threshold-jitter regression) still passes unchanged,
confirming the new node/icon did not disturb anything already covered.
Copied the freshly built `dist/alakazam-tree.html` over `src/
WorkSpaceTree.html` (real build output, not hand-synced). `checkcode`
clean on `Alakazam.m` and `WorkSpace/loadGrandAverages.m`.

**Follow-up**: recoloured both new badges, on request, into the same
blue family as `freq`'s existing `#4a7fc9` (the app's own accent blue --
ribbon, tile selection, tree row selection) rather than the amber/violet
first picked -- `raw` (subject dataset) is now a lighter sky blue
(`#6fa8dc`), `grandAverage` a darker navy blue (`#2e5c8a`), bracketing
`freq`'s own shade rather than matching it exactly, so the three remain
distinguishable by lightness plus glyph shape, not colour alone (the
same "colour and shape both carry meaning" principle the whole `ICONS`
set already follows). Updated `test_node.mjs`'s colour-content assertion
to match the new `#2e5c8a`; re-ran the real build (`npm run build`) and
test (`npm test`) pipeline -- unchanged pass. Re-copied the freshly built
`dist/alakazam-tree.html` over `src/WorkSpaceTree.html`.

## Ribbon tab colours: exactly the new tree-icon blues, Grand Average darker than Tools

Follow-up to the section above: on request, the ribbon's own tab strip
(`src/AlakazamRibbon.html`, hand-written, no build step) now uses exactly
those same two colours, not just the tree. `.alz-tab-tools` was `#2d5f99`,
`.alz-tab-grandAverage` was `#7aa7dd` -- Grand Average was the *lighter*
of the two, which read backwards (it's normally thought of as "the more
composed/senior" concept). Set `.alz-tab-tools` to `#6fa8dc` (matching
the tree's `raw`/subject-dataset icon) and `.alz-tab-grandAverage` to
`#2e5c8a` (matching the tree's `grandAverage` icon) -- Grand Average is
now the darker of the two, as it should read. `.alz-tab-home` is
unchanged (`#4a7fc9`, already matching the tree's `freq` icon).

## EpochView redesigned as an ERP-image; trial mode removed

The multichannel epoched-data view ("really ugly," per direct feedback)
was an overlaid-line-traces plot: channel mode drew every trial as a
separate line for one channel, trial mode drew every channel as a
separate line for one trial. Neither scales -- MATLAB's own line colour
order cycles after 7 colours, so with realistic trial/channel counts
(dozens to hundreds) distinct trials/channels become visually
indistinguishable well before the legend (up to 35 rows per column) that
was supposed to tell them apart does too.

**Redesign**: an ERP-image -- the standard EEGLAB/FieldTrip answer to
exactly this problem. Time on the x-axis, trial on the y-axis, colour the
signed amplitude, for the current channel (still stepped by up/down
arrows, the same interaction the old channel mode used). A row's
position on the y-axis already identifies which trial it is, so no
legend is needed at all -- `ShowLegend`/the `"l"` key toggle were removed
entirely, not just defaulted off. A thin trial-average trace is drawn
below the heatmap (the same "single-trial detail plus the summary at
once" pairing an ERP-image conventionally uses). One shared, symmetric
colour scale is computed once over the *whole* dataset (every channel,
every trial) in the constructor, not autoscaled fresh per redraw -- the
same "shared scale across the whole view" convention `ScalpDistribution`/
`TimeFrequency` already established, so paging through channels is an
eye-to-eye comparison (does channel 3 swing wider than channel 5?), not
each channel silently getting its own local scale.

**Trial mode removed entirely**, on request ("There is no trial mode
anymore, is there? There shouldn't be...") -- not hidden, not defaulted
off: `Trial`/`Mode` properties, `redrawTrialMode`, and the left/right-
arrow key cases are gone from the class outright. Up/down arrows are now
the *only* navigation; left/right are a plain no-op (falls through
`onKey`'s `switch`/`otherwise`).

**Bin-aware row ordering**, reusing the existing `.epoch(t).bini`/
`.bindesc` infrastructure the old legend text already read from: rows are
grouped by each trial's first bin membership (a stable sort, so trials
within a group keep their original relative order), trials with no bin
membership trailing last -- a real, useful "sort trials by the one
variable this app already tracks" capability an ERP-image conventionally
supports, not just a rendering change. Thin white separator lines and a
right-margin text label mark each group boundary. A trial belonging to
more than one bin is grouped under its first bin only (a deliberate v1
simplification -- its other bin memberships aren't otherwise indicated).

**Shared `TransTools.DivergingColormap`**: the ERP-image's blue/white/red
colour scale is the exact same "signed, zero-centred quantity" convention
`TimeFrequencyView` already used for ERSP power -- pulled `TimeFrequencyView`'s
own private `divergingColormap` method out into `TransTools.DivergingColormap.m`
once a second view wanted the identical six-line construction, rather
than duplicating it a third time by hand-copying into `EpochView` too.
`TimeFrequencyView` now calls the shared version; its own copy is deleted.

**A real bug caught by testing, not just checkcode**: `yline`'s return
value has `Type == "constantline"` (`matlab.graphics.chart.decoration.
ConstantLine`), not `"line"` -- an early draft's own bin-group-separator
cleanup (`delete(findobj(this.HeatAxes, "Type", "line"))`, run at the top
of every redraw so stale separators from a prior channel don't
accumulate) would therefore never actually have found or deleted them,
confirmed directly with a standalone `yline` + `findobj` check before
fixing it, not assumed from the property name. Also caught (same
review pass, before it ever ran): channel-mode redraws left a prior
trial-mode redraw's explicit `YTick`/`YTickLabel` (channel names) stale
on the heatmap axes -- moot now that trial mode itself was removed
entirely, but was a real bug in the interim design and is documented here
since the fix (`YTickMode`/`YTickLabelMode` reset to `"auto"`) is exactly
the kind of "switching between two very different tick schemes on the
same axes" mistake worth remembering if a similar view ever grows a
second mode again.

Verified: a synthetic 3-channel, 6-trial dataset with a deliberately
mixed bin pattern (`bini` per trial = `[2, 1, [], 1, 2, []]`, trials 3
and 6 unbinned) confirmed `TrialOrder` exactly equals the hand-computed
expected stable-sort order (`[3 6 2 4 1 5]`); confirmed the heatmap's
`CData` is the current channel's data with rows in that exact order, and
`XData` is the real sample times; confirmed the trace is exactly
`mean(data, 2)` for the current channel; confirmed exactly 2 separator
lines and 3 group labels ("no bin", "1 BinA", "2 BinB") are drawn, with
the right text; confirmed `ColorLimit` is `max(abs())` over the *whole*
dataset, not just the current channel; exercised up/down arrow-key
stepping including clamping at both ends, confirming the heatmap updates
to the new channel's own bin-ordered data each time; confirmed the class
no longer has `Trial`/`Mode` properties or a `redrawTrialMode` method at
all (`isprop`/`ismethod`), and that left/right arrow keys are a genuine
no-op (channel and displayed `CData` both provably unchanged after
pressing them). Separately drove the real `AlakazamPlotter.plotCurrent`
dispatch path with a real multichannel `trials > 1` epoched dataset and
confirmed it still lands on `EpochView` as before, and that
`Alakazam.onSettingsChanged`'s own no-arg `view.redraw()` refresh call
still runs cleanly. Re-ran the full `TimeFrequency` regression suite
afterward to confirm extracting `DivergingColormap` didn't disturb it --
unchanged pass. `checkcode` clean on `EpochView.m`, `TimeFrequencyView.m`,
and the new `TransTools/DivergingColormap.m`.

## Three follow-ups: mismatched colorbars, and mouse-wheel channel stepping

Reported: "the time-frequency map colorbar does not match the colors in
the timefrequency plots," "in EpochView, mouse scroll should change
channels (cf. keyup/down)," and "ScalpDistribution now has a different
colorbar compared to all other plots."

**Colorbar/colormap mismatch (TimeFrequencyView and ScalpDistributionView
both).** Root cause, confirmed directly by reading the code rather than
just trusting the report: the dedicated hidden `colorbarAxes` added in an
earlier fix (to stop a colorbar shrinking whichever real tile it was
attached to) was never given `colormap(colorbarAxes, cmap)` at all -- it
silently used MATLAB's own default colormap (parula), while every real
tile used the diverging blue/white/red colormap (`TimeFrequencyView`) or
whatever colormap `DrawScalpMap` set on its own target axes
(`ScalpDistributionView`). The colorbar's gradient and the heatmaps'
actual colours were simply never the same colormap object. Fixed in both
views: `colormap(colorbarAxes, cmap)` (or `TransTools.DivergingColormap()`
directly) right after creating the hidden axes, matching whatever the
real tiles use exactly.

**`DrawScalpMap` itself never set a colormap either** -- unlike
`TimeFrequencyView`/`EpochView`'s ERP-image, it left every scalp-map
tile on MATLAB's own default (parula), which is why ScalpDistribution's
colours looked different from "all other plots" even before the
colorbar-mismatch bug above: scalp amplitude is exactly the same signed,
zero-centred quantity ERSP power and ERP-image amplitude already are, so
on request it now explicitly sets `colormap(ax, TransTools.
DivergingColormap())` too, for one consistent colour convention across
every plot in the app that shows a signed quantity.

**EpochView mouse-wheel channel stepping.** Added `EpochView.onWheel`
(the same public contract `SignalView.onWheel` already establishes:
`callbackData.VerticalScrollCount`, positive for scrolling down), mapped
to the identical direction/clamping logic the up/down arrow keys already
use (`VerticalScrollCount > 0` steps forward, matching `downarrow`).
Wired into `Alakazam.dispatchWheel`, which previously only ever checked
`SignalView` -- turned into the same `for viewName = [...]` loop pattern
`dispatchKey` already uses for its own multi-view list, rather than a
second bespoke single-view dispatch method.

Verified: extended `test_timefrequency_fixes.m` and `test_scalpdistribution.m`
with a direct check that the hidden colorbar axes' `colormap(...)`
exactly equals the real tiles' own `colormap(...)` (located via
`setdiff` against the known tile-axes array, since neither view stores
the hidden axes as a class property); `test_scalpdistribution.m`
additionally confirms the tiles' colormap now equals
`TransTools.DivergingColormap()` exactly, not MATLAB's default. Extended
`test_epochview.m` with a wheel-scroll test: scrolling up steps the
channel back (matching `uparrow`), scrolling down steps it forward
(matching `downarrow`), clamps at the last channel exactly like the
arrow-key test already confirms, and the heatmap's `CData` reflects the
wheel-selected channel's own bin-ordered data. Re-ran the full
`TimeFrequency`/`ScalpDistribution`/`DrawScalpMap`-orientation/`EpochView`
regression suite afterward -- all still pass. `checkcode` clean on
`TimeFrequencyView.m`, `ScalpDistributionView.m`,
`TransTools/DrawScalpMap.m`, `EpochView.m`, and `Alakazam.m`.

**EpochView "plot trials by bin" setting, and TimeFrequency mouse-wheel
channel stepping.**

New `AlakazamSettings` schema entry: `graphics`/`epochImage`/`groupByBin`
(bool, default `false`), auto-built into the Settings dialog's Graphics
tab as a second section alongside the existing `erpPlot` one (the tab
builder's third argument just takes an array of sections --
`AlakazamSettings.tab('graphics', 'Graphics', [erpPlot, epochImage])` --
no dialog-side code needed at all, per the class's own "add one schema
entry, everything else follows" design). Confirmed `erpPlot` is consumed
exclusively by `AverageView` (the trial-averaged ERP view), not
`EpochView` at all, so the new setting got its own section rather than
being folded into `erpPlot`.

Unchecked (default), `EpochView` is unchanged: one row per trial,
grouped by its first bin membership only. Checked, rows are grouped
strictly by bin, top to bottom, and a trial belonging to more than one
bin is plotted once per bin -- so the row count can exceed the trial
count. Implementation: `TrialOrder` was already "a list of trial indices
to plot as rows, in order" rather than strictly a permutation of
`1:nTrials`, and MATLAB's row-indexing (`data(this.TrialOrder, :)`)
already replicates a row on a repeated index for free, so no change was
needed to the drawing code itself -- only to how `TrialOrder` is built.
Added `RowBinKey` (1 x nRows, parallel to `TrialOrder`, one bin key per
*row* rather than per *trial*) since a trial can now occupy more than
one row, each under a different bin -- `drawBinGroupLines` (separators +
right-margin labels) now reads `RowBinKey` directly instead of
re-deriving a per-row key via `groupKey(this.TrialOrder)`, which would
have given a duplicated row's SECOND occurrence the same ("first bin")
key as its first. New private `computeTrialOrderByBin` builds the
grouped-by-bin order/keys: unbinned trials first (same convention as
before), then each bin ascending, listing every trial that belongs to it
in original trial order.

`TrialOrder`/`RowBinKey` are now recomputed at the top of every
`redraw()` (moved out of the constructor, where they were previously
computed once) specifically so toggling the setting in the Settings
dialog and clicking Save -- which calls every open view's no-arg
`redraw()` via `Alakazam.onSettingsChanged` -- actually updates an
already-open EpochView tab, rather than only taking effect on tabs
opened after the change.

`TimeFrequencyView` gained `onWheel`, mirroring `EpochView.onWheel`'s
exact contract and direction convention (`VerticalScrollCount > 0` steps
forward, matching its existing `onKey`'s `downarrow` case -- it already
had arrow-key channel stepping, just not wheel). `Alakazam.dispatchWheel`
now includes `"TimeFrequencyView"` in its view-name loop alongside
`SignalView`/`EpochView`.

Verified: extended `test_epochview.m` with a dedicated 4-trial fixture
where one trial belongs to two bins -- confirms `groupByBin=false`
matches the pre-existing single-row-per-trial behaviour exactly (regression
guard), and `groupByBin=true` produces the expected 5-row order with the
duplicated trial's row appearing twice, both showing that trial's data,
correct separator/label placement across 3 groups, and a trial-average
trace unaffected by the row duplication (still the mean over the 4 real
trials). Extended `test_timefrequency_tree.m` with a wheel-scroll test
identical in spirit to `EpochView`'s: scroll up/down step the channel
matching uparrow/downarrow, clamp at the last channel, and the tile's
`CData` reflects the wheel-selected channel. Settings-side: confirmed
`AlakazamSettings.schema()` reports two sections under the `graphics`
tab and that a headless `SettingsDialog()` builds without error against
the two-section tab. All tests only ever call `AlakazamSettings.set()`
(in-memory), never `.save()`, so none of this touches the real
`AlakazamSettings.json` in `prefdir`. `checkcode` clean on `EpochView.m`,
`TimeFrequencyView.m`, `Alakazam.m`, and `AlakazamSettings.m`.

**Follow-up: bin labels moved onto the y-axis itself.** The bin-group
labels were originally drawn as floating `text()` annotations along the
plot's right margin; on request they're now genuine `YTick`/
`YTickLabel` values on `HeatAxes` (replacing the default numeric trial
ticks), which is the conventional place a reader looks for row-grouping
information and stays correctly positioned regardless of pan/zoom.
`drawBinGroupLines` no longer creates or cleans up `text` objects at
all -- just separators (`yline`, unchanged) plus `this.HeatAxes.YTick`/
`YTickLabel` set directly from each group's midpoint row and label
string. Verified: `test_epochview.m`'s label assertions now read
`view.HeatAxes.YTick`/`YTickLabel` (confirming exactly 3 ticks reading
"no bin"/"1 BinA"/"2 BinB", and that no `text`-type objects remain in
`HeatAxes`) instead of hunting for `text` objects; the "group by bin"
duplication sub-test was updated the same way. `checkcode` clean on
`EpochView.m`.

**Mouse-wheel time scrubbing for ScalpDistribution.** Added
`ScalpDistributionView.onWheel`, the same public contract as
`EpochView`/`TimeFrequencyView`'s own `onWheel` (`callbackData.
VerticalScrollCount`, positive = scroll down = step forward) -- but
stepping the time *slider* by one real sample (`eeg.times`) rather than
a channel, since this view has no channel axis at all. Wired into
`Alakazam.dispatchWheel`'s view-name loop alongside the other three.

One wrinkle the other views didn't have: `Slider.Limits` is `eeg.times(1)`/
`(end)` rounded to the nearest 5 ms (an earlier fix, for pretty-printed
tick labels), which can land just *inside* the true data range -- e.g.
`times(1) = -197` rounds up to a Limits floor of `-195`. Setting
`Slider.Value` to the raw edge sample directly would then throw (`uislider`
requires `Value` within `Limits`), so `onWheel` clamps the target sample
time into `Slider.Limits` before assigning; `redraw()` already snaps
whatever `Value` it's given back to the nearest real sample regardless,
so the clamp never changes which sample actually gets drawn, just avoids
a bogus out-of-range assignment.

Verified: extended `test_scalpdistribution.m` with a wheel-scroll test
(scroll down/up steps `Slider.Value` to the next/previous real sample,
`10` ms apart in the test fixture, and the time-label readout updates to
match) plus a dedicated edge-clamping test at both ends of the data
range, confirming no error is thrown and the slider settles on the true
edge sample rather than overshooting past it. `checkcode` clean on
`ScalpDistributionView.m` and `Alakazam.m`.

**EpochView bin-group brackets.** On request ("draw accolades from the
label that indicate what trials are in what bin"), added a dedicated
left-margin `BraceAxes` panel (a narrow extra `uigridlayout` column,
collapsed to 0 width when the dataset has no bins) drawing an actual
bracket per bin group, replacing the earlier plain y-axis tick labels.
First pass drew a real curly-brace *curve* (cubic Bezier halves meeting
at a spiked cusp) -- visually recognisable but, on review, "ugly": too
wide, and long bin names got clipped against the axes edge. Rewritten on
request to a much slimmer design: a plain vertical line spanning the
group's rows, small perpendicular "grip" ticks at the two ends (marking
the exact row boundaries, pointing right towards the heatmap), and one
small tip at the vertical midpoint pointing left towards the label --
which is now drawn rotated 90 degrees (`Text.Rotation = 90`), reading
bottom-to-top alongside its own bracket, instead of horizontal text that
needed unbounded width. `BraceAxes.Clipping = "off"` so a label longer
than the column is still fully visible rather than truncated. The old
Bezier-curve `drawBrace` implementation and its `bezierPt` static helper
were replaced outright (four `plot` calls per bracket instead), not kept
alongside the new one.

Verified visually first, not just by assertion: rendered a real EpochView
(via `exportapp`, headless) to a PNG for a deliberately adversarial
fixture (tiny bin groups + a very long bin name) that reproduced the
old curve's clipping problem, confirmed the redesign fixes it, then
re-rendered with realistic-sized groups (dozens of trials, short typical
bin names like "Standard"/"Deviant") to confirm the common case reads
cleanly with no label overlap. `test_epochview.m`'s label assertions
now check `BraceAxes` directly: exactly 4 line segments per bin group
(the vertical line + 2 grips + 1 tip), one `text` object per group with
`Rotation == 90`, and the label strings themselves -- both for the
default and `groupByBin=true` fixtures. Also confirmed directly (outside
the assertion-based suite) that a bins-less dataset collapses
`Grid.ColumnWidth{1}` to 0 and leaves `BraceAxes` empty, matching the
pre-existing "full heatmap width when there's nothing to bracket"
behaviour. `checkcode` clean on `EpochView.m`.

**Follow-up: rounded bracket tips, bigger labels, and trace/heatmap
x-axis alignment.** Three more requests on the same bracket panel:

1. *"Round the tips"* -- the bracket was previously drawn as 4 separate
   sharp-cornered line segments (vertical line, 2 perpendicular grip
   ticks, 1 perpendicular tip). Rewritten as a single continuous
   polyline: straight segments joined by small elliptical-arc corners at
   the two grip ends, and the tip replaced by a smooth half-sine "bump"
   (rather than a flat right-angle stub) that peaks at the label side --
   no sharp corners anywhere. Corner/bump radii shrink proportionally
   for a very short (few-row) group rather than overlapping. `FontSize`
   for the bracket labels bumped 8 -> 10 ("labels a bit bigger").

2. *"Make the x-axis of the average ERP ... coincide with the x-axis of
   the main part of the plot"* -- `TraceAxes` (the trial-average trace
   below the heatmap) previously spanned both grid columns (`Layout.
   Column = [1, 2]`, under the brace margin too), while `HeatAxes` only
   occupied column 2 -- different widths, so their "t = 0" ticks did not
   line up vertically even though both used the same XLim. Changed
   `TraceAxes.Layout.Column` to `2`, matching `HeatAxes` exactly. That
   alone wasn't sufficient though: `HeatAxes` also had its colorbar
   attached directly to it (`colorbar(this.HeatAxes)`), which narrows an
   axes' own `Position` to make room for the colorbar -- exactly the
   "colorbar shrinks its target axes" bug already fixed in
   `ScalpDistributionView`/`TimeFrequencyView` via a dedicated hidden
   colorbar axes, just not yet applied to `EpochView`. Applied the same
   fix here: a third, narrow (56px) trailing grid column holds a hidden
   `colorbarAxes` (colour-matched via `TransTools.DivergingColormap()`,
   `CLim` set once from `this.ColorLimit` since it never changes across
   redraws), and `HeatAxes` no longer carries its own colorbar at all.
   With both narrowing effects removed, `HeatAxes` and `TraceAxes` end
   up pixel-identical in width and x-position.

Verified: re-rendered a real `EpochView` (via `exportapp`, headless) to a
PNG to confirm the rounded corners/tip actually render smoothly (not
just "the math should produce a curve") -- both for a small-group case
and a realistic-sized one, no overlap regression from the earlier
brace-panel work. `test_epochview.m` updated: the bracket line-count
assertion now expects 1 polyline per group (was asserting 4 separate
segments); a new assertion directly checks `TraceAxes.Position` and
`HeatAxes.Position` match in both x-origin and width after `drawnow` --
this caught the colorbar-width bug immediately (first version of the
column-alignment fix alone still failed with a ~70px width mismatch,
which is what led to tracing it back to the direct-attached colorbar).
`checkcode` clean on `EpochView.m`.

**Bug fix: groupByBin=false still grouped by bin.** User report: "The
epochplot does not respect the plotbybin setting. It plots by bin when
there are bins." Root cause: EpochView's row-grouping (first-bin-only
sort, separators, bracket labels) had originally been unconditional
behaviour, from before the `groupByBin` setting existed at all -- when
the setting was added, `computeTrialOrder`'s `false` branch was written
to just keep that pre-existing "grouped by first bin" sort instead of
turning grouping off, so a dataset with bins looked bin-grouped
regardless of the setting; only the "does a multi-bin trial get
duplicated" behaviour actually toggled. Fixed by making `false` (or no
bins at all) mean genuinely NO grouping: natural `1:nTrials` order,
`RowBinKey` all-zero, and `drawBinGroupLines` now gates the whole
bracket/separator block on `this.HasBins && groupByBin` (both must be
true) rather than `HasBins` alone -- when not grouped, `BraceAxes` stays
empty and `Grid.ColumnWidth{1}` collapses to 0, exactly like a bins-less
dataset. The margin column width is now set live inside
`drawBinGroupLines` on every redraw (widened to 100 only when grouping
is actually active) instead of being fixed once at construction from
`HasBins` alone, so toggling the setting on an already-open tab both
turns the brackets on/off AND resizes the margin column correctly. The
now-dead `trialGroupKeys` helper (the old "first bin only" key
function, no longer called from anywhere once the false-branch stopped
using it) was deleted rather than left unused.

Verified: rewrote the relevant sections of `test_epochview.m` --
`groupByBin=false` now explicitly asserts natural order, all-zero
`RowBinKey`, empty `BraceAxes.Children`, and a collapsed margin column,
both for the original 6-trial fixture and the 4-trial multi-bin-trial
fixture (previously that block asserted the OLD, buggy "grouped under
first bin" behaviour as if it were correct -- a case of the test
faithfully encoding the bug rather than catching it, since it was
written for the same original design). Added an explicit toggle round-
trip on the first fixture (set true, redraw, assert grouped+widened
column; set false, redraw, assert natural order+collapsed column again)
to directly exercise live toggling on an already-open tab, matching how
`Alakazam.onSettingsChanged` actually drives it. Schema tooltip in
`AlakazamSettings.m` and `EpochView.m`'s class-level doc comment updated
to describe the corrected (opt-in) semantics. `checkcode` clean on both
files.

**Bug fix: transformations stealing window focus.** User report: after
running a transformation (Baseline every time, reportedly others too),
focus jumped from the Alakazam window to the main MATLAB desktop/command
window. Root cause: `Baseline.m` (and likely other transforms) shows its
options via `uiextras.settingsdlg`, a classic Java/AWT-backed figure --
not a `uifigure`. Mixing that windowing system with an otherwise
all-`uifigure` app means focus doesn't reliably return to the app once
the classic dialog closes. Fixed centrally rather than per-transform:
`Alakazam.onTransformation` now calls a new `Alakazam.restoreFocus()`
(`figure(this.MainFigure)`) right after every transformation run, both
on success and in the `catch` block -- harmless for transformations that
never showed a dialog at all, and covers any transform that might hit
this, not just Baseline. `checkcode` clean; sanity-checked `restoreFocus`
is callable on a real `Alakazam()` instance.

**"Edit WorkSpace" dialog rewritten as a uifigure.** `WorkSpace/edit.m`
previously used `uiextras.inputgui` -- the same category of classic
Java/AWT dialog as the focus-stealing bug above, for the same underlying
reason. Rewritten as a `uifigure` styled to match the main app: a header
bar in the ribbon's own Home-tab blue (`#4a7fc9`), the rest at
`uifigure`'s default background. Three rows (Raw data / Intermediate /
Exports folder), each a label + `uieditfield` + a small "..." (U+2026)
browse button that opens a native `uigetdir` folder picker and writes
the chosen path back into the field. OK normalizes each path with a
trailing `filesep` (matching the old dialog's own behaviour, but via
`filesep` instead of a hardcoded `'\'`) and calls `WorkSpace.open()`
(which already handles a missing/uncreatable directory gracefully, so
this dialog does not duplicate that validation); Cancel, or the window's
own close button, discards changes. `WorkSpace.edit()` can only be
invoked via `@WorkSpace`-folder method dispatch on a real `WorkSpace`
instance (not a lightweight stub), so verified end-to-end against a real
`Alakazam()` app: a `timer` clicking the dialog's OK/Cancel buttons
directly (`ButtonPushedFcn`) while the main thread sits in `uiwait`,
the same pattern `test_iirfilter_mlapptools_removal.m` already
established for this exact "single-threaded script can't literally wait
then click" problem. Confirms the dialog is genuinely a `uifigure` (not
classic), exactly 3 fields pre-populated from the current workspace, 3
browse buttons, OK applies an edited field with the trailing separator
and leaves the app/figure valid afterward, Cancel discards an edited
field and also leaves the app/figure valid. `checkcode` clean.

**`uiextras.settingsdlg` removed from every real call site.** New
`src/TransformOptionsDialog.m`: a `uifigure`-based, generic settings
dialog deliberately mirroring `settingsdlg`'s own call signature
(`'title'`/`'Description'`/`'separator'`/`{label;fieldname},default`
pairs) so each of the 5 real call sites only needed its FUNCTION NAME
swapped, not its argument list rewritten:
`Baseline.m`, `TimeFrequency.m`, `AutoGEDAI.m`, `AutoEyeICA.m`,
`ArtefactDetect.m`. Field kind is inferred from each default's MATLAB
type, exactly like `settingsdlg` itself: a cell array of strings is a
`uidropdown` (first element pre-selected -- callers already pre-order
that with their own `putFirst`-style helper, e.g. AutoGEDAI's
`strengthChoices`), a scalar logical a `uicheckbox`, numeric a
`uieditfield('numeric')`, anything else a `uieditfield('text')`.
Cancelling (or the window's own close button) returns `settings` built
from the ORIGINAL default values, unchanged -- the same contract
`settingsdlg`'s single-output form already has (confirmed by reading
its own source: `[settings,button]=settingsdlg(...)` documents
`button` as `'ok'`/`'cancel'`/`[]`, but `settings` itself is always a
real struct even on cancel, which is why none of the 5 original call
sites ever checked for an empty result) -- so no call site needed its
own new cancel-handling code.

Two real implementation bugs surfaced and fixed during construction,
both caught by direct testing rather than assumption:
- `struct('default', args{i+1}, ...)` inside the varargin parser threw
  ("different number of elements") whenever a default was itself a cell
  array of choices -- `struct()`'s own built-in behaviour treats a bare
  cell-array VALUE as "broadcast into a struct array". Fixed by passing
  `args(i+1)` (paren-indexed, a 1x1 cell) instead of `args{i+1}` (its
  unwrapped contents), which `struct()` correctly collapses back to a
  scalar field.
- `uieditfield(...,'numeric')` and `uieditfield(...,'text')` report
  DIFFERENT `.Type` values (`'uinumericeditfield'` vs. `'uieditfield'`)
  -- confirmed directly with a two-line repro. Every test/call site that
  searches for "edit fields" needs both types, not just `'uieditfield'`;
  this cost a lengthy false-alarm debugging detour (chased a suspected
  `uiwait`/timer race that never existed) before the real cause was
  isolated by constructing the dialog synchronously, without `uiwait`,
  and comparing `findobj` counts directly against the real component
  classes created.

Verified: `test_transformoptionsdialog.m` (structural checks across all
four field kinds, Cancel-returns-original-defaults, OK-applies-edits)
and `test_baseline_dialog_swap.m` (the real, unmodified `Baseline.m`
end-to-end: `TransformSettings.get` seeds the dialog, a `timer` drives
OK with an edited window, `TransformSettings.set` persists it, and the
actual baseline correction is computed from the EDITED window, not the
default -- confirmed numerically, mean amplitude ~0 over the edited
window after correction). `checkcode` clean on `TransformOptionsDialog.m`
and all 5 swapped transform files.

**Remaining classic Java/AWT dialogs flagged, not migrated.** On
request ("flag all uses of old-style java based graphics obsolete, if
possible"): a full inventory found `msgbox`/`inputdlg`/`questdlg`/
`warndlg`/`errordlg` calls remaining in `Alakazam.m` (9 sites -- tree
CRUD confirmations and grand-average status dialogs), `rawclear.m`,
`open.m`, `EEGLabEnvironment.m` (3 sites, all run at app STARTUP before
`MainFigure` even exists, so there is no `uifigure` yet to parent a
replacement to), and `AutoGEDAI.m`'s separate GEDAI-plugin-install
consent prompt. `FourierGui.m` is a whole GUIDE-generated dialog (its
`handles.figure1` comes from the companion `.fig` binary, not any
`uifigure(...)` call in the `.m` text) -- migrating it would mean
rebuilding its entire options UI from scratch, not a single-function
swap like `settingsdlg` was. None of these were rewritten this pass
(genuinely out of scope for "if possible" given the volume and, for
`FourierGui.m`, the risk) -- each now carries a `% LEGACY-JAVA-GUI:`
comment immediately above the call (or, for `FourierGui.m`, one
file-level note at the top), so a future cleanup pass can find every
site with `grep -rn LEGACY-JAVA-GUI src`. The `+uiextras/` package
itself (`supergui.m`, `inputgui.m`, `settingsdlg.m`,
`setFigDockGroup.m`) is left untouched -- third-party-style library
code, not marked individually since `settingsdlg` itself has no more
real callers and the others are still load-bearing for `FourierGui.m`.

**Colour map setting.** New `AlakazamSettings` entry:
`graphics`/`colormap`/`name`, a `'choice'` setting (`uidropdown` in
`SettingsDialog`) between `"diverging"` (default -- this app's own
hand-built blue-white-red map) and MATLAB's own `parula`/`jet`/`turbo`/
`hot`/`cool`. Implemented inside `TransTools.DivergingColormap()`
itself rather than as a new function: every one of its 5 existing call
sites (`EpochView.m` x2, `ScalpDistributionView.m`,
`TimeFrequencyView.m`, `TransTools/DrawScalpMap.m`) already calls it
with zero arguments, so making its OWN body settings-aware means every
plot that shows a signed, zero-centred quantity picks up the chosen
colour map automatically, with no changes needed in any of the 4 view
files -- confirmed directly (`EpochView.HeatAxes`'s live `colormap()`
matches `parula(64)` after only changing the setting, no other code
touched). Kept the existing function name despite it now covering
non-diverging choices too, rather than renaming across 5 call sites, and
updated its docstring to describe the broadened, settings-driven scope
instead.

Verified: `test_colormap_setting.m` -- the default reproduces the
original hand-built map byte-for-byte (backward compatible), each
built-in choice resolves to MATLAB's own `parula(64)`/`jet(64)`/etc.
exactly, and a real `EpochView` picks up a changed setting with no view-
side code touched. Re-ran the full existing `EpochView`/`TimeFrequency`/
`ScalpDistribution` regression suite afterward with the setting at its
default -- all still pass unchanged. `checkcode` clean on
`AlakazamSettings.m` and `TransTools/DivergingColormap.m`.

**`findobj` usage, surveyed on request.** Real (non-`+uiextras/`) call
sites: `Alakazam.m` (10x -- tab/tile lookup by `Tag`, the `existingTab`/
`tiledContent`/`wrapper` pattern `AlakazamPlotter.plotCurrent`,
`closeTab`, `onDeleteNode`, `retile`/`untile`/`tileWrapperFor` all
share), `AlakazamPlotter.m` (1x, the same tab-by-`Tag` lookup),
`ScalpDistributionView.m` (1x, finding a sibling `AverageView` tab by
its source file's `Tag`), `SignalView.m`/`EpochView.m` (1x each,
`delete(findobj(ax,'Type',...))` to clear old event markers/separator
lines before redrawing), and `TransTools/SelectWindow.m`/
`FourierGui.m` (GUIDE-era controls, found by `Tag`/`Style`). The
`+uiextras/` library files (`supergui.m`, `inputgui.m`) use it
internally for their own classic-dialog control lookup -- unrelated to
the app's own code.

**AverageView mouse-wheel channel stepping.** The last of the 5 tab
views to get it: `AverageView.onWheel` mirrors its own existing
`onKey`'s up/down-arrow channel stepping (same clamping via
`min(cellfun(@(s) size(s.data,1), this.Series))` for the per-series
channel-count bound) and the same direction convention every other
view's `onWheel` already uses (`VerticalScrollCount > 0` steps forward,
matching downarrow). `Alakazam.dispatchWheel`'s view-name loop now
reads `["SignalView", "EpochView", "TimeFrequencyView",
"ScalpDistributionView", "AverageView"]` -- every dispatched-key-capable
tab view now also has wheel navigation. Verified with
`test_averageview_wheel.m`: direction/clamping at both ends, and the
axes title reflects the wheel-selected channel after scrolling.
`checkcode` clean on `AverageView.m` and `Alakazam.m`.

**Bug fix: `Workspace.EEG` going stale when switching tabs/tiles.** User
report: running ScalpDistribution while viewing a Grand Average (after
copying the whole workspace folder tree elsewhere and repointing
`Edit WorkSpace` at the new location) failed with a raw "The system
cannot find the path specified" -- which `showTransformationError`
dressed up as "this dataset is not yet [segmented/averaged/frequency-
domain]" since it wasn't an `Alakazam:`-prefixed error, even though the
data genuinely was already an average. The user's own diagnosis nailed
it: inspecting `Workspace.EEG` while the Grand Average was the dataset
on screen showed it was NOT the Grand Average at all.

Root cause: `Workspace.EEG` -- "the dataset a ribbon transformation
actually runs on" -- was previously only ever updated by clicking a TREE
node (`onSelectionChanged`/`onNodeDoubleClicked`). Neither switching
tabs by clicking a tab header (`PlotsTabGroup` had no
`SelectionChangedFcn` at all) nor clicking a different tile's own
content in Grid/Stack mode (`registerTileClick` only ever updated
`LastClickedTag`, used purely for keyboard/wheel dispatch) touched it.
So `Workspace.EEG` could silently drift from whatever was actually being
viewed on screen; running a transformation from the ribbon would then
apply to whatever dataset was last *tree*-selected -- in this report,
some other, unrelated dataset whose own stale path (from before the
folder copy) is what actually produced the "path not found" error.

Fixed with a new `Alakazam.syncActiveDataset(file)`, called from both:
- `onPlotTabSelected` (new), wired to `PlotsTabGroup.SelectionChangedFcn`
  -- fires on a real tab-header click (confirmed directly it does NOT
  fire on a programmatic `SelectedTab` assignment, only a genuine user
  click, which is exactly why the functional test below invokes the
  callback directly rather than just setting `SelectedTab`).
- `registerTileClick` (existing), extended to also call
  `syncActiveDataset` alongside its existing `LastClickedTag` update --
  covers Grid/Stack mode's own "click a different tile" case with the
  same fix.

`syncActiveDataset` re-`load()`s the tab's own file (a no-op if it's
already the active dataset), and also looks the file up in both
`Workspace.Tree` and `Workspace.GrandAveragesTree` (via each tree's
`allNodes()`, matching on `UserData`) to keep `Workspace.ActiveTree` and
the tree's own visual `SelectedNodes` in step too -- not just
`Workspace.EEG` -- so the tree highlight now follows the user around the
same way switching by tree-click already did. A missing/unreadable file
is caught and ignored rather than left to propagate a confusing error
from what looks like an unrelated click.

Verified with `test_syncactivedataset.m` against a real `Alakazam()`
app: opening two datasets as tabs, then switching back to the first by
invoking `SelectionChangedFcn` directly confirms `Workspace.EEG`
resyncs; adding a real tree node and repeating the switch confirms the
tree's own `SelectedNodes`/`ActiveTree` follow along too; Grid/Stack
mode's `registerTileClick` is exercised directly; and both the
already-active no-op and a nonexistent-file case are confirmed not to
throw or corrupt state. `checkcode` clean on `Alakazam.m`.

**Bug fix: cancelling a transformation's options dialog still added a
tree node.** User report: "Some of the transformations don't play nice
on cancel. They then do appear in the tree. A cancel should just return
cancel, and there should be no item added to the tree. In any case."

Root cause, found in `TransformOptionsDialog.m` (the earlier session's
own `uiextras.settingsdlg` replacement, already wired into every real
call site -- `ArtefactDetect`, `AutoEyeICA`, `AutoGEDAI`, `Baseline`,
`TimeFrequency`): its `onCancel` callback only ever `delete(fig)`d the
window, never touching the `settings` struct, which had already been
pre-filled from the CALLER's defaults before the dialog even opened.
Its own header comment even documented this as deliberate ("the same
contract settingsdlg's single-output form has"), treating a genuine bug
in the thing it replaced as a compatibility requirement to preserve.
Confirmed directly in `uiextras/settingsdlg.m` itself that this really
is settingsdlg's own behaviour: `Cancel(varargin)` sets `button =
'cancel'` and deletes the figure, full stop -- it never modifies
`settings` -- so its single-output call form (`opts = settingsdlg(...)`,
the only form any of these transformations ever used) always returns
the pre-fill defaults on Cancel, indistinguishable from OK. None of the
5 real call sites had any way to detect that (no `button` output was
ever captured), so clicking Cancel ran the transformation anyway with
default/last-used values and added a tree node nobody asked for.

Fixed in three layers:
1. `TransformOptionsDialog.m`: `settings` now starts as `[]` and stays
   `[]` unless `onOK` runs (which fully repopulates it from the live
   controls regardless, so the old pre-fill-defaults block was dead
   weight once Cancel stopped relying on it -- deleted, along with the
   now-unused `defaultValueOf` helper). Header comment corrected to
   document the new, actually-correct contract and require every caller
   to check `isempty(settings)`.
2. All 5 real call sites (`ArtefactDetect.m`, `AutoEyeICA.m`,
   `AutoGEDAI.m`, `Baseline.m`, `TimeFrequency.m`) now check
   `if isempty(opts) ... EEG = []; return; end` immediately after the
   dialog call, BEFORE `TransformSettings.set(...)` -- so a cancelled
   dialog also leaves the remembered per-transform settings untouched,
   not just skips running. `Fourier.m` (a different, GUIDE-based dialog,
   `FourierGui.m` -- confirmed its own `Cancel_Button_Callback` already
   correctly sets `handles.options = []`) had the same *caller-side* gap
   -- `Fourier.m` never checked for that empty result at all, so
   cancelling would previously fall through into the transform body and
   crash on `options.FullSpectrum` with a confusing raw error instead of
   a clean abort. Given the same `if isempty(...) ... return; end` fix.
3. `Alakazam.onTransformation`: the existing `if ishandle(result.EEG)
   ... return; end` "pure plot" short-circuit is now `if isempty(...)
   || ishandle(...) ... return; end`, treating an empty `EEG` result
   (any transformation cancelling itself) exactly like a pure plot --
   nothing to persist, no error shown. Also fixed, in passing, since it
   shares this exact code path: neither branch previously reset
   `MainFigure.Pointer` back from "watch" or called `restoreFocus()`
   before returning, so a pure-plot transformation left the cursor stuck
   on the busy icon; both early-return paths now do.

A duplicate, differently-located `TransformOptionsDialog` I initially
wrote from scratch (before discovering the real one already existed,
already integrated, in `src/TransformOptionsDialog.m` from an earlier
session) was deleted rather than kept alongside it.

Verified with `test_transformcancel.m`: `TransformOptionsDialog` itself
returns `[]` on Cancel and a real settings struct on OK; then, against a
real `Alakazam()` app running the real `Baseline` transformation on a
real epoched dataset, cancelling adds NO tree node, opens NO tab, and
correctly resets the pointer -- while confirming OK still adds exactly
one tree node/tab, so the fix didn't break the normal path. `checkcode`
clean on `TransformOptionsDialog.m`, `Alakazam.m`, and all 6 edited
transformation files.

## "Recalculate" generalized: edit a node's own parameters, cascade the recompute down its branch

`Recalculate` used to only ever be reachable for a Grand Average node
(revisit its subject list). Every other node's context menu simply had
it disabled -- despite each node already carrying everything needed to
redo it: `EEG.Call` (the transformation id) and `EEG.params` (exactly
what it ran with), the same provenance `evaluateDroppedBranch` already
replays when a branch is dragged onto another dataset.

Generalized so `Recalculate` also works for any node produced by a
transformation with a genuinely re-seedable options dialog: reopen that
dialog pre-filled with the NODE's own stored parameters (not the
workspace's usual "last used" value), and if the analyst changes them,
recompute that node AND every one of its descendants, overwriting them
IN PLACE (same node ids, same files) rather than creating new sibling
nodes the way a drag-drop replay does -- the point of "recalculate" is
revising a branch, not duplicating it.

Not every transformation qualifies. Only `ArtefactDetect`, `AutoEyeICA`,
`AutoGEDAI`, `Baseline`, `DefineBins`, `Fourier` and `TimeFrequency` (see
`WorkSpaceTree.RecalculableTransforms`) have a dialog that can be
re-seeded with an arbitrary parameter struct -- they all read their
interactive default from `TransformSettings.get(id)`. `ReRef`/
`SelectData` delegate to EEGLAB's own `pop_reref`/`pop_select` dialogs
(no seed parameter at all), `IIRFilter`'s dialog is a binary `.mlapp`
(not text-seedable), and `Average`/`ScalpDistribution` take no options
at all. `WorkSpaceTree.optsFor` now bakes `canRecalculate` in for a node
from either of these two families of eligibility (Grand Average, or a
`Call` in `RecalculableTransforms`) -- everything else, including a raw
root import, keeps the menu item disabled: offering an edit the app
cannot actually apply would be worse than not offering it at all.

Design, in `Alakazam.m`:
- `onRecalculateNode` now branches on the loaded node's own `EEG`: the
  existing Grand-Average path is untouched; everything else goes to the
  new `recalculateTransformNode(node, ownEEG)`.
- `recalculateTransformNode` re-validates eligibility itself (defence in
  depth -- a `.wksp` saved before this feature existed, or before a
  Transformations folder cleanup, could otherwise reach here with a
  stale/foreign `Call`), finds the node's parent file via the new
  `WorkSpaceTree.parentFile(id)` (Nodes is a flat id -> struct map, the
  only way to walk to a parent), then seeds the transform's own dialog
  with this node's stored params by temporarily standing in for
  `TransformSettings` -- `TransformSettings.set(id, ownEEG.params)`
  before calling `feval(transformId, parentEEG)` the normal 1-arg
  ("Init") way, restoring whatever was there before via `onCleanup` on
  exit. This reuses every qualifying transform's existing dialog code
  completely unchanged; no per-transform edits were needed.
- If the result is empty (cancelled) or the new params `isequal` the old
  ones, nothing happens -- no disk write, no descendant recompute, no
  tab closed. This is a real no-op, not just "re-save the same thing".
- Otherwise, the whole downstream branch is computed in memory FIRST
  (`planDescendantRecalc`, a pure function -- no disk writes, throws
  without saving anything if any step fails) before a single file is
  overwritten: a failure partway down a branch must never leave it
  half-updated, some nodes reflecting the new parameters and others
  still stale. Only once the full plan succeeds does a loop `save()` each
  file in parent-then-children order. Each descendant re-`feval`s its
  OWN already-recorded transform id and parameters UNCHANGED (only the
  node the analyst actually edited gets new parameters -- everything
  downstream just re-runs headlessly, exactly like
  `evaluateDroppedBranch`'s own replay).
- Every file that gets overwritten also has `closeTab(file)` called on
  it: `AlakazamPlotter.plotCurrent` reuses an already-open tab for a
  given file rather than rebuilding it, so a stale open tab would
  otherwise keep showing pre-edit data forever. The edited node itself
  is then replotted immediately (`Workspace.EEG` + `plotCurrent()`), so
  the analyst sees the fresh result without having to reselect it; a
  descendant's tab, if one was open, is simply left closed -- reselecting
  its tree node shows the (already recomputed) fresh result.
- A Grand Average built from a node further down an edited branch keeps
  pointing at whatever that node's file contained when it was built --
  recalculating a branch does not cascade into any Grand Average, the
  same way editing upstream data never automatically has; revisit it
  separately with its own (pre-existing) Recalculate action if needed.

Verified with `test_recalculate.m`: `WorkSpaceTree.optsFor` eligibility
for a Baseline-produced node, a SelectData-produced node, a raw root
import and a Grand Average; `parentFile` resolution including root-node
and unknown-id edge cases; then, end to end against a real `Alakazam()`
app with an on-disk root -> Baseline -> ArtefactDetect chain: editing
the Baseline node's Start/Stop recomputes it AND independently
recomputes the ArtefactDetect descendant against the new upstream data
(both checked against an independently-recomputed expected result, not
just "did the data change"), the descendant's own parameters stay
untouched, no new tree nodes appear, the edited node's tab shows the
fresh result immediately and the descendant's stale tab is closed;
re-running with unchanged values or Cancel is confirmed to touch nothing
on disk; and a synthetic ineligible (`SelectData`) node is confirmed
refused safely via a direct call, bypassing the (already-disabled) menu
gate. `checkcode` clean on `Alakazam.m` and `WorkSpaceTree.m`.

While building the test, confirmed directly (a MATLAB version/API detail
worth recording since it is easy to get wrong from memory) that a
numeric edit field's `Type` property is `'uinumericeditfield'`, not the
more guessable `'uieditfieldnumeric'` -- and that a fixed-delay timer
probing a `TransformOptionsDialog` for its OK/Cancel button can fire
before the button row finishes constructing (the dialog's figure and
early fields are already live at that point, which is what makes the
race easy to miss); the test's dialog-interaction helper polls for the
button to exist rather than checking once.

## Two live bugs reported interactively, both fixed

The Recalculate work above was only ever exercised through headless
MATLAB tests (`app.onContextMenuAction(...)` called directly) -- which,
it turns out, was hiding a real bug in the actual UI. Both of the
following were caught by trying the app interactively, not by any test.

**"Recalculate" showed greyed out even on an eligible node.** The JS
side's context menu never actually read `canRecalculate` at all:
- `alakazam-tree.js`'s `CONTEXT_ITEMS` template hardcoded
  `{ action: 'recalculate', label: 'Recalculate', disabled: true }` --
  unlike `listEvents`, there was no per-node override clause for it in
  `_openMenu`'s `disabled` computation at all.
- Worse, `setNodes`'s per-node object (what `_openMenu` actually reads as
  `data`) only ever copied `canListEvents: !!n.canListEvents` off the
  incoming node -- `canRecalculate` was silently dropped during the
  MATLAB -> JS mapping, so even fixing the first point alone would not
  have been enough.

This means Recalculate had likely never actually been clickable in the
live UI for ANY node, including a Grand Average -- the MATLAB-side
implementation was correct and heavily tested, but nothing ever reached
it through a real right-click, only through tests that called
`onContextMenuAction` directly and skip the JS menu entirely. Fixed in
three places, in both `webtree/src/alakazam-tree.js` (the source) and
`src/WorkSpaceTree.html` (the built artifact -- hand-synced, no Node.js
available in this environment to rebuild, see `webtree/README.md`):
dropped the template's hardcoded `disabled: true`; added
`canRecalculate: !!n.canRecalculate` to the per-node object `setNodes`
builds; added `|| (item.action === 'recalculate' && !data.canRecalculate)`
to `_openMenu`'s `disabled` computation, mirroring the existing
`listEvents`/`canListEvents` pattern exactly.

**Selecting a tree node whose backing `.mat` file had gone missing
crashed the app outright** -- a raw "Unable to find file" error
propagating up through `Alakazam/onSelectionChanged`'s unguarded
`load(eventData.UserData, "EEG")`, through `WorkSpaceTree/onEvent`, and
out through the uihtml event bridge
(`appdesservices...AbstractModel/executeUserCallback`) as an unreadable
low-level MATLAB error instead of anything actionable. A tree node can
outlive its file: a cache folder cleared by hand, a `.wksp` copied from
another computer with different paths, a branch deleted outside the app.

`onListEvents` already guarded against this (`isempty(file) ||
exist(file,"file")~=2`, silently returning); `onSelectionChanged` and
every other node-file load never did. Fixed by adding one shared
`Alakazam.loadNodeEEG(file, action)`: returns the loaded `EEG`, or `[]`
after a clear `uialert` ("Could not %s: its cache file is missing...")
if the file is missing or fails to load -- ACTION is a short phrase used
only in the alert text ('select this dataset', 'rename this dataset', ...).
Wired into `onSelectionChanged`, `onNodeDoubleClicked`, `onRenameNode`,
`onRecalculateNode`'s own initial load, and `onListEvents` (upgraded
from a silent no-op to the same clear alert, for consistency). Every
caller now checks `if isempty(EEG) ... return; end` and leaves
`Workspace.EEG`/the tree exactly as they were.

The same crash CLASS existed via drag-drop too, just never reported:
`onNodeDropped` called `evaluateDroppedBranch` with no try/catch at all,
so a missing target/source file (or the pre-existing "stored
transformation no longer exists" `MException`) would have crashed
exactly the same way. `evaluateDroppedBranch` now checks both
`targetFile`/`sourceFile` exist before each `load` in its replay loop,
throwing a clear `MException` if not (consistent with its existing
missing-transformation check); `onNodeDropped` now wraps its call in
try/catch, showing a `uialert` on any failure instead of letting it
propagate.

Verified with two new scratchpad tests. `test_missing_file.m`: a real
`Alakazam()` app with a tree node whose `UserData` points at a file that
genuinely does not exist -- `loadNodeEEG` itself, `onSelectionChanged`,
`onNodeDoubleClicked`, both context-menu actions, and `onNodeDropped`
(a fabricated drag-drop event) are all confirmed to complete without
throwing and to leave `Workspace.EEG` untouched, where a raw crash used
to propagate. `test_recalculate.m` re-run as a regression check since
`onRecalculateNode` was touched again -- still fully passing. `checkcode`
clean on `Alakazam.m`.

## Root cause of the missing-file crash: a tree node's file came from EEG.File, not from where it actually was

The missing-file crash above turned out to have a real cause, not just a
missing guard: a workspace built on one machine (a work PC, Windows
username "P154492") still tried to load
`C:\Users\P154492\...\Cache\...\Baseline....mat` when reopened on another
(home, username "mmspa") -- even though the workspace's own `.wksp`
Directories were correctly `~`-relative and resolved to the right
`mmspa`-rooted `CacheDirectory` (`toStoredPath`/`fromStoredPath`, see the
earlier "Convert WorkSpace .wksp files..." section, were already doing
their job correctly).

The actual bug was in `WorkSpace/treeTraverse.m`: it lists the real
`.mat` files under the (correctly resolved) `CacheDirectory` with `dir`,
but then handed each tree node `data.EEG.File` -- a field baked INTO the
`.mat` at the moment `persistResultNode`/`saveGrandAverage`/etc. first
saved it, correct only on the machine/username that created it -- as
the node's `UserData`, instead of the file's own real, just-verified
location (`fullfile(file.folder, file.name)`). Every subsequent load
(select, rename, recalculate, ...) then tried that stale absolute path
verbatim. Since a workspace's files keep the same structure RELATIVE to
its own Cache directory regardless of which computer it's opened on,
deriving the node's path from where it was actually just found on disk
(not from a value stored inside the file) is what makes the tree itself
portable, matching how `RawDirectory`/`CacheDirectory`/`ExportsDirectory`
were already made portable.

Fixed in two places:
- `treeTraverse.m`: `addNode` is now given `fullfile(file.folder,
  file.name)`, not `data.EEG.File`.
- `Alakazam.loadNodeEEG` (the shared single-node load helper from the
  crash fix above): now stamps `EEG.File = file` (the path it was just
  loaded from) unconditionally after `load()`, as a second line of
  defence for any node still carrying a stale `EEG.File` from before
  this fix (an already-open tree from an old session, or a tree rebuilt
  by an older Alakazam version).
- `evaluateDroppedBranch`: the same stamping, on `targetStruct.EEG.File`/
  `sourceStruct.EEG.File`, right after loading -- it previously passed
  `targetStruct.EEG.File` straight into `persistResultNode` (deriving the
  new node's sibling-folder location from it), the same stale-path risk
  via drag-drop instead of selection.

## `startAlakazam`/`Alakazam` can now open a specific workspace directly

Requested alongside the fix above, for the same underlying situation
(switching computers/projects): `startAlakazam(workspaceFile)` /
`Alakazam(workspaceFile)` opens with WORKSPACEFILE instead of always
reading the repository's `DefaultWorkSpace.wksp`. A bare filename (no
path separator, e.g. `"p300.wksp"`) resolves next to
`DefaultWorkSpace.wksp` under the repository root; a relative or
absolute path is used as given -- letting an analyst always launch
straight into a specific project's workspace without going through "Open
WorkSpace"'s interactive file picker every time.

`WorkSpace`'s constructor gained a matching `nargin == 2` form (myParent
+ an explicit workspace file/name), sharing the exact same
read-then-fall-back-to-RepoRoot-defaults logic the existing `nargin ==
1` (default workspace) form already had -- the difference is only which
file gets read. Took the opportunity to fix the pre-existing inconsistent
indentation in this constructor's nested `if`/`try` structure while
touching it (purely cosmetic, no behaviour change -- `checkcode` still
flags the `try`/`end` keyword-alignment as a stylistic nit, which traces
to a separate, pre-existing bug in the SAME constructor: the
per-transformation `TransformSettings.loadFrom(...)` block is
mis-nested inside the `catch` body rather than after the whole
`try`/`catch`, so it currently only ever runs on the fallback-defaults
path, never on a normal successful read -- flagged as a follow-up task
rather than fixed here, since it is unrelated to what was actually
asked for in this pass and deserves its own verification).

Verified with `test_portable_paths.m`: a `.mat` file whose own `EEG.File`
field points at a fabricated `C:\Users\P154492\...` path is placed in a
temp cache folder and traversed with `WorkSpace.treeTraverse` directly --
confirmed the resulting node's file is the real scanned path, not the
stale one; `Alakazam.loadNodeEEG` independently confirmed to re-stamp
`EEG.File` to the real path on load; `Alakazam(fullPathToWksp)` confirmed
to adopt that workspace's own directories; `Alakazam(bareName)` confirmed
to resolve and load a same-named `.wksp` placed directly under RepoRoot
(created and removed via `onCleanup` for the test, never left behind --
confirmed with `git status` afterward). `checkcode` clean on
`Alakazam.m`, `treeTraverse.m` and `startAlakazam.m`; `WorkSpace.m` has
only the pre-existing, now-explained `try`/`end` alignment nit.

## Fixed the `try`/`end` alignment nit itself: TransformSettings was never actually restored on a normal open

Went back and fixed the underlying bug the nit traced to (previously
flagged as a follow-up, fixed on request): in `WorkSpace`'s constructor,
the `TransformSettings.loadFrom(...)`/`.reset()` block was nested INSIDE
the `catch` body of the `try`/`catch` that reads the workspace file, not
after the whole construct. MATLAB's `try`/`catch` has one closing `end`
for both branches, easy to misread as two separate blocks; the effect
was that a workspace's remembered per-transformation options (last-used
Baseline/ArtefactDetect/... parameters) were silently never restored on
a normal, successful open, only on the fallback-defaults (missing/broken
file) path.

Moved the block to run after the try/catch (using the same
`exist('DIRS','var')` check it already had to tell success from
failure). Fixing this exposed a second, genuine bug hiding in the same
few lines: with the block properly closed off, the OUTER
`if/elseif/else` (`nargin==1||2||4` / `elseif nargin==4` / `else`)
needed exactly one fewer closing `end` than before -- the original code
had relied on `elseif` silently binding to the wrong (inner, `nargin==1`)
`if` rather than the intended outer one, because that inner `if` was
never given its own explicit close. Properly closing the inner `if`
(needed for the new `nargin==2` branch added earlier) shifted `elseif`
onto the outer `if`, which then had one extra `end` left over before its
own `else` -- a genuine parse error, caught immediately by `checkcode`
rather than shipped. Removed the stray `end`.

Verified with `test_transformsettings_restore.m`: builds a custom `.wksp`
with a `TransformSettings.Baseline` entry, opens it via
`Alakazam(customWksp)`, and confirms `TransformSettings.get('Baseline')`
actually returns the stored value afterward (poisoning the store to empty
first, so a stale pass from leftover session state can't be mistaken for
the fix working). `checkcode` clean on `WorkSpace.m`.

## Recalculate now cascades into any Grand Average built from the edited branch

Closes the gap `recalculateTransformNode`'s own doc comment used to
name explicitly ("a Grand Average built from a node further down this
branch... does not cascade... revisit it separately"): a Grand Average's
`sources` are frozen absolute paths, recorded once when it was built
(`GrandAverage.m`/`saveGrandAverage`) -- editing an upstream node used to
leave any Grand Average built from something in that branch silently
pointing at now-outdated data, with no indication anything had changed.

New `Alakazam.recalculateAffectedGrandAverages(touchedFiles)`, called
from `recalculateTransformNode` right after its main plan-save loop:
walks every node in `Workspace.GrandAveragesTree`, and for any Grand
Average whose own `etc.GrandAverage.sources` intersects `touchedFiles`
(the full set of files the just-completed recalculation overwrote,
`{plan.file}`), silently re-runs it -- reusing its own already-recorded
sources and weighting unchanged (no dialog, no membership change),
exactly what its own "Recalculate" context-menu action would produce if
reopened and confirmed without touching anything. The source-path
comparison is case-insensitive on Windows (`ispc` branch, mirroring
`toStoredPath`'s own reasoning: paths there are case-insensitive but
`strcmp`/`ismember` are not). A Grand Average is never itself a valid
source of another (`findGrandAverageCandidates` excludes them), so this
never needs more than one cascade level. `recalculateTransformNode`
re-asserts the originally-edited node as `Workspace.EEG`/the current tab
afterward, since refreshing a Grand Average adopts it as current in its
own right (same as running it manually would).

**A real near-miss while testing this**, worth recording since it could
recur: `saveGrandAverage` (and therefore this cascade) always saves to
`Workspace.CacheDirectory/GrandAverages`, regardless of where the node
actually lives -- unlike everywhere else recalculation touches, which
derives paths from the node's own file. A first test draft called plain
`Alakazam()`, which opens the repository's real default workspace; the
cascade under test then wrote a real `TestGA.mat` into the real
`Data/Cache/GrandAverages/` folder. Caught immediately (the file's own
`Access`/`Modify`/`Birth` timestamps matched the test run to the minute,
and a `find -newermt` sweep of `Data/` confirmed nothing else, including
the actual project data under `Data/p300/`, had been touched) and
deleted. Rewrote the test to construct `Alakazam(customWksp)` against an
isolated temp Raw/Cache/Exports tree throughout (the same pattern
`test_portable_paths.m` already established) -- necessary specifically
because this is the one code path that reaches into the real workspace's
cache directory regardless of test fixture locations; every earlier test
this session was already safe since none of them exercised anything
Grand-Average-related.

Verified with `test_recalculate_grandaverage.m` (isolated workspace
throughout): a two-subject Grand Average built from a branch's Average
output; recalculating the branch's Baseline node with changed parameters
is confirmed to refresh the Grand Average automatically, with its data
matching an independent recompute against the new upstream result (not
just "did it change"); a second, unrelated Grand Average sharing no
sources with the recalculated branch is confirmed to be left completely
untouched. `checkcode` clean on `Alakazam.m`.

## Alakazam.m split into an @Alakazam class folder (2255 lines -> a 177-line classdef + 59 method files)

`src/Alakazam.m` -- the application controller, and by far the largest
file in the project -- had grown to 2255 lines and ~60 methods. Split it
into a `src/@Alakazam/` class folder: the classdef (`@Alakazam/Alakazam.m`,
177 lines) keeps the header comment, all properties, the method prototype
declarations, and the constructor + `delete` inline; every other method
body moved to its own `@Alakazam/<name>.m` file.

Chose a class folder over extracting helper/controller classes precisely
because it is the *safe* option: MATLAB treats folder methods identically
to in-file methods, so the class identity, every method's name /
signature / access, and all the callbacks other components wire onto the
instance keep resolving unchanged -- `registerTileClick` / `closeTab`
(from `AlakazamPlotter`, `AverageView`, `EpochView`), `onNodeDropped` /
`onContextMenuAction` (from `@WorkSpace/CreateTreeComponent`),
`dispatchKey` / `dispatchWheel`. It is a pure file reorganisation, not a
redesign, so nothing calling into `Alakazam` had to change.

The one substantive edit: the constructor resolves `RootDir` / `RepoRoot`
from `mfilename('fullpath')`, which assumed the classdef sat directly in
`src/`. With the file now one level deeper (`src/@Alakazam/`), `RootDir`
became `fileparts(fileparts(mfilename('fullpath')))`. That is the only
line whose behaviour changed; every method body was moved byte-for-byte
(de-indented only). `mfilename` is used nowhere else -- the other
`pwd`-based paths are unrelated export-directory fallbacks.

Method access is preserved by declaring prototypes: the 17 private
methods are declared in a `methods (Access = private)` block, because a
method defined in a separate class-folder file is *public by default*, so
without the declaration they would silently widen to public. The public
methods are declared too, so the classdef reads as a complete index and
MATLAB's metaclass reports their real signatures rather than a
placeholder.

Verified behaviour-preserving by capturing the class's full metaclass API
-- every method with its access and input/output argument counts, plus
every property -- before and after the split, and confirming the two are
byte-identical. With the bodies moved verbatim, an identical metaclass API
is a strong equivalence proof for a class-folder split (dispatch depends
only on the method set, signatures and access). `checkcode` clean on all
60 files; `which -all Alakazam` resolves to the single new definition with
no shadow. The two non-obvious MATLAB mechanics this relied on -- a `~`
argument inside a prototype, and preserving private access via a prototype
declaration -- were confirmed in a throwaway class first. The running app
was then smoke-tested (open a workspace, run a transform) and works.

Note for the older entries in this log: references to `src/Alakazam.m:<line>`
and to methods "in `Alakazam.m`" now live under `src/@Alakazam/` -- the
classdef holds the constructor and properties, and `@Alakazam/<method>.m`
holds each method. The historical line numbers no longer resolve; the
method names are unchanged and remain the reliable way to find the code.
