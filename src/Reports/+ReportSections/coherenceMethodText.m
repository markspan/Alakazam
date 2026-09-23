function text = coherenceMethodText(entries)
%COHERENCEMETHODTEXT  One paragraph saying how the report's coherence values
%   were estimated, or '' when there is nothing to say.
%
%   A coherence to a reference depends heavily on how it is estimated: on ten
%   RIFT recordings the single-window estimate read 2.4 to 2.9 times the
%   frame-averaged one for the same data. The exported CSV carries the number
%   and not the method (its twelve columns are a contract the report and the
%   exporter both pin), so without this the report would present a value the
%   reader cannot place against a coherence map, a topography or a published
%   figure.
%
%   The method is read from each SpectralMeasure node's own settings
%   (EEG.params). Entries with no reference channel measured no coherence, and
%   entries without settings (a grand average that dropped them) say nothing.
%   Settings from before the method existed mean what they always did: newcrossf
%   when crossf.enabled was on, the single window when it was off.
%
%   EVERY NUMBER IS THE RUN'S OWN. The frame length, the time range the frames
%   are averaged over and newcrossf's band are read from what the estimator
%   actually used (params.crossfUsed), falling back to the saved choice for
%   nodes made before that was recorded. None of them is a default written into
%   the prose, and recordings that share an estimator but not its settings are
%   said to differ rather than described by the first one.
%
%   See also SPECTRALMEASURE, GENERATEQUARTOREPORT.
    text = '';
    sentences = {};
    usedMethods = {};
    for i = 1:numel(entries)
        EEG = entries(i).EEG;
        if ~isfield(EEG, 'spectralMeasures') || isempty(EEG.spectralMeasures) ...
                || ~isfield(EEG, 'params') || ~isstruct(EEG.params)
            continue;
        end
        withReference = false;
        for w = 1:numel(EEG.spectralMeasures)
            m = EEG.spectralMeasures{w};
            withReference = withReference || (isfield(m, 'refChannel') && ~isempty(strtrim(char(string(m.refChannel)))));
        end
        if ~withReference
            continue;
        end
        d = methodOf(EEG.params, TransTools.FieldOr(EEG, 'srate', NaN));
        s = describe(d);
        if ~any(strcmp(sentences, s))
            sentences{end + 1} = s; %#ok<AGROW>
            usedMethods{end + 1} = d.method; %#ok<AGROW>
        end
    end
    if isempty(sentences)
        return;
    end

    if isscalar(sentences)
        text = ['**How coherence was estimated.** Coherence and phase-lag to the reference were computed as ' ...
            sentences{1} '.'];
    elseif isscalar(unique(usedMethods))
        text = ['**How coherence was estimated.** The recordings in this report used the same estimator ' ...
            'with different settings, so compare their coherence values with care. They used: ' ...
            strjoin(cellfun(@(s) ['(' s ')'], sentences, 'UniformOutput', false), '; ') '.'];
    else
        text = ['**How coherence was estimated.** The recordings in this report do not share one estimator, ' ...
            'so their coherence values are not comparable with each other. They used: ' ...
            strjoin(cellfun(@(s) ['(' s ')'], sentences, 'UniformOutput', false), '; ') '.'];
    end
end

function s = describe(d)
%DESCRIBE  The estimator in words, with this run's own settings.
    switch d.method
        case 'frames'
            s = ['the frame-averaged coherence: the signals are cut into overlapping frames' ...
                frameLength(d.winMs) ', each frame is read at the frequency of the row itself, the ' ...
                'coherence across trials is taken in each frame, and ' averaged('frames', d.range) '. ' ...
                'It is the quantity the coherence map and the topography show, and matches them closely ' ...
                'when they use the same frame length and time range'];
        case 'newcrossf'
            s = ['EEGLAB''s newcrossf: a window' frameLength(d.winMs) ' is slid across each trial, the ' ...
                'coherence across trials is taken at each position, and ' averaged('positions', d.range) ...
                bandText(d.band, d.bandAuto) '. With the same window and time range it agrees closely ' ...
                'with the frame-averaged coherence the coherence map shows'];
        otherwise
            s = ['a single window: one Fourier coefficient per trial over the whole epoch, pooled ' ...
                'over trials. This estimate is biased upwards, and read 2.4 to 2.9 times the frame-averaged ' ...
                'value on ten recordings of frequency-tagged data, so it should not be compared with a ' ...
                'coherence map, a topography or a published figure'];
    end
