function w = ColorbarColumnWidth()
%COLORBARCOLUMNWIDTH  Pixel width every TransTools.AddSharedColorbar
%   caller should reserve for its own colorbar column.
%
%   A colorbar's own bar + tick numbers fit comfortably in ~56px, which is
%   what every caller originally reserved (56px/60px, picked independently
%   per file and already drifted from each other) -- but a colorbar's
%   .Label (its own axis title, e.g. "Amplitude (\muV)", set by
%   AddSharedColorbar's own LABELTEXT) is a SEPARATE element positioned
%   outside the bar+ticks, rotated 90 degrees for a vertical colorbar, and
%   was never accounted for in that 56/60px figure -- it was silently
%   clipped by the grid cell's own bounds. Confirmed directly: reported as
%   a label "falling outside the view" once a longer label
%   ("dSPM (\sigma, noise-normalized)") made a marginal clipping problem
%   impossible to miss, but the same clipping already applied to every
%   other caller's own (shorter, less noticeably clipped) label.
%
%   One shared constant, not five independently re-guessed numbers, so a
%   future caller starts from a value already wide enough for a real
%   label instead of re-discovering this the same way.
%
%   100 (still not quite enough once the label's own FontSize grew --
%   see AddSharedColorbar's own cb.Label.FontSize) doubled to 200 on
%   request.
%
%   See also TRANSTOOLS.ADDSHAREDCOLORBAR.
    w = 200;
end
