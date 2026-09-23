function [traceFile, mapFile, chosen, referenceFile] = exportCoherenceCSVs(entries, stem, opts)
%EXPORTCOHERENCECSVS  The CoherenceMap result, as data rather than a picture.
%   [TRACEFILE, MAPFILE, CHOSEN, REFERENCEFILE] = exportCoherenceCSVs(ENTRIES,
%   STEM, OPTS) writes three long-format CSVs beside each other and returns
%   their paths plus the channel labels the map was written for.
%
%   WHY THREE FILES AND NOT ONE. A coherence map is nChan x nFreq x nTime x
%   nBin, and at the settings of Dimigen et al. (2025) (STFT 510 ms, pad 4,
%   52 to 68 Hz, a 13 s epoch at 1000 Hz) that is 33 frequencies by 98
%   frames. Written whole for 64 channels and 3 bins it is 620,928 rows,
%   about 37 MB PER SUBJECT, so a twenty-subject study would put three
%   quarters of a gigabyte beside the report. The files split that along the
%   axis that matters:
%
%     TRACE  coherence against time at the tagged frequency alone, for
%            EVERY channel. 18,816 rows, about 1 MB, and it is the plot
%            that shows fade-in, steady state and fade-out, which is where
%            the steady-state measurement window comes from. Each row also
%            carries the number of trials behind it (n_trials), because the
%            coherence of N independent trials is 1/N by chance alone.
%     MAP    the full time x frequency plane, for a FEW channels. The
%            figure a tagging paper prints, at about 5 MB for eight
%            channels rather than 37 for all of them.
%     REFERENCE  the reference channel's own amplitude spectrum, 0 to 150 Hz,
%            per dataset and condition, with the band the coherence covers
%            and the reference's strongest frequency. About 25,000 rows for
%            ten datasets and four conditions. It shows where the flicker
%            actually was, which the band-limited trace cannot: a condition
%            tagged outside the analysed band is otherwise reported at
%            whatever unrelated frequency inside the band is strongest.
%
%   THE TAGGED FREQUENCY IS FOUND IN THE DATA, per bin, from the reference
%   channel's OWN power (EEG.cohRefPower) at the frequency where it is
%   greatest, averaged over time. A photodiode measures the flicker directly,
%   so its own peak is the tag, independent of how any EEG channel responded.
%   A result computed before cohRefPower existed has no such field, and falls
%   back to the frequency whose coherence is greatest averaged over channels
%   and time, which is noisier: for a weak response it can peak on line noise
%   or on another condition's tag. Either way the tag is the strongest
%   frequency INSIDE the analysed band, so a condition tagged outside it must
%   be recognised from the REFERENCE file.
%
%   THE MAP'S CHANNELS ARE CHOSEN BY RESPONSE, AND THAT IS A DISPLAY
%   DECISION, NOT AN ANALYSIS ONE. They are the OPTS.MaxChannels (default
%   8) with the highest coherence at the tagged frequency. Choosing what to
%   plot after seeing the data is how every figure in every tagging paper
%   is made, and it is only dangerous when a test follows; nothing here is
%   tested, and the report says which channels were picked and why. If a test
%   does follow, Arora et al. (2026) ask that channels be chosen blind to the
%   conditions being compared, which OPTS.SelectBy = 'pooled' does: every
%   condition of a dataset then uses the channels that respond most on
%   average over all its conditions, rather than each its own strongest.
%
%   OPTS fields, all optional:
%     MaxChannels   how many channels the map is written for   (default 8)
%     Channels      explicit labels for the map instead        (default [])
%     SelectBy      'condition' (each condition its own strongest channels,
%                   the default) or 'pooled' (the same channels for every
%                   condition of a dataset, ranked over all of them)
%     OnlyChannels  labels to restrict BOTH files to           (default [])
%
%   ONLYCHANNELS is how the report follows the electrodes a user named
%   in the Spectral Measure rows. Every other channel is left out of the
%   trace and the map, and the map's channels are chosen among the named ones
%   alone. It does not touch the tag: that is read off the reference (or, for
%   a result that has none, off every channel), so naming one electrode does
%   not change which frequency a condition is tagged at. A dataset that has
%   none of the named channels is written whole rather than left empty, so a
%   montage that differs from the user's does not silently drop a subject.
%
%   A condition whose coherence is entirely missing (a single trial, or none)
%   contributes no trace or map rows; its reference spectrum is still written.
%
%   See also COHERENCEMAP, EXPORTSPECTRACSV, GENERATEQUARTOREPORT.
    if nargin < 3 || isempty(opts)
        opts = struct();
    end
    maxChannels = TransTools.FieldOr(opts, 'MaxChannels', 8);
    wanted = TransTools.FieldOr(opts, 'Channels', {});
    only = TransTools.FieldOr(opts, 'OnlyChannels', {});
    selectBy = lower(char(string(TransTools.FieldOr(opts, 'SelectBy', 'condition'))));
    if ~any(strcmp(selectBy, {'condition', 'pooled'}))
        throw(MException('Alakazam:exportCoherenceCSVs', '%s', sprintf( ...
            'I''m afraid SelectBy must be "condition" or "pooled", not "%s".', selectBy)));
    end

    traceFile = [stem '_coherence_trace.csv'];
    mapFile   = [stem '_coherence_map.csv'];
    referenceFile = [stem '_coherence_reference.csv'];
    chosen = {};

    traceFid = openFile(traceFile);
    closeTrace = onCleanup(@() fclose(traceFid));
    fprintf(traceFid, ['dataset,dataset_type,group,person_id,session,bin,channel,' ...
        'time_ms,tag_hz,coherence,n_trials\n']);

    mapFid = openFile(mapFile);
    closeMap = onCleanup(@() fclose(mapFid));
    fprintf(mapFid, ['dataset,dataset_type,group,person_id,session,bin,channel,' ...
        'time_ms,frequency_hz,coherence\n']);

    referenceFid = openFile(referenceFile);
    closeReference = onCleanup(@() fclose(referenceFid));
    fprintf(referenceFid, ['dataset,dataset_type,group,person_id,session,bin,' ...
        'n_trials,band_lo_hz,band_hi_hz,peak_hz,frequency_hz,amplitude\n']);

    for i = 1:numel(entries)
        picked = writeEntry(traceFid, mapFid, referenceFid, entries(i), ...
            maxChannels, wanted, selectBy, only);
        chosen = unique([chosen, picked], 'stable');
    end
