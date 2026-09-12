function [EEG, options] = ReRef(input, varargin)
%% ReRef  Re-reference the data to the average, or to specific channel(s).
%
%   The app-styled ReRefDialog collects the reference choice (the same one
%   pop_reref offers); the compute delegates to EEGLAB's pop_reref, called
%   programmatically from a plain options struct (no eval of a command string).
%   Reference / exclude channels are stored as labels and resolved to indices
%   against the current dataset, so a stored choice replays on a dataset whose
%   channels differ.
%
%   OPTIONALLY RECONSTRUCTS THE IMPLICIT REFERENCE. Some recordings are made
%   against a reference channel that was never itself saved as a channel (a
%   single active electrode, e.g. Cz or a mastoid, whose own voltage relative
%   to itself is by definition always zero, so nothing was recorded for it).
%   Re-referencing to something else is exactly the computation that recovers
%   it: options.implicitRef, a channel label the analyst names (typed, or
%   picked from the 10-5 template, in ReRefDialog), adds that channel back to
%   the result with its true signal relative to the NEW reference. See
%   addImplicitReferenceChannel below for the maths.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = ReRef(input)        % interactive dialog
%     [EEG, options] = ReRef(input, opts)  % replay a stored options struct
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:ReRef', varargin{:});
if interactive
    elcFile = TransTools.Template1005File('Alakazam:ReRef');
    options = ReRefDialog(input.chanlocs, TransformSettings.get('ReRef'), elcFile);
    if isempty(options)
        EEG = [];   % cancelled -- no node, no compute (see Alakazam.onTransformation)
        return;
    end
    TransformSettings.set('ReRef', options);
else
    options = opts;
end

if strcmpi(options.mode, 'Average')
    refarg = [];
else
    refarg = TransTools.LabelsToIdx(input, options.refChannels);
    if isempty(refarg)
        throw(MException('Alakazam:ReRef', ...
            'ReRef: I''m afraid none of the reference channels are in this dataset.'));
    end
end

extra = {};
if isfield(options, 'exclude')
    exidx = TransTools.LabelsToIdx(input, options.exclude);
    if ~isempty(exidx)
        extra = [extra, {'exclude', exidx}];
    end
end
keepref = isfield(options, 'keepref') && logical(options.keepref);
if keepref
    extra = [extra, {'keepref', 'on'}];
else
    extra = [extra, {'keepref', 'off'}];
end

EEG = pop_reref(input, refarg, extra{:});

implicitRef = strtrim(char(string(TransTools.FieldOr(options, 'implicitRef', ''))));
if ~isempty(implicitRef)
    EEG = addImplicitReferenceChannel(EEG, input, implicitRef, options);
end
end

