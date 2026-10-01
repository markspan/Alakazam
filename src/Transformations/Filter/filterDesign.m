function d = filterDesign(type, spec, srate)
%FILTERDESIGN  Every parameter of one of Filter's windowed-sinc filters.
%   D = filterDesign(TYPE, SPEC, SRATE) works out the Kaiser-windowed sinc
%   for TYPE 'high', 'low' or 'notch' from SPEC, for data sampled at SRATE
%   Hz. SPEC has
%     freq        the cutoff in Hz, where the gain is one half (-6 dB); the
%                 centre of the stop band for a notch
%     db          the stopband attenuation, in dB
%     auto        true (the default, and what older settings mean): the
%                 transition band and the order follow from FREQ and DB
%     transition  the transition band's width in Hz, when AUTO is false
%     order       the filter order (the kernel has ORDER + 1 taps), when
%                 AUTO is false; it wins over TRANSITION when both are given
%     width       a notch's stop band, in Hz (default 2)
%   and D has every parameter of the filter that results: .type, .freq,
%   .db, .dev (the deviation, 10^(-DB/20)), .ripple (the passband ripple in
%   dB, 20*log10(1 + DEV)), .beta (the Kaiser window's), .transition,
%   .order, .width (a notch's), .auto, and what firws needs: .fc (the band
%   edges as a fraction of Nyquist) and .ftype.
%
%   THE COUPLING IS EEGLAB'S. A Kaiser-windowed sinc has one deviation for
%   both its passband and its stopband, so the attenuation and the passband
%   ripple are one parameter in two units, and the Kaiser beta follows from
%   it (kaiserbeta). The order and the transition band are tied by firfilt's
%   firwsord, order from transition and deviation, and its inverse
%   invfirwsord, transition from order and deviation, so an edited order
%   gives the transition band it implies and an edited transition band the
%   order it needs, the attenuation kept. The order is even (a type I FIR,
%   firws needs one), rounded up.
%
%   AUTOMATIC, as Filter has always designed: a high-pass's transition band
%   is FREQ/4, at least 1 Hz and at most 0.9 FREQ; a low-pass's FREQ/4, at
%   least 2 Hz and at most 90% of the distance to Nyquist; a notch's 1 Hz,
%   with a 2 Hz stop band.
%
%   A frequency outside (0, Nyquist), a notch whose stop band reaches 0 or
%   Nyquist, a non-positive DB or WIDTH, or an order below 2 is refused with
%   a message for the user.
%
%   See also DESIGNFILTERKERNEL, FIRWSORD, INVFIRWSORD, KAISERBETA, FIRWS.
    nyq  = srate / 2;
    freq = double(spec.freq);
    db   = double(spec.db);
    auto = logical(field(spec, 'auto', true));
    if ~(freq > 0 && freq < nyq)
        refuse(sprintf(['the %s frequency (%.4g Hz) needs to sit between 0 and the Nyquist ' ...
            'frequency (%.4g Hz) -- would you choose a value in that range?'], type, freq, nyq));
    end
    if ~(db > 0)
        refuse(sprintf(['the %s attenuation needs to be a positive number of dB -- could you ' ...
            'check that value?'], type));
    end

    d = struct('type', type, 'freq', freq, 'db', db, 'auto', auto);
    d.dev    = 10 ^ (-db / 20);
    d.ripple = 20 * log10(1 + d.dev);
    d.beta   = kaiserbeta(d.dev);                      % EEGLAB firfilt helper
    d.width  = [];

    switch type
        case 'high'
            autoTransition = min(max(freq * 0.25, 1), freq * 0.9);
            d.fc = freq / nyq;
            d.ftype = 'high';
        case 'low'
            autoTransition = min(max(freq * 0.25, 2), (nyq - freq) * 0.9);
            d.fc = freq / nyq;
            d.ftype = '';                                  % lowpass: no type token
        case 'notch'
            d.width = double(field(spec, 'width', 2));
            if auto
                d.width = 2;
            end
            if ~(d.width > 0)
                refuse('the notch''s stop band needs a positive width in Hz.');
            end
            if freq - d.width / 2 <= 0 || freq + d.width / 2 >= nyq
                refuse(sprintf(['I''m afraid the notch frequency (%.4g Hz) sits too close to 0 or ' ...
                    'to Nyquist for a %.4g Hz stop band.'], freq, d.width));
            end
            autoTransition = 1;
            d.fc = [freq - d.width / 2, freq + d.width / 2] / nyq;
            d.ftype = 'stop';
        otherwise
            refuse(sprintf('"%s" is not a filter type I know.', type));
    end

    order = double(field(spec, 'order', []));
    transition = double(field(spec, 'transition', []));
    if auto || (isempty(order) && isempty(transition))
        d.transition = autoTransition;
        d.order = evenOrder(firwsord('kaiser', srate, d.transition, d.dev));   % as Filter always has
        d.auto = auto;
    elseif ~isempty(order)
        if ~(order >= 2)
            refuse('the filter order needs to be at least 2.');
        end
        d.order = evenOrder(order);
        d.transition = invfirwsord('kaiser', srate, d.order, d.dev);
    else
        if ~(transition > 0)
            refuse('the transition band needs a positive width in Hz.');
        end
        d.transition = transition;
        d.order = orderFor(srate, d.transition, d.dev);
    end
end

% ======================================================================= %
function m = orderFor(srate, transition, dev)
%ORDERFOR  firwsord's order for an entered transition band. firwsord rounds
%   up, so a transition band that is exactly what invfirwsord gave for an
%   order, as one shown in the dialog after an order was entered is, can
%   come back two higher from floating-point dust alone; the order below is
%   kept when it gives that same transition band.
    m = firwsord('kaiser', srate, transition, dev);
    if m > 2 && abs(invfirwsord('kaiser', srate, m - 2, dev) - transition) <= 1e-9 * transition
        m = m - 2;
    end
end

function m = evenOrder(m)
    m = ceil(round(m, 6) / 2) * 2;                     % the round absorbs floating-point dust
end

function v = field(s, name, default)
    v = default;
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    end
end

function refuse(text)
    throw(MException('Alakazam:Filter', 'Problem in Filter: %s', text));
end
