function [EEG, options] = Photodiode(input, varargin)
%% Photodiode  Measure display delay from a photodiode channel, or import its onsets as events.
%
%   A photodiode watching a white patch at the edge of the screen records
%   when the display ACTUALLY changed. This reads that channel and does one
%   of two things with it:
%
%     'measure'  compare each diode onset with the trigger that caused it,
%                and report how late the screen was. Nothing is changed.
%     'events'   add the diode onsets to the event table as events of their
%                own, the way EEGLAB's pop_chanevent does.
%
%   MEASURE IS THE DEFAULT, because it is the useful one. A lab that already
%   records 600 clean triggers does not need 600 more; what it does not have
%   is the monitor's lag, and that is the number a photodiode exists to
%   provide. The correction that follows is EventEditor's millisecond
%   latency shift: measure here, correct there.
%
%   WHAT MAKES THE DETECTION NON-TRIVIAL is not finding a step but declining
%   to find one that is not there. A diode channel with no patch presented
%   still swings thousands of units at mains frequency, continuously, and a
%   plain threshold turns that into fifty events a second while looking
%   entirely healthy. detectDiodeOnsets smooths away the flicker and then
%   tests whether two states genuinely exist before reporting anything; it
%   was checked against real recordings from this lab that contain no
%   patches, where the right answer is nothing and that is what it gives.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = Photodiode(input)        % interactive dialog
%     [EEG, options] = Photodiode(input, opts)  % replay stored settings
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:Photodiode', varargin{:});

if ~isfield(input, 'data') || isempty(input.data)
    throw(MException('Alakazam:Photodiode', ...
        'Problem in Photodiode: I''m afraid this dataset has no data to read a diode from.'));
end
if ~isfield(input, 'srate') || isempty(input.srate) || input.srate <= 0
    throw(MException('Alakazam:Photodiode', ...
        'Problem in Photodiode: this dataset has no usable sampling rate.'));
end

if interactive
    options = PhotodiodeDialog(input);
    if isempty(options)
        EEG = [];            % cancelled -- no node, no compute
        options = [];
        return;
    end
    TransformSettings.set('Photodiode', options);
else
    options = opts;
end

if ~isstruct(options) || ~isfield(options, 'Channel')
    EEG = input;             % nothing recorded
    return;
end

chan = resolveChannel(input, options.Channel);
signal = double(input.data(chan, :));

[onsets, info] = detectDiodeOnsets(signal, input.srate, options);

EEG = input;
EEG.DiodeOnsets = onsets;
EEG.DiodeInfo = info;

mode = 'measure';
if isfield(options, 'Mode') && ~isempty(options.Mode)
    mode = options.Mode;
end

switch lower(mode)
    case 'events'
        EEG.event = appendOnsets(input.event, onsets, options);
        EEG.DiodeReport = struct([]);
    otherwise
        EEG.DiodeReport = diodeTriggerDelay(onsets, TransTools.FieldOr(input, 'event', []), input.srate, options);
        % Said out loud rather than left in a field: the measurement IS the
        % result of this step, and a node whose whole output is a number
        % nobody sees has not really produced anything.
        if ~isempty(EEG.DiodeReport) && ~isempty(EEG.DiodeReport.summary)
            warning('Alakazam:Photodiode:delay', '%s', EEG.DiodeReport.summary);
        end
end

if isempty(onsets) && ~isempty(info.reason)
    warning('Alakazam:Photodiode:noOnsets', '%s', info.reason);
end
end

% ======================================================================= %
function chan = resolveChannel(EEG, wanted)
%RESOLVECHANNEL  The diode channel, BY LABEL where possible.
%   Replay onto another subject is why. An index is only stable while every
%   recording has the same montage, and the diode is conventionally last,
%   which is exactly the position that moves when a channel is dropped. A
%   label survives that; the index is the fallback for an unlabelled rig.
    labels = {};
    if isfield(EEG, 'chanlocs') && ~isempty(EEG.chanlocs)
        labels = {EEG.chanlocs.labels};
    end

    if ischar(wanted) || isstring(wanted)
        name = char(string(wanted));
        hit = find(strcmpi(labels, name), 1);
        if isempty(hit)
            throw(MException('Alakazam:Photodiode', ...
                ['Problem in Photodiode: this dataset has no channel called "%s". ' ...
                 'The recorded setting names the diode channel by label so it survives ' ...
                 'replay onto other recordings; if this one calls it something else, ' ...
                 'run the dialog again on it.'], name));
        end
        chan = hit;
        return;
    end

    chan = round(double(wanted));
    if chan < 1 || chan > size(EEG.data, 1)
        throw(MException('Alakazam:Photodiode', ...
            ['Problem in Photodiode: channel %d was recorded as the diode, but this ' ...
             'dataset has %d channels.'], chan, size(EEG.data, 1)));
    end
end


function events = appendOnsets(events, onsets, options)
%APPENDONSETS  Add the diode onsets to the event table, then re-sort it:
%   EEGLAB assumes EEG.event is ordered by latency, and inserting at the end
%   would break that for everything downstream.
    label = 'diode';
    if isfield(options, 'EventType') && ~isempty(options.EventType)
        label = char(string(options.EventType));
    end
    if isempty(onsets)
        return;
    end

    added = struct('type', label, 'latency', num2cell(double(onsets)));
    if isempty(events)
        events = added;
    else
        % Only the fields the existing table already has, so the struct
        % array stays homogeneous; anything else it carries is left empty.
        template = events(1);
        for f = fieldnames(template)'
            if ~isfield(added, f{1})
                [added.(f{1})] = deal([]);
            end
        end
        for f = fieldnames(added)'
            if ~isfield(events, f{1})
                [events.(f{1})] = deal([]);
            end
        end
        events = [events, orderfields(added, events)];
    end

    [~, order] = sort([events.latency]);
    events = events(order);
end
