function restoreFocus(this)
%RESTOREFOCUS  Bring MainFigure back to front/focus after running a
%   transformation. Most transforms' own options dialogs are now
%   TransformOptionsDialog (uifigure-based, replacing the old
%   uiextras.settingsdlg -- see migration.md), but a few classic
%   Java/AWT dialogs remain in the pipeline (e.g. AutoGEDAI's
%   GEDAI-install consent questdlg). Once one of those closes,
%   focus lands on the main
%   MATLAB desktop/command window instead of back on this
%   uifigure-based app, a known quirk of mixing the two windowing
%   systems. Called after every transformation (success or
%   failure), harmless for ones that never showed a dialog at all.
    figure(this.MainFigure);
end
