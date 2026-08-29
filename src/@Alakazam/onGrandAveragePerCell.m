function onGrandAveragePerCell(this)
%ONGRANDAVERAGEPERCELL  Ribbon action (Grand Average tab): build one grand
%   average per design cell.
%
%   Replaces picking files out of a list once per cell. The cells come from
%   the design already recorded in this workspace (see deriveDesign), so
%   each grand average is named from its cell and carries that cell on the
%   result -- which makes it traceable to the design it came from rather
%   than being a set of files someone once chose.
%
%   Existing grand averages are left alone; these are added alongside. A
%   cell whose name matches one already in the tree gets a new node rather
%   than replacing it, since silently overwriting a result somebody built
%   by hand is not this action's decision to make.
%
%   See also DESIGNCELLSPECS, DERIVEDESIGN, ALAKAZAM.SAVEGRANDAVERAGE,
%   ALAKAZAM.ONDEFINEGRANDAVERAGE.
    [restoreBusy, setBusy] = beginBusy(this.MainFigure, 'Reading the design...');

    recordings = this.collectDesignRecordings();
    design = deriveDesign(recordings);
    [specs, skipped] = designCellSpecs(design, recordings, false);

    if isempty(specs)
        clear restoreBusy;
        % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
        msgbox(noSpecsMessage(design, skipped), 'Nothing to average');
        return;
    end

    clear restoreBusy;   % the confirmation must not open behind the indicator
    if ~confirmed(this.MainFigure, specs, skipped)
        return;
    end

    [restoreBusy, setBusy] = beginBusy(this.MainFigure, 'Building grand averages...'); %#ok<ASGLU>
    built = {};
    failed = struct('name', {}, 'message', {});
    for i = 1:numel(specs)
        setBusy(sprintf('Grand average %d of %d: %s...', i, numel(specs), specs(i).name));
        try
            this.saveGrandAverage(specs(i), []);
            built{end + 1} = specs(i).name; %#ok<AGROW>
        catch ME
            % One incompatible cell must not lose the others: a mismatched
            % channel count in one group is exactly the case this reports
            % rather than aborting on.
            failed(end + 1) = struct('name', specs(i).name, 'message', ME.message); %#ok<AGROW>
        end
    end

    clear restoreBusy;
    report(built, failed, skipped);
end

% ----------------------------------------------------------------------- %
function text = noSpecsMessage(design, skipped)
    if design.nRecordings == 0
        text = ['There are no averaged recordings in this workspace yet, so there is nothing ' ...
            'to combine. Run Average on some recordings first.'];
        return;
    end
    text = 'No design cell holds two or more recordings, so no grand average can be built.';
    if ~isempty(skipped)
        text = [text newline newline 'Cells that were too small:' newline ...
            skippedList(skipped)];
    end
end

function tf = confirmed(fig, specs, skipped)
%CONFIRMED  Say exactly what will be built before building it. These are
%   new nodes in the workspace, so the list is worth showing rather than
%   producing a dozen results and letting the tree explain afterwards.
    lines = arrayfun(@(s) sprintf('    %s  (%d recordings)', s.name, numel(s.sources)), ...
        specs, 'UniformOutput', false);
    text = sprintf('Build %d grand average(s)?\n\n%s', numel(specs), strjoin(lines, newline));
    if ~isempty(skipped)
        text = sprintf('%s\n\nSkipped, too few recordings:\n%s', text, skippedList(skipped));
    end
    tf = confirmAction(fig, text, 'Grand averages per cell', 'Build them', 'Cancel');
end

function report(built, failed, skipped)
    parts = {};
    if ~isempty(built)
        parts{end + 1} = sprintf('Built %d grand average(s):\n    %s', ...
            numel(built), strjoin(built, sprintf('\n    ')));
    end
    if ~isempty(skipped)
        parts{end + 1} = sprintf('Skipped, too few recordings:\n%s', skippedList(skipped));
    end
    if ~isempty(failed)
        lines = arrayfun(@(f) sprintf('    %s: %s', f.name, f.message), failed, ...
            'UniformOutput', false);
        parts{end + 1} = sprintf('Could not build:\n%s', strjoin(lines, newline));
    end

    text = strjoin(parts, sprintf('\n\n'));
    if isempty(failed)
        % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
        msgbox(text, 'Grand averages per cell');
    else
        % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
        warndlg(text, 'Grand averages per cell');
    end
end

function text = skippedList(skipped)
    lines = arrayfun(@(s) sprintf('    %s / %s: %s', s.group, s.session, s.reason), ...
        skipped, 'UniformOutput', false);
    text = strjoin(lines, newline);
end