end

function d = methodOf(params, srate)
%METHODOF  The estimator and the settings it ran with, from SpectralMeasure's options.
%   RANGE is [] for the whole epoch. BANDAUTO is true when newcrossf's band was
%   left blank and worked out from the rows.
    crossf = TransTools.FieldOr(params, 'crossf', struct());
    used = TransTools.FieldOr(params, 'crossfUsed', struct());
    method = lower(char(string(TransTools.FieldOr(params, 'coherenceMethod', ''))));
    if isempty(method)
        method = lower(char(string(TransTools.FieldOr(crossf, 'Method', ''))));
    end
    if ~any(strcmp(method, {'frames', 'window', 'newcrossf'}))
        if logical(TransTools.FieldOr(crossf, 'enabled', false))
            method = 'newcrossf';
        else
            method = 'window';
        end
    end
    % Whatever the estimator recorded wins; a node from before it was recorded
    % has only the choice, which then held the resolved values.
    setting = @(name) TransTools.FieldOr(used, name, TransTools.FieldOr(crossf, name, NaN));
    haveUsed = isstruct(used) && isfield(used, 'Method');

    d = struct('method', method, 'winMs', NaN, 'range', [], 'band', [NaN NaN], 'bandAuto', false);
    samples = setting('WinSize');
    if isFiniteScalar(samples) && isfinite(srate) && srate > 0
        d.winMs = 1000 * samples / srate;
    end
    if haveUsed
        t0 = TransTools.FieldOr(used, 'TimeStart', NaN);
        t1 = TransTools.FieldOr(used, 'TimeStop', NaN);
    else
        t0 = TransTools.FieldOr(crossf, 'TimeStart', NaN);
        t1 = TransTools.FieldOr(crossf, 'TimeStop', NaN);
    end
    if isFiniteScalar(t0) && isFiniteScalar(t1)
        d.range = [t0 t1];
    end
    lo = setting('MinFreq');
    hi = setting('MaxFreq');
    if isFiniteScalar(lo) && isFiniteScalar(hi)
        d.band = [lo hi];
        d.bandAuto = haveUsed && ~isFiniteScalar(TransTools.FieldOr(crossf, 'MinFreq', NaN)) ...
            && ~isFiniteScalar(TransTools.FieldOr(crossf, 'MaxFreq', NaN));
    end
end

function tf = isFiniteScalar(v)
    tf = isnumeric(v) && isscalar(v) && isfinite(v);
end

function t = frameLength(ms)
    if isfinite(ms)
        t = sprintf(' of about %.0f ms', ms);
    else
        t = '';
    end
end

function t = averaged(noun, range)
%AVERAGED  "the frames are averaged over the whole epoch", or over the range the
%   user set (a frame counts when its centre lies inside it).
    if isempty(range)
        t = sprintf('the %s are averaged over the whole epoch', noun);
    else
        t = sprintf('the %s centred between %g and %g ms are averaged', noun, range(1), range(2));
    end
end

function t = bandText(band, auto)
    if ~all(isfinite(band))
        t = '';
    elseif auto
        t = sprintf('. Its frequency band was %g to %g Hz, set automatically to reach 8 Hz beyond the lowest and highest row', ...
            band(1), band(2));
    else
        t = sprintf('. Its frequency band was %g to %g Hz', band(1), band(2));
    end
end
