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
%   options.implicitRef, a channel label the user names (typed, or picked
%   from the 10-5 template, in ReRefDialog), adds that channel back as a flat
%   zero BEFORE re-referencing, which is what EEGLAB advises (and what
%   pop_reref's own 'refloc' option does). Re-referencing then gives it its
%   true signal relative to the new reference, and an Average reference is
%   taken over every site, the original reference included, so the channels
%   sum to zero. See addImplicitReferenceChannel below for the maths.
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

% The implicit reference goes in first, so every index below (reference
% channels, exclusions) is resolved against the dataset pop_reref really sees.
implicitRef = strtrim(char(string(TransTools.FieldOr(options, 'implicitRef', ''))));
if ~isempty(implicitRef)
    input = addImplicitReferenceChannel(input, implicitRef);
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

% A nicety, not a requirement: positioning the reconstructed channel (for
% scalp maps, interpolation, ...) if its label matches the standard
% template. The data are correct with or without this.
if ~isempty(implicitRef)
    try
        EEG = TransTools.FillChanlocs(EEG, 'Alakazam:ReRef', ...
            TransTools.Template1005File('Alakazam:ReRef'));
    catch
    end
end
end

% ======================================================================= %
function EEG = addImplicitReferenceChannel(EEG, label)
%ADDIMPLICITREFERENCECHANNEL  Add the reference channel the data were
%   recorded against, which was never saved, to EEG as a flat zero.
%
%   THE MATHS. The channel this adds, R, was the recording's reference, and a
%   channel referenced to itself reads zero at every sample, so zero IS its
%   recorded signal. Re-referencing subtracts one waveform w from every
%   channel it touches, R included:
%       new(X) = old(X) - w        new(R) = 0 - w = -w
%   With specific reference channels, w is their mean, so R reads minus that
%   mean. With an Average reference, w is the mean over every site that is
%   not excluded, and R is one of those sites: with N recorded channels in
%   the average,
%       w = sum(old) / (N + 1)
%   so the re-referenced channels, R included, sum to zero, which is what an
%   average reference means. Adding R only AFTER averaging (Alakazam's
%   earlier approach) left it out of its own average, and every channel off
%   by sum(old) / (N(N + 1)). EEGLAB's re-referencing tutorial gives the
%   same advice: add the reference back as zeros before taking the average.
%
%   WHERE IT GOES. Tacking it onto the very end put a scalp channel after
%   every peripheral one (EOG, ECG, ... conventionally last) and told a user
%   nothing about where on the head it sits. Instead it is inserted right
%   after whichever channel sits closest to it on the standard 10-5 template:
%   Cz lands next to C3 or C4, whichever is nearer, not after the diode. Only
%   the TEMPLATE'S positions are compared (not EEG.chanlocs' own X/Y/Z, which
%   may be absent, digitised, or in another coordinate frame), so the
%   comparison is apples to apples however this dataset was positioned. It
%   falls back to the end when the label is not on the template, or nothing
%   else in the dataset resolves to a template position either: ordering is
%   a nicety, and never blocks adding the channel.
    labels = lower(string({EEG.chanlocs.labels}));
    if any(labels == lower(string(label)))
        throw(MException('Alakazam:ReRef', ...
            'ReRef: I''m afraid "%s" is already a channel in this dataset.', label));
    end

    % Cloned from an existing entry and blanked, rather than hand-built, so
    % its field set matches exactly: chanlocs can carry extra fields (ref,
    % urchan, sph_theta_besa, ...) depending on how it was loaded, and a
    % struct array concatenation fails the moment two elements disagree on
    % which fields they have.
    newChan = EEG.chanlocs(1);
    for f = fieldnames(newChan)'
        newChan.(f{1}) = [];
    end
    newChan.labels = label;

    at = nearestTemplateNeighbour(EEG.chanlocs, label, ...
        TransTools.Template1005File('Alakazam:ReRef'));
    if isempty(at)
        at = numel(EEG.chanlocs);
    end

    flat = zeros(1, size(EEG.data, 2), size(EEG.data, 3), 'like', EEG.data);
    EEG.data = cat(1, EEG.data(1:at, :, :), flat, EEG.data(at + 1:end, :, :));
    EEG.chanlocs = [EEG.chanlocs(1:at), newChan, EEG.chanlocs(at + 1:end)];
    EEG.nbchan = numel(EEG.chanlocs);

    % An ICA decomposition keeps naming the same channels: the ones after the
    % insertion point have moved down by one.
    if isfield(EEG, 'icachansind') && ~isempty(EEG.icachansind)
        moved = EEG.icachansind > at;
        EEG.icachansind(moved) = EEG.icachansind(moved) + 1;
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
