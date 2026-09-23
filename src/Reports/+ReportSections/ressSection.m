function text = ressSection(entries)
%RESSSECTION  What the report's RESS components are, and their null: each
%   component's coherence and SNR at its own frequency, in every bin, with
%   the role that bin plays for it. '' when no entry carries a RESS
%   component that a Spectral Measure row reads.
%
%   A RESS filter (see RESS) is fitted to the trials of the bins it is built
%   from and applied to every trial. In a bin it was not built from, the
%   flicker it was built for is absent, so there it shows what the filter
%   gives on its own: its null, which the report is to show automatically.
%
%   NOT EVERY OTHER BIN IS A NULL, and calling one a null when it is not
%   would make the null look worse than it is. A bin is not a clean null when
%   a harmonic of its own frequency, the fundamental included, lies within
%   2/T Hz of the filter's, T being the coherence frame's length:
%
%     ON IT. 30 Hz flicker drives a response at 60 Hz, and the RIFT 30 Hz
%     condition's square-wave photodiode carries a small 60 Hz component the
%     response locks to (coherence 0.48 to 0.82 at Oz).
%
%     TOO CLOSE FOR THE FRAMES. A Hann-tapered frame of T seconds cannot
%     separate frequencies closer than 2/T Hz, the first zero of its
%     spectrum. On the RIFT recordings at 2000 Hz, 510-sample frames last
%     255 ms: 60 Hz trials read a coherence of 0.12 at 64 Hz at Oz and 0.29
%     on the 64 Hz component, and the 30 Hz trials 0.22 to 0.32 at Oz
%     through their 60 Hz harmonic. With 1020 ms frames both fell to the
%     noise floor (0.02 to 0.03): leakage, not a response at 64 Hz.
%
%   A bin's frequency is read from its label (TransTools.FrequencyFromLabel);
%   when a label names none, the bin is only said not to have built the
%   filter.
%
%   A recording with no usable trial of a component's bins has that
%   component left empty by RESS; the section names those recordings, so a
%   mean over fewer recordings than the study has is not read as the whole.
%
%   It also states what the article asks a reader to check: how far each
%   filter separated its frequency from the frequencies beside it (the
%   largest eigenvalue), which recordings it separated nothing in, which
%   ones carry an inverted map, and that a component's SNR is a partly
%   biased measure. See separationLines and biasLines.
%
%   See also RESS, RESSFILTER, REPORTSECTIONS.COHERENCEMETHODTEXT.
    text = '';
    [info, EEG] = firstRessEntry(entries);
    if isempty(info)
        return;
    end
    binLabels = cellstr(string({EEG.bindesc.label}));
    if isfield(EEG.bindesc, 'combo')
        binLabels = binLabels(cellfun(@isempty, {EEG.bindesc.combo}));
    end
    frameSeconds = frameLength(EEG);

    roles = strings(0, 4);
    for k = 1:numel(info)
        for b = 1:numel(binLabels)
            roles(end + 1, :) = [string(info(k).label), string(info(k).freq), string(binLabels{b}), ...
                string(roleOf(info(k), binLabels{b}, frameSeconds))]; %#ok<AGROW>
        end
    end

    labels = strjoin(cellfun(@ReportSections.mdLit, {info.label}, 'UniformOutput', false), ', ');
    empty = emptyComponents(entries, {info.label});
    if ~isempty(empty)
        empty = [empty {''}];
    end
    separation = separationLines(entries, {info.label});
    if ~isempty(separation)
        separation = [separation {''}];
    end
    suppressed = suppressedConditions(info, binLabels);
    if ~isempty(suppressed)
        suppressed = [suppressed {''}];
    end
    bias = [biasLines(info, EEG) {''}];
    lines = ReportDoc.lines([{ ...
        '## RESS components and their null' ...
        '' ...
        [labels ' ' plural(numel(info), 'is a RESS component', 'are RESS components') ' (Cohen & Gulbinaite, 2017): ' ...
         describe(info) ' The weights are fitted separately for each recording, so the component, not an ' ...
         'electrode, is what is compared across recordings.'] ...
        ''} empty separation suppressed bias {...
        ['Each filter was fitted to the trials of the bins it was built from and then applied to every ' ...
         'trial. In the other bins the flicker it was built for was absent, so there it shows what the ' ...
         'filter gives on its own: its null. Values in the bins it was built from are measured on the trials ' ...
         'it was fitted to. A bin is not a clean null when one of the harmonics of its own frequency falls ' ...
         'on the filter''s, since flicker at 30 Hz drives a response at 60 Hz, or so close to it that the ' ...
         'coherence frames cannot separate the two: a frame cannot tell apart frequencies closer than two ' ...
         'divided by its length. The table names each such bin and why.'] ...
        '' ...
        '```{r}' ...
        '#| label: ress-null' ...
        '#| results: asis' ...
        ['ress_roles <- tibble(component = ' rVector(roles(:, 1)) ', freq = as.numeric(' rVector(roles(:, 2)) '),'] ...
        ['                     bin = ' rVector(roles(:, 3)) ', role = ' rVector(roles(:, 4)) ')'] ...
        ReportDoc.template('ress-null-table.qmd') ...
        ''}]);
    text = strjoin(lines, newline);
