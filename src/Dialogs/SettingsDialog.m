classdef SettingsDialog < handle
%SETTINGSDIALOG  Tabbed editor for the global AlakazamSettings.
%
%   SettingsDialog builds its whole UI from AlakazamSettings.schema(): one tab
%   per schema tab, a titled panel per section, and one labelled control per
%   setting (checkbox / numeric / text / dropdown by type). Plus one further
%   tab, "Frequency bands", NOT schema-driven (AlakazamSettings.getBands/
%   setBands are a separate array-valued store, not a scalar schema setting
%   -- see AlakazamSettings' own header comment): a row-per-band editor with
%   a label field, start/stop frequency fields, a colour-picker button and a
%   remove button, plus an "Add band" button, built by buildBandsTab/
%   rebuildBandsList. Save writes the values back to AlakazamSettings,
%   persists them, closes the window and runs an optional callback so open
%   views can refresh; Cancel just closes.
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

        BandsList           % uigridlayout the band rows are rebuilt into
        BandRows = struct('LabelField', {}, 'LoField', {}, 'HiField', {}, 'ColorBtn', {})
    end

    properties (Constant, Access = private)
        % Layout constants buildTab's own section-height estimate (see
        % sectionHeight) and buildSection's actual grid construction both
        % derive from, so the two cannot independently drift out of sync
        % the way they did before: buildSection was changed to skip
        % building a checkbox row when a section has none (e.g. "Colour
        % map", one dropdown), but buildTab's own SEPARATE height formula
        % was hand-tuned and not updated to match, reserving a checkbox
        % row's worth of dead space that section never used -- forcing an
        % unnecessary scrollbar. One shared set of numbers, not two
        % independently-guessed formulas, going forward.
        ItemRowPx     = 40   % px per non-checkbox control row (buildSection's own RowHeight for one)
        RowSpacingPx  = 8    % buildSection's own grid RowSpacing
        PaddingPx     = 8    % buildSection's own grid Padding (each of top/bottom)
        CheckboxRowPx = 42   % estimated height of the 'fit' checkbox row, when a section has any
        PanelChromePx = 20   % estimated uipanel title-bar chrome, outside buildSection's own grid entirely
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
            % Header bar + accent styling, matching every other dialog's
            % own look (ReRefDialog, GrandAverageDialog, ...) -- this was
            % previously the one dialog left unstyled, with no apparent
            % reason to look different from its siblings.
            [accentColor, bgColor] = dialogChromeColors();
            this.Fig = uifigure('Name', 'Settings', 'Position', [200 200 540 460], 'Color', bgColor);
            root = uigridlayout(this.Fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
            uilabel(root, 'Text', '  Settings', 'FontSize', 14, 'FontWeight', 'bold', ...
                'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');

            outer = uigridlayout(root, [2 1], 'RowHeight', {'1x', 44});

            tabgroup = uitabgroup(outer);
            tabgroup.Layout.Row = 1;

            tabs = AlakazamSettings.schema();
            for t = 1:numel(tabs)
                this.buildTab(tabgroup, tabs(t));
            end
            this.buildBandsTab(tabgroup);

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
                items = tabDef.sections(s).settings;
                nOther = sum(~strcmp({items.type}, 'bool'));
                nBool  = numel(items) - nOther;
                heights{s} = this.sectionHeight(nBool, nOther);
            end
            heights{end} = '1x';   % absorb slack, keep sections at the top

            grid = uigridlayout(tab, [numel(tabDef.sections) + 1, 1], ...
                'RowHeight', heights, 'Scrollable', 'on', 'Padding', [10 10 10 10]);

            % Section title colour: the darker blue AlakazamRibbon.html's own
            % .alz-group-title uses (#2e5c8a), not dialogChromeColors' own
            % (lighter) accentColor -- a deliberately different shade, on
            % request, not a copy-paste of the dialog header bar's own colour.
            sectionTitleColor = [0.1804 0.3608 0.5412];
            for s = 1:numel(tabDef.sections)
                panel = uipanel(grid, 'Title', tabDef.sections(s).label, ...
                    'FontWeight', 'bold', 'ForegroundColor', sectionTitleColor);
                panel.Layout.Row = s;
                this.buildSection(panel, tabDef.name, tabDef.sections(s));
            end
        end

        function h = sectionHeight(this, nBool, nOther)
        %SECTIONHEIGHT  Panel height buildTab should reserve for a section
        %   with NBOOL checkboxes and NOTHER other controls -- derived from
        %   the same ItemRowPx/RowSpacingPx/PaddingPx/CheckboxRowPx/
        %   PanelChromePx constants buildSection's own grid construction
        %   uses, so the two stay in sync by construction (see the
        %   properties block's own comment for why that matters).
            hasCheckboxRow = nBool > 0;
            nRows = double(hasCheckboxRow) + nOther;
            rowsPx = double(hasCheckboxRow) * this.CheckboxRowPx + nOther * this.ItemRowPx;
            spacingPx = max(0, nRows - 1) * this.RowSpacingPx;
            h = this.PanelChromePx + 2 * this.PaddingPx + rowsPx + spacingPx;
        end

        function buildSection(this, panel, tabName, sectionDef)
            % Checkboxes sit side by side on the top row; other controls (e.g.
            % sliders) get a labelled row each, below the checkboxes. A
            % section with no checkboxes at all (e.g. "Colour map", one
            % dropdown) gets no checkbox row -- not just a zero-height one
            % -- so it doesn't reserve dead space for a row it never uses
            % (see sectionHeight's own matching formula).
            items = sectionDef.settings;
            isBool = strcmp({items.type}, 'bool');
            boolItems  = items(isBool);
            otherItems = items(~isBool);
            nOther = numel(otherItems);
            nb = numel(boolItems);
            hasCheckboxRow = nb > 0;
            cbRows = double(hasCheckboxRow);   % 0 or 1 -- computed once, used for both the row count and RowHeight below

            grid = uigridlayout(panel, [cbRows + nOther, 1], ...
                'RowHeight', [repmat({'fit'}, 1, cbRows), repmat({this.ItemRowPx}, 1, nOther)], ...
                'Padding', [this.PaddingPx this.PaddingPx this.PaddingPx this.PaddingPx], ...
                'RowSpacing', this.RowSpacingPx);

            byKey = containers.Map('KeyType', 'char', 'ValueType', 'any');

            % Top row: checkboxes, side by side -- only built at all when
            % there is at least one.
            if hasCheckboxRow
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
            end

            % Following rows: label + control for each non-bool setting.
            for j = 1:nOther
                item = otherItems(j);
                current = AlakazamSettings.get(tabName, sectionDef.name, item.key);
                rowGrid = uigridlayout(grid, [1 2], 'ColumnWidth', {220, '1x'}, ...
                    'Padding', [0 0 0 0], 'ColumnSpacing', 8);
                rowGrid.Layout.Row = cbRows + j;
                uilabel(rowGrid, 'Text', item.label, 'Tooltip', item.tooltip, ...
                    'VerticalAlignment', 'center');
                handle = this.makeControl(rowGrid, item, current);
                byKey(item.key) = handle;
                this.addField(tabName, sectionDef.name, item, handle);
            end

            this.wireEnable(items, byKey);
        end

        function buildBandsTab(this, tabgroup)
        %BUILDBANDSTAB  The "Frequency bands" tab: an explanatory blurb, a
        %   scrollable row-per-band editor (see rebuildBandsList) and an
        %   "Add band" button. Not schema-driven, unlike every other tab --
        %   see this class's own header comment and AlakazamSettings' for
        %   why bands need their own store.
            tab = uitab(tabgroup, 'Title', 'Frequency bands');
            outer = uigridlayout(tab, [3 1], 'RowHeight', {'fit', '1x', 'fit'}, ...
                'Padding', [10 10 10 10], 'RowSpacing', 6);

            uilabel(outer, 'Text', [ ...
                'Bands FourierView shades under the power spectrum. Edit the label, ' ...
                'start/stop frequency (Hz) or colour of a band, or add/remove one.'], ...
                'WordWrap', 'on');

            this.BandsList = uigridlayout(outer, [1 1], 'Scrollable', 'on', 'Padding', [0 0 0 0]);
            this.BandsList.Layout.Row = 2;

            addRow = uigridlayout(outer, [1 2], 'ColumnWidth', {120, '1x'}, 'Padding', [0 0 0 0]);
            addRow.Layout.Row = 3;
            uibutton(addRow, 'Text', 'Add band', 'ButtonPushedFcn', @(~, ~) this.onAddBand());

            this.rebuildBandsList(AlakazamSettings.getBands());
        end

        function rebuildBandsList(this, bands)
        %REBUILDBANDSLIST  Replace BandsList's contents with one row per
        %   entry in BANDS (a label/loFreq/hiFreq/color struct array), plus
        %   a header row. Rebuilt wholesale on Add/Remove rather than
        %   inserting/deleting a single row in place: uigridlayout's row
        %   count is fixed at construction, so a variable-length list needs
        %   a fresh grid each time the count changes anyway, and this way
        %   there is exactly one code path (used by buildBandsTab too) that
        %   lays a band list out, not two that can drift apart.
            delete(this.BandsList.Children);
            n = numel(bands);
            grid = uigridlayout(this.BandsList, [n + 1, 1], ...
                'RowHeight', [{'fit'}, repmat({36}, 1, n)], 'Padding', [0 4 0 4], 'RowSpacing', 4);

            header = uigridlayout(grid, [1 5], 'ColumnWidth', {'1x', 90, 90, 60, 32}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 6);
            header.Layout.Row = 1;
            uilabel(header, 'Text', 'Label', 'FontWeight', 'bold');
            uilabel(header, 'Text', 'Start (Hz)', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
            uilabel(header, 'Text', 'Stop (Hz)', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
            uilabel(header, 'Text', 'Colour', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
            uilabel(header, 'Text', '');

            this.BandRows = struct('LabelField', {}, 'LoField', {}, 'HiField', {}, 'ColorBtn', {});
            for i = 1:n
                row = uigridlayout(grid, [1 5], 'ColumnWidth', {'1x', 90, 90, 60, 32}, ...
                    'Padding', [0 0 0 0], 'ColumnSpacing', 6);
                row.Layout.Row = i + 1;
                labelField = uieditfield(row, 'text', 'Value', bands(i).label);
                loField = uieditfield(row, 'numeric', 'Value', bands(i).loFreq, 'Limits', [0 Inf]);
                hiField = uieditfield(row, 'numeric', 'Value', bands(i).hiFreq, 'Limits', [0 Inf]);
                colorBtn = uibutton(row, 'Text', '', 'BackgroundColor', bands(i).color, ...
                    'Tooltip', 'Pick colour', 'ButtonPushedFcn', @(src, ~) this.onPickColor(src));
                uibutton(row, 'Text', char(215), 'Tooltip', 'Remove this band', ...
                    'ButtonPushedFcn', @(~, ~) this.onRemoveBand(i));
                this.BandRows(end + 1) = struct('LabelField', labelField, 'LoField', loField, ...
                    'HiField', hiField, 'ColorBtn', colorBtn);
            end
        end

        function onPickColor(~, btn)
        %ONPICKCOLOR  Open the platform colour picker, seeded with the
        %   button's current swatch colour; Cancel (uisetcolor returns the
        %   scalar 0, not an RGB triple) leaves it unchanged.
            c = uisetcolor(btn.BackgroundColor, 'Band colour');
            if ~isequal(c, 0)
                btn.BackgroundColor = c;
            end
        end

        function onAddBand(this)
            bands = this.collectBandRows();
            bands(end + 1) = struct('label', 'New band', 'loFreq', 0, 'hiFreq', 1, ...
                'color', [0.290 0.498 0.788]);
            this.rebuildBandsList(bands);
        end

        function onRemoveBand(this, index)
            bands = this.collectBandRows();
            bands(index) = [];
            this.rebuildBandsList(bands);
        end

        function bands = collectBandRows(this)
        %COLLECTBANDROWS  The band list as currently shown in BandRows'
        %   live controls (not yet validated or persisted).
            n = numel(this.BandRows);
            bands = struct('label', {}, 'loFreq', {}, 'hiFreq', {}, 'color', {});
            for i = 1:n
                r = this.BandRows(i);
                bands(i) = struct('label', char(r.LabelField.Value), ...
                    'loFreq', r.LoField.Value, 'hiFreq', r.HiField.Value, ...
                    'color', r.ColorBtn.BackgroundColor);
            end
        end

        function ok = validateBands(this, bands)
        %VALIDATEBANDS  Every band needs a non-blank label and a stop
        %   frequency strictly above its start frequency; alerts and
        %   returns false on the first violation, matching the validation
        %   style SpectralMeasureDialog's own onOK uses.
            ok = true;
            for i = 1:numel(bands)
                if isempty(strtrim(bands(i).label))
                    uialert(this.Fig, sprintf('Band %d is missing a label -- would you give it one?', i), 'Check the frequency bands');
                    ok = false;
                    return;
                end
                if ~(bands(i).hiFreq > bands(i).loFreq)
                    uialert(this.Fig, sprintf('I''m afraid band "%s" needs its stop frequency to be greater than its start frequency.', ...
                        bands(i).label), 'Check the frequency bands');
                    ok = false;
                    return;
                end
            end
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
                    if ~isempty(item.step)
                        % uislider has no native step/SliderStep concept, so
                        % discrete stepping is hand-rolled: snap to the
                        % nearest multiple of item.step (relative to the
                        % lower limit) both live while dragging
                        % (ValueChangingFcn) and on release/click
                        % (ValueChangedFcn, which fires even for a plain
                        % click that never triggers ValueChangingFcn).
                        lo = item.limits(1);
                        hi = item.limits(2);
                        step = item.step;
                        snap = @(v) min(hi, max(lo, round((v - lo) / step) * step + lo));
                        handle.MinorTicks = lo:step:hi;
                        handle.ValueChangingFcn = @(src, event) set(src, 'Value', snap(event.Value));
                        handle.ValueChangedFcn  = @(src, ~) set(src, 'Value', snap(src.Value));
                    end
                otherwise
                    error('AlakazamSettings:type', ...
                        'I''m afraid ''%s'' is not a setting type this dialog recognises.', item.type);
            end
            handle.Tooltip = item.tooltip;
        end

        function onSaveClicked(this)
            bands = this.collectBandRows();
            if ~this.validateBands(bands)
                return;
            end
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
            AlakazamSettings.setBands(bands);
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
