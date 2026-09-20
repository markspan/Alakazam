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
%   See also SPECTRALMEASURE, GENERATEQUARTOREPORT.
    text = '';
    used = {};
    details = struct('method', {}, 'winMs', {}, 'band', {});
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
        [method, winMs, band] = methodOf(EEG.params, TransTools.FieldOr(EEG, 'srate', NaN));
        if ~any(strcmp(used, method))
            used{end + 1} = method; %#ok<AGROW>
            details(end + 1) = struct('method', method, 'winMs', winMs, 'band', band); %#ok<AGROW>
        end
    end
    if isempty(used)
        return;
    end

    sentences = cell(1, numel(used));
    for k = 1:numel(used)
        d = details(k);
        switch d.method
            case 'frames'
                sentences{k} = ['the frame-averaged coherence: the signals are cut into overlapping frames' ...
                    frameLength(d.winMs) ', each frame is read at the frequency of the row itself, the coherence ' ...
                    'across trials is taken in each frame, and the frames are averaged. It is the same quantity ' ...
                    'the coherence map and the topography show'];
            case 'newcrossf'
                sentences{k} = ['EEGLAB''s newcrossf, which slides a window across each trial and averages over ' ...
                    'the frames and the trials' bandText(d.band) '. It agrees closely with the frame-averaged coherence ' ...
                    'the coherence map shows'];
            otherwise
                sentences{k} = ['a single window: one Fourier coefficient per trial over the whole epoch, pooled ' ...
                    'over trials. This estimate is biased upwards, and read 2.4 to 2.9 times the frame-averaged ' ...
                    'value on ten recordings of frequency-tagged data, so it should not be compared with a ' ...
                    'coherence map, a topography or a published figure'];
        end
    end
    if isscalar(used)
        text = ['**How coherence was estimated.** Coherence and phase-lag to the reference were computed as ' ...
            sentences{1} '.'];
    else
        text = ['**How coherence was estimated.** The recordings in this report do not share one estimator, ' ...
            'so their coherence values are not comparable with each other. They used: ' ...
            strjoin(cellfun(@(s) ['(' s ')'], sentences, 'UniformOutput', false), '; ') '.'];
    end
end

function [method, winMs, band] = methodOf(params, srate)
%METHODOF  The estimator, its window in ms and its band, from SpectralMeasure's options.
    crossf = TransTools.FieldOr(params, 'crossf', struct());
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
    winMs = NaN;
    samples = TransTools.FieldOr(crossf, 'WinSize', NaN);
    if isnumeric(samples) && isscalar(samples) && isfinite(samples) && isfinite(srate) && srate > 0
        winMs = 1000 * samples / srate;
    end
    band = [NaN NaN];
    lo = TransTools.FieldOr(crossf, 'MinFreq', NaN);
    hi = TransTools.FieldOr(crossf, 'MaxFreq', NaN);
    if isnumeric(lo) && isscalar(lo) && isnumeric(hi) && isscalar(hi)
        band = [lo hi];
    end
end

function t = frameLength(ms)
    if isfinite(ms)
        t = sprintf(' of about %.0f ms', ms);
    else
        t = '';
    end
end

function t = bandText(band)
    if all(isfinite(band))
        t = sprintf(' (between %g and %g Hz)', band(1), band(2));
    else
        t = '';
    end
end
