classdef GrandAverageTest < matlab.unittest.TestCase
%GRANDAVERAGETEST  Unit tests for src/GrandAverage.m's compatibility
%   errors, which are the part of it an analyst actually has to act on.
%
%   Every subject's Average is cached under a name made of the
%   transformation plus a timestamp, so reporting a mismatch as
%   "Average25225213" and "Average27224649" identifies nothing: in a
%   workspace holding more than one study those two may not even be the
%   same experiment. Each dataset carries the recording it came from as
%   EEG.setname, so the errors name both.
%
%   Run with: runtests('tests/GrandAverageTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src')));
        end
    end

    methods (Test)
        function channelMismatchNamesBothRecordingAndAverage(testCase)
            files = testCase.writeSubjects( ...
                struct('setname', '12_N400_preprocessed', 'nbchan', 30, 'stem', 'Average25225213'), ...
                struct('setname', '11_P3_corrected',      'nbchan', 32, 'stem', 'Average27224649'));

            err = testCase.errorFrom(@() GrandAverage(files, false));

            testCase.verifySubstring(err.message, '11_P3_corrected / Average27224649');
            testCase.verifySubstring(err.message, '12_N400_preprocessed / Average25225213');
            testCase.verifySubstring(err.message, '32 channels');
        end

        function epochLengthMismatchIsAlsoNamed(testCase)
            files = testCase.writeSubjects( ...
                struct('setname', 'subjA', 'pnts', 50, 'stem', 'Average1'), ...
                struct('setname', 'subjB', 'pnts', 80, 'stem', 'Average2'));

            err = testCase.errorFrom(@() GrandAverage(files, false));

            testCase.verifySubstring(err.message, 'subjB / Average2');
            testCase.verifySubstring(err.message, 'subjA / Average1');
        end

        function binMismatchIsAlsoNamed(testCase)
            files = testCase.writeSubjects( ...
                struct('setname', 'subjA', 'bins', {{'Rare', 'Frequent'}}, 'stem', 'Average1'), ...
                struct('setname', 'subjB', 'bins', {{'Rare', 'Odd'}},      'stem', 'Average2'));

            err = testCase.errorFrom(@() GrandAverage(files, false));

            testCase.verifySubstring(err.message, 'subjB / Average2');
            testCase.verifySubstring(err.message, 'subjA / Average1');
        end

        function aDatasetWithoutASetnameFallsBackToTheFileStem(testCase)
        %ADATASETWITHOUTASETNAMEFALLSBACKTOTHEFILESTEM  setname can be
        %   absent or blank on a dataset built before it was set, or
        %   imported from a format that never had one. An error message
        %   must still name something rather than fail while being built.
            files = testCase.writeSubjects( ...
                struct('setname', '', 'nbchan', 30, 'stem', 'AverageOld'), ...
                struct('setname', '', 'nbchan', 32, 'stem', 'AverageNewer'));

            err = testCase.errorFrom(@() GrandAverage(files, false));

            testCase.verifySubstring(err.message, 'AverageNewer');
            testCase.verifySubstring(err.message, 'AverageOld');
            testCase.verifyEmpty(strfind(err.message, ' / ')); %#ok<STRIFCND>
        end

        function filenameStandsInWhenSetnameIsBlank(testCase)
            files = testCase.writeSubjects( ...
                struct('setname', '', 'filename', 'sub01.set', 'nbchan', 30, 'stem', 'Average1'), ...
                struct('setname', '', 'filename', 'sub02.set', 'nbchan', 32, 'stem', 'Average2'));

            err = testCase.errorFrom(@() GrandAverage(files, false));

            testCase.verifySubstring(err.message, 'sub02 / Average2');
            testCase.verifySubstring(err.message, 'sub01 / Average1');
        end
    end

    % ==================================================================== %
    methods
        function err = errorFrom(testCase, fcn)
        %ERRORFROM  The MException FCN throws, so its message can be
        %   asserted on. verifyError checks the identifier but returns no
        %   exception, and the whole point here is the wording.
            err = [];
            try
                fcn();
            catch caught
                err = caught;
            end
            testCase.assertNotEmpty(err, 'Expected a compatibility error, but none was thrown.');
            testCase.verifyEqual(err.identifier, 'Alakazam:GrandAverage');
        end

        function files = writeSubjects(testCase, varargin)
        %WRITESUBJECTS  Save one .mat per spec into a temp folder and return
        %   their paths. GrandAverage loads from disk, so the fixtures have
        %   to be real files; the stem is what ends up in the message.
            folder = fullfile(tempname());
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));

            files = cell(1, numel(varargin));
            for i = 1:numel(varargin)
                spec = varargin{i};
                EEG = testCase.averagedSubject(spec); %#ok<NASGU>
                files{i} = fullfile(folder, [spec.stem '.mat']);
                save(files{i}, 'EEG');
            end
        end

        function EEG = averagedSubject(~, spec)
            nbchan = getOr(spec, 'nbchan', 4);
            pnts   = getOr(spec, 'pnts', 50);
            bins   = getOr(spec, 'bins', {'Rare', 'Frequent'});

            EEG = struct();
            EEG.setname    = getOr(spec, 'setname', '');
            if isfield(spec, 'filename')
                EEG.filename = spec.filename;
            end
            EEG.DataFormat = 'Averaged';
            EEG.trials     = 1;
            EEG.srate      = 250;
            EEG.times      = (0:pnts - 1) / 250 * 1000;
            EEG.nbchan     = nbchan;
            EEG.chanlocs   = struct('labels', arrayfun(@(k) sprintf('Ch%d', k), ...
                1:nbchan, 'UniformOutput', false));
            EEG.data  = randn(nbchan, pnts, numel(bins));
            EEG.stErr = abs(randn(nbchan, pnts, numel(bins)));
            EEG.bindesc = struct('label', bins, ...
                'index', num2cell(1:numel(bins)), 'n', num2cell(repmat(20, 1, numel(bins))));
        end
    end
end

function value = getOr(s, name, default)
    if isfield(s, name) && ~isempty(s.(name))
        value = s.(name);
    else
        value = default;
    end
end
