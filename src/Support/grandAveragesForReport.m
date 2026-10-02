function nodes = grandAveragesForReport(gaNodes, measuredFiles)
%GRANDAVERAGESFORREPORT  The grand averages a report on MEASUREDFILES may
%   draw: those made from the datasets it measured.
%
%   NODES = GRANDAVERAGESFORREPORT(GANODES, MEASUREDFILES) keeps, of the
%   Grand Averages tree's top-level nodes GANODES, each grand average whose
%   every source still exists and has a measured dataset (a file in
%   MEASUREDFILES) in its branch: the source itself, or a step computed from
%   it, which is where a Measure run on an Average sits. A grand average
%   that was itself measured is kept too.
%
%   WHY. ERP & Report draws the grand averages' waveforms beside the
%   measurements, as the waveforms the numbers came from. It used to draw
%   every grand average in the tree, so a report on one pipeline could show
%   the waveforms of another, made from branches deleted since.
%
%   See also GRANDAVERAGERECORD, ONEXPORTMEASUREMENTS.
    nodes = gaNodes([]);
    if isempty(gaNodes) || isempty(measuredFiles)
        return;
    end
    measured = pathKey(measuredFiles);
    keep = false(1, numel(gaNodes));
    for i = 1:numel(gaNodes)
        if ~gaNodes(i).IsRoot
            continue;
        end
        if any(inBranchOf(measured, gaNodes(i).UserData))
            keep(i) = true;   % the grand average was measured itself
            continue;
        end
        record = grandAverageRecord(gaNodes(i).UserData);
        if isempty(record.sources) || any(record.missing)
            continue;
        end
        keep(i) = all(cellfun(@(s) any(inBranchOf(measured, s)), record.sources));
    end
    nodes = gaNodes(keep);
end

function tf = inBranchOf(measured, file)
%INBRANCHOF  Which of the MEASURED keys are FILE itself or lie in its branch:
%   a node's results are cached in a folder named after it.
    [folder, stem] = fileparts(char(file));
    self = pathKey(file);
    branch = pathKey([fullfile(folder, stem) filesep]);
    tf = strcmp(measured, self{1}) | startsWith(measured, branch{1});
end
