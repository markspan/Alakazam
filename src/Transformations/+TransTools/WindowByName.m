function prev = WindowByName(type, n)
%WINDOWBYNAME  A named taper window's N-sample values.
%   PREV = WINDOWBYNAME(TYPE, N) returns the N-sample window for TYPE
%   ('No', 'Hanning', 'Hamming', 'Bartlett', 'BlackmanHarris', 'BohmanWin',
%   'NuttallWin', 'ParzenWin', 'RectWin', 'Triang'), matched case-
%   insensitively; an unrecognised TYPE returns a flat (all-ones) window,
%   same as 'No'.
%
%   Shared by Fourier.m (the real per-segment analysis window, sized to
%   the loaded signal) and FourierGui's live preview (SelectWindow.m,
%   sized to a fixed preview canvas) so both always agree on which window
%   types exist and what each one computes -- previously two independent,
%   separately-maintained copies of the same dispatch list.
%
%   See also: Fourier, TransTools.SelectWindow.
    switch lower(type)
        case 'no'
            prev = zeros(n,1)+1;
        case 'hanning'
            prev = hanning(n);
        case 'hamming'
            prev = hamming(n);
        case 'bartlett'
            prev = bartlett(n);
        case 'blackmanharris'
            prev = blackmanharris(n);
        case 'bohmanwin'
            prev = bohmanwin(n);
        case 'nuttallwin'
            prev = nuttallwin(n);
        case 'parzenwin'
            prev = parzenwin(n);
        case 'rectwin'
            prev = rectwin(n);
        case 'triang'
            prev = triang(n);
        otherwise
            prev = zeros(n,1)+1;
    end
end