end

% ======================================================================= %
function fid = openFile(path)
    fid = fopen(path, 'w');
    if fid < 0
        throw(MException('Alakazam:exportCoherenceCSVs', '%s', sprintf( ...
            'I''m afraid I wasn''t able to open "%s" for writing.', path)));
    end
end

function chosen = writeEntry(traceFid, mapFid, referenceFid, entry, maxChannels, wanted, selectBy, only)
%WRITEENTRY  One dataset's trace, map and reference rows.
    chosen = {};
    EEG = entry.EEG;
    if ~isfield(EEG, 'coherence') || isempty(EEG.coherence) || ...
            ~isfield(EEG, 'cohFreqs') || ~isfield(EEG, 'cohTimes')
        return;
    end

    coh   = double(EEG.coherence);         % nChan x nFreq x nTime x nBin
    freqs = reshape(double(EEG.cohFreqs), 1, []);
    times = reshape(double(EEG.cohTimes), 1, []);
    [nChan, nFreq, nTime, nBin] = size(coh);
    if nFreq ~= numel(freqs) || nTime ~= numel(times)
        return;    % a shape nothing here can interpret; skip rather than guess
    end

    % The reference channel's own power spectrum (see CoherenceMap.m /
    % ComputeCoherenceMap's own header): present from any dataset
    % processed since cohRefPower was added, absent (and so silently unused
    % below) for an older cached result computed before it existed.
    % size(X), the vector form, drops a trailing singleton dimension (a
    % single-bin cohRefPower is nFreq x nTime x 1, and size() reports that
    % as just [nFreq nTime]), so it is checked per dimension instead: an
    % isequal against a literal 3-element size vector silently never
    % matches a 1-bin export and falls back to the noisier read-out below
    % for the single most common case there is.
    refPower = [];
    if isfield(EEG, 'cohRefPower') && ndims(EEG.cohRefPower) <= 3 && ...
            size(EEG.cohRefPower, 1) == nFreq && size(EEG.cohRefPower, 2) == nTime && ...
            size(EEG.cohRefPower, 3) == nBin
        refPower = double(EEG.cohRefPower);
    end

    labels = channelLabels(EEG, nChan);
    pool = channelPool(labels, only);
    fields = {csvField(entry.subject), csvField(entry.datasetType), ...
        csvField(entry.group), csvField(entry.person), csvField(entry.session)};
    prefix = [strjoin(fields, ','), ','];
    nTrials = trialCounts(EEG, nBin);

    writeReference(referenceFid, prefix, EEG, nBin, nTrials, freqs);

    % First pass: each condition's tag and its trace at that frequency.
    valid = false(1, nBin);
    tagHz = nan(1, nBin);
    traces = cell(1, nBin);
    for b = 1:nBin
        slab = coh(:, :, :, b);                        % nChan x nFreq x nTime

        % THE TAG: read off the REFERENCE'S OWN power, not off the EEG
        % channels' coherence to it. Averaging coherence over every channel
        % picked the same wrong frequency for two different RIFT/SSVEP
        % conditions, because that average is small and noisy for a
        % weak/distant channel and can peak on line noise, a harmonic, or
        % another condition's own tag entirely. The reference (typically a
        % photodiode) measures the physical flicker directly, so its own
        % spectral peak IS the tag, independent of how any one EEG channel
        % responded. Falls back to the old channel-averaged read-out when
        % cohRefPower is absent (an older cached result, or a reference this
        % dataset never recorded a clean signal for) so a report from before
        % this fix still renders.
        if ~isempty(refPower)
            perFreq = mean(refPower(:, :, b), 2, 'omitnan')';
        else
            perFreq = mean(mean(slab, 3, 'omitnan'), 1, 'omitnan');
        end
        % A bin this dataset has no trials for (a condition run for other
        % subjects but not this one, e.g. RIFT's own peripheral-60Hz/SSVEP
        % split by subject group), a combination bin (see coherenceOverBins),
        % or a bin with a single trial (whose coherence is undefined) is
        % entirely NaN here. max() of an all-NaN vector does not itself
        % return NaN, it silently returns INDEX 1, so without this check
        % tagHz would become freqs(1), the analysis band's own lowest
        % frequency, written out as if it were a real detected tag for every
        % channel and timepoint. Once even one dataset contributes that
        % fabricated value for a bin, it can surface as THE reported "tagged
        % frequency" for that condition across the whole report. Skipping the
        % bin entirely here (no trace rows, no map rows, no tag) is the same
        % "nothing to say" response coherenceOverBins already gives an
        % empty-trial bin.
        if all(isnan(perFreq)) || all(isnan(slab(:)))
            continue;
        end
        [~, fTag] = max(perFreq);
        valid(b) = true;
        tagHz(b) = freqs(fTag);
        traces{b} = reshape(slab(:, fTag, :), nChan, nTime);
    end

    % Which channels the map is written for. By default each condition gets
    % its own strongest, which is a display decision (see the header). Pooled
    % ranks every channel once over all the dataset's conditions, so the
    % choice does not depend on which condition happened to win.
    peaks = nan(nChan, nBin);
    for b = find(valid)
        peaks(:, b) = max(traces{b}, [], 2, 'omitnan');
    end
    pooledPeak = mean(peaks, 2, 'omitnan');

    for b = find(valid)
        binField = csvField(csvBinLabel(EEG, b));
        trace = traces{b};
        for c = pool
            chField = csvField(labels{c});
            for t = 1:nTime
                fprintf(traceFid, '%s%s,%s,%s,%s,%s,%s\n', prefix, binField, chField, ...
                    numField(times(t)), numField(tagHz(b)), numField(trace(c, t)), ...
                    numField(nTrials(b)));
            end
        end

        % And the full plane, for the few channels worth printing.
        % Ranked among the channels being written alone; pickChannels
        % numbers them 1..numel(pool), so its answer is mapped back.
        if strcmp(selectBy, 'pooled')
            picked = pool(pickChannels(pooledPeak(pool), labels(pool), maxChannels, wanted));
        else
            picked = pool(pickChannels(peaks(pool, b), labels(pool), maxChannels, wanted));
        end
        chosen = unique([chosen, labels(picked)], 'stable');
        slab = coh(:, :, :, b);
        for c = picked
            chField = csvField(labels{c});
            for f = 1:nFreq
                fHz = numField(freqs(f));
                for t = 1:nTime
                    fprintf(mapFid, '%s%s,%s,%s,%s,%s\n', prefix, binField, chField, ...
                        numField(times(t)), fHz, numField(slab(c, f, t)));
                end
            end
        end
    end
