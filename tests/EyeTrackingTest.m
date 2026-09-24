classdef EyeTrackingTest < matlab.unittest.TestCase
%EYETRACKINGTEST  Joining an EyeLink recording onto its EEG.
%
%   THE FIXTURE IS A SESSION RECORDED ON TWO CLOCKS. The EEG runs at 500 Hz;
%   the eye tracker at 1000 Hz on its own clock, which starts at an
%   arbitrary 5,000,000 ms and runs a little fast against the EEG's (40 ppm,
%   the order two independent crystals differ by). Both received the same
%   numbered triggers. That is what EYE-EEG's synchronisation exists for,
%   and the .asc file is written in EyeLink's own text format (a SAMPLES
%   header, tab-separated samples, MSG lines carrying "MYKEYWORD <code>",
%   ESACC and EFIX lines for the tracker's own events), so the real parser
%   reads it and the real import joins it.
%
%   What the toolbox-free cases pin is the part that is Alakazam's own:
%   finding the file by name, refusing without one, never writing into the
%   raw directory when an .edf is converted, the sync-quality summary, and
%   EYE channels no longer counting as scalp EEG.
%
%   Run with: runtests('tests/EyeTrackingTest.m').
%
%   See also EYETRACKING, EYEEEG.FINDEYEFILE, EYEEEG.SYNCQUALITY.

    properties (Constant)
        Base = 'subject1myex'
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Reports'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'EyeTracking'), ...
                     fullfile(root, 'tests'), fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function theEyeFileIsFoundByTheRecordingsName(testCase)
            folder = testCase.tempFolder();
            EEG = EyeTrackingTest.datasetFrom(fullfile(folder, [EyeTrackingTest.Base '.set']));
            asc = fullfile(folder, [EyeTrackingTest.Base '.asc']);
            writeText(asc, 'placeholder');

            [found, how] = EyeEeg.findEyeFile(EEG);

            testCase.verifyEqual(found, asc);
            testCase.verifyEqual(how, 'found');
        end

        function aDerivedNodeStillFindsIt(testCase)
        %ADERIVEDNODESTILLFINDSIT  The raw path travels in EEG.etc, which
        %   every transformation passes on, so a node several steps down the
        %   branch finds the same file.
            folder = testCase.tempFolder();
            EEG = EyeTrackingTest.datasetFrom(fullfile(folder, [EyeTrackingTest.Base '.vhdr']));
            EEG.data = EEG.data * 2;         % a transformation happened
            EEG.filename = 'Filter23204236.mat';
            writeText(fullfile(folder, [EyeTrackingTest.Base '.asc']), 'placeholder');

            found = EyeEeg.findEyeFile(EEG);

            testCase.verifySubstring(found, [EyeTrackingTest.Base '.asc']);
        end

        function withoutAnEyeFileItSaysWhereItLooked(testCase)
            folder = testCase.tempFolder();
            EEG = EyeTrackingTest.datasetFrom(fullfile(folder, [EyeTrackingTest.Base '.set']));

            err = caught(@() EyeEeg.findEyeFile(EEG));

            testCase.verifyEqual(err.identifier, 'Alakazam:EyeEeg:NoEyeFile');
            testCase.verifySubstring(err.message, [EyeTrackingTest.Base '.asc']);
        end

        function anEdfWithoutAConverterAsksForTheAsc(testCase)
            folder = testCase.tempFolder();
            EEG = EyeTrackingTest.datasetFrom(fullfile(folder, [EyeTrackingTest.Base '.set']));
            writeText(fullfile(folder, [EyeTrackingTest.Base '.edf']), 'binary');

            err = caught(@() EyeEeg.findEyeFile(EEG, 'Edf2asc', 'none'));

            testCase.verifyEqual(err.identifier, 'Alakazam:EyeEeg:NeedsAsc');
            testCase.verifySubstring(err.message, 'edf2asc');
        end

        function anEdfIsConvertedWithoutTouchingTheRawDirectory(testCase)
        %ANEDFISCONVERTEDWITHOUTTOUCHINGTHERAWDIRECTORY  Raw data stays as it
        %   was recorded: the conversion runs on a copy elsewhere.
            folder = testCase.tempFolder();
            EEG = EyeTrackingTest.datasetFrom(fullfile(folder, [EyeTrackingTest.Base '.set']));
            writeText(fullfile(folder, [EyeTrackingTest.Base '.edf']), 'binary');
            before = dir(folder);

            [found, how] = EyeEeg.findEyeFile(EEG, 'Edf2asc', @fakeConverter);

            testCase.verifyEqual(how, 'converted');
            testCase.verifyTrue(isfile(found));
            testCase.verifyFalse(startsWith(found, folder), 'The .asc was written elsewhere.');
            testCase.verifyEqual(sort({dir(folder).name}), sort({before.name}), ...
                'Nothing was added to the raw directory.');
        end

        function syncQualityIsSummarisedFromEyeEegsTable(testCase)
            table = [(-4:4)', [0 0 0 2 90 6 0 0 1]'];

            q = EyeEeg.syncQuality(table, 500, 120);

            testCase.verifyEqual(q.nShared, 99);
            testCase.verifyEqual(q.pctMatched, 100 * 99 / 120, 'AbsTol', 1e-9);
            testCase.verifyEqual(q.nWithinOne, 98);
            testCase.verifyEqual(q.maxAbsSamples, 4);
            testCase.verifyEqual(q.meanAbsMs, (2 + 6 + 4) / 99 * 2, 'AbsTol', 1e-9);
        end

        function theJoinReachesTheDataQualityReport(testCase)
        %THEJOINREACHESTHEDATAQUALITYREPORT  EEG.etc travels down the branch,
        %   so the epoched node the report reads still carries the record of
        %   the join made on its continuous ancestor, and it becomes a
        %   provenance row with its numbers in columns rather than prose.
            EEG = makeTestEEG('trials', 8);
            EEG.etc.alz.eyeTracking = EyeTrackingTest.joinRecord();

            q = dataQualityMetrics(EEG);

            row = q.provenance(strcmp({q.provenance.step}, 'EyeTracking'));
            testCase.assertNumElements(row, 1);
            testCase.verifyEqual([row.n row.n_total], [31 32]);
            testCase.verifyEqual(row.pct_within_one, 96.8, 'AbsTol', 1e-9);
            testCase.verifyEqual(row.mean_offset_ms, 0.4, 'AbsTol', 1e-9);
            testCase.verifyEqual(row.threshold, 90);
            testCase.verifySubstring(row.detail, 'anchored on 100 and 200');
        end

        function aDatasetWithoutAJoinHasNoSuchRow(testCase)
            q = dataQualityMetrics(makeTestEEG('trials', 8));

            testCase.verifyFalse(any(strcmp({q.provenance.step}, 'EyeTracking')));
        end

        function eyeElectrodesNamedByPositionAreEog(testCase)
        %EYEELECTRODESNAMEDBYPOSITIONAREEOG  Orbital electrodes labelled by
        %   where they sit (LO1, IO2, ...) rather than by type. EYE-EEG's own
        %   reading data carries LO1, LO2, IO1 and IO2, and counting them as
        %   scalp EEG put the recording's largest swings into every scan.
        %   Matched as whole labels, so nothing that merely contains the
        %   letters (O1, PO7, OI1) is caught.
            labels = {'Cz', 'LO1', 'IO2', 'SO1', 'LOC', 'ROC', 'O1', 'PO7', 'Oz', 'OI1', 'POO9'};
            chanlocs = struct('labels', labels, 'type', repmat({''}, 1, numel(labels)));

            testCase.verifyEqual(eegChannelMask(chanlocs), ...
                [true false false false false false true true true true true]);
        end

        function eyeChannelsAreNotScalpEeg(testCase)
        %EYECHANNELSARENOTSCALPEEG  EYE-EEG types its gaze and pupil channels
        %   EYE. They are pixels and pupil units, and counting them as EEG put
        %   them in every display scale, artefact scan and ICA.
            chanlocs = struct('labels', {'Cz', 'L_GAZE_X', 'L_AREA'}, 'type', {'', 'EYE', 'EYE'});

            testCase.verifyEqual(eegChannelMask(chanlocs), [true false false]);
        end
    end

    methods (Test, TestTags = {'External'})
        function itJoinsTheEyeTrackOntoTheEeg(testCase)
            testCase.assumeTrue(EyeEeg.isAvailable(), 'EYE-EEG is not installed.');
            folder = testCase.tempFolder();
            EEG = EyeTrackingTest.session(folder);

            joined = EyeTracking(EEG, struct('keyword', 'MYKEYWORD'));

            added = joined.chanlocs(3:end);
            testCase.verifyEqual({added.labels}, {'L-GAZE-X', 'L-GAZE-Y', 'L-AREA'}, ...
                'EYE-EEG''s own naming: underscores become hyphens on the channels.');
            testCase.verifyEqual(unique({added.type}), {'EYE'});
            testCase.verifyEqual(size(joined.data, 2), size(EEG.data, 2), ...
                'The eye track is resampled onto the EEG''s own samples.');
            testCase.verifyEqual(joined.times, EEG.times, 'Alakazam keeps its own time axis.');
            quality = joined.etc.alz.eyeTracking.quality;
            testCase.verifyEqual(quality.nShared, 32, 'Every trigger was found in both.');
            testCase.verifyEqual(quality.pctWithinOne, 100);
        end

        function theGazeLandsOnTheRightSamples(testCase)
        %THEGAZELANDSONTHERIGHTSAMPLES  The point of synchronising: a gaze
        %   step the tracker saw 20 s into the session appears 20 s into the
        %   EEG, not at wherever the tracker's own clock would put it.
            testCase.assumeTrue(EyeEeg.isAvailable(), 'EYE-EEG is not installed.');
            folder = testCase.tempFolder();
            EEG = EyeTrackingTest.session(folder);

            joined = EyeTracking(EEG, struct('keyword', 'MYKEYWORD'));

            x = joined.data(strcmp({joined.chanlocs.labels}, 'L-GAZE-X'), :);
            stepAt = (find(x > 700, 1) - 1) / joined.srate;     % sample 1 is time 0
            testCase.verifyEqual(stepAt, 20, 'AbsTol', 0.004, ...
                'Within two EEG samples of where the step really was.');
        end

        function theTrackersOwnEventsArrive(testCase)
            testCase.assumeTrue(EyeEeg.isAvailable(), 'EYE-EEG is not installed.');
            folder = testCase.tempFolder();
            EEG = EyeTrackingTest.session(folder);

            joined = EyeTracking(EEG, struct('keyword', 'MYKEYWORD'));

            types = cellfun(@(t) char(string(t)), {joined.event.type}, 'UniformOutput', false);
            testCase.verifyTrue(any(contains(types, 'saccade')), 'Saccades were imported.');
            testCase.verifyTrue(any(contains(types, 'fixation')), 'Fixations were imported.');
        end

        function theWrongKeywordIsRefusedNotJoinedEmpty(testCase)
        %THEWRONGKEYWORDISREFUSEDNOTJOINEDEMPTY  With no triggers read from
        %   the eye track there is nothing to align on; EYE-EEG itself would
        %   return the dataset unchanged without an error.
            testCase.assumeTrue(EyeEeg.isAvailable(), 'EYE-EEG is not installed.');
            folder = testCase.tempFolder();
            EEG = EyeTrackingTest.session(folder);

            err = caught(@() EyeTracking(EEG, struct('keyword', 'WRONGWORD')));

            testCase.verifyTrue(startsWith(err.identifier, 'Alakazam:EyeTracking:'), err.identifier);
            testCase.verifySubstring(err.message, 'keyword');
        end

        function aTooStrictLimitIsRefusedWithTheNumbers(testCase)
            testCase.assumeTrue(EyeEeg.isAvailable(), 'EYE-EEG is not installed.');
            folder = testCase.tempFolder();
            EEG = EyeTrackingTest.session(folder);

            err = caught(@() EyeTracking(EEG, struct('keyword', 'MYKEYWORD', 'minSharedEvents', 500)));

            testCase.verifyEqual(err.identifier, 'Alakazam:EyeTracking:TooFewShared');
            testCase.verifySubstring(err.message, '32 trigger(s)');
        end

        function chosenColumnsAreImportedByName(testCase)
            testCase.assumeTrue(EyeEeg.isAvailable(), 'EYE-EEG is not installed.');
            folder = testCase.tempFolder();
            EEG = EyeTrackingTest.session(folder);

            byColumn = EyeTracking(EEG, struct('keyword', 'MYKEYWORD', 'columns', {{'L_AREA'}}));
            byChannel = EyeTracking(EEG, struct('keyword', 'MYKEYWORD', 'columns', {{'L-AREA'}}));

            testCase.verifyEqual({byColumn.chanlocs(3:end).labels}, {'L-AREA'});
            testCase.verifyEqual({byChannel.chanlocs(3:end).labels}, {'L-AREA'}, ...
                'The channel''s own spelling chooses the same column.');
        end
    end

    methods (Access = private)
        function folder = tempFolder(testCase)
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
        end
    end

    methods (Static)
        function info = joinRecord()
        %JOINRECORD  What EyeTracking leaves in EEG.etc.alz.eyeTracking.
            info = struct('file', 'C:\data\subject1myex.asc', 'how', 'found', ...
                'keyword', 'MYKEYWORD', 'startEvent', 100, 'endEvent', 200, ...
                'columns', {{'L_GAZE_X'}}, 'channels', {{'L-GAZE-X'}}, ...
                'importEyeEvents', true, 'searchRadius', 4, 'filterEyetrack', false, ...
                'quality', struct('nShared', 31, 'nTriggers', 32, 'pctMatched', 100 * 31 / 32, ...
                    'nWithinOne', 30, 'pctWithinOne', 96.8, 'meanAbsMs', 0.4, 'maxAbsSamples', 2), ...
                'limits', struct('minSharedEvents', 10, 'minPctWithinOne', 90));
        end

        function EEG = datasetFrom(rawFile)
        %DATASETFROM  A small continuous dataset that knows its raw file.
            EEG = struct('data', zeros(2, 100), 'srate', 500, 'pnts', 100, 'trials', 1, ...
                'nbchan', 2, 'times', (0:99) / 500, 'DataFormat', 'CONTINUOUS', ...
                'chanlocs', struct('labels', {'Cz', 'Pz'}), 'event', struct('type', {}, 'latency', {}), ...
                'filename', '', 'filepath', '');
            EEG = recordRawFile(EEG, rawFile);
        end

        function EEG = session(folder)
        %SESSION  The EEG of a 60 s session, with its .asc beside the
        %   recording it names. See this class's header for the two clocks.
            EEGLabEnvironment.ensure();
            srate = 500;
            seconds = 60;
            EEG = eeg_emptyset();
            EEG.srate = srate;
            EEG.pnts = seconds * srate;
            EEG.nbchan = 2;
            EEG.trials = 1;
            EEG.data = 0.1 * randn(2, EEG.pnts);
            EEG.chanlocs = struct('labels', {'Cz', 'Pz'}, 'type', {'EEG', 'EEG'});
            EEG.xmin = 0;
            EEG.xmax = (EEG.pnts - 1) / srate;

            triggerSeconds = [1, linspace(3, 57, 30), 59];
            triggerCodes = [100, repmat(1:5, 1, 6), 200];
            EEG.event = struct('type', arrayfun(@(c) sprintf('%d', c), triggerCodes, 'UniformOutput', false), ...
                'latency', num2cell(round(triggerSeconds * srate) + 1));
            EEG = eeg_checkset(EEG, 'eventconsistency');
            EEG.times = ((1:EEG.pnts) - 1) / srate;      % Alakazam's continuous times, in seconds
            EEG.DataFormat = 'CONTINUOUS';
            EEG.DataType = 'TIMEDOMAIN';
            EEG = recordRawFile(EEG, fullfile(folder, [EyeTrackingTest.Base '.set']));

            writeAsc(fullfile(folder, [EyeTrackingTest.Base '.asc']), ...
                round(triggerSeconds * srate) / srate, triggerCodes, seconds);
        end
    end
