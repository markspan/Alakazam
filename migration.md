# Migration: ToolGroup docking is going away

MATLAB 2025b/2026a stop creating Java(Swing)-backed figures; every `figure()`
now uses the web/CEF-rendered uifigure architecture under the hood. This
breaks Alakazam's app shell, which docks plot windows via the old
Java-based `ToolGroup` desktop. Not yet reproduced locally (only R2024b is
installed here) -- this is a design note to pick up the investigation from,
not a confirmed-fixed changelog entry.

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
