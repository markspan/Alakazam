function result = DeriveChannelsDialog(EEG, stored)
%DERIVECHANNELSDIALOG  Collect a block of "let" statements for DeriveChannels.
%
%   RESULT is struct('derivations', <text>), or [] if cancelled (the
%   transformation contract's "no node, no compute").
%
%   The block is VALIDATED AT OK TIME against this dataset's own channel
%   list, by running the same engine the transformation will run
%   (TransTools.ApplyDerivations) over a dummy dataset built from EEG's
%   chanlocs. So a typo, an unknown channel or a name clash is reported here,
%   in the dialog, rather than after the node has been created -- and the two
%   can never disagree about what parses, because there is only one parser.
%
%   See also DERIVECHANNELS, TRANSTOOLS.APPLYDERIVATIONS, MEASUREDIALOG
%   (which validates the same block the same way).
    labels = {EEG.chanlocs.labels};

    if isempty(stored) || ~isstruct(stored)
        stored = struct();
    end
    defaultText = char(string(TransTools.FieldOr(stored, 'derivations', ...
        sprintf('%% One per line, e.g. a lateralised difference:\n%% let LRP = %s - %s\n', ...
            labels{1}, labels{min(2, numel(labels))}))));

    result = [];
    [accentColor, bgColor] = dialogChromeColors();
    fig = uifigure('Name', 'Derive Channels', ...
        'Position', fitOnScreen([100 100 620 420]), 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 0);

    header = uilabel(root, 'Text', '  Derive Channels', ...
        'FontSize', 16, 'FontWeight', 'bold', 'FontColor', [1 1 1], ...
        'BackgroundColor', accentColor);
    header.Layout.Row = 1;

    outer = uigridlayout(root, [4 1], 'RowHeight', {'fit', '1x', 'fit', 'fit'}, ...
        'Padding', [12 12 12 12], 'RowSpacing', 8);
    outer.Layout.Row = 2;

    uilabel(outer, 'Text', ['One "let <name> = <expression>" per line. Channels by label; ' ...
        '+ - * / with parentheses, abs() and sqrt(); % starts a comment.'], ...
        'WordWrap', 'on');

    scriptArea = uitextarea(outer, 'Value', strsplit(defaultText, newline), ...
        'FontName', 'Consolas');

    uilabel(outer, 'Text', sprintf('Channels available: %s', strjoin(labels, ', ')), ...
        'WordWrap', 'on', 'FontColor', [0.35 0.35 0.35]);

    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 8);
    uilabel(buttons, 'Text', '');
    uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) onCancel());
    uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~,~) onOK());

    fig.CloseRequestFcn = @(~,~) onCancel();
    uiwait(fig);

    % ------------------------------------------------------------------- %
    function onOK()
        text = strjoin(cellstr(scriptArea.Value), newline);
        try
            % Same engine, same grammar, so the dialog cannot accept
            % something the transformation would then refuse.
            TransTools.ApplyDerivations(dummyEEG(), text);
        catch err
            uialert(fig, err.message, 'That block has a problem');
            return;
        end
        result = struct('derivations', text);
        delete(fig);
    end

    function onCancel()
        result = [];
        delete(fig);
    end

    function d = dummyEEG()
    %DUMMYEEG  This dataset's channels over three samples: enough for the
    %   engine to resolve labels, catch clashes and evaluate the grammar,
    %   without copying the real recording.
        d = struct('chanlocs', EEG.chanlocs, 'nbchan', numel(labels), ...
            'data', zeros(numel(labels), 3));
    end
end