end

function n = trialCounts(EEG, nBin)
%TRIALCOUNTS  Trials behind each bin, NaN where the dataset does not say.
    n = nan(1, nBin);
    if ~isfield(EEG, 'bindesc') || ~isfield(EEG.bindesc, 'trials')
        return;
    end
    for b = 1:min(nBin, numel(EEG.bindesc))
        if ~isempty(EEG.bindesc(b).trials)
            n(b) = numel(EEG.bindesc(b).trials);
        end
    end
end

function writeReference(fid, prefix, EEG, nBin, nTrials, freqs)
%WRITEREFERENCE  The reference channel's amplitude spectrum, one row per
%   frequency cell, for each bin that has one. Nothing is written for a
%   result computed before the spectrum was stored.
    if ~isfield(EEG, 'cohRefSpectrum') || isempty(EEG.cohRefSpectrum) || ...
            ~isfield(EEG, 'cohRefSpecFreqs')
        return;
    end
    spec = double(EEG.cohRefSpectrum);
    specFreqs = reshape(double(EEG.cohRefSpecFreqs), 1, []);
    if size(spec, 1) ~= numel(specFreqs) || size(spec, 2) ~= nBin
        return;
    end
    peakHz = nan(1, nBin);
    if isfield(EEG, 'cohRefPeakHz') && numel(EEG.cohRefPeakHz) == nBin
        peakHz = reshape(double(EEG.cohRefPeakHz), 1, []);
    end
    lo = min(freqs);
    hi = max(freqs);
    for b = 1:nBin
        if all(isnan(spec(:, b)))
            continue;
        end
        binField = csvField(csvBinLabel(EEG, b));
        for k = 1:numel(specFreqs)
            fprintf(fid, '%s%s,%s,%s,%s,%s,%s,%s\n', prefix, binField, ...
                numField(nTrials(b)), numField(lo), numField(hi), numField(peakHz(b)), ...
                numField(specFreqs(k)), numField(spec(k, b)));
        end
    end