end

function sentences = emptyComponents(entries, labels)
%EMPTYCOMPONENTS  One paragraph per component that some recordings could
%   not build, naming them. RESS leaves such a component's channel all NaN
%   (nTrials 0) when a recording has no usable trial of its bins, so its
%   values there are missing and the table's means leave those recordings
%   out; a reader has to be told which, and why. {} when every recording
%   built every component.
    sentences = {};
    nRecordings = 0;
    missing = repmat({{}}, 1, numel(labels));
    bins = cell(1, numel(labels));
    for i = 1:numel(entries)
        E = entries(i).EEG;
        if ~isfield(E, 'etc') || ~isstruct(E.etc) || ~isfield(E.etc, 'alz') || ...
                ~isstruct(E.etc.alz) || ~isfield(E.etc.alz, 'ress') || isempty(E.etc.alz.ress)
            continue;
        end
        nRecordings = nRecordings + 1;
        ress = E.etc.alz.ress;
        if ~isfield(ress, 'nTrials')
            continue;
        end
        for k = 1:numel(labels)
            hit = find(strcmp({ress.label}, labels{k}), 1);
            if ~isempty(hit) && ress(hit).nTrials == 0
                missing{k}{end + 1} = recordingName(entries(i), i);
                bins{k} = ress(hit).bins;
            end
        end
    end
    for k = 1:numel(labels)
        n = numel(missing{k});
        if n == 0
            continue;
        end
        names = strjoin(cellfun(@ReportSections.mdLit, missing{k}, 'UniformOutput', false), ', ');
        sentences{end + 1} = sprintf(['%s could not be built in %d of the %d recordings (%s), which %s ' ...
            'no usable trial of %s: no filter was fitted there and its channel was left empty, so its ' ...
            'values in %s are missing rather than zero, and the table below averages over the ' ...
            'recordings in which it was built.'], ReportSections.mdLit(labels{k}), n, nRecordings, names, ...
            plural(n, 'has', 'have'), ReportSections.mdLit(strjoin(bins{k}, ' or ')), ...
            plural(n, 'that recording', 'those recordings')); %#ok<AGROW>
    end
end

