function onDefineGrandAverage(this)
%ONDEFINEGRANDAVERAGE  Toolbar callback (Grand Average tab): define
%   a brand new grand average. Lets the analyst pick which Averaged
%   subject datasets to combine, name it, and choose weighted/
%   unweighted combining (GrandAverageDialog), then computes and
%   saves it as a new top-level node in the Grand Averages tree.
    [candidateFiles, candidateLabels] = this.findGrandAverageCandidates();
    if numel(candidateFiles) < 2
        % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
        msgbox(['A grand average needs at least two Averaged datasets ' ...
                'to combine, and fewer than two were found in this ' ...
                'workspace. Run the Average transformation on more ' ...
                'subjects first.'], 'Not enough subjects');
        return;
    end

    spec = GrandAverageDialog(candidateFiles, candidateLabels, []);
    if isempty(spec)
        return; % cancelled
    end

    try
        this.saveGrandAverage(spec, []);
    catch err
        % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
        warndlg(err.message, 'Could not compute grand average');
    end
end
