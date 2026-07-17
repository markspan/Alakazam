function recalculateAffectedGrandAverages(this, touchedFiles)
%RECALCULATEAFFECTEDGRANDAVERAGES  Silently refresh every Grand
%   Average built from any file in TOUCHEDFILES (a cell array of
%   paths just overwritten by recalculateTransformNode). Reuses
%   each affected Grand Average's OWN already-recorded sources
%   and weighting -- no dialog, no membership change -- exactly
%   what its own "Recalculate" context-menu action would produce
%   if the analyst reopened it and pressed OK without touching
%   anything. A Grand Average is never itself a valid source of
%   another (findGrandAverageCandidates excludes them), so this
%   never needs to cascade further than one level.
    gaNodes = this.Workspace.GrandAveragesTree.allNodes();
    for i = 1:numel(gaNodes)
        gaFile = gaNodes(i).UserData;
        if isempty(gaFile) || exist(gaFile, "file") ~= 2
            continue;
        end
        loaded = load(gaFile, "EEG");
        gaEEG = loaded.EEG;
        if ~isfield(gaEEG, "etc") || ~isfield(gaEEG.etc, "GrandAverage")
            continue;
        end
        % Case-insensitive on Windows (paths there are
        % case-insensitive; ismember/strcmp are not -- same
        % reasoning as toStoredPath's own ispc branch), so a
        % harmless casing difference between how a source path
        % was originally recorded and how it comes back from a
        % fresh dir() scan doesn't silently defeat the match.
        if ispc
            matched = any(cellfun(@(s) any(strcmpi(s, touchedFiles)), gaEEG.etc.GrandAverage.sources));
        else
            matched = any(cellfun(@(s) any(strcmp(s, touchedFiles)), gaEEG.etc.GrandAverage.sources));
        end
        if ~matched
            continue; % this Grand Average does not draw on anything just recalculated
        end

        spec = struct('name', gaEEG.id, ...
            'sources', {gaEEG.etc.GrandAverage.sources}, ...
            'weighted', gaEEG.etc.GrandAverage.weighted);
        % Same stale-tab risk saveGrandAverage's own plotCurrent
        % call has (see recalculateTransformNode's own note):
        % close any open tab for this Grand Average first, so it
        % gets rebuilt fresh rather than silently reused.
        this.closeTab(gaFile);
        try
            this.saveGrandAverage(spec, gaNodes(i));
        catch err
            % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
            warndlg(sprintf( ...
                ['Could not refresh Grand Average "%s" after recalculating ' ...
                 'an upstream branch:\n\n%s'], gaEEG.id, err.message), ...
                'Could not recalculate Grand Average');
        end
    end
end
