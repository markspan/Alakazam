classdef (TestTags = {'Slow'}) FieldTripTutorialErpTest < matlab.unittest.TestCase
%FIELDTRIPTUTORIALERPTEST  The library's FieldTrip ERP template against
%   FieldTrip's own tutorial, on the tutorial's recording.
%
%   FieldTrip's tutorial (tutorial/sensor/preprocessing_erp) reads a 64-channel
%   BrainVision recording of words judged in two tasks, cuts a trial from 200
%   ms before to 1000 ms after each word, low-passes at 100 Hz, re-references
%   to the linked mastoids (the left one the implicit reference), derives two
%   bipolar EOG channels, rejects eight trials it finds by eye and averages
%   each task. library/templates/fieldtrip/preprocessing-erp.alztemplate does
%   the same in Alakazam. Here the template is replayed as Apply Template
%   replays it (every step through TransTools.invoke, on its parent's result)
%   and FieldTrip's tutorial is run beside it, and the two averages are
%   compared on every channel, both tasks and their difference.
%
%   WHAT THEY SHOULD SHARE, AND DO (8 October 2026):
%     the trials: all 192 words locked to the same samples, 92 per task kept;
%     without the low-pass on either side, the averages, to 3e-6 uV (EEGLAB
%       reads the recording in single precision, FieldTrip in double);
%     with FieldTrip's own 6th-order Butterworth on both, applied to the whole
%       recording before the trials are cut, the same.
%   WHERE THEY DIFFER, AND WHY:
%     the filter, as shipped: the template's low-pass is Filter's Kaiser FIR
%       on the whole recording, the tutorial's a Butterworth on each 1.2 s
%       trial alone. The averages differ by 0.026 uV RMS against a signal of
%       5 uV, and by up to 1.1 uV at the first sample, which is the trial's
%       edge in the tutorial's filtering: FieldTrip's own Butterworth on the
%       whole recording is within 0.0012 uV RMS of Alakazam's inside the
%       epoch and differs from the tutorial by that 1 uV at its edges.
%     the last sample: FieldTrip's trial keeps both ends (601 samples, to
%       1000 ms), and Alakazam cuts as EEGLAB's pop_epoch does, up to the end
%       (600, to 998 ms). The comparisons are on the 600 they share.
%
%   THE DATA: s04.vhdr, s04.vmrk and s04.eeg (143 MB) from
%   https://download.fieldtriptoolbox.org/tutorial/preprocessing_erp/, in
%   FieldTrip/preprocessing_erp under the data folder (see
%   FieldTripFixtures.dataFolder). The test skips without them, and never
%   downloads them. The tutorial's trial function, trialfun_affcog, is not run
%   from there: its rule (a word, S141, and the task code that follows it,
%   S131 or S132) is restated in fieldtripTutorial below.
%
%   See also LIBRARYREPLAYTEST, FIELDTRIPTUTORIALDIPOLETEST, DERIVECHANNELS.

    properties (Constant)
        Files = {'s04.vhdr', 's04.vmrk', 's04.eeg'}
        Url = 'https://download.fieldtriptoolbox.org/tutorial/preprocessing_erp/'
        Template = fullfile('fieldtrip', 'preprocessing-erp.alztemplate')
        Rejected = [22 42 89 90 92 126 136 150]
    end

    properties
        Folder
        Nodes
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = FieldTripTutorialErpTest.root();
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations'), 'IncludeSubfolders', true));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src', 'Support')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src', 'IO')));
            try
                EEGLabEnvironment.ensure();
            catch
                % The assumption below says what is missing.
            end
            testCase.assumeTrue(~isempty(which('pop_loadbv')) && ~isempty(which('firfilt')), ...
                'EEGLAB with its BrainVision reader and firfilt is not on the path.');
            FieldTripFixtures.require(testCase);
        end

        function findTheData(testCase)
            testCase.Folder = FieldTripFixtures.dataFolder(fullfile('FieldTrip', 'preprocessing_erp'), ...
                testCase.Files);
            testCase.assumeNotEmpty(testCase.Folder, sprintf(['FieldTrip''s ERP tutorial recording ' ...
                '(%s) is not under FieldTrip/preprocessing_erp in ALAKAZAM_DATA, Data or D:\\data; ' ...
                'it is at %s.'], strjoin(testCase.Files, ', '), testCase.Url));
        end

        function readTheTemplate(testCase)
            testCase.Nodes = templateNodes(fullfile(FieldTripTutorialErpTest.root(), 'library', ...
                'templates', testCase.Template));
        end
    end

    methods (Test)
        function withoutTheLowPassTheyAreTheSame(testCase)
            nodes = testCase.Nodes(~strcmp({testCase.Nodes.transformId}, 'Filter'));
            nodes = reparent(nodes, testCase.Nodes);
            alakazam = testCase.replay(nodes);
            fieldtrip = FieldTripFixtures.quietly(@() fieldtripTutorial(testCase.Folder, 'nofilter', ...
                testCase.Rejected));

            testCase.verifyEqual([alakazam.bindesc(1:2).n], fieldtrip.n, ...
                'The same trials per task, after the same eight are rejected.');
            [worst, ~] = compareAverages(alakazam, fieldtrip);
            testCase.verifyLessThan(worst, 1e-4, sprintf(['Without a low-pass the averages differ by ' ...
                'up to %.3g uV.'], worst));
        end

        function withTheTutorialsButterworthTheyAreTheSame(testCase)
            nodes = testCase.Nodes;
            k = strcmp({nodes.transformId}, 'Filter');
            butter6 = designfilt('lowpassiir', 'FilterOrder', 6, 'HalfPowerFrequency', 100, ...
                'SampleRate', 500, 'DesignMethod', 'butter');
            nodes(k).params.lowpass.enabled = false;
            nodes(k).params.designed = designedFilterFromObject(butter6, 'butter6', 500);
            alakazam = testCase.replay(nodes);
            fieldtrip = FieldTripFixtures.quietly(@() fieldtripTutorial(testCase.Folder, 'continuous', ...
                testCase.Rejected));

            [worst, ~] = compareAverages(alakazam, fieldtrip);
            testCase.verifyLessThan(worst, 1e-4, sprintf(['FieldTrip''s Butterworth on the whole ' ...
                'recording, on both sides: the averages differ by up to %.3g uV.'], worst));
        end

        function asShippedTheyDifferByTheFilterAlone(testCase)
            alakazam = testCase.replay(testCase.Nodes);
            published = FieldTripFixtures.quietly(@() fieldtripTutorial(testCase.Folder, 'published', ...
                testCase.Rejected));
            whole = FieldTripFixtures.quietly(@() fieldtripTutorial(testCase.Folder, 'continuous', ...
                testCase.Rejected));

            [worst, overall] = compareAverages(alakazam, published);
            testCase.verifyLessThan(overall, 0.05, sprintf(['Against the tutorial as published, %.3g ' ...
                'uV RMS: more than its filter explains.'], overall));
            testCase.verifyLessThan(worst, 1.5, sprintf('Up to %.3g uV.', worst));
            [worstWhole, overallWhole] = compareAverages(alakazam, whole);
            testCase.verifyLessThan(worstWhole, 0.25, sprintf(['Against the tutorial''s filter on ' ...
                'the whole recording, up to %.3g uV (%.3g RMS): the two filters'' designs differ ' ...
                'by no more than that.'], worstWhole, overallWhole));
        end
    end

    methods (Test)
        function theExportedFieldTripScriptGivesAlakazamsAverages(testCase)
        %THEEXPORTEDFIELDTRIPSCRIPTGIVESALAKAZAMSAVERAGES  Export as FieldTrip,
        %   run the script it writes, and get Alakazam's averages back: every
        %   step of this template is exact or a decision read back, so the
        %   script should agree to rounding (see EXPORTFIELDTRIPSCRIPT).
            [alakazam, results, raw] = testCase.replay(testCase.Nodes);
            nodes = testCase.Nodes;
            contexts = struct('srate', {}, 'labels', {}, 'format', {}, 'decision', {});
            for k = 1:numel(nodes)
                if nodes(k).parent < 1
                    input = raw;
                else
                    input = results{nodes(k).parent};
                end
                contexts(k) = fieldtripStepContext(nodes(k).transformId, input, results{k});
            end
            subject = struct('name', 's04', 'rawFile', fullfile(testCase.Folder, 's04.vhdr'), ...
                'steps', rmfield(nodes, setdiff(fieldnames(nodes), {'transformId', 'params', 'parent'})), ...
                'contexts', contexts);
            [code, sidecars] = exportFieldTripScript(subject);
            testCase.verifyEmpty(regexp(code, '%\s+\d+\s+\S+\s+(NOT TRANSLATED|APPROXIMATE)', 'once'), ...
                'Every step of this template should be exact or a decision.');

            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            script = fullfile(folder, 'erp_fieldtrip.m');
            writeText(script, code);
            for k = 1:numel(sidecars)
                writeText(fullfile(folder, sidecars(k).name), sidecars(k).content);
            end
            exported = runScript(script);
            erp = exported.s04;
            for b = 1:3
                [~, a, f] = intersect({alakazam.chanlocs.labels}, erp{b}.label, 'stable');
                testCase.assertNumElements(a, 59);
                testCase.assertEqual(round(erp{b}.time * 1000), round(alakazam.times), ...
                    'The trials the script cut are Alakazam''s, sample for sample.');
                d = double(alakazam.data(a, :, b)) - erp{b}.avg(f, :);
                testCase.verifyLessThan(max(abs(d(:))), 1e-4, sprintf(['Bin %d (%s): the exported ' ...
                    'script''s average differs from Alakazam''s by up to %.3g uV.'], b, ...
                    alakazam.bindesc(b).label, max(abs(d(:)))));
            end
        end
    end

    methods (Access = private)
        function [EEG, results, raw] = replay(testCase, nodes)
        %REPLAY  The recording as the workspace loads a .vhdr (loadBVAFile),
        %   then every node on its parent's result, as onApplyTemplate does.
            cache = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            raw = pop_loadbv(testCase.Folder, 's04.vhdr');
            raw = eeg_checkset(raw);
            raw = recordRawFile(raw, fullfile(testCase.Folder, 's04.vhdr'));
            raw.times = ((1:raw.pnts) - 1) / raw.srate;
            raw.DataType = 'TIMEDOMAIN';
            raw.DataFormat = 'CONTINUOUS';
            raw.File = fullfile(cache, 's04.mat');
            results = cell(1, numel(nodes));
            for k = 1:numel(nodes)
                if nodes(k).parent < 1
                    input = raw;
                else
                    input = results{nodes(k).parent};
                end
                results{k} = FieldTripFixtures.quietly(@() ...
                    TransTools.invoke(nodes(k).transformId, input, nodes(k).params));
                results{k}.File = resultCacheFile(input.File, nodes(k).transformId);
            end
            EEG = results{end};
        end
    end

    methods (Static, Access = private)
        function r = root()
            r = fileparts(fileparts(mfilename('fullpath')));
        end
    end