end

function idx = channelPool(labels, only)
%CHANNELPOOL  Indices of the channels the trace and the map are written for.
%   Everything when ONLY is empty, or when none of its labels is in this
%   dataset (matched case-insensitively, as the Spectral Measure rows are).
    idx = 1:numel(labels);
    if isempty(only)
        return;
    end
    hit = false(1, numel(labels));
    for k = 1:numel(only)
        hit = hit | strcmpi(labels, char(string(only{k})));
    end
    if any(hit)
        idx = find(hit);
    end
end

function idx = pickChannels(peak, labels, maxChannels, wanted)
%PICKCHANNELS  Which channels the full map is written for.
%   An explicit list wins, so a user who knows their montage is never
%   overruled by the data. Otherwise the strongest responders, which is
%   what a figure shows. PEAK is each channel's strongest coherence at the
%   tagged frequency, nChan x 1.
    if ~isempty(wanted)
        idx = [];
        for k = 1:numel(wanted)
            hit = find(strcmpi(labels, char(string(wanted{k}))), 1);
            if ~isempty(hit)
                idx(end + 1) = hit; %#ok<AGROW>
            end
        end
        if ~isempty(idx)
            return;
        end
    end
    peak(~isfinite(peak)) = -Inf;
    [~, order] = sort(peak, 'descend');
    idx = sort(order(1:min(maxChannels, numel(order))))';
end

function labels = channelLabels(EEG, nChan)
    labels = arrayfun(@(k) sprintf('ch%d', k), 1:nChan, 'UniformOutput', false);
    if isfield(EEG, 'chanlocs') && numel(EEG.chanlocs) >= nChan
        for c = 1:nChan
            name = EEG.chanlocs(c).labels;
            if ~isempty(name)
                labels{c} = char(string(name));
            end
        end
    end
end
