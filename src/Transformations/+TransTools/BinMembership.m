classdef BinMembership
%BINMEMBERSHIP  Which trials, or events, are in which bin: read from the one
%   place Alakazam keeps it.
%
%   THE STORE. Membership lives on the units it describes, as ERPLAB keeps
%   it:
%
%     EEG.epoch(t).bini    the bins trial t is in (their bindesc .index
%     EEG.epoch(t).binrt   values, in the order they matched), and the
%                          reaction time each bin captured, in ms (NaN where
%                          it captured none); one per bin, so a trial in two
%                          bins can have two
%
%   on epoched data, and the same pair on EEG.event(i) on continuous data.
%   EEGLAB carries the epoch pair along by itself: pop_select keeps the
%   EEG.epoch entries of the trials it keeps, and eeg_checkset keeps every
%   epoch field whose name does not start with "event". EEG.bindesc describes
%   the bins (index, label, script, plan, combo, n, rtTrim, filters) and
%   holds no membership.
%
%   WHY ONE STORE. Until 2026-10-24 each bin also listed its events, trials
%   and reaction times in EEG.bindesc (.events, .trials, .rt), beside .bini.
%   Every step that changed the trials had to keep the two in step
%   (SelectData renumbered .trials by hand), and readers differed in which
%   one they believed.
%
%   OLD DATASETS still carry those lists. Every method here converts such a
%   dataset first (migrate), in memory, so an old workspace reads as it
%   did, with the lists believed over .bini as they always were; and
%   TransTools.invoke converts each step's input, so what a step saves is in
%   the new form.
%
%   METHODS (B is a position in EEG.bindesc, T a trial or event)
%     [members, rts] = of(EEG, b)    trials of bin B (events, on continuous
%                                    data), with each one's reaction time
%     bins = ofTrial(EEG, t)         the bins trial T is in, in bindesc order
%     [bini, binrt] = perUnit(EEG)   one cell per trial (event): bins, times
%     EEG = migrate(EEG)             an old dataset in the new form
%     EEG = recount(EEG)             each bin's .n counted from the store
%     EEG = fromEvents(EEG)          epoch pair rebuilt from each trial's
%                                    events, after DefineBins re-tags them
%
%   Averaged data has no trials, and every bin's members are empty.
%
%   See also TRANSTOOLS.BINTRIALS, DEFINEBINS, SELECTDATA.

    methods (Static)
        function [members, rts] = of(EEG, b)
        %OF  The trials of bin B (the events, on continuous data), as a row,
        %   and the reaction time the bin captured for each.
            members = zeros(1, 0);
            rts = zeros(1, 0);
            if ~hasBins(EEG) || b < 1 || b > numel(EEG.bindesc)
                return;
            end
            EEG = TransTools.BinMembership.migrate(EEG);
            [bini, binrt] = TransTools.BinMembership.perUnit(EEG);
            index = indices(EEG.bindesc);
            index = index(b);
            for u = 1:numel(bini)
                at = find(bini{u} == index, 1);
                if ~isempty(at)
                    members(end + 1) = u; %#ok<AGROW>
                    rts(end + 1) = binrt{u}(at); %#ok<AGROW>
                end
            end
        end

        function bins = ofTrial(EEG, t)
        %OFTRIAL  The positions in EEG.bindesc of every bin trial T (event T,
        %   on continuous data) is in, in bindesc order. All of them: a
        %   trial can be in more than one bin.
            bins = zeros(1, 0);
            if ~hasBins(EEG)
                return;
            end
            EEG = TransTools.BinMembership.migrate(EEG);
            bini = TransTools.BinMembership.perUnit(EEG);
            if t < 1 || t > numel(bini)
                return;
            end
            bins = find(ismember(indices(EEG.bindesc), bini{t}));
        end

        function [bini, binrt] = perUnit(EEG)
        %PERUNIT  One cell per trial (per event, on continuous data): the
        %   bin indices it is in, as a row, and their reaction times, a row
        %   of the same length.
            bini = {};
            binrt = {};
            switch unitOf(EEG)
                case 'trials'
                    n = nTrials(EEG);
                    if isfield(EEG, 'epoch') && isstruct(EEG.epoch) && numel(EEG.epoch) == n ...
                            && isfield(EEG.epoch, 'bini')
                        [bini, binrt] = pairs(EEG.epoch);
                    else
                        % Re-tagged events not yet copied to the epochs, or a
                        % single trial, whose EEG.epoch EEGLAB clears.
                        epoched = TransTools.BinMembership.fromEvents(EEG);
                        if isfield(epoched, 'epoch') && numel(epoched.epoch) == n
                            [bini, binrt] = pairs(epoched.epoch);
                        else
                            bini = repmat({zeros(1, 0)}, 1, n);
                            binrt = bini;
                        end
                    end
                case 'events'
                    if isfield(EEG, 'event') && isstruct(EEG.event) && isfield(EEG.event, 'bini')
                        [bini, binrt] = pairs(EEG.event);
                    end
            end
        end

        function EEG = migrate(EEG)
        %MIGRATE  A dataset saved before 2026-10-24 in the new form: the
        %   .trials, .events and .rt of each bin moved onto its trials (or
        %   events) as .bini and .binrt, and removed from EEG.bindesc. A bin
        %   with no list of its own keeps what its trials' .bini said, as the
        %   old readers fell back to. A dataset in the new form is returned
        %   as it is.
            if ~hasBins(EEG) || ~any(isfield(EEG.bindesc, {'events', 'rt', 'trials'}))
                return;
            end
            old = EEG.bindesc;
            index = indices(old);
            ordinary = find(~TransTools.IsComboBin(old));
            switch unitOf(EEG)
                case 'trials'
                    n = nTrials(EEG);
                    tagged = {};
                    if isfield(EEG, 'epoch') && isstruct(EEG.epoch) && numel(EEG.epoch) == n ...
                            && isfield(EEG.epoch, 'bini')
                        tagged = pairs(EEG.epoch);
                    end
                    bini = repmat({zeros(1, 0)}, 1, n);
                    binrt = bini;
                    for b = ordinary
                        [members, rts] = listed(old(b), 'trials');
                        if isempty(members) && ~isempty(tagged)
                            members = find(cellfun(@(x) any(x == index(b)), tagged));
                            rts = nan(size(members));
                        end
                        for k = find(members >= 1 & members <= n & members == round(members))
                            t = members(k);
                            bini{t}(end + 1) = index(b);
                            binrt{t}(end + 1) = rts(k);
                        end
                    end
                    if n > 0
                        if ~isfield(EEG, 'epoch') || ~isstruct(EEG.epoch) || numel(EEG.epoch) ~= n
                            EEG.epoch = struct('bini', bini, 'binrt', binrt);
                        else
                            [EEG.epoch.bini] = bini{:};
                            [EEG.epoch.binrt] = binrt{:};
                        end
                    end
                case 'events'
                    if isfield(EEG, 'event') && isstruct(EEG.event) && ~isempty(EEG.event)
                        if ~isfield(EEG.event, 'bini')
                            [EEG.event.bini] = deal(zeros(1, 0));
                        end
                        [bini, binrt] = pairs(EEG.event);
                        for b = ordinary
                            [members, rts] = listed(old(b), 'events');
                            for k = find(members >= 1 & members <= numel(bini) & members == round(members))
                                e = members(k);
                                at = find(bini{e} == index(b), 1);
                                if isempty(at)
                                    bini{e}(end + 1) = index(b);
                                    binrt{e}(end + 1) = rts(k);
                                else
                                    binrt{e}(at) = rts(k);
                                end
                            end
                        end
                        [EEG.event.bini] = bini{:};
                        [EEG.event.binrt] = binrt{:};
                    end
            end
            EEG.bindesc = rmfield(old, intersect(fieldnames(old), {'events', 'rt', 'trials'}));
        end

        function EEG = recount(EEG)
        %RECOUNT  Each ordinary bin's .n, where it is a count, set to the
        %   number of its trials (events), as after a selection of trials.
        %   A combination bin, and an .n that is text ("12 subjects"), are
        %   left alone.
            if ~hasBins(EEG) || ~isfield(EEG.bindesc, 'n')
                return;
            end
            EEG = TransTools.BinMembership.migrate(EEG);
            for b = find(~TransTools.IsComboBin(EEG.bindesc))
                if isnumeric(EEG.bindesc(b).n)
                    EEG.bindesc(b).n = numel(TransTools.BinMembership.of(EEG, b));
                end
            end
        end

        function EEG = fromEvents(EEG)
        %FROMEVENTS  Each trial's .bini and .binrt gathered from its own
        %   events (those whose .epoch is that trial), for epoched data
        %   whose events were tagged after the trials were cut (DefineBins
        %   on epoched data, without an epoch window).
            n = nTrials(EEG);
            if n < 1 || ~isfield(EEG, 'event') || ~isstruct(EEG.event) || ~isfield(EEG.event, 'bini')
                return;
            end
            bini = repmat({zeros(1, 0)}, 1, n);
            binrt = bini;
            [eventBini, eventRt] = pairs(EEG.event);
            if isfield(EEG.event, 'epoch')
                owner = arrayfun(@(e) firstNumber(e.epoch), EEG.event);
            elseif n == 1
                owner = ones(1, numel(EEG.event));   % EEGLAB drops .epoch for one trial
            else
                return;
            end
            for i = find(owner >= 1 & owner <= n)
                bini{owner(i)} = [bini{owner(i)}, eventBini{i}];
                binrt{owner(i)} = [binrt{owner(i)}, eventRt{i}];
            end
            if ~isfield(EEG, 'epoch') || ~isstruct(EEG.epoch) || numel(EEG.epoch) ~= n
                EEG.epoch = struct('bini', bini, 'binrt', binrt);
            else
                [EEG.epoch.bini] = bini{:};
                [EEG.epoch.binrt] = binrt{:};
            end
        end
    end
