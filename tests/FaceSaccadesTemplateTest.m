classdef FaceSaccadesTemplateTest < matlab.unittest.TestCase
%FACESACCADESTEMPLATETEST  templates/FaceSaccadesDeconvolution.alztemplate,
%   the analysis of Ehinger & Dimigen (2019, PeerJ, Fig. 11) on their face
%   data (Data/opendata, not under version control).
%
%   What is pinned is the part a later edit could quietly break: every
%   node's parent is an earlier node (Apply Template replays
%   resultNodes{parent}, see DimigenRiftTemplateTest for what a bad index
%   did there), both Deconvolve nodes carry the paper's settings and differ
%   only in what they return, and the comparison branch ends in an average.
%   The analysis itself was replayed on the real data when the template was
%   written: the stimulus ERP at Oz matched the authors' own script's
%   (r = 0.997).
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

        function bothDeconvolutionsFitThePapersModel(testCase)
        %BOTHDECONVOLUTIONSFITTHEPAPERSMODEL  Three event types, -1.5 to 1 s,
        %   250 uV in a 2 s window, saccade amplitude as a covariate, and
        %   nothing else modelled.
            nodes = testCase.readTemplateNodes();
            deconvolve = nodes(cellfun(@(n) strcmp(n.transformId, 'Deconvolve'), nodes));
            testCase.assertNumElements(deconvolve, 2);

            for k = 1:2
                p = deconvolve{k}.params;
                testCase.verifyEqual(reshape(p.windowMs, 1, []), [-1500 1000]);
                testCase.verifyEqual(p.artifactThresholdUv, 250);
                testCase.verifyEqual(p.artifactWindowMs, 2000);
                testCase.verifyEqual(cellstr(p.covariates), {'sac_amplitude'});
                testCase.verifyEmpty(p.otherEvents, 'Only the three event types are modelled.');
                for code = {'"stimonset"', '"saccade"', '"buttonpress"'}
                    testCase.verifySubstring(p.binScript, code{1});
                end
            end
            outputs = sort(cellfun(@(n) char(n.params.output), deconvolve, 'UniformOutput', false));
            testCase.verifyEqual(reshape(outputs, 1, []), {'average', 'trials'});
            same = rmfield(deconvolve{1}.params, 'output');
            testCase.verifyEqual(rmfield(deconvolve{2}.params, 'output'), same, ...
                'The waveforms and the trials come from the same model.');
        end

        function theComparisonBranchEndsInAnAverage(testCase)
            nodes = testCase.readTemplateNodes();
            ids = cellfun(@(n) n.transformId, nodes, 'UniformOutput', false);
            average = find(strcmp(ids, 'Average'), 1);
            testCase.assertNotEmpty(average);

            chain = {};
            k = average;
            while k >= 1
                chain{end + 1} = ids{k}; %#ok<AGROW>
                k = nodes{k}.parent;
            end
            testCase.verifyEqual(fliplr(chain), {'DefineBins', 'Baseline', 'ArtefactDetect', 'Average'});
        end
    end

    methods (Access = private)
        function nodes = readTemplateNodes(testCase)
        %READTEMPLATENODES  The node list as a cell array, parsed as
        %   Alakazam.readTemplate reads a version-2 template.
            root = fileparts(fileparts(mfilename('fullpath')));
            file = fullfile(root, 'templates', testCase.TemplateFile);
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
