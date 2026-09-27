classdef TemplateBinScriptsTest < matlab.unittest.TestCase
%TEMPLATEBINSCRIPTSTEST  Every bin script in the shipped templates parses.
%
%   The bin language refuses text before its first statement (it used to
%   drop it silently) and knows an epoch statement, so a script that parsed
%   before could, in principle, stop parsing. The templates are the scripts
%   users start from, so each DefineBins script and Deconvolve bin script in
%   templates/ is parsed here, and a DefineBins script must still compile to
%   as many bins as the template stored.
%
%   Run with: runtests('tests/TemplateBinScriptsTest.m').
%
%   See also DEFINEBINSTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'DefineBins'), ...
                     fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function everyTemplateBinScriptParses(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            files = dir(fullfile(root, 'templates', '**', '*.alztemplate'));
            testCase.assertNotEmpty(files, 'No templates found to check.');

            checked = 0;
            for f = 1:numel(files)
                path = fullfile(files(f).folder, files(f).name);
                template = jsondecode(fileread(path));
                steps = templateSteps(template);
                for k = 1:numel(steps)
                    [script, storedBins] = binScriptOf(steps(k));
                    if isempty(script)
                        continue;
                    end
                    checked = checked + 1;
                    where = sprintf('%s, step %d (%s)', files(f).name, k, steps(k).transformId);
                    try
                        spec = DefineBinsEngine.parseSpec(script);
                    catch err
                        testCase.verifyFail(sprintf('%s does not parse: %s', where, err.message));
                        continue;
                    end
                    if ~isempty(storedBins)
                        testCase.verifyNumElements(spec.bins, numel(storedBins), ...
                            sprintf('%s compiles to a different number of bins.', where));
                    end
                end
            end
            testCase.verifyGreaterThan(checked, 0, 'No bin script was found in any template.');
        end
    end
end

% ======================================================================= %
function steps = templateSteps(template)
%TEMPLATESTEPS  A template's steps, which older files call nodes.
    if isfield(template, 'steps')
        steps = template.steps;
    else
        steps = template.nodes;
    end
    if iscell(steps)
        steps = [steps{:}];
    end
end

function [script, storedBins] = binScriptOf(step)
%BINSCRIPTOF  The bin script a step carries, and the bins it stored.
    script = '';
    storedBins = [];
    if ~isfield(step, 'params') || ~isstruct(step.params)
        return;
    end
    p = step.params;
    switch step.transformId
        case 'DefineBins'
            if isfield(p, 'script'); script = char(p.script); end
            if isfield(p, 'bins'); storedBins = p.bins; end
        case 'Deconvolve'
            if isfield(p, 'binScript'); script = char(p.binScript); end
    end
end
