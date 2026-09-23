classdef RecalculableTransformsTest < matlab.unittest.TestCase
%RECALCULABLETRANSFORMSTEST  Every transformation that remembers its
%   settings must offer Recalculate.
%
%   WHY THIS EXISTS. Recalculate is gated by a hand-maintained allowlist,
%   WorkSpaceTree.RecalculableTransforms, and a new transformation does not
%   fail visibly when it is left out: it simply has the context-menu item
%   greyed out, which nobody notices until they want to edit a parameter.
%   Rectify, DCDetrend, Covariance, CrossCorrelation and DeriveChannels were
%   each added without it, so this pins the rule instead of relying on
%   whoever adds the next one remembering.
%
%   THE RULE. recalculateTransformNode works by standing in for
%   TransformSettings with the node's own stored parameters and re-running
%   the transform interactively. So the test for membership is exactly
%   whether the transformation reads its stored settings when it opens its
%   dialog:
%
%     reads TransformSettings.get  ->  must be in RecalculableTransforms
%     does not                     ->  must NOT be, since its dialog would
%                                      open at defaults and silently throw
%                                      away what the user chose
%
%   There are two kinds of exception, each carrying its reason beside the
%   property that names it:
%
%     DeliberatelyExcluded  reads its settings, but must not be recalculable
%                           anyway. RemoveComponents (ICA) is the one case:
%                           ICA is not deterministic, so pre-ticking stored
%                           component indices against a freshly re-run
%                           decomposition could tick the wrong components.
%     SeededFromTheDataset  recalculable, but re-seeded from the dataset
%                           rather than from stored settings, so the
%                           TransformSettings test does not apply to it.
%                           ChannelEditor is the one case.
%
%   Run with: runtests('tests/RecalculableTransformsTest.m').

    properties (Constant)
        % Reads its settings, but deliberately not recalculable. Each entry
        % needs its reason in this file's header before it is added.
        DeliberatelyExcluded = {'RemoveComponents'}

        % Recalculable, but re-seeded from the DATASET rather than from
        % stored settings, so the TransformSettings.get test below does not
        % apply. ChannelEditorDialog(input.chanlocs, elcFile) opens on the
        % parent's own channel list, which is real data rather than a
        % default, so Recalculate is useful there. It is lossy, though: the
        % table opens on the parent's ORIGINAL channels, so a previous
        % round of edits has to be redone. Seeding the dialog from the
        % node's stored chanlocs would fix that, and is a change to
        % ChannelEditor rather than to this list.
        SeededFromTheDataset = {'ChannelEditor'}
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src')));
        end
    end

    methods (Test)
        function everyTransformThatRemembersItsSettingsIsRecalculable(testCase)
            [reseedable, ~] = testCase.surveyTransformations();
            listed = WorkSpaceTree.RecalculableTransforms;

            missing = setdiff(reseedable, [listed, testCase.DeliberatelyExcluded]);

            testCase.verifyEmpty(missing, sprintf([ ...
                'These transformations re-seed their dialog from stored ' ...
                'settings but are not in WorkSpaceTree.RecalculableTransforms, ' ...
                'so their nodes have Recalculate greyed out: %s. Add them, or ' ...
                'add them to DeliberatelyExcluded with a reason.'], ...
                strjoin(missing, ', ')));
        end

        function nothingIsRecalculableThatCannotBeReSeeded(testCase)
        %NOTHINGISRECALCULABLETHATCANNOTBERESEEDED  The other direction. A
        %   transform in the list whose dialog ignores stored settings would
        %   open at its defaults on Recalculate and quietly discard the
        %   user's parameters, which is worse than a greyed-out menu item.
            [reseedable, all] = testCase.surveyTransformations();
            listed = WorkSpaceTree.RecalculableTransforms;

            % Only judge entries that correspond to a transformation folder;
            % the list is allowed to be conservative about anything else.
            known = intersect(listed, all);
            offenders = setdiff(known, [reseedable, testCase.SeededFromTheDataset]);

            testCase.verifyEmpty(offenders, sprintf([ ...
                'These are marked recalculable but never read their stored ' ...
                'settings, so Recalculate would reopen them at defaults: %s.'], ...
                strjoin(offenders, ', ')));
        end

        function theListNamesOnlyRealTransformations(testCase)
        %THELISTNAMESONLYREALTRANSFORMATIONS  A typo or a renamed folder
        %   leaves a dead entry, which disables Recalculate silently.
            [~, all] = testCase.surveyTransformations();
            stale = setdiff(WorkSpaceTree.RecalculableTransforms, all);

            testCase.verifyEmpty(stale, sprintf( ...
                'RecalculableTransforms names transformations that do not exist: %s.', ...
                strjoin(stale, ', ')));
        end

        function theExceptionListsAreNotStale(testCase)
        %THEEXCEPTIONLISTSARENOTSTALE  An exception that no longer applies
        %   should be removed, not left to look deliberate.
            [~, all] = testCase.surveyTransformations();

            gone = setdiff(testCase.DeliberatelyExcluded, all);
            testCase.verifyEmpty(gone, sprintf( ...
                'DeliberatelyExcluded names transformations that no longer exist: %s.', ...
                strjoin(gone, ', ')));

            goneToo = setdiff(testCase.SeededFromTheDataset, all);
            testCase.verifyEmpty(goneToo, sprintf( ...
                'SeededFromTheDataset names transformations that no longer exist: %s.', ...
                strjoin(goneToo, ', ')));
        end

        function aDatasetSeededTransformIsStillRecalculable(testCase)
        %ADATASETSEEDEDTRANSFORMISSTILLRECALCULABLE  The SeededFromTheDataset
        %   escape hatch exists to let such a transform BE recalculable, so
        %   an entry that is not in the allowlist is just a mistake.
            listed = WorkSpaceTree.RecalculableTransforms;
            missing = setdiff(testCase.SeededFromTheDataset, listed);

            testCase.verifyEmpty(missing, sprintf([ ...
                'SeededFromTheDataset only excuses a transform from the ' ...
                'TransformSettings test; it still has to be recalculable: %s.'], ...
                strjoin(missing, ', ')));
        end
    end

    methods (Access = private)
        function [reseedable, all] = surveyTransformations(~)
        %SURVEYTRANSFORMATIONS  ALL is every transformation folder that has
        %   a registry entry and an entry-point function; RESEEDABLE is the
        %   subset whose entry point reads its stored settings.
        %
        %   Comment lines are stripped before looking, so a transformation
        %   that merely mentions TransformSettings in its help does not count.
            root = fileparts(fileparts(mfilename('fullpath')));
            folders = dir(fullfile(root, 'src', 'Transformations', '*'));
            folders = folders([folders.isdir]);

            all = {};
            reseedable = {};
            for k = 1:numel(folders)
                name = folders(k).name;
                if any(strncmp(name, {'.', '+', '@'}, 1))
                    continue;
                end
                dirPath = fullfile(root, 'src', 'Transformations', name);
                entry = fullfile(dirPath, [name '.m']);
                if isempty(dir(fullfile(dirPath, '*.json'))) || exist(entry, 'file') ~= 2
                    continue;   % not a registered transformation
                end
                all{end + 1} = name;   %#ok<AGROW>

                lines = splitlines(string(fileread(entry)));
                lines = lines(~startsWith(strtrim(lines), '%'));
                if contains(strjoin(lines, newline), 'TransformSettings.get')
                    reseedable{end + 1} = name;   %#ok<AGROW>
                end
            end
        end
    end
end