function lines = separationLines(entries, labels)
%SEPARATIONLINES  How well each filter separated its frequency, per
%   component, and which recordings it failed in.
%
%   The largest generalized eigenvalue IS the separation the filter
%   achieved: the ratio of power at the frequency to power beside it, in
%   the combination of channels it chose. Near 1 means no combination of
%   this recording's channels had more power at the frequency than at its
%   neighbours, which is what "no response" looks like, and the component
%   is then a direction through noise rather than a response. The article
%   inspects the eigenvalue spectrum for exactly this reason, so the report
%   states it rather than leaving it in EEG.etc.alz.ress.
%
%   A recording whose scalp map is inverted relative to the others is named
%   too: the sign of a component is fixed by the largest channel of its own
%   map (see RESSFilter), which makes the recordings comparable only while
%   their maps agree. Where one is inverted, that recording's component,
%   and every phase and phase lag read from it, is half a cycle from the
%   others.
    lines = {};
    saidWeak = false;
    saidFlipped = false;
    [best, maps, names] = gatherComponents(entries, labels);
    for k = 1:numel(labels)
        v = best{k};
        who = names{k};
        ok = isfinite(v);
        if nnz(ok) == 0
            continue;
        end
        v = v(ok); who = who(ok);
        sentence = sprintf(['%s separated %g Hz from the frequencies beside it by a factor of %.1f ' ...
            '(median over %d recording%s, %.2f to %.2f).'], ReportSections.mdLit(labels{k}), ...
            componentFreq(entries, labels{k}), median(v), numel(v), plural(numel(v), '', 's'), ...
            min(v), max(v));
        % Each explanation is given once, on the first component that needs
        % it: a study with three components otherwise repeats the same two
        % paragraphs three times, and a reader stops reading them.
        weak = who(v < 1);
        if ~isempty(weak)
            if saidWeak
                sentence = [sentence sprintf(' It is below 1 in %s.', namesOf(weak))]; %#ok<AGROW>
            else
                sentence = [sentence sprintf([' A factor near 1 means no combination of that ' ...
                    'recording''s channels held more power at the frequency than beside it, which is ' ...
                    'what no response looks like: %s %s below 1, so %s component is a direction ' ...
                    'through noise rather than a response and should be read as such.'], ...
                    namesOf(weak), plural(numel(weak), 'is', 'are'), ...
                    plural(numel(weak), 'its', 'their'))]; %#ok<AGROW>
                saidWeak = true;
            end
        end
        flipped = invertedMaps(maps{k}(ok), who);
        if ~isempty(flipped)
            if saidFlipped
                sentence = [sentence sprintf(' Its map is inverted in %s.', namesOf(flipped))]; %#ok<AGROW>
            else
                sentence = [sentence sprintf([' The scalp map of %s %s inverted relative to the ' ...
                    'others, so %s component, and any phase or phase lag read from it, %s half a ' ...
                    'cycle from theirs: the sign of a component is fixed by the largest channel of ' ...
                    'its own map, which lines the recordings up only while their maps agree.'], ...
                    namesOf(flipped), plural(numel(flipped), 'is', 'are'), ...
                    plural(numel(flipped), 'its', 'their'), plural(numel(flipped), 'is', 'are'))]; %#ok<AGROW>
                saidFlipped = true;
            end
        end
        lines{end + 1} = sentence; %#ok<AGROW>
    end
end

function [best, maps, names] = gatherComponents(entries, labels)
%GATHERCOMPONENTS  Per component, each recording's largest eigenvalue, its
%   map (as a containers.Map from channel label to weight, so recordings
%   with different montages can still be compared) and its name.
    best = repmat({[]}, 1, numel(labels));
    maps = repmat({{}}, 1, numel(labels));
    names = repmat({{}}, 1, numel(labels));
    for i = 1:numel(entries)
        E = entries(i).EEG;
        if ~isfield(E, 'etc') || ~isstruct(E.etc) || ~isfield(E.etc, 'alz') || ...
                ~isstruct(E.etc.alz) || ~isfield(E.etc.alz, 'ress') || isempty(E.etc.alz.ress)
            continue;
        end
        ress = E.etc.alz.ress;
        for k = 1:numel(labels)
            hit = find(strcmp({ress.label}, labels{k}), 1);
            if isempty(hit)
                continue;
            end
            e = ress(hit).eigenvalues;
            best{k}(end + 1) = firstOr(e, NaN);
            maps{k}{end + 1} = struct('channels', {ress(hit).channels}, 'map', ress(hit).map);
            names{k}{end + 1} = recordingName(entries(i), i);
        end
    end
end

