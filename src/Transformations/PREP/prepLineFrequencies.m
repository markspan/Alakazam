function frequencies = prepLineFrequencies(choice, srate)
%PREPLINEFREQUENCIES  The line-noise peaks PREP should remove: the mains
%   frequency and its harmonics below the Nyquist frequency.
%
%   FREQUENCIES = prepLineFrequencies(CHOICE, SRATE) takes CHOICE as the
%   dialog stores it ('50', '60' or 'none', or the number itself) and returns
%   a row vector, empty for 'none'.
%
%   PREP's own default is 60 Hz and its multiples up to the Nyquist frequency
%   inclusive. Two things differ here, on purpose. The mains frequency is
%   asked for, because 60 Hz is wrong everywhere outside the Americas and a
%   European recording cleaned at 60 Hz keeps its 50 Hz. And a harmonic AT
%   the Nyquist frequency is left out: it is the one frequency a sampled
%   signal cannot represent with a phase, so a sinusoid fitted there is
%   meaningless.
%
%   See also PREP.
    if ischar(choice) || isstring(choice)
        choice = char(choice);
        if strcmpi(choice, 'none')
            frequencies = zeros(1, 0);
            return;
        end
        base = str2double(choice);
    else
        base = double(choice);
    end
    if ~isscalar(base) || ~isfinite(base) || base <= 0
        throw(MException('Alakazam:PREP', ['I''m afraid "%s" is not a line frequency I ' ...
            'understand. Would you choose 50, 60 or none?'], char(string(choice))));
    end
    nyquist = srate / 2;
    frequencies = base * (1:ceil(nyquist / base));
    frequencies = frequencies(frequencies < nyquist);
end
