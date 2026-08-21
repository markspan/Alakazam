classdef AlakazamSettings < handle
%ALAKAZAMSETTINGS  Global, user-editable settings for Alakazam.
%
%   A single, application-wide settings store organised as tabs -> sections ->
%   settings, mirroring the spectHR settings layout. The set of settings and
%   their defaults live in one place (defineSchema); the SettingsDialog builds
%   its editor from that schema, and any code can read a value from anywhere:
%
%       up = AlakazamSettings.get('graphics', 'erpPlot', 'positiveUp');
%
%   Values persist across sessions as a plain JSON file (SettingsFile, under
%   MATLAB's own per-user preferences directory -- see prefdir -- but a
%   readable/editable/backup-able text file, not MATLAB's opaque setpref/
%   getpref store). The store is a lazily-created singleton, so reads and
%   writes always see the same in-memory values; SettingsDialog persists
%   them on Save.
%
%   Adding a setting: add one entry to defineSchema (key, label, type, default,
%   tooltip). Supported types: 'bool', 'number', 'text', 'choice' (with a
%   choices cell array). Everything else - the editor row, the default, the
%   persistence - follows automatically.
%
%   Frequency bands (FourierView's shaded bands) are a separate store, not a
%   schema setting: they are a variable-length list of records (label,
%   loFreq, hiFreq, color), which does not fit the schema's one-scalar-
%   per-key shape. GETBANDS/SETBANDS read and write Values.bands directly;
%   SettingsDialog builds their own dedicated "Frequency bands" tab (a
%   row-per-band editor with Add/Remove) rather than going through the
%   generic per-setting-type control the rest of the dialog uses.
%
%   See also SETTINGSDIALOG.

    properties (Constant, Access = private)
        SettingsFile = fullfile(prefdir, 'AlakazamSettings.json')
    end

    properties (SetAccess = private)
        Values   % struct: Values.(tab).(section).(key) = value
    end

    methods (Static)
        function obj = instance()
        %INSTANCE  The shared settings object (created on first use).
            persistent theInstance
            if isempty(theInstance) || ~isvalid(theInstance)
                theInstance = AlakazamSettings();
            end
            obj = theInstance;
        end

        function value = get(tab, section, key)
        %GET  Read a setting value: AlakazamSettings.get(tab, section, key).
            value = AlakazamSettings.instance().Values.(tab).(section).(key);
        end

        function set(tab, section, key, value)
        %SET  Update a setting in memory (call save() to persist).
            obj = AlakazamSettings.instance();
            obj.Values.(tab).(section).(key) = value;
        end

        function save()
        %SAVE  Persist the current values to SettingsFile (JSON).
            obj = AlakazamSettings.instance();
            fid = fopen(AlakazamSettings.SettingsFile, 'w');
            if fid < 0
                throw(MException('Alakazam:AlakazamSettings', ...
                    'Could not open %s for writing.', AlakazamSettings.SettingsFile));
            end
            closeFile = onCleanup(@() fclose(fid));
            fprintf(fid, '%s', jsonencode(obj.Values, 'PrettyPrint', true));
        end

        function s = schema()
        %SCHEMA  The tabs -> sections -> settings description.
            s = AlakazamSettings.defineSchema();
        end

        function reload()
        %RELOAD  Discard the cached singleton (e.g. after resetting prefs).
            AlakazamSettings.instance().refresh();
        end

        function bands = getBands()
        %GETBANDS  The frequency-band list (label/loFreq/hiFreq/color struct
        %   array) FourierView shades its power spectrum with.
            bands = AlakazamSettings.instance().Values.bands;
        end

        function setBands(bands)
        %SETBANDS  Replace the frequency-band list in memory (call save() to
        %   persist). BANDS may be empty (0x0 struct with the right fields,
        %   or []) to mean "no shaded bands", not "use the defaults".
            obj = AlakazamSettings.instance();
            obj.Values.bands = AlakazamSettings.normalizeBands(bands);
        end

        function bands = defaultBands()
        %DEFAULTBANDS  The standard EEG bands, shaded in shades of the same
        %   blue (#4a7fc9, see dialogChromeColors) used throughout the rest
        %   of the UI: light for the low, slow bands, darkening through the
        %   accent blue itself (Alpha) to a dark navy for Gamma.
            bands = struct('label', {}, 'loFreq', {}, 'hiFreq', {}, 'color', {});
            bands(end + 1) = AlakazamSettings.bandDef('Sub-Delta', 0,    0.5,  [0.839 0.894 0.961]);
            bands(end + 1) = AlakazamSettings.bandDef('Delta',     0.5,  3.5,  [0.663 0.776 0.910]);
            bands(end + 1) = AlakazamSettings.bandDef('Theta',     3.5,  7.5,  [0.435 0.627 0.839]);
            bands(end + 1) = AlakazamSettings.bandDef('Alpha',     7.5,  12.5, [0.290 0.498 0.788]);
            bands(end + 1) = AlakazamSettings.bandDef('Beta',      12.5, 30,   [0.180 0.361 0.541]);
            bands(end + 1) = AlakazamSettings.bandDef('Gamma',     30,   100,  [0.102 0.227 0.361]);
        end
    end

    methods (Access = private)
        function this = AlakazamSettings()
            this.refresh();
        end

        function refresh(this)
        %REFRESH  Rebuild Values from the schema defaults overlaid with the
        %   stored SettingsFile, if one exists yet (first run on a machine
        %   has none; schema defaults apply until the first Save).
            if exist(AlakazamSettings.SettingsFile, 'file') == 2
                stored = jsondecode(fileread(AlakazamSettings.SettingsFile));
            else
                stored = struct();
            end
            this.Values = AlakazamSettings.buildValues(stored);
        end
    end

    methods (Static, Access = private)
        function values = buildValues(stored)
        %BUILDVALUES  Defaults from the schema, overridden by stored prefs.
        %   Rebuilding from the schema each time keeps Values in step with the
        %   current schema: new settings get their default, removed ones drop.
            values = struct();
            tabs = AlakazamSettings.defineSchema();
            for t = 1:numel(tabs)
                tab = tabs(t);
                for se = 1:numel(tab.sections)
                    section = tab.sections(se);
                    for st = 1:numel(section.settings)
                        item = section.settings(st);
                        v = item.default;
                        if isfield(stored, tab.name) ...
                                && isfield(stored.(tab.name), section.name) ...
                                && isfield(stored.(tab.name).(section.name), item.key)
                            v = stored.(tab.name).(section.name).(item.key);
                        end
                        values.(tab.name).(section.name).(item.key) = v;
                    end
                end
            end

            if isfield(stored, 'bands')
                values.bands = AlakazamSettings.normalizeBands(stored.bands);
            else
                values.bands = AlakazamSettings.defaultBands();
            end
        end

        function bands = normalizeBands(raw)
        %NORMALIZEBANDS  RAW (a struct array fresh from jsondecode, or one
        %   already built via bandDef) coerced to the canonical
        %   label/loFreq/hiFreq/color shape, with color as a 1x3 double.
        %   jsondecode turns a JSON "[]" into 0x0 double, not a 0x0 struct,
        %   so that (deliberately empty -- see setBands) case is handled
        %   explicitly rather than falling through to a field access.
            template = struct('label', {}, 'loFreq', {}, 'hiFreq', {}, 'color', {});
            if isempty(raw)
                bands = template;
                return;
            end
            bands = template;
            for i = 1:numel(raw)
                r = raw(i);
                bands(i) = AlakazamSettings.bandDef(char(string(r.label)), ...
                    double(r.loFreq), double(r.hiFreq), double(r.color(:)'));
            end
        end

        function b = bandDef(label, loFreq, hiFreq, color)
            b = struct('label', label, 'loFreq', loFreq, 'hiFreq', hiFreq, 'color', color);
        end

        function tabs = defineSchema()
        %DEFINESCHEMA  The single source of truth for all settings.
            tabs = struct('name', {}, 'label', {}, 'sections', {});

            % ---- Tab: Graphics ------------------------------------------
            erpPlot = AlakazamSettings.section('erpPlot', 'ERP plot', [ ...
                AlakazamSettings.setting('positiveUp', 'Positive up', 'bool', true, ...
                    'If checked, the positive y-axis points up; otherwise it points down.') ...
                AlakazamSettings.setting('clampYAxis', 'Clamp y-axis to largest', 'bool', false, ...
                    ['If checked, every electrode uses the same y-axis, scaled to the ' ...
                     'electrode with the largest range, instead of rescaling per electrode.']) ...
                AlakazamSettings.setting('showConfInt', 'Show confidence interval', 'bool', true, ...
                    'If checked, draw the confidence band (n x standard error) around each average.') ...
                AlakazamSettings.setting('confIntN', 'Confidence band (n x SE)', 'slider', 3, ...
                    'Width of the confidence band in standard errors.', ...
                    'limits', [0 5], 'step', 0.5, 'enabledBy', 'showConfInt') ...
            ]);
            epochImage = AlakazamSettings.section('epochImage', 'Epoch image', [ ...
                AlakazamSettings.setting('groupByBin', 'Plot trials by bin', 'bool', false, ...
                    ['If checked, EpochView''s rows are grouped by bin, top to bottom, ' ...
                     'and a trial belonging to more than one bin is plotted once per bin ' ...
                     '(so the row count can exceed the trial count). If unchecked ' ...
                     '(default), trials are shown in their natural order with no bin ' ...
                     'grouping at all, even if the dataset has bins.']) ...
            ]);
            colormapSection = AlakazamSettings.section('colormap', 'Colour map', [ ...
                AlakazamSettings.setting('name', 'Colour map', 'choice', 'diverging', ...
                    ['Colour map used by every plot that shows a signed, zero-centred ' ...
                     'quantity: EpochView''s ERP-image, TimeFrequencyView''s ERSP power, ' ...
                     'and ScalpDistributionView''s/Brain3DView''s scalp topography. "diverging" is this ' ...
                     'app''s own blue-white-red scale (negative/zero/positive); the rest ' ...
                     'are MATLAB''s own built-in colour maps.'], ...
                    'choices', {'diverging', 'parula', 'jet', 'turbo', 'hot', 'cool'}) ...
            ]);
            fourierPlot = AlakazamSettings.section('fourierPlot', 'Fourier plot', [ ...
                AlakazamSettings.setting('smoothSpectrum', 'Smooth spectrum', 'bool', false, ...
                    ['If checked, FourierView''s power spectrum is smoothed with a light ' ...
                     'moving average before it is plotted (and before the frequency bands ' ...
                     'are shaded under it), to make the trend easier to read on a noisy ' ...
                     'spectrum. Unchecked (default) plots the raw per-frequency values.']) ...
            ]);
            tabs(end + 1) = AlakazamSettings.tab('graphics', 'Graphics', ...
                [erpPlot, epochImage, colormapSection, fourierPlot]);
        end

        % --- small schema builders --------------------------------------
        function t = tab(name, label, sections)
            t = struct('name', name, 'label', label, 'sections', sections);
        end

        function s = section(name, label, settings)
            s = struct('name', name, 'label', label, 'settings', settings);
        end

        function item = setting(key, label, type, default, tooltip, varargin)
            % Optional name-value extras: 'choices' (for 'choice'), 'limits'
            % ([min max] for 'slider'/'number'), 'step' (snap increment for
            % 'slider'; empty means continuous), 'enabledBy' (key of a bool
            % in the same section that must be true for this control to be
            % active).
            opts = struct('choices', {{}}, 'limits', [], 'step', [], 'enabledBy', '');
            for k = 1:2:numel(varargin)
                opts.(varargin{k}) = varargin{k + 1};
            end
            item = struct('key', key, 'label', label, 'type', type, ...
                'default', default, 'tooltip', tooltip, ...
                'choices', {opts.choices}, 'limits', opts.limits, ...
                'step', opts.step, 'enabledBy', opts.enabledBy);
        end
    end
end
