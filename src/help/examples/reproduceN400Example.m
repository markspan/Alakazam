function result = reproduceN400Example(varargin)
%REPRODUCEN400EXAMPLE  Chapter 20's worked example, from the template to the
%   report: N400.alztemplate on Luck's ten chapter 3 recordings, then the
%   measurements export and the statistics report as ERP & Report writes
%   them. Every number the chapter quotes comes from this run.
%
%   RESULT = reproduceN400Example() runs it and returns a struct with
%     .subjects    the ten recordings, by subject number
%     .amplitude   subjects x 5: mean amplitude at Cz, 300 to 500 ms, in the
%                  four bins and the N400 difference bin
%     .means, .sds the four bins' mean and SD over subjects, the chapter's
%                  table
%     .difference  the difference bin's [mean, SD]
%     .csvFile     the measurements export
%     .reportFile  the rendered report ('' when not rendered)
%
%   Name-value options:
%     'Output'  folder for the export and the report
%               (default: tempdir/alakazam-n400-example)
%     'Render'  false to stop at the report's .qmd (default: true)
%
%   WHAT IT DOES, as the app would. Each recording is loaded as
%   WorkSpace.loadSETFile loads it, the template's steps run in order through
%   TransTools.invoke (the call Apply Template makes), and the ten Measure
%   results become the entries ERP & Report collects
%   (collectMeasurementEntries): no group, no session, each subject its own
%   person. exportMeasurementsCSV, generateQuartoReport and
%   renderQuartoReport then write the export and the report. The grand
%   average's waveforms, which the report can also draw, are left out: they
%   add figures, not numbers. Nothing in a workspace is touched: the
%   intermediate results stay in memory, and the cache paths the steps are
%   given point into OUTPUT/cache, where nothing but empty folders is written.
%
%   NEEDS EEGLAB, GEDAI (AutoGEDAI installs it the first time it runs in the
%   app), Luck's chapter 3 recordings in Data/Luck/ch3 (DATA.md,
%   downloadLuckData), and Quarto and R for the report. LibraryReplayTest
%   (theN400WorkedExampleGivesTheManualsTable) replays the same steps and
%   holds the results to the chapter's table, so a change that moves them
%   fails a test; rerun this to regenerate the chapter's statistics.
%
%   Run it from the repository root:
%       addpath('src/help/examples'); reproduceN400Example();
%
%   See also LIBRARYREPLAYTEST, TRANSTOOLS.INVOKE, GENERATEQUARTOREPORT.
    parsed = inputParser();
    parsed.addParameter('Output', '', @(v) ischar(v) || isstring(v));
    parsed.addParameter('Render', true, @(v) islogical(v) || isnumeric(v));
    parsed.parse(varargin{:});
    outDir = char(parsed.Results.Output);
    if isempty(outDir)
        outDir = fullfile(tempdir, 'alakazam-n400-example');
    end
    if ~isfolder(outDir); mkdir(outDir); end

    repo = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
    addAppPaths(fullfile(repo, 'src'));
    EEGLabEnvironment.ensure();
    if isempty(which('GEDAI'))
        installed = EEGLabEnvironment.findInstalled('GEDAI', 'GEDAI.m');
        if isempty(installed)
            error('reproduceN400Example:noGEDAI', ['GEDAI is not installed. Run AutoGEDAI once ' ...
                'in Alakazam, which offers to install it, then run this again.']);
        end
        addpath(installed);
    end

    [ids, params] = templateSteps(fullfile(repo, 'library', 'templates', 'N400.alztemplate'));
    files = recordings(fullfile(repo, 'Data', 'Luck', 'ch3'));
    if numel(files) ~= 10
        error('reproduceN400Example:data', ['The worked example uses the ten chapter 3 ' ...
            'recordings, *_N400_preprocessed.set in Data/Luck/ch3; %d were found. See DATA.md.'], ...
            numel(files));
    end

    cache = fullfile(outDir, 'cache');
    if ~isfolder(cache); mkdir(cache); end
    entries = struct('subject', {}, 'datasetType', {}, 'group', {}, 'person', {}, ...
        'session', {}, 'EEG', {}, 'file', {});
    amplitude = nan(numel(files), 5);
    subjects = cell(1, numel(files));
    for s = 1:numel(files)
        [~, subjects{s}] = fileparts(files{s});
        fprintf('%s ...\n', subjects{s});
        EEG = loadRecording(files{s});
        EEG.File = fullfile(cache, [subjects{s} '.mat']);
        for k = 1:numel(ids)                % a flat template: each step on the one before
            input = EEG;
            EEG = TransTools.invoke(ids{k}, input, params{k});
            EEG.File = resultCacheFile(input.File, ids{k});
        end
        amplitude(s, :) = EEG.measurements{1}.amplitude(1, 1:5);
        entries(end + 1) = struct('subject', subjects{s}, 'datasetType', 'subject', 'group', '', ...
            'person', subjects{s}, 'session', '', 'EEG', EEG, 'file', EEG.File); %#ok<AGROW>
    end

    result = struct('subjects', {subjects}, 'amplitude', amplitude, ...
        'means', mean(amplitude(:, 1:4), 1), 'sds', std(amplitude(:, 1:4), 0, 1), ...
        'difference', [mean(amplitude(:, 5)), std(amplitude(:, 5))], ...
        'csvFile', fullfile(outDir, 'measurements_n400.csv'), 'reportFile', '');
    fprintf('\nN400 at Cz, 300 to 500 ms, over %d subjects\n', numel(files));
    fprintf('  bin means %s, SDs %s\n', mat2str(round(result.means, 3)), mat2str(round(result.sds, 3)));
    fprintf('  difference bin M %.3f, SD %.3f\n', result.difference);

    exportMeasurementsCSV(entries, result.csvFile);
    qmdFile = fullfile(outDir, 'measurements_n400.qmd');
    writeQmdFile(qmdFile, generateQuartoReport(entries, 'measurements_n400.csv', [], '', ''), ...
        'reproduceN400Example:report');
    fprintf('  export %s\n  report source %s\n', result.csvFile, qmdFile);
    if logical(parsed.Results.Render)
        [htmlFile, renderError] = renderQuartoReport(qmdFile);
        if isempty(htmlFile)
            warning('reproduceN400Example:render', 'The report was not rendered: %s', renderError);
        else
            result.reportFile = htmlFile;
            fprintf('  report %s\n', htmlFile);
        end
    end
