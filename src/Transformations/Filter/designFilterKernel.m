function b = designFilterKernel(type, freq, db, srate)
%DESIGNFILTERKERNEL  The FIR kernel Filter applies for one filter.
%   B = designFilterKernel(TYPE, FREQ, DB, SRATE) designs a Kaiser-windowed
%   sinc (EEGLAB's firfilt plugin: kaiserbeta, firwsord, windows, firws) for
%   TYPE 'high', 'low' or 'notch' at FREQ Hz with DB of stopband attenuation,
%   for data sampled at SRATE Hz. B is a row vector of odd length (an even
%   order), symmetric, so applying it with its group delay compensated, as
%   firfilt does, is zero-phase.
%
%   ONE DESIGN, TWO READERS. Filter applies these kernels, and FilterDialog
%   plots their combined impulse response (filterImpulseResponse), so what the
%   dialog shows is exactly what the step does.
%
%   The design:
%     * the stopband deviation is 10^(-DB/20), and the Kaiser beta and the
%       order follow from it and the transition band;
%     * high-pass: a transition band of FREQ/4, at least 1 Hz and at most
%       0.9 FREQ;
%     * low-pass: FREQ/4, at least 2 Hz and at most 90% of the distance to
%       Nyquist;
%     * notch: a stop band of FREQ +/- 1 Hz with 1 Hz transitions.
%   A frequency outside (0, Nyquist), a notch too close to either end, or a
%   non-positive DB is refused with a message for the user.
%
%   See also FILTER, FILTERIMPULSERESPONSE, FIRWS, FIRWSORD.
    nyq  = srate / 2;
    freq = double(freq);
    db   = double(db);
    if ~(freq > 0 && freq < nyq)
        throw(MException('Alakazam:Filter', sprintf( ...
            'Problem in Filter: the %s frequency (%.4g Hz) needs to sit between 0 and the Nyquist frequency (%.4g Hz) -- would you choose a value in that range?', ...
            type, freq, nyq)));
    end
    if ~(db > 0)
        throw(MException('Alakazam:Filter', ...
            'Problem in Filter: the %s dB rating needs to be a positive number (the stopband attenuation) -- could you check that value?', type));
    end

    dev  = 10 ^ (-db / 20);          % stopband deviation from the dB rating
    beta = kaiserbeta(dev);          % EEGLAB firfilt helper

    switch type
        case 'high'
            df    = min(max(freq * 0.25, 1), freq * 0.9);
            fc    = freq / nyq;
            ftype = 'high';
        case 'low'
            df    = min(max(freq * 0.25, 2), (nyq - freq) * 0.9);
            fc    = freq / nyq;
            ftype = '';              % lowpass (no type token)
        case 'notch'
            hbw = 1;                 % half stop-band width (Hz)
            df  = 1;                 % transition bandwidth (Hz)
            if freq - hbw <= 0 || freq + hbw >= nyq
                throw(MException('Alakazam:Filter', ...
                    'Problem in Filter: I''m afraid the notch frequency (%.4g Hz) sits too close to 0 or to Nyquist for a %.4g Hz notch.', ...
                    freq, 2 * hbw));
            end
            fc    = [(freq - hbw) / nyq, (freq + hbw) / nyq];
            ftype = 'stop';
    end

    m = firwsord('kaiser', srate, df, dev);   % order from transition bw + deviation
    m = m + mod(m, 2);                         % firws needs an even order
    w = windows('kaiser', m + 1, beta);

    if isempty(ftype)
        b = firws(m, fc, w);
    else
        b = firws(m, fc, ftype, w);
    end
    b = reshape(b, 1, []);
end