function flipped = invertedMaps(maps, names)
%INVERTEDMAPS  The recordings whose map points against the orientation the
%   others share, over the channels they have in common.
%
%   Orientation comes from the leading eigenvector of the map-to-map
%   correlation matrix, whose sign per recording is that recording's
%   polarity in the pattern the group shares, and the minority of those
%   signs is what is inverted. Comparing each map with the median of the
%   others instead breaks on an even split: with one map inverted out of
%   three, the median of the other two is the mean of one map and its own
%   negative, which is noise, and both ends get flagged.
%
%   Two claims are withheld: with fewer than three recordings there is no
%   majority to be against, and when the leading eigenvalue carries less
%   than half of the total the maps simply do not share a pattern, which is
%   worth knowing but is not the same as one being inverted.
    flipped = {};
    if numel(maps) < 3
        return;
    end
    shared = cellstr(string(maps{1}.channels));
    for i = 2:numel(maps)
        shared = intersect(shared, cellstr(string(maps{i}.channels)), 'stable');
    end
    if numel(shared) < 3
        return;
    end
    M = zeros(numel(shared), numel(maps));
    for i = 1:numel(maps)
        [~, where] = ismember(shared, cellstr(string(maps{i}.channels)));
        M(:, i) = reshape(maps{i}.map(where), [], 1);
    end
    keep = all(isfinite(M), 1);   % a component this recording could not build has a NaN map
    M = M(:, keep);
    names = names(keep);
    if size(M, 2) < 3
        return;
    end
    C = corr(M);
    if any(~isfinite(C(:)))
        return;
    end
    [V, D] = eig(C);
    [values, order] = sort(real(diag(D)), 'descend');
    if values(1) / sum(abs(values)) < 0.5
        return;      % no shared pattern to be inverted relative to
    end
    polarity = sign(real(V(:, order(1))));
    polarity(polarity == 0) = 1;
    minority = polarity == -sign(sum(polarity));
    if sum(polarity) == 0 || ~any(minority)
        return;      % an even split has no majority
    end
    flipped = names(minority);
end

function lines = suppressedConditions(info, binLabels)
%SUPPRESSEDCONDITIONS  Whether a filter's reference covariance is built at
%   the frequency of another condition in the same study.
%
%   The reference covariance is what the filter suppresses, so building it
%   at a frequency another condition was tagged with makes the filter
%   suppress that condition's response on purpose. The authors avoided
%   exactly this, using neither 17 Hz as a neighbour for their 16 Hz filter
%   nor the reverse (Cohen & Gulbinaite, 2017). It costs nothing to check,
%   and a reader comparing those conditions has to know.
    lines = {};
    for k = 1:numel(info)
        c = info(k);
        if isempty(c.neighbourDistance) || isempty(c.neighbourFWHM)
            continue;
        end
        hit = {};
        for b = 1:numel(binLabels)
            if any(strcmpi(c.bins, binLabels{b}))
                continue;                       % a bin it was built from
            end
            fb = TransTools.FrequencyFromLabel(binLabels{b});
            if ~isfinite(fb)
                continue;
            end
            near = min(abs(fb - (c.freq - c.neighbourDistance)), abs(fb - (c.freq + c.neighbourDistance)));
            if near < c.neighbourFWHM / 2
                hit{end + 1} = sprintf('%s (%g Hz)', ReportSections.mdLit(binLabels{b}), fb); %#ok<AGROW>
            end
        end
        if ~isempty(hit)
            lines{end + 1} = sprintf(['%s is built to suppress the frequencies %g Hz either side of ' ...
                '%g Hz, and %s tagged at one of them. The filter therefore suppresses that condition''s ' ...
                'own response by construction, and the two are not to be compared through it; the ' ...
                'authors avoided using one stimulation frequency as the neighbour of another for this ' ...
                'reason. Moving the neighbours, or narrowing them, would separate the two.'], ...
                ReportSections.mdLit(c.label), c.neighbourDistance, c.freq, ...
                [strjoin(hit, ', ') ' ' plural(numel(hit), 'was', 'were')]); %#ok<AGROW>
        end
    end
end

