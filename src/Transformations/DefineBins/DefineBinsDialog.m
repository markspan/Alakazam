function result = DefineBinsDialog(defaultScript, prevEpoch, opts)
%DEFINEBINSDIALOG  Modal editor: epoch start/stop side by side, script below.
%   Returns a struct with .start, .stop (raw text) and .script, or [] if the
%   user cancelled or closed the window. Epoch-bounds validation and script
%   parsing happen in the caller (DefineBins.m, via DefineBinsEngine), not
%   here: Save is a convenience for resuming the same setup later, so it
%   (like Save elsewhere in this dialog) accepts whatever is currently
%   typed, valid or not.
%
%   OPTS (optional) adapts the same editor for another transformation that
%   needs bins defined in this language:
%     .showEpoch  false hides the epoch start/stop row, for a caller that
%                 does not cut epochs at all (Deconvolve fits a response
%                 window against continuous data instead). .start and .stop
%                 then come back empty, which DefineBins reads as "tag the
%                 events, reshape nothing".
%     .name       the window's title bar, default 'DefineBins'.
%     .note       a line of explanation above the editor, for a caller whose
%                 reason for asking is not simply "define bins".
%   Reusing this editor rather than putting a second script box in another
%   dialog is deliberate: Save, Load, Import BDF and the language reference
%   are most of its value, and a copy would have none of them.
%
%   See also DEFINEBINS, DECONVOLVE, DECONVOLVEDIALOG.
    result = [];
    if nargin < 3 || isempty(opts); opts = struct(); end
    showEpoch = logical(TransTools.FieldOr(opts, 'showEpoch', true));
    name      = char(TransTools.FieldOr(opts, 'name', 'DefineBins'));
    note      = char(TransTools.FieldOr(opts, 'note', ''));

    % 780 wide, not the original 640: the button row's fixed widths plus its
    % padding and gaps need 646px before the flexible spacer gets anything,
    % so adding "Syntax..." pushed the last button off the edge. This leaves
    % the spacer real room rather than only just fitting.
    [accentColor, bgColor] = dialogChromeColors();
    fig = uifigure('Name', name, 'Position', fitOnScreen([100 100 780 520]), 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Define bins', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [3 1], 'RowHeight', {'fit', '1x', 44});

    % Row 1: epoch start/stop fields, side by side; or, for a caller that cuts
    % no epochs, its reason for asking in their place.
    if showEpoch
        epochRow = uigridlayout(outer, [1 4], ...
            'ColumnWidth', {'fit', 90, 'fit', 90}, 'Padding', [8 8 8 0]);
        epochRow.Layout.Row = 1;
        uilabel(epochRow, 'Text', 'Epoch start (ms):');
        startField = uieditfield(epochRow, 'text', 'Value', prevEpoch{1});
        uilabel(epochRow, 'Text', 'Epoch stop (ms):');
        stopField = uieditfield(epochRow, 'text', 'Value', prevEpoch{2});
    else
        startField = [];
        stopField  = [];
        noteRow = uigridlayout(outer, [1 1], 'Padding', [8 8 8 0]);
        noteRow.Layout.Row = 1;
        uilabel(noteRow, 'WordWrap', 'on', 'FontColor', [0.35 0.35 0.35], 'Text', note);
    end

    % Row 2: bin definitions, a multi-line text area.
    scriptArea = uitextarea(outer, 'Value', strsplit(defaultScript, newline), ...
        'FontName', 'Consolas');
    scriptArea.Layout.Row = 2;

    % Row 3: Save / Load / Import / Syntax on the left, OK / Cancel right.
    buttons = uigridlayout(outer, [1 7], 'ColumnWidth', {90, 90, 120, 90, '1x', 90, 90}, ...
        'Padding', [8 6 8 6]);
    buttons.Layout.Row = 3;
    saveBtn = uibutton(buttons, 'Text', 'Save...', 'ButtonPushedFcn', @(~,~) onSave());
    saveBtn.Layout.Column = 1;
    loadBtn = uibutton(buttons, 'Text', 'Load...', 'ButtonPushedFcn', @(~,~) onLoad());
    loadBtn.Layout.Column = 2;
    importBtn = uibutton(buttons, 'Text', 'Import BDF...', 'ButtonPushedFcn', @(~,~) onImportBdf(), ...
        'Tooltip', 'Import an ERPLAB bin descriptor file and translate it to this language');
    importBtn.Layout.Column = 3;
    syntaxBtn = uibutton(buttons, 'Text', 'Syntax...', 'ButtonPushedFcn', @(~,~) onSyntax(), ...
        'Tooltip', 'Open the bin-definition language reference');
    syntaxBtn.Layout.Column = 4;
    cancelBtn = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) onCancel());
    cancelBtn.Layout.Column = 6;
    okBtn = uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, 'FontColor', [1 1 1], ...
        'ButtonPushedFcn', @(~,~) onOK());
    okBtn.Layout.Column = 7;
    fig.CloseRequestFcn = @(~,~) onCancel();

    % The reference window, kept so a second click refocuses the open one
    % rather than stacking up copies -- the same singleton the Help and
    % About windows use.
    syntaxFig = [];

    uiwait(fig);

    function onSyntax()
    %ONSYNTAX  Open the language reference beside the editor.
    %   Deliberately non-modal: the reason for putting the reference here at
    %   all is being able to read it while writing a bin definition.
        if ~isempty(syntaxFig) && isvalid(syntaxFig)
            figure(syntaxFig);
            return;
        end
        % A sibling now: this dialog lives in its own transformation's
        % folder, alongside the language reference it opens. It previously
        % lived in src/Dialogs and walked up to src and back down, which
        % broke the moment the file moved.
        mdFile = fullfile(fileparts(mfilename('fullpath')), 'bin_language.md');
        try
            syntaxFig = MarkdownDialog('Bin-definition language', mdFile, fig);
        catch err
            uialert(fig, sprintf(['I could not open the language reference, I am afraid: ' ...
                '%s\n\nIt should be at %s.'], err.message, mdFile), ...
                'Language reference unavailable', 'Icon', 'warning');
        end
    end

    function [startStr, stopStr] = epochText()
    %EPOCHTEXT  What is typed in the epoch fields, or nothing when a caller
    %   asked for them to be hidden. Empty bounds are how DefineBins is told
    %   to tag the events and reshape nothing.
        if isempty(startField)
            startStr = '';
            stopStr  = '';
        else
            startStr = strtrim(startField.Value);
            stopStr  = strtrim(stopField.Value);
        end
    end

    function onOK()
        [startStr, stopStr] = epochText();
        result = struct('start', startStr, 'stop', stopStr, ...
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
        [startStr, stopStr] = epochText();
        try
            writeScriptFile(fullfile(path, file), startStr, stopStr, ...
                strjoin(scriptArea.Value, newline));
        catch err
            uialert(fig, err.message, 'Save failed');
        end
    end

    function onLoad()
        [file, path] = uiextras.uigetfile2('*.binscript', 'Load bin definitions');
        if isequal(file, 0); return; end
        try
            [startStr, stopStr, script] = readScriptFile(fullfile(path, file));
            if ~isempty(startField)
                startField.Value = startStr;
                stopField.Value  = stopStr;
            end
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
