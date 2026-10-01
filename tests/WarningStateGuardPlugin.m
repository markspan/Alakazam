classdef WarningStateGuardPlugin < matlab.unittest.plugins.TestRunnerPlugin
%WARNINGSTATEGUARDPLUGIN  Keep a test class from changing which warnings the
%   classes after it see, and name the class that changed them.
%
%   Which warnings are on is one global state. A test class that leaves
%   them off, usually through a toolbox call that switched them off and
%   stopped with an error before switching them on again, silences every
%   warning check that runs after it. Those checks then fail in classes
%   that pass when run alone, and the failure names the class that was
%   silenced, not the class that silenced it.
%
%   Around each test class this plugin compares the warning state before
%   and after. When they differ it restores the state from before, so the
%   next class starts as this one did, and records the class and what it
%   changed in Leaks. runAlakazamTests lists them at the end of the run.
%
%   Only whether each warning is on or off is compared. Two states are
%   equal when every warning would be issued in one exactly when it would
%   be issued in the other, however they are written down: a test that
%   turns a warning off and restores it leaves an entry of its own behind,
%   saying the same as 'all', which is no change. 'backtrace' and
%   'verbose' only decide how a warning is printed and are left out.
%
%   EnabledWarningsFixture is the other half: a test that checks a warning
%   turns that warning on for itself, so it passes under runtests() too,
%   where this plugin is not added.
%
%   See also ENABLEDWARNINGSFIXTURE, RUNALAKAZAMTESTS.

    properties (SetAccess = private)
        % One element per test class that left the warning state changed:
        %   TestClass  the class's name, as the runner reports it
        %   Changes    one string per warning that changed, such as
        %              "all: on to off"
        Leaks = struct('TestClass', {}, 'Changes', {})
    end

    methods (Access = protected)
        function runTestClass(plugin, pluginData)
            before = warning();
            runTestClass@matlab.unittest.plugins.TestRunnerPlugin(plugin, pluginData);
            changes = WarningStateGuardPlugin.stateChanges(before, warning());
            if ~isempty(changes)
                plugin.Leaks(end + 1) = struct('TestClass', string(pluginData.Name), ...
                    'Changes', changes);
                warning(before);
            end
        end
    end

    methods (Static)
        function changes = stateChanges(before, after)
        %STATECHANGES  "id: on to off" for each warning whose state differs
        %   between two warning() states, as a 1-by-N string array.
            displayModes = ["backtrace", "verbose"];
            ids = unique(string([{before.identifier}, {after.identifier}]));
            ids = setdiff(ids, displayModes);
            changes = strings(1, 0);
            for id = ids
                was = WarningStateGuardPlugin.effectiveState(before, id);
                is = WarningStateGuardPlugin.effectiveState(after, id);
                if was ~= is
                    changes(end + 1) = sprintf('%s: %s to %s', id, was, is); %#ok<AGROW>
                end
            end
        end

        function state = effectiveState(states, id)
        %EFFECTIVESTATE  Whether warning ID is "on" or "off" under STATES:
        %   its own entry when it has one, otherwise the entry for 'all'.
            own = strcmp({states.identifier}, id);
            if ~any(own)
                own = strcmp({states.identifier}, 'all');
            end
            state = string(states(find(own, 1, 'last')).state);
        end
    end
end
