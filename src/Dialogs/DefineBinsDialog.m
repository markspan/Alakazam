function result = DefineBinsDialog(defaultScript, prevEpoch)
%DEFINEBINSDIALOG  Modal editor: epoch start/stop side by side, script below.
%   Returns a struct with .start, .stop (raw text) and .script, or [] if the
%   user cancelled or closed the window. Epoch-bounds validation and script
%   parsing happen in the caller (DefineBins.m, via DefineBinsEngine), not
%   here: Save is a convenience for resuming the same setup later, so it
%   (like Save elsewhere in this dialog) accepts whatever is currently
%   typed, valid or not.
    result = [];

    fig = uifigure('Name', 'DefineBins', 'Position', [100 100 640 480]);
    outer = uigridlayout(fig, [3 1], 'RowHeight', {'fit', '1x', 44});

    % Row 1: epoch start/stop fields, side by side.
    epochRow = uigridlayout(outer, [1 4], ...
        'ColumnWidth', {'fit', 90, 'fit', 90}, 'Padding', [8 8 8 0]);
    epochRow.Layout.Row = 1;
    uilabel(epochRow, 'Text', 'Epoch start (ms):');
    startField = uieditfield(epochRow, 'text', 'Value', prevEpoch{1});
    uilabel(epochRow, 'Text', 'Epoch stop (ms):');
    stopField = uieditfield(epochRow, 'text', 'Value', prevEpoch{2});

    % Row 2: bin definitions, a multi-line text area.
    scriptArea = uitextarea(outer, 'Value', strsplit(defaultScript, newline), ...
        'FontName', 'Consolas');
    scriptArea.Layout.Row = 2;

    % Row 3: Save / Load / Import on the left, OK / Cancel right-aligned.
    buttons = uigridlayout(outer, [1 6], 'ColumnWidth', {90, 90, 120, '1x', 90, 90}, ...
        'Padding', [8 6 8 6]);
    buttons.Layout.Row = 3;
    saveBtn = uibutton(buttons, 'Text', 'Save...', 'ButtonPushedFcn', @(~,~) onSave());
    saveBtn.Layout.Column = 1;
    loadBtn = uibutton(buttons, 'Text', 'Load...', 'ButtonPushedFcn', @(~,~) onLoad());
    loadBtn.Layout.Column = 2;
    importBtn = uibutton(buttons, 'Text', 'Import BDF...', 'ButtonPushedFcn', @(~,~) onImportBdf(), ...
        'Tooltip', 'Import an ERPLAB bin descriptor file and translate it to this language');
    importBtn.Layout.Column = 3;
    cancelBtn = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) onCancel());
    cancelBtn.Layout.Column = 5;
    okBtn = uibutton(buttons, 'Text', 'OK', 'ButtonPushedFcn', @(~,~) onOK());
    okBtn.Layout.Column = 6;
    fig.CloseRequestFcn = @(~,~) onCancel();

    uiwait(fig);

    function onOK()
        result = struct('start', strtrim(startField.Value), ...
            'stop', strtrim(stopField.Value), ...
            'script', strjoin(scriptArea.Value, newline));
        uiresume(fig);
        delete(fig);
    end

    function onCancel()
        uiresume(fig);
        delete(fig);
    end

    function onSave()
        [file, path] = uiextras.uiputfile2('*.binscript', 'Save bin definitions as');
        if isequal(file, 0); return; end
        try
            writeScriptFile(fullfile(path, file), strtrim(startField.Value), ...
                strtrim(stopField.Value), strjoin(scriptArea.Value, newline));
        catch err
            uialert(fig, err.message, 'Save failed');
        end
    end

    function onLoad()
        [file, path] = uiextras.uigetfile2('*.binscript', 'Load bin definitions');
        if isequal(file, 0); return; end
        try
            [startStr, stopStr, script] = readScriptFile(fullfile(path, file));
            startField.Value = startStr;
            stopField.Value  = stopStr;
            scriptArea.Value = splitlines(script);
        catch err
            uialert(fig, err.message, 'Load failed');
        end
    end

    function onImportBdf()
        % Import an ERPLAB bin descriptor file and translate it into this
        % language (see erplabBdfToBinScript). Fills the script editor; the
        % epoch bounds are ERPLAB's separate step, so they are left untouched.
        [file, path] = uiextras.uigetfile2( ...
            {'*.txt;*.bdf', 'ERPLAB bin descriptor file (*.txt, *.bdf)'}, ...
            'Import ERPLAB bin descriptor file');
        if isequal(file, 0); return; end
        try
            [script, warnings] = erplabBdfToBinScript(fileread(fullfile(path, file)));
            scriptArea.Value = splitlines(script);
        catch err
            uialert(fig, err.message, 'Import failed');
            return;
        end
        if ~isempty(warnings)
            uialert(fig, sprintf(['The import went through, but with %d note(s) -- would you mind reviewing ' ...
                'the lines marked WARNING in the script below?\n\n%s'], numel(warnings), strjoin(warnings, newline)), ...
                'Imported with notes', 'Icon', 'warning');
        end
    end
end

function writeScriptFile(filePath, startStr, stopStr, script)
%WRITESCRIPTFILE  Save epoch bounds + script text as a small header + body.
    fid = fopen(filePath, 'w');
    if fid < 0
        throw(MException('Alakazam:DefineBins', ...
            ['I''m afraid I could not save to %s -- the folder might be read-only, the disk ' ...
             'might be full, or another program might have the file open. ' ...
             'Would you try a different location or filename?'], filePath));
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%% epoch_start_ms: %s\n', startStr);
    fprintf(fid, '%% epoch_stop_ms: %s\n', stopStr);
    fprintf(fid, '%s', script);
end

function [startStr, stopStr, script] = readScriptFile(filePath)
%READSCRIPTFILE  Inverse of writeScriptFile; tolerates a body with no header.
    lines = splitlines(fileread(filePath));
    startStr = '';
    stopStr  = '';
    i = 1;
    if numel(lines) >= i
        tok = regexp(lines{i}, '^%\s*epoch_start_ms:\s*(.*)$', 'tokens', 'once');
        if ~isempty(tok); startStr = strtrim(tok{1}); i = i + 1; end
    end
    if numel(lines) >= i
        tok = regexp(lines{i}, '^%\s*epoch_stop_ms:\s*(.*)$', 'tokens', 'once');
        if ~isempty(tok); stopStr = strtrim(tok{1}); i = i + 1; end
    end
    script = strjoin(lines(i:end), newline);
end