end

% ======================================================================= %
function out = fieldtripTutorial(folder, variant, rejected)
%FIELDTRIPTUTORIAL  FieldTrip's preprocessing_erp tutorial, step by step.
%   VARIANT: 'published' (as written, a 100 Hz Butterworth on each trial),
%   'nofilter', or 'continuous' (that Butterworth on the whole recording, the
%   trials cut afterwards). REJECTED are the trials its summary view rejects.
    vhdr = fullfile(folder, 's04.vhdr');
    % trialfun_affcog's rule: every word (S141), with the task its next
    % event names (S131 affective, S132 ontological), 0.2 s before to 1 s after.
    hdr = ft_read_header(vhdr);
    event = ft_read_event(vhdr);
    values = {event.value};
    samples = [event.sample];
    words = find(strcmp(values, 'S141'));
    task = 1 + strcmp(values(words + 1), 'S132');
    pre = round(0.2 * hdr.Fs);
    post = round(1 * hdr.Fs);
    trl = [samples(words)' - pre, samples(words)' + post, -pre * ones(numel(words), 1), task'];

    reference = struct('implicitref', 'LM', 'reref', 'yes', 'refchannel', {{'LM', 'RM'}});
    switch variant
        case {'published', 'nofilter'}
            cfg = reference;
            cfg.dataset = vhdr;
            cfg.trl = trl;
            cfg.demean = 'yes';
            cfg.baselinewindow = [-0.2 0];
            if strcmp(variant, 'published')
                cfg.lpfilter = 'yes';
                cfg.lpfreq = 100;
            end
            data = ft_preprocessing(cfg);
        case 'continuous'
            cfg = reference;
            cfg.dataset = vhdr;
            cfg.lpfilter = 'yes';
            cfg.lpfreq = 100;
            data = ft_redefinetrial(struct('trl', trl), ft_preprocessing(cfg));
            data = ft_preprocessing(struct('demean', 'yes', 'baselinewindow', [-0.2 0]), data);
    end

    eogv = ft_preprocessing(struct('channel', {{'53', 'LEOG'}}, 'reref', 'yes', 'implicitref', [], ...
        'refchannel', {{'53'}}), data);
    eogv = ft_selectdata(struct('channel', 'LEOG'), eogv);
    eogv.label = {'eogv'};
    eogh = ft_preprocessing(struct('channel', {{'57', '25'}}, 'reref', 'yes', 'implicitref', [], ...
        'refchannel', {{'57'}}), data);
    eogh = ft_selectdata(struct('channel', '25'), eogh);
    eogh.label = {'eogh'};
    data = ft_selectdata(struct('channel', setdiff(1:60, [53, 57, 25])), data);
    data = ft_appenddata(struct(), data, eogv, eogh);

    clean = ft_selectdata(struct('trials', setdiff(1:numel(data.trial), rejected)), data);
    one = find(clean.trialinfo == 1);
    two = find(clean.trialinfo == 2);
    task1 = ft_timelockanalysis(struct('trials', one), clean);
    task2 = ft_timelockanalysis(struct('trials', two), clean);
    out = struct('label', {task1.label}, 'time', task1.time, ...
        'avg', cat(3, task1.avg, task2.avg, task1.avg - task2.avg), 'n', [numel(one) numel(two)]);
end

function [worst, overall] = compareAverages(EEG, fieldtrip)
%COMPAREAVERAGES  Largest and RMS difference (uV) over every channel, both
%   tasks and their difference, on the samples both have.
    [shared, a, f] = intersect({EEG.chanlocs.labels}, fieldtrip.label, 'stable');
    assert(numel(shared) == numel(fieldtrip.label), 'Not every channel of the tutorial is there.');
    [~, ta, tf] = intersect(round(EEG.times), round(fieldtrip.time * 1000));
    assert(numel(ta) >= numel(fieldtrip.time) - 1, 'Too few shared samples.');
    d = double(EEG.data(a, ta, 1:3)) - fieldtrip.avg(f, tf, :);
    worst = max(abs(d(:)));
    overall = rms(d(:));
end

function results = runScript(file)
%RUNSCRIPT  Run an exported script, quietly, and return its RESULTS.
    results = struct(); %#ok<NASGU> assigned by the script
    evalc('run(file)');
end

function writeText(file, text)
    fid = fopen(file, 'w');
    fwrite(fid, text, 'char');
    fclose(fid);
end

function nodes = templateNodes(file)
%TEMPLATENODES  A version-2 template as Apply Template reads it.
    raw = jsondecode(fileread(file));
    items = raw.nodes;
    if ~iscell(items)
        items = num2cell(items);
    end
    nodes = struct('transformId', cellfun(@(it) char(it.transformId), items(:)', 'UniformOutput', false), ...
        'params', cellfun(@(it) it.params, items(:)', 'UniformOutput', false), ...
        'parent', cellfun(@(it) double(it.parent), items(:)', 'UniformOutput', false));
end

function nodes = reparent(nodes, original)
%REPARENT  Parents renumbered after nodes were taken out of a chain: each
%   node's parent is the nearest kept ancestor.
    kept = ismember({original.transformId}, {nodes.transformId});
    newIndex = cumsum(kept);
    for k = 1:numel(nodes)
        orig = find(strcmp({original.transformId}, nodes(k).transformId), 1);
        p = original(orig).parent;
        while p >= 1 && ~kept(p)
            p = original(p).parent;
        end
        if p < 1
            nodes(k).parent = -1;
        else
            nodes(k).parent = newIndex(p);
        end
    end
end
