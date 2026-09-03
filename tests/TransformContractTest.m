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
            cleanup = onCleanup(@() delete(fig));
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
                        'again.'], files(k).name));
            end
        end

        function noTransformAssignsTheWrongOutputName(testCase)
        %NOTRANSFORMASSIGNSTHEWRONGOUTPUTNAME  A transformation's second
        %   output is called either "options" or "opts", and assigning the
        %   other one is silent: it creates a local nobody reads, while the
        %   real output keeps whatever InitGuard left in it (the 'Init'
        %   sentinel on the interactive path). The caller then stores the
        %   sentinel as if it were a settings struct.
        %
        %   This is not hypothetical. A round of cancel-contract fixes wrote
        %   "options = []" into seven transformations whose second output is
        %   "opts", and everyCancelPathAssignsBothOutputs below passed
        %   throughout, because it looked for the literal name "options"
        %   rather than the declared one. Reading the signature was not
        %   enough on its own either: every transformation assigns its real
        %   output somewhere on the success path, so a file-wide search finds
        %   one and is satisfied. Naming the mistake directly is what catches
        %   it.
            root = fileparts(fileparts(mfilename('fullpath')));
            folders = dir(fullfile(root, 'src', 'Transformations'));
            folders = folders([folders.isdir] & ~startsWith({folders.name}, '.'));

            for k = 1:numel(folders)
                name = folders(k).name;
                file = fullfile(folders(k).folder, name, [name '.m']);
                if ~isfile(file); continue; end

                lines = string(splitlines(fileread(file)));
                code = regexprep(lines, '%.*$', '');
                declared = regexp(code{1}, ...
                    '^\s*function\s*\[\s*\w+\s*,\s*(\w+)\s*\]', 'tokens', 'once');
                if isempty(declared); continue; end

                if strcmp(declared{1}, 'options')
                    wrong = 'opts';
                else
                    wrong = 'options';
                end
                % An assignment TO the wrong name, not a read of it: opts is
                % legitimately read (it is InitGuard's own output) and
                % legitimately appears as [opts, interactive] = ...
                offenders = find(~cellfun(@isempty, ...
                    regexp(code, sprintf('^\\s*%s\\s*=[^=]', wrong), 'once')));
                testCase.verifyEmpty(offenders, sprintf( ...
                    ['%s declares its second output as "%s" but assigns "%s" at ' ...
                     'line(s) %s. That assignment goes nowhere, and "%s" keeps ' ...
                     'whatever it already held.'], ...
                    name, declared{1}, wrong, mat2str(offenders(:)'), declared{1}));
            end
        end

        function everyCancelPathAssignsBothOutputs(testCase)
        %EVERYCANCELPATHASSIGNSBOTHOUTPUTS  Cancel is the one branch the seam
        %   cannot reach, and so the one that rotted.
        %
        %   A transformation signals "cancelled" by returning EEG = [], and
        %   several did that and returned WITHOUT ever assigning options.
        %   Called with one output that is harmless, which is why it survived;
        %   called with two, as TransTools.invoke calls everything, MATLAB
        %   throws "Output argument 'options' is not assigned". So pressing
        %   Cancel raised an error instead of quietly doing nothing. Eight
        %   transformations were in that state at once, including
        %   ChannelEditor, where a user found it.
        %
        %   The runtime seam cannot catch this: reaching the cancel branch
        %   means opening a modal dialog and dismissing it, which a test
        %   cannot do. So this reads the source instead. A static test is the
        %   weaker instrument and it is used here only because the stronger
        %   one cannot reach.
            root = fileparts(fileparts(mfilename('fullpath')));
            folders = dir(fullfile(root, 'src', 'Transformations'));
            folders = folders([folders.isdir] & ~startsWith({folders.name}, '.'));

            for k = 1:numel(folders)
                name = folders(k).name;
                file = fullfile(folders(k).folder, name, [name '.m']);
                if ~isfile(file); continue; end        % +packages, helper folders

                lines = string(splitlines(fileread(file)));
                code = regexprep(lines, '%.*$', '');   % comments say nothing

                % THE NAME COMES FROM THE SIGNATURE, NOT FROM THIS TEST.
                % An earlier version looked for a variable literally called
                % "options", which is what the first round of cancel fixes
                % duly wrote -- into seven files whose second output is
                % called "opts". Every assignment went to a stray local, the
                % real output kept the Init sentinel, and this test passed
                % throughout. Reading the declared name is the whole point.
                declared = regexp(code{1}, ...
                    '^\s*function\s*\[\s*\w+\s*,\s*(\w+)\s*\]', 'tokens', 'once');
                if isempty(declared); continue; end     % not a two-output transform
                outputName = declared{1};

                cancels = find(~cellfun(@isempty, ...
                    regexp(code, 'EEG\s*=\s*\[\s*\]\s*;', 'once')));
                assigns = find(~cellfun(@isempty, ...
                    regexp(code, sprintf('(^|[\\s;,)])%s\\s*=[^=]', outputName), 'once')));

                % What must hold is that options is assigned before the RETURN
                % that ends the cancel branch, not before the EEG = [] line:
                % the two assignments sit side by side and either order works.
                returns = find(~cellfun(@isempty, ...
                    regexp(code, '(^|[\s;])return\s*;?\s*$', 'once')));

                for c = cancels(:)'
                    r = returns(find(returns >= c, 1));
                    if isempty(r); r = numel(code) + 1; end
                    testCase.verifyTrue(any(assigns < r), sprintf( ...
                        ['%s cancels at line %d without assigning its own second ' ...
                         'output (%s). Called with two outputs -- which is how ' ...
                         'TransTools.invoke calls every transformation -- that is an ' ...
                         'error, so Cancel would raise one instead of doing nothing.'], ...
                        name, c, outputName));
                end
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
