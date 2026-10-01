classdef EnabledWarningsFixture < matlab.unittest.fixtures.Fixture
%ENABLEDWARNINGSFIXTURE  Turn the named warnings on while the fixture is set
%   up, and put MATLAB's whole warning state back afterwards.
%
%   The counterpart of MATLAB's SuppressedWarningsFixture, for the tests
%   that check a warning IS given. verifyWarning sees only a warning that
%   is issued, and a warning that is switched off is not issued: the check
%   then reports that the code "did not issue any warnings", although it
%   reached its warning() call.
%
%   WHY A TEST NEEDS IT. Which warnings are on is one global state, shared
%   with everything that ran earlier in the MATLAB session. Several of the
%   toolboxes Alakazam calls switch every warning off around a call and on
%   again after it (EEGLAB's topoplot, erpimage and dipplot; ERPLAB's
%   studio functions). One that stops with an error in between leaves all
%   warnings off until something switches them on again. In a full run of
%   the suite that failed eight tests in five classes, while
%   FieldTrip's warnings still printed, because ft_warning switches
%   warnings on for itself. A warning check that names its warnings here
%   does not depend on what ran before it.
%
%   Apply it per test method, so that a test earlier in the same class
%   cannot undo it either:
%
%       methods (TestMethodSetup)
%           function enableTheWarningsChecked(testCase)
%               testCase.applyFixture(EnabledWarningsFixture('Alakazam:RESS:noTrials'));
%           end
%       end
%
%   A per-identifier "on" holds even when all warnings are off, so only the
%   warnings a class checks are turned on and nothing else starts printing.
%
%   WarningStateGuardPlugin, which runAlakazamTests adds to the run, is
%   the other half: it names the class that left the state changed.
%
%   See also MATLAB.UNITTEST.FIXTURES.SUPPRESSEDWARNINGSFIXTURE,
%   WARNINGSTATEGUARDPLUGIN, RUNALAKAZAMTESTS.

    properties (SetAccess = immutable)
        % The warning identifiers turned on, sorted and without repeats.
        Identifiers (1, :) string
    end

    properties (Access = private)
        % MATLAB's whole warning state as it was before setup, as warning()
        % returns it, so that teardown restores 'all' and every identifier.
        Previous
    end

    methods
        function fixture = EnabledWarningsFixture(identifiers)
        %ENABLEDWARNINGSFIXTURE  A fixture for one identifier, or several
        %   as a cellstr or string array.
            arguments
                identifiers {mustBeText, mustBeNonzeroLengthText}
            end
            fixture.Identifiers = unique(reshape(string(identifiers), 1, []));
            fixture.SetupDescription = sprintf('Turn on the warning(s) %s.', ...
                strjoin(fixture.Identifiers, ', '));
            fixture.TeardownDescription = 'Restore the warning state from before.';
        end

        function setup(fixture)
            fixture.Previous = warning();
            for id = fixture.Identifiers
                warning('on', char(id));
            end
        end

        function teardown(fixture)
            warning(fixture.Previous);
        end
    end

    methods (Access = protected)
        function tf = isCompatible(fixture, other)
            tf = isequal(fixture.Identifiers, other.Identifiers);
        end
    end
end
