function qmdText = generateSourceReport(entries, csvFileName)
%GENERATESOURCEREPORT  A Quarto report for measurements taken on cortical
%   source REGIONS rather than scalp channels.
%
%   ENTRIES are Measure results from parcellated datasets (see Parcellate):
%   their "channels" are anatomical regions, so the measurements CSV has a
%   region name where it normally has an electrode.
%
%   ITS OWN DOCUMENT, NOT ITS OWN STATISTICS. The design logic, the section
%   builders, the preamble and the closing FDR summary are shared with the
%   ERP/Spectral report (generateQuartoReport), because the statistics do
%   not change just because the numbers came out of an inverse solution: a
%   region measured in two bins across subjects is the same design as a
%   channel measured in two bins across subjects, and giving it a second
%   implementation would only let the two drift apart.
%
%   WHAT IS DIFFERENT IS WHAT HAS TO BE SAID. A region name reads like an
%   anatomical finding in a way "channel P7" never does, and this one is
%   not: it comes from a template head model, template electrode positions
%   and a template atlas, stacked. Neighbouring regions are also strongly
%   correlated, because the inverse is spatially smooth, so the FDR summary
%   at the end of the document is adjusting across tests that are nowhere
%   near independent. Both of those belong at the TOP of the report, where
%   somebody reading the tables will see them, not in a methods note
%   nobody reaches.
%
%   The provenance is printed too -- which inverse method, which atlas, how
%   regions were aggregated -- because six months later that is exactly
%   what nobody remembers and no table records.
%
%   See also GENERATEQUARTOREPORT, PARCELLATE, TRANSTOOLS.PARCELLATESOURCE,
%   EXPORTMEASUREMENTSCSV, ALAKAZAM.ONEXPORTSOURCEREPORT.
    if isempty(entries)
        throw(MException('Alakazam:generateSourceReport', ...
            ['I''m afraid a source report needs at least one parcellated dataset with ' ...
             'Measure results on it.']));
    end

    qmdText = generateQuartoReport(entries, csvFileName, struct( ...
        'Title', 'Source Region', ...
        'Notes', {provenanceNotes(entries)}));
end

% ======================================================================= %
function notes = provenanceNotes(entries)
%PROVENANCENOTES  The caveats and the parcellation settings, as markdown.
    notes = { ...
        '> **These are source estimates, not measurements.**' ...
        '> Every number below was computed through an inverse solution built on a' ...
        '> **template** head model, **template** electrode positions and a **template**' ...
        '> atlas. No per-subject MRI or digitised cap is involved. A region name here' ...
        '> names where the model puts the activity, not where it was observed.' ...
        '>' ...
        '> **Regions are not independent tests.** The inverse is spatially smooth, so' ...
        '> neighbouring regions carry much of the same signal. The false-discovery-rate' ...
        '> summary at the end of this document adjusts across the tests it was given;' ...
        '> it cannot know how few of them are really distinct.' ...
        '>' ...
        '> **Signs are within-region only.** Each region''s time course is projected onto' ...
        '> its own dominant cortical normal, so its sign is comparable across bins,' ...
        '> conditions and subjects -- every subject shares the same template geometry --' ...
        '> but NOT between regions.' ...
        ''};

    settings = settingsLine(entries);
    if ~isempty(settings)
        notes = [notes, {['**Parcellation:** ' settings], ''}];
    end
end

function line = settingsLine(entries)
%SETTINGSLINE  How the parcellation was actually done, read off the first
%   entry that recorded it. Silent rather than invented when absent: a CSV
%   from an older export has no provenance to report, and a made-up line
%   would be worse than none.
    line = '';
    for k = 1:numel(entries)
        EEG = entries(k).EEG;
        if ~isfield(EEG, 'parcellation') || ~isstruct(EEG.parcellation)
            continue;
        end
        p = EEG.parcellation;
        described = {'Method', 'inverse method'; 'Atlas', 'atlas'; 'Mode', 'aggregation'};
        bits = strings(0);
        for d = 1:size(described, 1)
            value = TransTools.FieldOr(p, described{d, 1}, '');
            if ~isempty(value)
                bits(end + 1) = sprintf('%s %s', described{d, 2}, char(string(value))); %#ok<AGROW>
            end
        end
        if isfield(p, 'Regions') && ~isempty(p.Regions)
            bits(end + 1) = sprintf('%d region(s)', numel(p.Regions)); %#ok<AGROW>
        end
        if ~isempty(bits)
            line = char(strjoin(bits, ', ') + ".");
        end
        return;
    end
end
