classdef FieldTripFixtures
%FIELDTRIPFIXTURES  Shared scaffolding for tests that need FieldTrip.
%
%   Not a test file: it has no Test methods, so runtests() walking the tests
%   folder never tries to run it. Same role, and the same reason for
%   existing, as ReportFixtures.
%
%   Two things every source-modelling test file needs, and which existed in
%   three slightly different versions before this:
%
%     require(testCase)  skip cleanly when FieldTrip is absent
%     quietly(fn)        run something without FieldTrip's narration
%
%   THE SKIP MUST NEVER TRIGGER A DOWNLOAD. TransTools.ensureFieldTrip is
%   the app's path to FieldTrip and it is deliberately consent-gated: it can
%   pop a dialog and fetch ~400 MB. A test must do neither, so this reuses
%   an existing install if there is one and assumes out otherwise -- which
%   is why it cannot simply call ensureFieldTrip and why the logic is worth
%   having in exactly one place.
%
%   See also REPORTFIXTURES, TRANSTOOLS.ENSUREFIELDTRIP,
%   TRANSTOOLS.ISFIELDTRIPAVAILABLE.

    methods (Static)
        function require(testCase)
        %REQUIRE  Put an EXISTING FieldTrip on the path, or skip the test.
        %   Never downloads and never prompts: see the class comment.
        %   Delegates to TransTools.isFieldTripAvailable, which now also
        %   backs GenerateSourceEstimateReportAssets' own "skip, don't
        %   prompt" batch path -- one non-prompting check, not two copies
        %   of the same which()/findInstalled() logic drifting apart.
            testCase.assumeTrue(TransTools.isFieldTripAvailable(), ...
                'FieldTrip is not installed, so the source-modelling path cannot be exercised.');
        end

        function folder = dataFolder(relative, files)
        %DATAFOLDER  Where a downloaded dataset is, or '' when it is nowhere.
        %   RELATIVE is its folder under the data folder (for example
        %   'FieldTrip/natmeg2014/dipolefitting'), FILES the files that must
        %   all be there. The data folder is the ALAKAZAM_DATA environment
        %   variable, the repository's Data folder, or D:\data, in that
        %   order. Like require, this never downloads: a test assumes on a
        %   non-empty result and says where the data are to be had.
            root = fileparts(fileparts(mfilename('fullpath')));
            candidates = {getenv('ALAKAZAM_DATA'), fullfile(root, 'Data'), 'D:\data'};
            folder = '';
            for c = candidates(~cellfun(@isempty, candidates))
                where = fullfile(c{1}, relative);
                if all(cellfun(@(f) isfile(fullfile(where, f)), cellstr(files)))
                    folder = where;
                    return;
                end
            end
        end

        function varargout = quietly(fn)
        %QUIETLY  Run FN with its console output swallowed.
        %   FieldTrip narrates every inverse call ("using precomputed
        %   leadfields", "computing the solution where..."), which buries a
        %   test run's own output. Errors still propagate straight through
        %   evalc, so nothing is hidden except the narration.
            assert(isa(fn, 'function_handle')); % also keeps fn visibly used: evalc hides it
            [varargout{1:nargout}] = deal([]);
            evalc('[varargout{1:nargout}] = fn();');
        end
    end
end
