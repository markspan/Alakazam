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

Investigation paused here. No code changes made yet.
