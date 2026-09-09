classdef MeasurePresetsTest < matlab.unittest.TestCase
%MEASUREPRESETSTEST  Every shipped .alm preset must load and be usable.
%
%   A preset is a file an analyst reaches for through Load..., and a broken
%   one fails in a dialog with no way back except editing JSON by hand.
%   Nothing tested any of them before this file: they were valid because
%   whoever added one looked at it.
%
%   THE ROW-HOMOGENEITY CHECK IS THE ONE THAT MATTERS. jsondecode turns an
%   array of JSON objects into a struct array only when every object has
%   the same fields; give one row an extra key, or omit one, and it decodes
%   as a CELL array instead. readMeasuresFile then indexes raw.rows(i) and
%   reads r.label off a cell, which fails with an error naming neither the
%   file nor the row. A multi-row preset is exactly where that mistake is
%   easy to make.
%
%   Run with: runtests('tests/MeasurePresetsTest.m').
%
%   See also MEASUREDIALOG, MEASURE.

    properties (Constant)
        % MeasureDialog.MEASURE_CHOICES, restated because that property is
        % private to the dialog class. Kept in step by hand; a preset naming
        % something outside this list would load into a dropdown that has no
        % such entry.
        Measures = {'Mean Amplitude', 'Peak', 'Area', ...
            'Fractional Peak Latency', 'Fractional Area Latency'}
        Polarities = {'Positive', 'Negative'}
    end

    methods (Test)
        function everyPresetIsAUsableMeasureFile(testCase)
            files = testCase.presetFiles();
            testCase.assertNotEmpty(files, 'No presets were found to check.');

            for k = 1:numel(files)
                file = files(k);
                raw = testCase.decode(file);

                testCase.verifyTrue(isfield(raw, 'alakazamMeasures') && ...
                    isequal(raw.alakazamMeasures, true), sprintf( ...
                    '%s: readMeasuresFile refuses a file without alakazamMeasures = true.', ...
                    file.name));
                testCase.assertTrue(isfield(raw, 'rows'), sprintf( ...
                    '%s: no rows.', file.name));
                testCase.verifyTrue(isstruct(raw.rows), sprintf( ...
                    ['%s: the rows decoded as a %s rather than a struct array, which ' ...
                     'means they do not all carry the same fields. readMeasuresFile ' ...
                     'indexes them as a struct array and fails on this.'], ...
                    file.name, class(raw.rows)));
                testCase.verifyNotEmpty(raw.rows, sprintf('%s: no rows.', file.name));
            end
        end

        function everyRowCarriesWhatTheLoaderReads(testCase)
        %EVERYROWCARRIESWHATTHELOADERREADS  label, start, stop, measure,
        %   polarity, refChannel and channels are read WITHOUT a default
        %   (see readMeasuresFile); the numeric extras have defaults and are
        %   deliberately not required here.
            required = {'label', 'start', 'stop', 'measure', 'polarity', ...
                'refChannel', 'channels'};
            files = testCase.presetFiles();

            for k = 1:numel(files)
                file = files(k);
                raw = testCase.decode(file);
                if ~isfield(raw, 'rows') || ~isstruct(raw.rows)
                    continue;   % reported by the case above
                end
                for r = 1:numel(raw.rows)
                    row = raw.rows(r);
                    where = sprintf('%s row %d', file.name, r);
                    for f = required
                        testCase.verifyTrue(isfield(row, f{1}), ...
                            sprintf('%s: missing "%s".', where, f{1}));
                    end
                    testCase.verifyNotEmpty(strtrim(char(string(row.label))), ...
                        sprintf('%s: blank label.', where));
                    testCase.verifyNotEmpty(strtrim(char(string(row.channels))), ...
                        sprintf('%s: no channels.', where));
                    testCase.verifyTrue(any(strcmp(char(string(row.measure)), ...
                        MeasurePresetsTest.Measures)), sprintf( ...
                        '%s: "%s" is not one of the dialog''s measures.', ...
                        where, char(string(row.measure))));
                    testCase.verifyTrue(any(strcmp(char(string(row.polarity)), ...
                        MeasurePresetsTest.Polarities)), sprintf( ...
                        '%s: "%s" is not a polarity.', where, char(string(row.polarity))));
                    testCase.verifyLessThan(row.start, row.stop, sprintf( ...
                        '%s: the window does not run forwards.', where));
                end
            end
        end

        function bracedRoisAreBalanced(testCase)
        %BRACEDROISAREBALANCED  A pooled channel spec is written {PO7 PO8}.
        %   An unclosed brace is a typo that survives JSON perfectly well
        %   and only fails when the window is measured.
            files = testCase.presetFiles();

            for k = 1:numel(files)
                file = files(k);
                raw = testCase.decode(file);
                if ~isfield(raw, 'rows') || ~isstruct(raw.rows)
                    continue;
                end
                for r = 1:numel(raw.rows)
                    spec = char(string(raw.rows(r).channels));
                    testCase.verifyEqual(count(spec, '{'), count(spec, '}'), ...
                        sprintf('%s row %d: unbalanced braces in "%s".', ...
                        file.name, r, spec));
                end
            end
        end

        function everyPresetIsDocumented(testCase)
        %EVERYPRESETISDOCUMENTED  measure.md lists the presets, and a file
        %   added without a line there is one nobody discovers.
            root = fileparts(fileparts(mfilename('fullpath')));
            doc = fileread(fullfile(root, 'src', 'Transformations', 'Measure', 'measure.md'));
            files = testCase.presetFiles();

            for k = 1:numel(files)
                [~, stem] = fileparts(files(k).name);
                testCase.verifySubstring(doc, stem, sprintf( ...
                    'The preset "%s" is not mentioned in measure.md.', stem));
            end
        end
    end

    methods (Access = private)
        function files = presetFiles(~)
            root = fileparts(fileparts(mfilename('fullpath')));
            files = dir(fullfile(root, 'src', 'Transformations', 'Measure', ...
                'presets', '*.alm'));
        end

        function raw = decode(testCase, file)
            text = fileread(fullfile(file.folder, file.name));
            try
                raw = jsondecode(text);
            catch err
                testCase.assertFail(sprintf('%s is not valid JSON: %s', ...
                    file.name, err.message));
            end
        end
    end
end
