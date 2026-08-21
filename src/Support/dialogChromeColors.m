function [accentColor, bgColor] = dialogChromeColors()
%DIALOGCHROMECOLORS  The two colours every Alakazam dialog's own header
%   bar / OK button uses: ACCENTCOLOR (#4a7fc9, matching
%   AlakazamRibbon.html's .alz-tab-home) and BGCOLOR (uifigure's own
%   default Color, restated explicitly since a dialog's header bar needs
%   an actual value to contrast against, not just the implicit default).
%
%   Previously restated as the same two literal RGB triples in every one
%   of TransformOptionsDialog.m, MeasureDialog.m, FilterDialog.m,
%   ReRefDialog.m, SelectDataDialog.m, ChannelEditorDialog.m,
%   InterpolateDialog.m, RemoveComponentsDialog.m, SpectralMeasureDialog.m,
%   GrandAverageDialog.m and SettingsDialog.m (the last one to get this
%   treatment; previously the one dialog left unstyled entirely);
%   consolidated here. The dialogs' own header bar / body-grid / button-row
%   construction is NOT consolidated (varies enough per dialog -- size, row
%   count, extra widgets -- that forcing it through one generic template
%   risked more than the duplication itself; this is the one piece that
%   was purely, safely literal).
    accentColor = [0.290 0.498 0.788];
    bgColor     = [0.9608 0.9608 0.9608];
end
