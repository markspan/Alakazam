function colour = lineColour(k)
%LINECOLOUR  The colour of the K-th line of a view that draws one line per
%   bin: blue, red, teal, orange, black, green, magenta, and round again.
%
%   ONE PALETTE FOR EVERY VIEW. AverageView (an ERP per bin) and FourierView
%   (an averaged spectrum per bin) both colour their K-th bin with it, so a
%   condition keeps its colour from the waveform to the spectrum. The colours
%   are fixed rather than taken from the axes' ColorOrder so that a bin keeps
%   its colour while bins are ticked and unticked and electrodes stepped.
%
%   See also AVERAGEVIEW, FOURIERVIEW.
    PALETTE = [ ...
        0.00 0.00 1.00;   % blue
        1.00 0.00 0.00;   % red
        0.00 0.55 0.55;   % teal
        0.85 0.55 0.00;   % orange
        0.00 0.00 0.00;   % black
        0.00 0.55 0.00;   % green
        0.75 0.00 0.75];  % magenta
    colour = PALETTE(mod(k - 1, size(PALETTE, 1)) + 1, :);
end
