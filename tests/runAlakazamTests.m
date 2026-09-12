function results = runAlakazamTests(scope, opts)
%RUNALAKAZAMTESTS  Run the test suite, quickly or in full.
%   RESULTS = runAlakazamTests() runs the quick suite: everything except
%   the cases tagged Slow.
%   RESULTS = runAlakazamTests("full") runs all of it.
%   RESULTS = runAlakazamTests("slow") runs only the slow cases, which is
%   what to do after touching source estimation, cluster statistics or the
%   report generators.
%
%   runAlakazamTests(..., "Report", true) also lists the ten slowest cases,
%   which is how the Slow tags were decided and how they should be revised.
%
%   WHY THE SPLIT EXISTS. The suite grew past the point where running it
%   after every edit was realistic, and a suite that is too slow to run is
%   one that stops being run. What makes it slow is not the number of
%   cases: it is a handful of them standing up real machinery, a FieldTrip
%   leadfield over thousands of dipoles, a permutation test, a Quarto
%   render that shells out to R. Those are worth their cost and are not
%   worth paying on every save.
%
%   THE TAGS WERE ALREADY THERE. Nine test classes have marked their heavy
%   cases TestTags = {'Slow'} for some time, several of them adding
%   'External' for needing R, quarto or a compiled mex alongside, and
%   QuartoReportKnownGapTest carries 'KnownGap' with a comment saying a
%   default run can exclude it and stay green. Nothing ever selected on
%   any of them: every run was the whole suite. This function is the half
%   that was missing, not a new convention.
%
%   WHAT "SLOW" MEANS. Wall clock, measured, and nothing else. A tagged
%   case is not a lesser test, it is one that does not have to run on
%   every save. It still has to pass before anything is pushed, which is
%   what "full" is for.
%
%   HOW TO TAG. The established form marks a block of methods, which is
%   usually right: most classes are quick apart from one or two cases.
%
%       methods (Test, TestTags = {'Slow'})
%
%   A class that is heavy all the way through can be tagged at class
%   level instead, which covers every case in it.
%
%       classdef (TestTags = {'Slow'}) SomethingHeavyTest < ...
%
%   Run with "Report" after adding cases, and move the tag if the ordering
%   has changed: a tag left where it no longer belongs is how a quick
%   suite stops being quick.
    arguments
        scope (1, 1) string {mustBeMember(scope, ["quick", "full", "slow"])} = "quick"
        opts.Report (1, 1) logical = false
    end

    import matlab.unittest.TestSuite
    import matlab.unittest.selectors.HasTag

    folder = fileparts(mfilename('fullpath'));
    initialiseEEGLab(folder);
    suite = TestSuite.fromFolder(folder);

    switch scope
        case "quick"
            suite = suite.selectIf(~HasTag('Slow'));
        case "slow"
            suite = suite.selectIf(HasTag('Slow'));
    end

    if isempty(suite)
        fprintf('=== no tests selected for scope "%s" ===\n', scope);
        results = matlab.unittest.TestResult.empty;
        return;
    end

    started = tic;
    results = suite.run();
    elapsed = toc(started);

    fprintf('\n=== %s: PASS %d FAIL %d SKIP %d of %d, %s ===\n', ...
        upper(scope), nnz([results.Passed]), nnz([results.Failed]), ...
        nnz([results.Incomplete]), numel(results), durationText(elapsed));

    failed = results([results.Failed]);
    if ~isempty(failed)
        fprintf('\nfailed:\n');
        fprintf('  %s\n', failed.Name);
    end

    if opts.Report
        reportSlowest(results);
    end
end

% ======================================================================= %
function reportSlowest(results)
%REPORTSLOWEST  The ten slowest cases, and the ten slowest classes.
%   The class total is the more useful of the two, since Slow is tagged per
%   class: one heavy case in a class of thirty is a different decision from
%   thirty cases of a second each.
    [~, order] = sort([results.Duration], 'descend');
    fprintf('\nslowest cases:\n');
    for k = 1:min(10, numel(order))
        r = results(order(k));
        fprintf('  %7.2f s  %s\n', r.Duration, r.Name);
    end

    classNames = arrayfun(@(r) string(extractBefore(r.Name + "/", "/")), results);
    [uniqueNames, ~, group] = unique(classNames);
    totals = accumarray(group, reshape([results.Duration], [], 1));
    [totals, order] = sort(totals, 'descend');

    fprintf('\nslowest classes:\n');
    for k = 1:min(10, numel(order))
        fprintf('  %7.2f s  %s\n', totals(k), uniqueNames(order(k)));
    end
end

% ======================================================================= %
function initialiseEEGLab(testFolder)
%INITIALISEEEGLAB  Put EEGLAB and its subfolders on the path before the
%   suite runs, so the EEGLAB-dependent cases actually execute.
%
%   Many cases gate themselves on an EEGLAB function being present
%   (assumeTrue(exist('eeg_interp','file')==2), and similar) and SKIP when
%   it is not. Nothing here used to initialise EEGLAB, so whether those
%   cases ran depended entirely on whatever the developer happened to have
%   on their saved MATLAB path. That silently stopped being true when EEGLAB
%   updated itself: having eeglab.m on the path is not enough, because
%   EEGLAB only adds its own subfolders (pop_reref, eeg_interp, firfilt, ...)
%   when eeglab() itself runs, and the saved path was left holding just the
%   root. The result was 37 cases quietly reporting "filtered by
%   assumption" instead of testing anything, including the whole of
%   ReRefTest and NativeExportEquivalenceTest.
%
%   A skip is not a pass, so the suite should not leave this to chance.
%   Failing to initialise is reported and left to the individual
%   assumptions rather than aborting the run: the great majority of cases
%   need no EEGLAB at all and should still run on a machine without it.
    if ~isempty(which('pop_reref'))
        return;   % already initialised in this session
    end
    srcFolder = fullfile(fileparts(testFolder), 'src');
    if exist(srcFolder, 'dir')
        addpath(srcFolder);
    end
    try
        EEGLabEnvironment.ensure();
    catch err
        fprintf(['=== EEGLAB could not be initialised (%s), so its cases will ' ...
                 'skip rather than run ===\n'], err.identifier);
        return;
    end
    if isempty(which('pop_reref'))
        fprintf(['=== EEGLAB is on the path but its subfolders are not, so its ' ...
                 'cases will skip rather than run ===\n']);
    end
end

% ======================================================================= %
function text = durationText(seconds)
    if seconds < 90
        text = sprintf('%.1f s', seconds);
    else
        text = sprintf('%d m %02d s', floor(seconds / 60), round(mod(seconds, 60)));
    end
end