end

% ======================================================================= %
function tf = hasBins(EEG)
    tf = isstruct(EEG) && isfield(EEG, 'bindesc') && isstruct(EEG.bindesc) && ~isempty(EEG.bindesc);
end

function index = indices(bindesc)
%INDICES  Each bin's .index, the number its trials are tagged with; a bin
%   without one (a dataset made by hand) is numbered by its position.
    index = 1:numel(bindesc);
    if isfield(bindesc, 'index')
        for b = 1:numel(bindesc)
            if isnumeric(bindesc(b).index) && isscalar(bindesc(b).index)
                index(b) = double(bindesc(b).index);
            end
        end
    end
end

function unit = unitOf(EEG)
%UNITOF  'trials' for epoched data, 'events' for continuous data, 'none' for
%   an average, whose third dimension is its bins. An old dataset whose bins
%   list trials is epoched, whatever else it lacks.
    format = upper(char(string(TransTools.FieldOr(EEG, 'DataFormat', ''))));
    if strcmp(format, 'AVERAGED')
        unit = 'none';
    elseif strcmp(format, 'EPOCHED') || nTrials(EEG) > 1 || ~isempty(oldTrialLists(EEG))
        unit = 'trials';
    else
        unit = 'events';
    end
end

function n = nTrials(EEG)
%NTRIALS  The trials of epoched data: its third dimension, else its epoch
%   entries, else the highest trial an old dataset's bins list.
    if isfield(EEG, 'data') && ~isempty(EEG.data)
        n = size(EEG.data, 3);
    elseif isfield(EEG, 'epoch') && isstruct(EEG.epoch) && ~isempty(EEG.epoch)
        n = numel(EEG.epoch);
    else
        n = max([0, oldTrialLists(EEG)]);
    end
