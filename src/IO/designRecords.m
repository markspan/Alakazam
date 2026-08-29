function records = designRecords(entries)
%DESIGNRECORDS  Report entries as the record list deriveDesign reads.
%
%   RECORDS = designRecords(ENTRIES) turns the struct array
%   Alakazam.collectEntriesWithField produces (subject / datasetType /
%   group / person / session / EEG) into the one
%   Alakazam.collectDesignRecordings produces (name / person / group /
%   session / bins / included / file), so a single deriveDesign call
%   answers "what is the design here?" for both the Design panel and the
%   statistical report.
%
%   WHY THIS EXISTS. The two collectors walk the same tree for the same
%   datasets and record the same facts about them under different field
%   names -- name versus subject, chiefly. That cosmetic difference was
%   enough that the report could not reuse deriveDesign, so it grew a
%   second derivation of its own with its own rules for blank labels, its
%   own cell counting and its own idea of when a cell is too small. Two
%   answers to one question: the Design panel could state one design while
%   the report fitted another, and nothing in the application could notice.
%
%   This function is the seam that removed the second derivation. It is
%   deliberately small and deliberately dull: mapping field names is all it
%   does, and the moment it starts making decisions about the design, the
%   duplication is back.
%
%   Grand averages are dropped. A grand average is a summary OVER people,
%   not a person, and counting one as a subject would inflate every cell it
%   fell into. collectEntriesWithField already marks them, so this only has
%   to respect the mark.
%
%   Everything reaching here is in the study: collectEntriesWithField
%   applies WorkSpace.includedFor before it loads anything, so an excluded
%   recording never becomes an entry in the first place. .included is
%   therefore true throughout, and deriveDesign's own exclusion reporting
%   simply has nothing to report on this path.
%
%   See also DERIVEDESIGN, REPORTDESIGNPLAN, ALAKAZAM.COLLECTDESIGNRECORDINGS.
    records = struct('name', {}, 'person', {}, 'group', {}, 'session', {}, ...
        'bins', {}, 'included', {}, 'file', {});
    if isempty(entries)
        return;
    end

    for k = 1:numel(entries)
        e = entries(k);
        if isfield(e, 'datasetType') && ~strcmp(e.datasetType, 'subject')
            continue;
        end
        records(end + 1) = struct( ...
            'name', e.subject, ...
            'person', fieldOr(e, 'person', e.subject), ...
            'group', fieldOr(e, 'group', ''), ...
            'session', fieldOr(e, 'session', ''), ...
            'bins', {binLabels(e)}, ...
            'included', true, ...
            'file', ''); %#ok<AGROW>
    end
end

% ======================================================================= %
function labels = binLabels(entry)
%BINLABELS  The bin labels this recording's Average carries, for
%   deriveDesign's bin factor and its mismatched-bins warning. A fixture or
%   an entry built without a bindesc simply contributes none, rather than
%   erroring: the design of the OTHER factors is still worth reading.
    labels = {};
    if ~isfield(entry, 'EEG') || isempty(entry.EEG)
        return;
    end
    EEG = entry.EEG;
    if ~isstruct(EEG) || ~isfield(EEG, 'bindesc') || isempty(EEG.bindesc)
        return;
    end
    bindesc = EEG.bindesc;
    if ~isfield(bindesc, 'label')
        return;
    end
    labels = {bindesc.label};
    labels = labels(cellfun(@(l) ischar(l) || isstring(l), labels));
    labels = cellfun(@char, labels, 'UniformOutput', false);
end

function value = fieldOr(s, name, default)
%FIELDOR  S.(NAME) when it is present and non-blank, DEFAULT otherwise.
%   Blank counts as absent for person specifically: WorkSpace.personFor
%   falls back to the recording's own name when nobody has set one, and an
%   entry carrying '' would otherwise merge every unlabelled recording into
%   a single phantom person.
    value = default;
    if isfield(s, name) && ~isempty(s.(name)) && ~isempty(strtrim(char(s.(name))))
        value = char(s.(name));
    end
end
