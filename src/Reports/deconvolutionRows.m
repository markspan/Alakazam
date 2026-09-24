function rows = deconvolutionRows(EEG, template, nChan)
%DECONVOLUTIONROWS  What a deconvolution left out, as provenance rows.
%   ROWS = deconvolutionRows(EEG, TEMPLATE, NCHAN) reads EEG.etc.alz.unfold
%   (written by Unfold.fitBins) and returns rows in TEMPLATE's shape (a
%   blank provenance row: every column, NaN or ''): one 'seconds of
%   recording' row for how much of the recording the model left out, and
%   one 'model note' row per note. Empty, in the same shape, when EEG was
%   not deconvolved.
%
%   TWO CALLERS, ONE SET OF ROWS. A subject deconvolved into one waveform
%   per bin reaches the report through deconvolutionQuality, having no
%   trials; one deconvolved into overlap-corrected trials reaches it through
%   dataQualityMetrics like any epoched subject, and EEG.etc travels down to
%   that epoched node. Both have to say the same thing about the model, so
%   it is said here. The one difference is written into the settings text:
%   the trials form says how many trials the model could correct, the
%   averaged form that there is no SME to be had.
%
%   See also DECONVOLUTIONQUALITY, DATAQUALITYMETRICS, EYETRACKINGROW,
%   UNFOLD.FITBINS.
    rows = template;
    rows(:) = [];
    info = unfoldInfo(EEG);
    if isempty(info)
        return;
    end

    seconds = numberOr(info, 'excludedSeconds');
    total = numberOr(info, 'recordingSeconds');
    row = fill(template, 'Deconvolve', 'seconds of recording', seconds, total);
    artifact = fieldOr(info, 'artifact', struct());
    row.threshold = numberOr(artifact, 'thresholdUv');
    row.channels_tested = nChan;
    row.n_samples_rejected = round(seconds * 1000);
    row.n_samples = round(total * 1000);
    row.scope = 'excluded from the model, not cut from the data';
    row.detail = settingsText(info);
    rows(end + 1) = row;

    notes = fieldOr(info, 'notes', {});
    for k = 1:numel(notes)
        note = fill(template, 'Deconvolve', 'model note', NaN, NaN);
        note.detail = notes{k};
        rows(end + 1) = note; %#ok<AGROW>
    end
end

% ======================================================================= %
function text = settingsText(info)
%SETTINGSTEXT  The settings a reader needs to interpret the result.
    window = fieldOr(info, 'window', []);
    baseline = fieldOr(info, 'baseline', []);
    parts = {};
    if numel(window) == 2
        parts{end + 1} = sprintf('response window %g to %g ms', window(1), window(2));
    end
    if numel(baseline) == 2
        parts{end + 1} = sprintf('baseline %g to %g ms', baseline(1), baseline(2));
    else
        parts{end + 1} = 'not baseline-corrected';
    end
    nuisance = fieldOr(info, 'nuisanceTypes', {});
    parts{end + 1} = sprintf('%d nuisance event type(s) modelled and dropped', numel(nuisance));
    if strcmpi(char(string(fieldOr(info, 'output', 'average'))), 'trials')
        parts{end + 1} = sprintf(['overlap-corrected trials: %d of %d kept, %d dropped ' ...
            '(window off the recording or on a stretch left out of the model)'], ...
            numberOr(info, 'trials'), numberOr(info, 'trialCandidates'), ...
            numberOr(info, 'trialsDropped'));
    else
        parts{end + 1} = 'no SME: a regression coefficient has no trials to spread';
    end
    text = strjoin(parts, '; ');
end

function row = fill(template, step, item, n, nTotal)
%FILL  TEMPLATE with the five columns every step fills.
    row = template;
    row.step = step;
    row.item = item;
    row.n = n;
    row.n_total = nTotal;
    row.pct = NaN;
    if isfinite(n) && isfinite(nTotal) && nTotal > 0
        row.pct = 100 * n / nTotal;
    end
end

function info = unfoldInfo(EEG)
    info = [];
    if isfield(EEG, 'etc') && isstruct(EEG.etc) && isfield(EEG.etc, 'alz') ...
            && isstruct(EEG.etc.alz) && isfield(EEG.etc.alz, 'unfold') ...
            && isstruct(EEG.etc.alz.unfold)
        info = EEG.etc.alz.unfold;
    end
end

function value = fieldOr(s, name, default)
    value = default;
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        value = s.(name);
    end
end

function value = numberOr(s, name)
    value = NaN;
    if isstruct(s) && isfield(s, name) && isnumeric(s.(name)) && isscalar(s.(name))
        value = double(s.(name));
    end
end