end

function listed = oldTrialLists(EEG)
%OLDTRIALLISTS  Every trial an old dataset's bins list (bindesc .trials),
%   as one row; empty for a dataset in the new form.
    listed = zeros(1, 0);
    if isstruct(EEG) && isfield(EEG, 'bindesc') && isstruct(EEG.bindesc) ...
            && isfield(EEG.bindesc, 'trials')
        for b = 1:numel(EEG.bindesc)
            t = EEG.bindesc(b).trials;
            if isnumeric(t) && ~isempty(t)
                listed = [listed, reshape(double(t), 1, [])]; %#ok<AGROW>
            end
        end
    end
end

function [bini, binrt] = pairs(units)
%PAIRS  The .bini of each unit (an epoch or an event) as a double row, and
%   its .binrt as a row of the same length, NaN where it has none.
    bini = cell(1, numel(units));
    binrt = cell(1, numel(units));
    hasRt = isfield(units, 'binrt');
    for u = 1:numel(units)
        b = units(u).bini;
        if iscell(b)
            b = [b{:}];   % eeg_checkset's form of a value, should one arrive here
        end
        b = reshape(double(b), 1, []);
        r = nan(1, numel(b));
        if hasRt
            given = reshape(double(units(u).binrt), 1, []);
            if numel(given) == numel(b)
                r = given;
            end
        end
        bini{u} = b;
        binrt{u} = r;
    end
end

function [members, rts] = listed(bin, field)
%LISTED  An old bindesc entry's own list (.trials or .events) as a row, and
%   its reaction times when they run parallel to it, NaN otherwise.
    members = zeros(1, 0);
    if isfield(bin, field) && ~isempty(bin.(field))
        members = reshape(double(bin.(field)), 1, []);
    end
    rts = nan(size(members));
    if isfield(bin, 'rt') && numel(bin.rt) == numel(members)
        rts = reshape(double(bin.rt), 1, []);
    end
end

function v = firstNumber(x)
    if isnumeric(x) && ~isempty(x)
        v = double(x(1));
    else
        v = 0;
    end
end