function lines = biasLines(info, EEG)
%BIASLINES  Cohen and Gulbinaite's own caveat about a component's SNR, and
%   whether this report's SNR neighbours sit inside the band the filter
%   suppressed, which is where the bias is largest.
    lines = {['The SNR of a component is partly a biased measure: the filter is built to maximise power ' ...
        'at its own frequency relative to the frequencies beside it, so a value above 1 is expected even ' ...
        'where the flicker was absent (Cohen & Gulbinaite, 2017). The null rows in the table below show ' ...
        'how large that bias is in these recordings, and a component''s SNR in the bins it was built from ' ...
        'is to be read against them rather than against 1.']};
    c = info(1);
    if ~isfield(EEG, 'params') || ~isstruct(EEG.params) || ~isfield(EEG, 'srate') || ~isfield(EEG, 'pnts')
        return;
    end
    n = TransTools.FieldOr(EEG.params, 'snrNeighbours', NaN);
    guard = TransTools.FieldOr(EEG.params, 'snrGuard', NaN);
    if ~isfinite(n) || ~isfinite(guard) || isempty(c.neighbourDistance)
        return;
    end
    df = EEG.srate / EEG.pnts;
    near = (guard + 1) * df;
    far = (guard + n) * df;
    band = c.neighbourDistance + c.neighbourFWHM / 2;   % where the reference filters still have gain
    if far > band
        return;
    end
    lines{end + 1} = sprintf(['Here that bias is at its largest: the SNR was measured against the ' ...
        'frequencies %.2f to %.2f Hz away, which lies inside the band the filter suppressed (its ' ...
        'reference covariance is built %g Hz either side, %g Hz wide). Reading the SNR against ' ...
        'frequencies beyond about %.1f Hz, by raising the Spectral Measure''s neighbour count or its ' ...
        'guard, would measure the component against frequencies it was not built to suppress.'], ...
        near, far, c.neighbourDistance, c.neighbourFWHM, band);
end

function f = componentFreq(entries, label)
%COMPONENTFREQ  The frequency of the component called LABEL.
    f = NaN;
    for i = 1:numel(entries)
        E = entries(i).EEG;
        if isfield(E, 'etc') && isstruct(E.etc) && isfield(E.etc, 'alz') && ...
                isstruct(E.etc.alz) && isfield(E.etc.alz, 'ress') && ~isempty(E.etc.alz.ress)
            hit = find(strcmp({E.etc.alz.ress.label}, label), 1);
            if ~isempty(hit)
                f = E.etc.alz.ress(hit).freq;
                return;
            end
        end
    end
end

function s = namesOf(names)
    names = cellfun(@ReportSections.mdLit, names, 'UniformOutput', false);
    if isscalar(names)
        s = names{1};
    else
        s = [strjoin(names(1:end - 1), ', ') ' and ' names{end}];
    end
end

function v = firstOr(values, default)
    if isempty(values)
        v = default;
    else
        v = values(1);
    end
end

function name = recordingName(entry, i)
%RECORDINGNAME  The subject the report knows ENTRY by, else its position.
    name = '';
    if isfield(entry, 'subject')
        name = strtrim(char(string(entry.subject)));
    end
    if isempty(name)
        name = sprintf('recording %d', i);
    end
end

function [info, EEG] = firstRessEntry(entries)
%FIRSTRESSENTRY  The RESS components of the first entry that has any, and
%   only those a Spectral Measure row reads.
    info = [];
    EEG = [];
    for i = 1:numel(entries)
        E = entries(i).EEG;
        if ~isfield(E, 'etc') || ~isstruct(E.etc) || ~isfield(E.etc, 'alz') || ...
                ~isstruct(E.etc.alz) || ~isfield(E.etc.alz, 'ress') || isempty(E.etc.alz.ress) || ...
                ~isfield(E, 'spectralMeasures') || isempty(E.spectralMeasures) || ~isfield(E, 'bindesc')
            continue;
        end
        read = {};
        for w = 1:numel(E.spectralMeasures)
            read = [read, cellstr(string(E.spectralMeasures{w}.channels))]; %#ok<AGROW>
        end
        candidate = E.etc.alz.ress;
        candidate = candidate(ismember({candidate.label}, read));
        if ~isempty(candidate)
            info = candidate;
            EEG = E;
            return;
        end
    end