% ======================================================================= %
function EEG = addImplicitReferenceChannel(EEG, input, label, options)
%ADDIMPLICITREFERENCECHANNEL  Reconstruct a reference channel that was never
%   recorded (the data arrived already referenced to it) and add it to EEG.
%
%   THE MATHS. Re-referencing subtracts one waveform -- the OLD reference's
%   own signal relative to the NEW reference -- from every channel it
%   touches:
%       new(X) = old(X) - waveform
%   The channel this reconstructs, R, was BY DEFINITION the old reference:
%   old(R) is identically zero, because a channel referenced to itself
%   always reads zero. So:
%       new(R) = 0 - waveform = -waveform
%
%   WAVEFORM IS NEVER COMPUTED DIRECTLY. Doing that would mean re-deriving
%   whatever pop_reref's own averaging and exclusion rules decided --
%   getting that wrong would silently produce a plausible-looking but
%   incorrect channel. Instead it is read back out of any one channel
%   pop_reref actually touched:
%       waveform = old(X) - new(X)   =>   -waveform = new(X) - old(X)
%   which is exactly right regardless of whether the reference was the
%   average, one channel or several, with or without exclusions, because
%   the SAME waveform was subtracted from every surviving channel alike.
%
%   THE PROBE CHANNEL, the X above, is the first one (by label) that exists
%   in both INPUT and EEG and was not excluded from re-referencing --
%   excluded channels are left untouched by pop_reref (old(X) == new(X) for
%   those), which would read back a flat zero instead of the real waveform.
    exclude = lower(string(TransTools.FieldOr(options, 'exclude', {})));
    oldLabels = lower(string({input.chanlocs.labels}));
    newLabels = lower(string({EEG.chanlocs.labels}));

    if any(newLabels == lower(string(label)))
        throw(MException('Alakazam:ReRef', ...
            'ReRef: I''m afraid "%s" is already a channel in this dataset.', label));
    end

    probe = [];
    for i = 1:numel(oldLabels)
        if any(oldLabels(i) == exclude)
            continue;
        end
        j = find(newLabels == oldLabels(i), 1);
        if ~isempty(j)
            probe = struct('old', i, 'new', j);
            break;
        end
    end
    if isempty(probe)
        throw(MException('Alakazam:ReRef', ...
            ['ReRef: I''m afraid I couldn''t reconstruct "%s" -- every channel that survived ' ...
             're-referencing was excluded from it, so there is nothing to read the reference ' ...
             'waveform back out of.'], label));
    end

    reconstructed = reshape(EEG.data(probe.new, :, :) - input.data(probe.old, :, :), ...
        [1, size(EEG.data, 2), size(EEG.data, 3)]);

    % Cloned from an existing entry and blanked, rather than hand-built,
    % so its field set matches exactly -- chanlocs can carry extra fields
    % (ref, urchan, sph_theta_besa, ...) depending on how it was loaded,
    % and a struct array concatenation fails the moment two elements
    % disagree on which fields they have.
    newChan = EEG.chanlocs(1);
    for f = fieldnames(newChan)'
        newChan.(f{1}) = [];
    end
    newChan.labels = label;

    % WHERE IT GOES. Tacking it onto the very end put a scalp channel after
    % every peripheral one (EOG, ECG, ... conventionally last) and told an
    % analyst nothing about where on the head it actually sits. Instead it
    % is inserted right after whichever surviving channel sits closest to it
    % on the standard 10-5 template -- Cz lands next to C3 or C4, whichever
    % is nearer, not after the diode. Only the TEMPLATE'S positions are
    % compared for this (not EEG.chanlocs' own X/Y/Z, which may be absent,
    % digitised, or otherwise not in the template's coordinate frame), so
    % the comparison is apples to apples regardless of how this dataset was
    % positioned. Falls back to the end when the label is not on the
    % template, or nothing else in the dataset resolves to a template
    % position either -- ordering is a nicety, and this never blocks adding
    % the channel itself.
    elcFile = TransTools.Template1005File('Alakazam:ReRef');
    insertAfter = nearestTemplateNeighbour(EEG.chanlocs, label, elcFile);
    if isempty(insertAfter)
        insertAfter = numel(EEG.chanlocs);
    end

    EEG.data = cat(1, EEG.data(1:insertAfter, :, :), reconstructed, EEG.data(insertAfter + 1:end, :, :));
    EEG.chanlocs = [EEG.chanlocs(1:insertAfter), newChan, EEG.chanlocs(insertAfter + 1:end)];
    EEG.nbchan = numel(EEG.chanlocs);

    % A nicety, not a requirement: positioning the reconstructed channel
    % (for scalp maps, interpolation, ...) if its label matches the
    % standard template. The data above is correct with or without this.
    try
        EEG = TransTools.FillChanlocs(EEG, 'Alakazam:ReRef', elcFile);
    catch
    end
end

% ======================================================================= %
function idx = nearestTemplateNeighbour(chanlocs, label, elcFile)
%NEARESTTEMPLATENEIGHBOUR  Index into CHANLOCS of the channel whose 10-5
%   template position is closest to LABEL's own, or [] when that cannot be
%   determined -- LABEL is not on the template, the template cannot be
%   read, or none of CHANLOCS resolve to a template position either.
    idx = [];
    try
        template = readlocs(elcFile);
    catch
        return;
    end
    templateLabels = lower(string({template.labels}));

    hit = find(templateLabels == lower(string(label)), 1);
    if isempty(hit)
        return;
    end
    target = [template(hit).X, template(hit).Y, template(hit).Z];

    bestDist = Inf;
    for i = 1:numel(chanlocs)
        m = find(templateLabels == lower(string(chanlocs(i).labels)), 1);
        if isempty(m)
            continue;
        end
        here = [template(m).X, template(m).Y, template(m).Z];
        d = norm(here - target);
        if d < bestDist
            bestDist = d;
            idx = i;
        end
    end
end