end

% ======================================================================= %
function err = caught(f)
    err = MException('none:none', 'no error');
    try
        f();
    catch err
    end
end

function writeText(file, text)
    fid = fopen(file, 'w');
    fprintf(fid, '%s', text);
    fclose(fid);
end

function fakeConverter(edfCopy)
%FAKECONVERTER  Stands in for edf2asc: leaves an .asc beside the copy.
    [folder, base] = fileparts(edfCopy);
    writeText(fullfile(folder, [base '.asc']), 'converted');
end

function writeAsc(file, triggerSeconds, triggerCodes, seconds)
%WRITEASC  An EyeLink .asc on the tracker's own clock: its clock reads
%   5,000,000 ms at the EEG's time zero and runs 40 ppm fast, and it was
%   started 3.7 s BEFORE the EEG and stopped 2 s after, as trackers usually
%   are. That early start is what makes the gaze-step case mean something:
%   lined up by where each file begins rather than by the triggers, the step
%   at 20 s of EEG time would land 3.7 s late. Gaze x steps from 400 to 800
%   pixels at 20 s; a saccade and a fixation are logged.
    t0 = 5000000;
    drift = 1 + 40e-6;
    toTracker = @(s) t0 + round(s * 1000 * drift);
    first = toTracker(-3.7);

    fid = fopen(file, 'w');
    closer = onCleanup(@() fclose(fid));
    fprintf(fid, '** CONVERTED FROM subject1myex.edf using edfapi\n');
    fprintf(fid, '** DATE: Thu Sep 24 10:00:00 2026\n');
    fprintf(fid, 'MSG\t%d !MODE RECORD CR 1000 2 1 L\n', first);
    fprintf(fid, 'START\t%d \tLEFT\tSAMPLES\tEVENTS\n', first);
    fprintf(fid, 'PRESCALER\t1\nVPRESCALER\t1\nPUPIL\tAREA\n');
    fprintf(fid, 'EVENTS\tGAZE\tLEFT\tRATE\t1000.00\tTRACKING\tCR\tFILTER\t2\n');
    fprintf(fid, 'SAMPLES\tGAZE\tLEFT\tRATE\t1000.00\tTRACKING\tCR\tFILTER\t2\n');

    messages = arrayfun(@(k) toTracker(triggerSeconds(k)), 1:numel(triggerCodes));
    next = 1;
    last = toTracker(seconds + 2);
    stepAt = toTracker(20);
    for t = first:last
        while next <= numel(messages) && messages(next) <= t
            fprintf(fid, 'MSG\t%d MYKEYWORD %d\n', messages(next), triggerCodes(next));
            next = next + 1;
        end
        x = 400 + 400 * (t >= stepAt);
        fprintf(fid, '%d\t  %.1f\t  %.1f\t %.1f\t...\n', t, x, 300 + mod(t, 7), 1100 + mod(t, 13));
        if t == toTracker(30)
            s = toTracker(29.95);
            fprintf(fid, 'ESACC L\t%d\t%d\t50\t  400.0\t  300.0\t  800.0\t  300.0\t   10.00\t    350\n', s, t);
        elseif t == toTracker(31)
            s = toTracker(30.2);
            fprintf(fid, 'EFIX L\t%d\t%d\t800\t  800.0\t  300.0\t   1100\n', s, t);
        end
    end
    fprintf(fid, 'END\t%d \tSAMPLES\tEVENTS\tRES\t 38.00\t 38.00\n', last);
end
