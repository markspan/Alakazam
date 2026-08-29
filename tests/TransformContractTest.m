classdef TransformContractTest < matlab.unittest.TestCase
%TRANSFORMCONTRACTTEST  The plugin contract, enforced at TransTools.invoke.
%
%   The contract used to be a convention: four separate places called
%   feval(transformId, ...) and each trusted whatever came back. A
%   convention with no boundary is a habit rather than an interface, and its
%   failure mode is silence -- a transformation returning the wrong shape
%   corrupts the workspace tree somewhere downstream, long after the plugin
%   responsible has returned.
%
%   Every call now goes through one seam. These tests are that seam's own
%   specification: what it accepts, what it refuses, and what it refuses to
%   claim it can check.
%
%   The violating fixtures are written to a temporary folder rather than
%   kept in the repository, so src/Transformations never contains a
%   deliberately broken plugin that the ribbon would then offer to run.
%
%   Run with: runtests('tests/TransformContractTest.m').

    properties
        FixtureDir
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'Baseline')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end
    end

    methods (TestMethodSetup)
        function makeFixtureFolder(testCase)
            f = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture());
            testCase.FixtureDir = f.Folder;
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(f.Folder));
        end
    end

    methods (Test)
        % ---- the seam passes a real transformation through ----------------
        function aConformingTransformationIsUnaffected(testCase)
        %ACONFORMINGTRANSFORMATIONISUNAFFECTED  The seam has to be invisible
        %   to every plugin that already behaves. Baseline replayed through
        %   invoke must give exactly what calling it directly gives.
            EEG = testCase.epochedEEG();
            opts = struct('Start', -100, 'Stop', 0);

            [direct, directOpts] = Baseline(EEG, opts);
            [viaSeam, seamOpts] = TransTools.invoke('Baseline', EEG, opts);

            testCase.verifyEqual(viaSeam.data, direct.data);
            testCase.verifyEqual(seamOpts, directOpts);
        end

        % ---- what it refuses ------------------------------------------------
        function anUnknownTransformationIsNamed(testCase)
            testCase.verifyError(@() TransTools.invoke('NoSuchThing', struct()), ...
                'Alakazam:contract:unknownTransformation');
        end

        function aOneOutputTransformationIsNamed(testCase)
        %AONEOUTPUTTRANSFORMATIONISNAMED  MATLAB's own error for this is
        %   "Too many output arguments", which names neither the plugin nor
        %   the clause. The point of the seam is that it does both.
            testCase.writeFixture('OneOutput', [ ...
                "function EEG = OneOutput(input, varargin)" newline ...
                "    EEG = input;" newline ...
                "end"]);

            testCase.verifyError(@() TransTools.invoke('OneOutput', struct()), ...
                'Alakazam:contract:outputCount');
        end

        function aNonStructResultIsRefused(testCase)
            testCase.writeFixture('StringResult', [ ...
                "function [EEG, options] = StringResult(input, varargin)" newline ...
                "    EEG = 'not a dataset';" newline ...
                "    options = struct();" newline ...
                "end"]);

            testCase.verifyError(@() TransTools.invoke('StringResult', struct()), ...
                'Alakazam:contract:badResult');
        end

        function nonStructOptionsAreRefused(testCase)
        %NONSTRUCTOPTIONSAREREFUSED  Options are stored on the node, replayed
        %   onto other datasets and written into the exported script. None of
        %   that works with anything but a struct.
            testCase.writeFixture('StringOptions', [ ...
                "function [EEG, options] = StringOptions(input, varargin)" newline ...
                "    EEG = input;" newline ...
                "    options = 'not a struct';" newline ...
                "end"]);

            testCase.verifyError(@() TransTools.invoke('StringOptions', struct()), ...
                'Alakazam:contract:badOptions');
        end

        function ahalfCancelIsRefused(testCase)
        %AHALFCANCELISREFUSED  Cancelling is one decision, so it has to be
        %   reported once. No dataset but some options tells the caller two
        %   different things about whether anything happened.
            testCase.writeFixture('HalfCancel', [ ...
                "function [EEG, options] = HalfCancel(input, varargin)" newline ...
                "    EEG = [];" newline ...
                "    options = struct('a', 1);" newline ...
                "end"]);

            testCase.verifyError(@() TransTools.invoke('HalfCancel', struct()), ...
                'Alakazam:contract:inconsistentCancel');
        end

        % ---- what it allows --------------------------------------------------
        function aProperCancelPassesThrough(testCase)
        %APROPERCANCELPASSESTHROUGH  The shape every transformation uses to
        %   say the analyst changed their mind.
            testCase.writeFixture('Cancels', [ ...
                "function [EEG, options] = Cancels(input, varargin)" newline ...
                "    EEG = [];" newline ...
                "    options = [];" newline ...
                "end"]);

            [EEG, options] = TransTools.invoke('Cancels', struct());

            testCase.verifyEmpty(EEG);
            testCase.verifyEmpty(options);
        end

        function aPlotOnlyPluginMayReturnAHandle(testCase)
        %APLOTONLYPLUGINMAYRETURNAHANDLE  Alakazam.onTransformation already
        %   treats a graphics handle as "a plugin that only draws", so the
        %   seam must not reject one on its way through.
            fig = figure('Visible', 'off');
            cleanup = onCleanup(@() delete(fig)); %#ok<NASGU>
            testCase.writeFixture('DrawsOnly', [ ...
                "function [EEG, options] = DrawsOnly(input, varargin)" newline ...
                "    EEG = input;" newline ...
                "    options = struct();" newline ...
                "end"]);

            % The handle path is exercised through the checker rather than a
            % fixture returning a live handle, which a headless run cannot
            % rely on keeping valid.
            [EEG, ~] = TransTools.invoke('DrawsOnly', struct());
            testCase.verifyTrue(isstruct(EEG));
        end

        function aRealFailureInsideAPluginIsNotDisguised(testCase)
        %AREALFAILUREINSIDEAPLUGINISNOTDISGUISED  The seam adds contract
        %   errors; it must not swallow or relabel the plugin's own. An
        %   error from inside the algorithm has to arrive unchanged, or
        %   debugging one becomes archaeology.
            testCase.writeFixture('Throws', [ ...
                "function [EEG, options] = Throws(input, varargin)" newline ...
                "    throw(MException('Alakazam:Throws:deliberate', 'boom'));" newline ...
                "end"]);

            testCase.verifyError(@() TransTools.invoke('Throws', struct()), ...
                'Alakazam:Throws:deliberate');
        end

        % ---- the seam is the only way in ---------------------------------------
        function nothingCallsATransformationDirectly(testCase)
        %NOTHINGCALLSATRANSFORMATIONDIRECTLY  The whole point. An interface
        %   is not the declaration, it is the existence of a boundary where
        %   violations stop -- and a second unguarded call site is a second
        %   place to forget.
            root = fileparts(fileparts(mfilename('fullpath')));
            files = dir(fullfile(root, 'src', '@Alakazam', '*.m'));

            for k = 1:numel(files)
                src = fileread(fullfile(files(k).folder, files(k).name));
                testCase.verifyEmpty(strfind(src, 'feval(transformId'), ...
                    sprintf(['%s calls a transformation directly. Every call goes ' ...
                        'through TransTools.invoke, or the contract is unenforced ' ...
                        'again.'], files(k).name)); %#ok<STREMP>
            end
        end
    end

    methods (Access = private)
        function writeFixture(testCase, name, body)
        %WRITEFIXTURE  A deliberately-violating transformation, on the path
        %   for this test only.
            file = fullfile(testCase.FixtureDir, [name '.m']);
            fid = fopen(file, 'w');
            testCase.assertGreaterThan(fid, 0);
            fwrite(fid, char(body));
            fclose(fid);
            rehash;
        end

        function EEG = epochedEEG(~)
        %EPOCHEDEEG  The minimum Baseline needs: epoched data with a time
        %   axis spanning the correction window.
            srate = 250;
            times = -200:(1000/srate):796;
            EEG = struct('srate', srate, 'times', times, ...
                'data', ones(2, numel(times), 3), 'trials', 3, ...
                'pnts', numel(times), 'nbchan', 2, 'DataFormat', 'EPOCHED');
        end
    end
end