end

function role = roleOf(component, binLabel, frameSeconds)
%ROLEOF  What BINLABEL is for COMPONENT: built from, a null, or why not.
    if any(strcmpi(component.bins, binLabel))
        role = 'built from';
        return;
    end
    fb = TransTools.FrequencyFromLabel(binLabel);
    f = component.freq;
    if ~isfinite(fb)
        role = 'not built from; frequency unknown';
        return;
    end
    if abs(fb - f) < 1e-9
        role = 'not built from; same frequency';
        return;
    end
    % Every harmonic of the bin's frequency, not only the fundamental: the
    % RIFT 30 Hz condition's square-wave photodiode has a small 60 Hz
    % component, the brain's second harmonic locks to it, and 255 ms frames
    % then leak that 60 Hz into a 64 Hz readout (0.22 to 0.32 at Oz, 0.02
    % with 1020 ms frames).
    reach = 2 / frameSeconds;
    if ~isfinite(reach)
        reach = 1e-9;   % no frame length known: only an exact harmonic counts
    end
    for k = 1:floor((f + reach) / fb)
        h = k * fb;
        if abs(h - f) < 1e-9
            role = sprintf('not a clean null: %g Hz has a harmonic at %g Hz', fb, f);
            return;
        elseif abs(h - f) < reach
            if k == 1
                role = sprintf('not a clean null: %.0f ms frames cannot separate %g from %g Hz', ...
                    1000 * frameSeconds, fb, f);
            else
                role = sprintf(['not a clean null: %.0f ms frames cannot separate %g Hz from %g Hz, ' ...
                    'a harmonic of %g Hz'], 1000 * frameSeconds, f, h, fb);
            end
            return;
        end
    end
    role = 'null';
end

function T = frameLength(EEG)
%FRAMELENGTH  The coherence frame, in seconds: the frame length for the frame
%   and newcrossf estimators, the whole (trimmed) epoch for a single window.
    T = NaN;
    if ~isfield(EEG, 'params') || ~isstruct(EEG.params) || ~isfield(EEG, 'srate')
        return;
    end
    used = TransTools.FieldOr(EEG.params, 'crossfUsed', struct());
    crossf = TransTools.FieldOr(EEG.params, 'crossf', struct());
    method = char(string(TransTools.FieldOr(EEG.params, 'coherenceMethod', ...
        TransTools.FieldOr(crossf, 'Method', ''))));
    if any(strcmpi(method, {'frames', 'newcrossf'}))
        samples = TransTools.FieldOr(used, 'WinSize', TransTools.FieldOr(crossf, 'WinSize', NaN));
        T = double(samples) / EEG.srate;
    elseif isfield(EEG, 'pnts')
        T = EEG.pnts / EEG.srate;
    end
end

function s = describe(info)
%DESCRIBE  How the components were made, from the first one's settings.
    c = info(1);
    window = 'over the whole epoch';
    if ~isempty(c.window)
        window = sprintf('between %g and %g ms', c.window(1), c.window(2));
    end
    parts = cell(1, numel(info));
    for k = 1:numel(info)
        parts{k} = sprintf('%s at %g Hz from %s', ReportSections.mdLit(info(k).label), info(k).freq, ...
            ReportSections.mdLit(strjoin(info(k).bins, ' and ')));
    end
    s = sprintf(['for each recording, the weighted combination of its %d scalp channels with the most ' ...
        'power at the frequency relative to %g Hz either side (Gaussian filters %g and %g Hz wide), fitted ' ...
        '%s with %g%% shrinkage of the reference covariance: %s.'], numel(c.channels), ...
        c.neighbourDistance, c.peakFWHM, c.neighbourFWHM, window, 100 * c.shrinkage, strjoin(parts, '; '));
end

function v = rVector(values)
    v = ['c(' strjoin(cellfun(@(x) ['"' ReportSections.rLit(x) '"'], cellstr(values), 'UniformOutput', false), ', ') ')'];
end

function s = plural(n, one, many)
    if n == 1
        s = one;
    else
        s = many;
    end
end
