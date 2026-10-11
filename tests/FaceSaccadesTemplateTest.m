classdef FaceSaccadesTemplateTest < matlab.unittest.TestCase
%FACESACCADESTEMPLATETEST  library/templates/FaceSaccadesDeconvolution.alztemplate,
%   the analysis of Ehinger & Dimigen (2019, PeerJ, Fig. 11) on their face
%   data (Data/opendata, not under version control).
%
%   The template is one Deconvolve step returning the overlap-corrected
%   trials, and an Average of them. What is pinned is the part a later edit
%   could quietly break: every node's parent is an earlier node (Apply
%   Template replays resultNodes{parent}, see DimigenRiftTemplateTest for
%   what a bad index did there), the deconvolution fits the paper's model,
%   formulas included, with the choices the template states, and the
%   Average averages the trials the deconvolution returns. The analysis
%   itself was replayed on the real data when the template was written:
%   with the paper's spline of saccade amplitude, the stimulus ERP at Oz
%   matched the authors' own script's (r = 0.9998).
%
%   Run with: runtests('tests/FaceSaccadesTemplateTest.m').
%
%   See also DECONVOLVE, DIMIGENRIFTTEMPLATETEST.

    properties (Constant)
        TemplateFile = 'FaceSaccadesDeconvolution.alztemplate'
    end

    methods (Test)
        function everyParentIsAnEarlierNode(testCase)
            nodes = testCase.readTemplateNodes();
            for k = 1:numel(nodes)
                parent = nodes{k}.parent;
                testCase.verifyTrue(parent < 1 || parent < k, sprintf( ...
                    'Node %d (%s) has parent %d, which is not an earlier node.', ...
                    k, nodes{k}.transformId, parent));
            end
        end

        function theDeconvolutionFitsThePapersModel(testCase)
        %THEDECONVOLUTIONFITSTHEPAPERSMODEL  Three event types, -1.5 to 1 s,
        %   250 uV in a 2 s window, the saccade fitted with 5 splines of its
        %   amplitude and the other two with their intercept alone, and
        %   nothing else modelled; and the choices the template states
        %   rather than leaving to the dialog's defaults.
            nodes = testCase.readTemplateNodes();
            deconvolve = nodes(cellfun(@(n) strcmp(n.transformId, 'Deconvolve'), nodes));
            testCase.assertNumElements(deconvolve, 1);
            p = deconvolve{1}.params;

            testCase.verifyEqual(reshape(p.windowMs, 1, []), [-1500 1000]);
            testCase.verifyEqual(p.artifactThresholdUv, 250);
            testCase.verifyEqual(p.artifactWindowMs, 2000);
            testCase.verifyEqual({p.formulas.bin}, {'Stimulus', 'Saccade', 'Button'});
            testCase.verifyEqual({p.formulas.formula}, ...
                {'y ~ 1', 'y ~ 1 + spl(sac_amplitude, 5)', 'y ~ 1'});
            testCase.verifyFalse(isfield(p, 'covariates'), ...
                'The formulas carry the model; the older covariates would add a second one.');
            testCase.verifyEmpty(p.otherEvents, 'Only the three event types are modelled.');
            for code = {'"stimonset"', '"saccade"', '"buttonpress"'}
                testCase.verifySubstring(p.binScript, code{1});
            end
            testCase.verifyEqual({p.artifactChannels, p.marginal, p.missingValues}, ...
                {'scalp', 'AME', 'median'}, ...
                'A template states its choices, so it replays as it ran whatever the defaults.');
        end

        function theOverlapCorrectedTrialsAreAveraged(testCase)
        %THEOVERLAPCORRECTEDTRIALSAREAVERAGED  The deconvolution returns a
        %   trial for every event, each with the other events' responses
        %   taken out, and the Average is made of those trials.
            nodes = testCase.readTemplateNodes();
            ids = cellfun(@(n) n.transformId, nodes, 'UniformOutput', false);
            testCase.verifyEqual(reshape(ids, 1, []), {'Deconvolve', 'Average'});
            testCase.verifyEqual(nodes{1}.params.output, 'trials');
            testCase.verifyLessThan(nodes{1}.parent, 1, 'The deconvolution starts from the recording.');
            testCase.verifyEqual(nodes{2}.parent, 1, 'The Average is of the deconvolution''s trials.');
        end
    end

    methods (Access = private)
        function nodes = readTemplateNodes(testCase)
        %READTEMPLATENODES  The node list as a cell array, parsed as
        %   Alakazam.readTemplate reads a version-2 template.
            root = fileparts(fileparts(mfilename('fullpath')));
            file = fullfile(root, 'library', 'templates', testCase.TemplateFile);
            testCase.assertTrue(isfile(file), sprintf('Template not found: %s', file));
            raw = jsondecode(fileread(file));
            testCase.assertTrue(isfield(raw, 'nodes'), 'Template has no "nodes" list.');
            nodes = raw.nodes;
            if isstruct(nodes)
                nodes = num2cell(nodes);
            end
        end
    end
end
