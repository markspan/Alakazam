classdef SettingsDialog < handle
%SETTINGSDIALOG  Tabbed editor for the global AlakazamSettings.
%
%   SettingsDialog builds its whole UI from AlakazamSettings.schema(): one tab
%   per schema tab, a titled panel per section, and one labelled control per
%   setting (checkbox / numeric / text / dropdown by type). Save writes the
%   values back to AlakazamSettings, persists them, closes the window and runs
%   an optional callback so open views can refresh; Cancel just closes.
%
%   Usage:
%       SettingsDialog();                 % standalone
%       SettingsDialog(@() app.onSettingsChanged());  % refresh on save
%
%   See also ALAKAZAMSETTINGS.

    properties (Access = private)
        Fig
        Fields = struct('tab', {}, 'section', {}, 'key', {}, 'type', {}, 'handle', {})
        OnSave = []
    end

    methods
        function this = SettingsDialog(onSave)
            if nargin > 0
                this.OnSave = onSave;
            end
            this.build();
        end
    end

    methods (Access = private)
        function build(this)
            this.Fig = uifigure('Name', 'Settings', 'Position', [200 200 540 460]);
            outer = uigridlayout(this.Fig, [2 1], 'RowHeight', {'1x', 44});

            tabgroup = uitabgroup(outer);
            tabgroup.Layout.Row = 1;

            tabs = AlakazamSettings.schema();
            for t = 1:numel(tabs)
                this.buildTab(tabgroup, tabs(t));
            end

            % Button row: Save / Cancel, right-aligned.
            buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, ...
                'Padding', [8 6 8 6]);
            buttons.Layout.Row = 2;
            cancelBtn = uibutton(buttons, 'Text', 'Cancel', ...
                'ButtonPushedFcn', @(~,~) this.onCancel());
            cancelBtn.Layout.Column = 2;
            saveBtn = uibutton(buttons, 'Text', 'Save', ...
                'ButtonPushedFcn', @(~,~) this.onSaveClicked());
            saveBtn.Layout.Column = 3;
        end

        function buildTab(this, tabgroup, tabDef)
            tab = uitab(tabgroup, 'Title', tabDef.label);

            heights = cell(1, numel(tabDef.sections) + 1);
            for s = 1:numel(tabDef.sections)
                nOther = sum(~strcmp({tabDef.sections(s).settings.type}, 'bool'));
                heights{s} = 78 + 56 * nOther;   % checkbox row + a row per other control
            end
            heights{end} = '1x';   % absorb slack, keep sections at the top

            grid = uigridlayout(tab, [numel(tabDef.sections) + 1, 1], ...
                'RowHeight', heights, 'Scrollable', 'on', 'Padding', [10 10 10 10]);

            for s = 1:numel(tabDef.sections)
                panel = uipanel(grid, 'Title', tabDef.sections(s).label, ...
                    'FontWeight', 'bold');
                panel.Layout.Row = s;
                this.buildSection(panel, tabDef.name, tabDef.sections(s));
            end
        end

        function buildSection(this, panel, tabName, sectionDef)
            % Checkboxes sit side by side on the top row; other controls (e.g.
            % sliders) get a labelled row each, below the checkboxes.
            items = sectionDef.settings;
            isBool = strcmp({items.type}, 'bool');
            boolItems  = items(isBool);
            otherItems = items(~isBool);
            nOther = numel(otherItems);

            grid = uigridlayout(panel, [1 + nOther, 1], ...
                'RowHeight', [{'fit'}, repmat({40}, 1, nOther)], ...
                'Padding', [8 8 8 8], 'RowSpacing', 8);

            byKey = containers.Map('KeyType', 'char', 'ValueType', 'any');

            % Top row: checkboxes, side by side.
            nb = numel(boolItems);
            cbRow = uigridlayout(grid, [1 nb + 1], ...
                'ColumnWidth', [repmat({'fit'}, 1, nb), {'1x'}], ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 20);
            cbRow.Layout.Row = 1;
            for i = 1:nb
                item = boolItems(i);
                current = AlakazamSettings.get(tabName, sectionDef.name, item.key);
                handle = uicheckbox(cbRow, 'Text', item.label, ...
                    'Value', logical(current), 'Tooltip', item.tooltip);
                handle.Layout.Column = i;
                byKey(item.key) = handle;
                this.addField(tabName, sectionDef.name, item, handle);
            end

            % Following rows: label + control for each non-bool setting.
            for j = 1:nOther
                item = otherItems(j);
                current = AlakazamSettings.get(tabName, sectionDef.name, item.key);
                rowGrid = uigridlayout(grid, [1 2], 'ColumnWidth', {220, '1x'}, ...
                    'Padding', [0 0 0 0], 'ColumnSpacing', 8);
                rowGrid.Layout.Row = 1 + j;
                uilabel(rowGrid, 'Text', item.label, 'Tooltip', item.tooltip, ...
                    'VerticalAlignment', 'center');
                handle = this.makeControl(rowGrid, item, current);
                byKey(item.key) = handle;
                this.addField(tabName, sectionDef.name, item, handle);
            end

            this.wireEnable(items, byKey);
        end

        function addField(this, tab, section, item, handle)
            this.Fields(end + 1) = struct('tab', tab, 'section', section, ...
                'key', item.key, 'type', item.type, 'handle', handle);
        end

        function wireEnable(this, items, byKey)
            % Controls with an 'enabledBy' key are active only while that
            % checkbox is ticked; toggling the checkbox updates them live.
            gateDeps = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for k = 1:numel(items)
                item = items(k);
                if isempty(item.enabledBy) || ~isKey(byKey, item.enabledBy) ...
                        || ~isKey(byKey, item.key)
                    continue;
                end
                if isKey(gateDeps, item.enabledBy)
                    gateDeps(item.enabledBy) = [gateDeps(item.enabledBy), {byKey(item.key)}];
                else
                    gateDeps(item.enabledBy) = {byKey(item.key)};
                end
            end
            gateKeys = gateDeps.keys;
            for g = 1:numel(gateKeys)
                gate = byKey(gateKeys{g});
                deps = gateDeps(gateKeys{g});
                this.setEnabled(deps, gate.Value);
                gate.ValueChangedFcn = @(src, ~) this.setEnabled(deps, src.Value);
            end
        end

        function setEnabled(~, deps, on)
            if on; state = 'on'; else; state = 'off'; end
            for i = 1:numel(deps)
                deps{i}.Enable = state;
            end
        end

        function handle = makeControl(~, grid, item, current)
            % Non-boolean controls (booleans are drawn inline in buildSection).
            switch item.type
                case 'number'
                    handle = uieditfield(grid, 'numeric', 'Value', current);
                case 'text'
                    handle = uieditfield(grid, 'text', 'Value', char(current));
                case 'choice'
                    handle = uidropdown(grid, 'Items', item.choices, 'Value', current);
                case 'slider'
                    handle = uislider(grid, 'Limits', item.limits, 'Value', current);
                    if ~isempty(item.limits)
                        handle.MajorTicks = item.limits(1):item.limits(2);
                    end
                otherwise
                    error('AlakazamSettings:type', ...
                        'Unknown setting type ''%s''.', item.type);
            end
            handle.Tooltip = item.tooltip;
        end

        function onSaveClicked(this)
            for i = 1:numel(this.Fields)
                f = this.Fields(i);
                switch f.type
                    case 'bool'
                        value = logical(f.handle.Value);
                    otherwise
                        value = f.handle.Value;
                end
                AlakazamSettings.set(f.tab, f.section, f.key, value);
            end
            AlakazamSettings.save();
            this.close();
            if ~isempty(this.OnSave)
                try
                    this.OnSave();
                catch err
                    warning('Alakazam:settingsCallback', ...
                        'Settings applied, but refresh failed: %s', err.message);
                end
            end
        end

        function onCancel(this)
            this.close();
        end

        function close(this)
            if ~isempty(this.Fig) && isvalid(this.Fig)
                delete(this.Fig);
            end
        end
    end
end
