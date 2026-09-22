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
%   See also RESS, TRANSTOOLS.RESSFILTER, REPORTSECTIONS.COHERENCEMETHODTEXT.
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
    lines = { ...
        '## RESS components and their null' ...
        '' ...
        [labels ' ' plural(numel(info), 'is a RESS component', 'are RESS components') ' (Cohen & Gulbinaite, 2017): ' ...
         describe(info) ' The weights are fitted separately for each recording, so the component, not an ' ...
         'electrode, is what is compared across recordings.'] ...
        '' ...
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
        'ress_tab <- dat %>%' ...
        '  filter(measure_type %in% c("coherence", "snr")) %>%' ...
        '  inner_join(ress_roles, by = c("channel" = "component", "bin" = "bin")) %>%' ...
        '  filter(abs(frequency_hz - freq) < 1e-6) %>%' ...
        '  group_by(channel, bin, role, measure_type) %>%' ...
        '  summarise(M = mean(value, na.rm = TRUE), SD = sd(value, na.rm = TRUE),' ...
        '            n = sum(!is.na(value)), .groups = "drop") %>%' ...
        '  pivot_wider(names_from = measure_type, values_from = c(M, SD, n))' ...
        'if (nrow(ress_tab) > 0) {' ...
        '  for (nm in c("M_coherence", "SD_coherence", "M_snr", "SD_snr", "n_coherence")) {' ...
        '    if (!nm %in% names(ress_tab)) ress_tab[[nm]] <- NA_real_' ...
        '  }' ...
        '  shown <- ress_roles %>% select(channel = component, bin, role) %>%' ...
        '    left_join(ress_tab, by = c("channel", "bin", "role")) %>%' ...
        '    transmute(Component = channel, Bin = bin, Role = role, Coherence = M_coherence,' ...
        '              `Coherence SD` = SD_coherence, SNR = M_snr, `SNR SD` = SD_snr, n = n_coherence)' ...
        '  cat(as_raw_html(blank_missing(apa_gt(shown, "Each Component at Its Own Frequency, by Bin"))))' ...
        '  cat("\n*Coherence to the reference and SNR of each component at its own frequency: mean and SD over recordings. A blank row is a bin the Spectral Measure did not read at that frequency.*\n\n")' ...
        '} else {' ...
        '  cat("\n*No Spectral Measure row reads a RESS component at its own frequency, so there is no null to show.*\n\n")' ...
        '}' ...
        '```' ...
        ''};
    text = strjoin(lines, newline);
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
