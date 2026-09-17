function EEG = alakazamBinsToEventList(EEG)
%ALAKAZAMBINSTOEVENTLIST  Convert Alakazam's own bin tagging (EEG.bindesc /
%   EEG.event(i).bini / EEG.epoch(k).bini -- see DefineBins.m's own header
%   comment) into ERPLAB's native EEG.EVENTLIST, so a dataset exported as
%   .set (onExportSet) is directly usable by ERPLAB's own bin-aware tools
%   (pop_averager and the rest of the EVENTLIST/BINLISTER-based pipeline),
%   not just loadable by them.
%
%   THE SHAPE IS FROM RUNNING REAL ERPLAB, NOT GUESSED: a synthetic
%   continuous recording was put through ERPLAB 13.10's own
%   pop_creabasiceventlist + pop_binlister + pop_epochbin, and the exact
%   resulting field names/values (EVENTLIST.eventinfo/.bdf, and the per-
%   event bepoch/bini/binlabel/codelabel/duration/enable/flag/item fields
%   pop_binlister adds to EEG.event, mirrored onto EEG.epoch(k) with an
%   "event" prefix by pop_epochbin) were read back, not inferred from
%   documentation. Confirmed end to end by running real ERPLAB's own
%   pop_averager on a dataset this function produced (see
%   AlakazamBinsToEventListTest.m).
%
%   ERPLAB REPLACES EEG.event(i).TYPE WITH THE BIN LABEL, e.g. "B1(112)"
%   -- confirmed directly, pop_binlister prints exactly this warning
%   itself ("EEG.EVENTLIST.eventinfo.code will replace your EEG.event.type
%   structure"). The original marker code survives at
%   EVENTLIST.eventinfo(i).code and is not otherwise recoverable from
%   EEG.event once converted -- matched here for authenticity: a real
%   ERPLAB user's own pop_binlister run does exactly this, and ERPLAB's
%   downstream tools expect it.
%
%   A combination/difference bin (DefineBins' own "bin N = bin A - bin B")
%   has no matched events of its own and no ERPLAB equivalent (same
%   reasoning as averagedToErpset's own comment) -- omitted from
%   EVENTLIST.bdf entirely, and never contributes a .bini tag.
%
%   ONE CAVEAT LEFT UNVERIFIED: an event matching MORE than one bin (a
%   real DefineBins case -- see EEG.event(i).bini's own "may be in several
%   bins" convention) was not exercised against real ERPLAB, so the
%   multi-bin .binlabel join text below ("B1(x)/B2(x)") is a reasonable
%   guess, not confirmed byte-for-byte against ERPLAB's own formatting;
%   the numeric .bini vector itself, which is what pop_averager actually
%   groups trials by, is not affected by that uncertainty.
%
%   A no-op (returns EEG unchanged) when there is no EEG.bindesc to
%   convert -- a plain recording with no DefineBins run on it needs
%   nothing done here.
%
%   See also ONEXPORTSET, DEFINEBINS, DEFINEBINSENGINE.EVALUATEBINS,
%   DEFINEBINSENGINE.CUTEPOCHS, AVERAGEDTOERPSET.
    if ~isfield(EEG, 'bindesc') || isempty(EEG.bindesc) ...
            || ~isfield(EEG, 'event') || isempty(EEG.event)
        return;
    end

    srate = TransTools.FieldOr(EEG, 'srate', 1);
    nEv = numel(EEG.event);

    % --- EVENTLIST.eventinfo: one entry per ORIGINAL event, matching
    % ERPLAB's own pop_creabasiceventlist shape exactly (field names,
    % order and the -1/'""' unbinned sentinels). ---
    eventinfo = repmat(struct('item', 0, 'code', 0, 'binlabel', '""', 'codelabel', '""', ...
        'time', 0, 'spoint', 0, 'dura', 0, 'flag', 0, 'enable', 1, 'bini', -1, 'bepoch', 0), 1, nEv);
    for i = 1:nEv
        ev = EEG.event(i);
        bini = TransTools.FieldOr(ev, 'bini', []);
        eventinfo(i).item   = i;
        eventinfo(i).code   = ev.type;
        eventinfo(i).time   = double(ev.latency) / srate;
        eventinfo(i).spoint = round(double(ev.latency));
        eventinfo(i).dura   = TransTools.FieldOr(ev, 'duration', 0);
        eventinfo(i).bepoch = TransTools.FieldOr(ev, 'epoch', 0);
        if ~isempty(bini)
            eventinfo(i).bini     = bini;
            eventinfo(i).binlabel = binLabelText(bini, ev.type);
        end
    end

    % --- EVENTLIST.bdf: one entry per plain (non-combination) bin. ---
    plainBins = find(arrayfun(@(b) isempty(b.combo), EEG.bindesc));
    bdf = repmat(struct('expression', '', 'description', '', 'prehome', [], ...
        'athome', [], 'posthome', [], 'namebin', '', 'rtname', [], 'rtindex', [], 'rt', []), 1, numel(plainBins));
    for k = 1:numel(plainBins)
        b = plainBins(k);
        bdf(k).description = char(string(EEG.bindesc(b).label));
        bdf(k).namebin      = sprintf('BIN %d', b);
        bdf(k).expression   = char(TransTools.FieldOr(EEG.bindesc(b), 'script', ''));
    end

    EEG.EVENTLIST = struct( ...
        'setname', char(string(TransTools.FieldOr(EEG, 'setname', TransTools.FieldOr(EEG, 'id', '')))), ...
        'report', '', ...
        'bdfname', 'Alakazam DefineBins (no external .bdf file)', ...
        'nbin', numel(plainBins), ...
        'version', 'Alakazam', ...
        'account', '', ...
        'username', '', ...
        'trialsperbin', arrayfun(@(b) EEG.bindesc(b).n, plainBins), ...
        'elname', '', ...
        'bdf', bdf, ...
        'eldate', datestr(now), ... %#ok<TNOW1,DATST> -- matches ERPLAB's own eldate format
        'eventinfo', eventinfo);

    % --- EEG.event: the same per-event fields pop_binlister adds, plus
    % its own .type-becomes-binlabel replacement (see this function's own
    % header comment on why). ---
    for i = 1:nEv
        EEG.event(i).item      = eventinfo(i).item;
        EEG.event(i).bepoch    = eventinfo(i).bepoch;
        EEG.event(i).bini      = eventinfo(i).bini;
        EEG.event(i).binlabel  = eventinfo(i).binlabel;
        EEG.event(i).codelabel = eventinfo(i).codelabel;
        EEG.event(i).duration  = eventinfo(i).dura;
        EEG.event(i).enable    = eventinfo(i).enable;
        EEG.event(i).flag      = eventinfo(i).flag;
        EEG.event(i).type      = eventinfo(i).binlabel;
    end

    % --- EEG.epoch (epoched data only): mirror each trial's own anchor
    % event with ERPLAB's "event"-prefixed field names, the same way
    % pop_epochbin does. Alakazam's own cutEpochs already gives .epoch(k)
    % the one-anchor-per-trial shape ERPLAB itself produces (.event is the
    % anchor's absolute index into EEG.event, .eventlatency is always 0)
    % -- only the extra bin-specific fields need adding. ---
    if isfield(EEG, 'epoch') && ~isempty(EEG.epoch) && isfield(EEG.epoch, 'event')
        for k = 1:numel(EEG.epoch)
            ei = EEG.epoch(k).event;
            if isempty(ei) || ~isscalar(ei) || ei < 1 || ei > nEv
                continue;
            end
            e = EEG.event(ei);
            EEG.epoch(k).eventbepoch    = k;
            EEG.epoch(k).eventbini      = e.bini;
            EEG.epoch(k).eventbinlabel  = e.binlabel;
            EEG.epoch(k).eventcodelabel = e.codelabel;
            EEG.epoch(k).eventduration  = e.duration;
            EEG.epoch(k).eventenable    = e.enable;
            EEG.epoch(k).eventflag      = e.flag;
            EEG.epoch(k).eventitem      = e.item;
            EEG.epoch(k).eventtype      = e.type;
        end
    end
end

function txt = binLabelText(bini, code)
%BINLABELTEXT  ERPLAB's own per-event bin-label text, "B<n>(<code>)" --
%   confirmed directly for a single-bin event; joined with '/' for an
%   event in several bins, which was NOT checked against real ERPLAB (see
%   this file's own header comment).
    labs = arrayfun(@(b) sprintf('B%d(%s)', b, char(string(code))), bini, 'UniformOutput', false);
    txt = strjoin(labs, '/');
end
