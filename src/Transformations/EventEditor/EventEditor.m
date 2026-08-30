function [EEG, options] = EventEditor(input, varargin)
%% EventEditor  Correct the event table, replayably.
%
%   An Alakazam-styled event editor: rename trigger codes, drop the ones that
%   are not stimuli, shift latencies to correct a known trigger delay, and
%   fix individual events by hand. It replaces the round trip through
%   EEGLAB's pop_editeventvals and friends, and does the one thing that round
%   trip cannot.
%
%   WHY THIS EXISTS AT ALL. Until it did, Alakazam could READ events richly
%   (DefineBins has a whole language for selecting them) but could not change
%   one. A mislabelled trigger, an off-by-one code, a photodiode-measured
%   delay: every one of them meant leaving the application, fixing it
%   elsewhere, and re-importing. That works, and it costs the provenance
%   record: the fix is not in the tree, so it is not in the exported analysis
%   script either, and the reproducible pipeline quietly stops describing
%   what was actually done. For a tool whose case rests on reproducibility,
%   that was the gap worth closing.
%
%   IT STORES OPERATIONS, NOT A TABLE. options.ops is the ordered list of
%   edits, so replaying onto another subject applies the same CORRECTION to
%   that subject's own events rather than overwriting them with this
%   subject's table. Trigger faults are properties of a recording setup and
%   are usually wrong the same way in every file, which is exactly what makes
%   "Apply to All Raw Files" worth having here. See applyEventOps, which is
%   where that reasoning is spelled out, and which does the work.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = EventEditor(input)        % interactive dialog
%     [EEG, options] = EventEditor(input, opts)  % replay the stored ops
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:EventEditor', varargin{:});

if ~isfield(input, 'event')
    throw(MException('Alakazam:EventEditor', ...
        ['Problem in EventEditor: I''m afraid this dataset has no event structure ' ...
         'at all, so there is nothing to edit.']));
end

if interactive
    if isempty(input.event)
        throw(MException('Alakazam:EventEditor', ...
            ['Problem in EventEditor: this dataset''s event table is empty. If the ' ...
             'triggers should be there, the import is the place to look; if they are ' ...
             'recorded on a data channel, they need extracting before they can be ' ...
             'edited here.']));
    end
    ops = EventEditorDialog(input);
    if isempty(ops)
        EEG = [];        % cancelled -- no node, no compute
        options = [];
        return;
    end
    options = struct('ops', ops);
    TransformSettings.set('EventEditor', options);
else
    options = opts;
end

if ~isstruct(options) || ~isfield(options, 'ops') || isempty(options.ops)
    EEG = input;         % nothing recorded; leave the dataset alone
    return;
end

srate = fieldOrDefault(input, 'srate', NaN);
pnts  = fieldOrDefault(input, 'pnts', NaN);

[events, notes] = applyEventOps(input.event, options.ops, srate, pnts);

EEG = input;
EEG.event = events;
EEG.EventEditNotes = notes;   % what did not apply cleanly, kept with the result

% Anything skipped or dropped is worth saying out loud rather than leaving in
% a field somebody has to know to look at. A warning rather than an error:
% the edits that DID apply are still wanted, and a replay across twenty
% subjects should not stop at the first one whose events differ.
for k = 1:numel(notes)
    warning('Alakazam:EventEditor:note', '%s', notes{k});
end
end

% ======================================================================= %
function value = fieldOrDefault(s, name, default)
    if isfield(s, name) && ~isempty(s.(name))
        value = double(s.(name));
    else
        value = default;
    end
end
