function plan = RESSPlan(EEG, options)
%RESSPLAN  Check RESS's settings against a dataset and work out what each
%   filter is built from. Shared by RESS and its dialog, so the two cannot
%   accept different things.
%
%   PLAN = TransTools.RESSPlan(EEG, OPTIONS) throws an Alakazam:RESS error
%   that says what to change when OPTIONS cannot be applied to EEG, and
%   otherwise returns
%     .rows      one per component: .label, .freq (Hz), .bins (cellstr: the
%                bins whose trials build it) and .trials (their union, empty
%                when this recording has none of those trials)
%     .channels  logical, the channels combined (TransTools.RESSChannels)
%     .window    logical, the samples the covariances use
%     .filter    the options TransTools.RESSFilter takes
%
%   OPTIONS: .rows (a cell array or struct array of .label, .freq, .bins;
%   bins is a comma-separated list of bin labels, blank for every ordinary
%   bin), .includeMastoids, .timeStart/.timeStop (ms, both blank for the
%   whole epoch), .peakFWHM, .neighbourDistance, .neighbourFWHM (Hz) and
%   .shrinkage (0 to 1).
%
%   See also RESS, RESSDIALOG, TRANSTOOLS.RESSFILTER.
    if ~isfield(EEG, 'DataFormat') || ~strcmpi(EEG.DataFormat, 'EPOCHED')
        fail(['RESS needs single-trial epoched data (DataFormat "EPOCHED"), because the filter ' ...
              'is built from the trials of chosen bins. Would you run DefineBins with an epoch ' ...
              'statement first?']);
    end
    if ~isfield(EEG, 'bindesc') || isempty(EEG.bindesc)
        fail('RESS builds each filter from the trials of named bins, and this dataset has no bins.');
    end
    binLabels = cellstr(string({EEG.bindesc.label}));
    isOrdinary = true(1, numel(EEG.bindesc));
    if isfield(EEG.bindesc, 'combo')
        isOrdinary = cellfun(@isempty, {EEG.bindesc.combo});
    end

    plan.filter = struct( ...
        'PeakFWHM', number(options, 'peakFWHM', 0.5, 'The width at the stimulation frequency'), ...
        'NeighbourDistance', number(options, 'neighbourDistance', 1, 'The distance of the neighbours'), ...
        'NeighbourFWHM', number(options, 'neighbourFWHM', 1, 'The width at the neighbours'), ...
        'Shrinkage', TransTools.FieldOr(options, 'shrinkage', 0.01));
    if ~isnumeric(plan.filter.Shrinkage) || ~isscalar(plan.filter.Shrinkage) || ...
            plan.filter.Shrinkage < 0 || plan.filter.Shrinkage >= 1
        fail('The shrinkage must be at least 0 and below 1; 0.01 shrinks the reference by one per cent.');
    end

    plan.channels = TransTools.RESSChannels(EEG.chanlocs, logical(TransTools.FieldOr(options, 'includeMastoids', false)));
    if nnz(plan.channels) < 2
        fail('A RESS filter combines channels, and fewer than two scalp EEG channels are left to combine.');
    end

    t0 = TransTools.FieldOr(options, 'timeStart', []);
    t1 = TransTools.FieldOr(options, 'timeStop', []);
    if xor(isempty(t0), isempty(t1))
        fail('Give both a window start and a window stop, or leave both blank for the whole epoch.');
    end
    if isempty(t0)
        plan.window = true(1, EEG.pnts);
    else
        if t0 >= t1
            fail('The window start must be before the window stop.');
        end
        plan.window = EEG.times >= t0 & EEG.times <= t1;
        if ~any(plan.window)
            fail('The window from %g to %g ms holds no sample of these epochs (%g to %g ms).', ...
                t0, t1, EEG.times(1), EEG.times(end));
        end
    end

    rows = TransTools.FieldOr(options, 'rows', {});
    if isstruct(rows)
        rows = num2cell(rows);   % a JSON round trip turns the cell array into a struct array
    end
    if isempty(rows)
        fail('RESS needs at least one stimulation frequency.');
    end
    otherLabels = cellstr(string({EEG.chanlocs.labels}));
    if isfield(EEG.chanlocs, 'type')
        otherLabels = otherLabels(~strcmpi({EEG.chanlocs.type}, 'RESS'));
    end
    seen = {};
    nyquist = EEG.srate / 2;
    plan.rows = struct('label', {}, 'freq', {}, 'bins', {}, 'trials', {});
    for k = 1:numel(rows)
        r = rows{k};
        label = strtrim(char(string(TransTools.FieldOr(r, 'label', ''))));
        if isempty(label)
            fail('Row %d has no label; it becomes the name of the component''s channel.', k);
        end
        if any(ismember(label, ' ,{}+'))
            fail(['The label "%s" contains a space, comma, brace or plus sign. It becomes a channel ' ...
                  'name, and Spectral Measure''s channel lists are split on those, so please write it ' ...
                  'without them (for example RESS60Hz).'], label);
        end
        if any(strcmpi(seen, label)) || any(strcmpi(otherLabels, label))
            fail('"%s" is already the name of a channel or of another row; please give it a name of its own.', label);
        end
        seen{end + 1} = label; %#ok<AGROW>
        freq = TransTools.FieldOr(r, 'freq', NaN);
        if ischar(freq) || isstring(freq)
            freq = str2double(freq);
        end
        if ~isnumeric(freq) || ~isscalar(freq) || ~isfinite(freq) || freq <= 0
            fail('Row "%s" needs a stimulation frequency in Hz.', label);
        end
        if freq - plan.filter.NeighbourDistance <= 0 || freq + plan.filter.NeighbourDistance >= nyquist
            fail('For row "%s", %g Hz with neighbours %g Hz either side must lie between 0 and %g Hz.', ...
                label, freq, plan.filter.NeighbourDistance, nyquist);
        end
        bins = TransTools.FieldOr(r, 'bins', '');
        if iscell(bins)
            bins = strjoin(cellstr(string(bins)), ',');
        end
        wanted = strtrim(strsplit(char(string(bins)), ','));
        wanted = wanted(~cellfun(@isempty, wanted));
        if isempty(wanted)
            idx = find(isOrdinary);
        else
            idx = zeros(1, numel(wanted));
            for j = 1:numel(wanted)
                hit = find(strcmpi(binLabels, wanted{j}), 1);
                if isempty(hit)
                    fail('Row "%s" names bin "%s", which this dataset does not have. Its bins are: %s.', ...
                        label, wanted{j}, strjoin(binLabels, ', '));
                end
                if ~isOrdinary(hit)
                    fail(['Row "%s" names "%s", a combination bin, which has no trials of its own to ' ...
                          'build a filter from.'], label, wanted{j});
                end
                idx(j) = hit;
            end
        end
        % Possibly empty, and not an error: one recording of a study may not
        % have a condition another has (in the RIFT study subjects 1 to 3 ran
        % the 30 Hz control, 4 to 10 the peripheral 60 Hz), and Apply to All
        % must not lose the rest of the branch over it. RESS leaves that
        % component's channel empty instead.
        trials = unique([EEG.bindesc(idx).trials]);
        plan.rows(end + 1) = struct('label', label, 'freq', freq, 'bins', {binLabels(idx)}, 'trials', trials);
    end
end

function v = number(options, name, default, what)
    v = TransTools.FieldOr(options, name, default);
    if ~isnumeric(v) || ~isscalar(v) || ~isfinite(v) || v <= 0
        fail('%s must be a positive number of Hz.', what);
    end
end

function fail(varargin)
    throw(MException('Alakazam:RESS', varargin{:}));
end
