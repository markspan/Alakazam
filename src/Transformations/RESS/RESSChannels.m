function mask = RESSChannels(chanlocs, includeMastoids)
%RESSCHANNELS  Which channels a RESS filter combines: scalp EEG, and the
%   mastoids only when asked.
%
%   MASK = RESSChannels(CHANLOCS, INCLUDEMASTOIDS) is a logical row, one value
%   per channel. It starts from eegChannelMask (which leaves out eye, heart,
%   muscle, trigger and photodiode channels, and earlier RESS components) and
%   then also leaves out:
%
%     eye electrodes named by position rather than by type: IO1/IO2
%     (infra-orbital), LO1/LO2 (lateral orbital), SO1/SO2 (supra-orbital),
%     LOC/ROC (outer canthi). The RIFT recordings carry IO1, IO2, LO1 and
%     LO2. A spatial filter built to find a visual response must not be
%     handed the eyes. eegChannelMask now also counts these as EOG when a
%     channel has no recorded type (channelTypeFromLabel); the rule is kept
%     here as well because this one applies whatever type a channel was
%     given, and a cap that labels its orbital electrodes EEG is still
%     handing the filter the eyes.
%
%     mastoid and earlobe electrodes (M1, M2, A1, A2, LM, RM, or a label
%     containing MAST), unless INCLUDEMASTOIDS. They are often the
%     reference, and whether they belong in a combination of scalp channels
%     depends on the study.
%
%   The mastoid rule lives here rather than in eegChannelMask on purpose:
%   whether a reference electrode belongs with the scalp channels depends on
%   the analysis, and changing it there would change artefact detection, ICA
%   and the displays for every existing one. The eye electrodes were moved
%   there (2026-09-24), that being a decision taken on its own, as it should
%   have been.
%
%   See also EEGCHANNELMASK, RESS, RESSPLAN.
    mask = eegChannelMask(chanlocs);
    if isempty(chanlocs)
        return;
    end
    labels = upper(regexprep(strtrim(cellstr(string({chanlocs.labels}))), '[^A-Za-z0-9]', ''));
    eye = ~cellfun(@isempty, regexp(labels, '^((IO|LO|SO|UO)\d*|LOC|ROC)$', 'once'));
    mastoid = ~cellfun(@isempty, regexp(labels, '^(M1|M2|A1|A2|LM|RM)$|MAST', 'once'));
    mask = mask & ~eye;
    if ~includeMastoids
        mask = mask & ~mastoid;
    end
end