end

% ======================================================================= %
function addAppPaths(src)
%ADDAPPPATHS  The folders Alakazam.setupDirectories puts on the path.
    addpath(src, '-end');
    for sub = {'Views', 'Dialogs', 'IO', 'Reports', 'Support'}
        addpath(fullfile(src, sub{1}), '-end');
    end
    addpath(genpath(fullfile(src, 'Transformations')));
end

function [ids, params] = templateSteps(file)
%TEMPLATESTEPS  A flat template's steps, as Alakazam.readTemplate reads them.
    raw = jsondecode(fileread(file));
    steps = raw.steps;
    if ~iscell(steps); steps = num2cell(steps); end
    ids = cellfun(@(st) char(st.transformId), steps, 'UniformOutput', false);
    params = cellfun(@(st) st.params, steps, 'UniformOutput', false);
end

function files = recordings(folder)
%RECORDINGS  The chapter's recordings, by subject number.
    listing = dir(fullfile(folder, '*_N400_preprocessed.set'));
    subject = arrayfun(@(d) str2double(regexp(d.name, '^\d+', 'match', 'once')), listing);
    [~, order] = sort(subject);
    files = arrayfun(@(d) fullfile(d.folder, d.name), listing(order), 'UniformOutput', false);
    files = reshape(files, 1, []);
end

function EEG = loadRecording(file)
%LOADRECORDING  A .set file as WorkSpace.loadSETFile prepares it.
    [folder, name, ext] = fileparts(file);
    EEG = pop_loadset([name ext], folder);
    EEG = eeg_checkset(EEG);
    EEG = recordRawFile(EEG, file);
    EEG.DataType = 'TIMEDOMAIN';
    EEG.DataFormat = inferDataFormat(EEG);
    if strcmpi(EEG.DataFormat, 'CONTINUOUS')
        EEG.times = ((1:EEG.pnts) - 1) / EEG.srate;
    elseif strcmpi(EEG.DataFormat, 'EPOCHED') && ~isempty(EEG.times) && max(abs(EEG.times(:))) < 10
        EEG.times = EEG.times * 1000;
    end
    EEG = deriveBinsFromEpochs(EEG);
end
