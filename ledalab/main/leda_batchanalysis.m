function leda_batchanalysis(varargin)
% LEDA_BATCHANALYSIS Analyzes a batch of data files using specified options.
%
% Usage:
%   leda_batchanalysis('dir', 'directory_path', 'param', value, ...)
%
% Parameters:
%   'dir' (required): Path to the directory containing files to analyze.
%   'open': Specifies the type of file to open ('leda' or other).
%   'filter': Array specifying filter order and lower cutoff (e.g., [1 5]).
%   'downsample': Downsample factor (numeric).
%   'smooth': Cell array for smoothing options (e.g., {'hann', width}).
%   'analyze': Analysis method ('none', 'CDA', 'DDA').
%   'optimize': Number of initial values for optimization (numeric).
%   'export_era': Array specifying ERA export settings.
%   'export_scrlist': Array specifying SCR list export settings.
%   'overview': Specifies whether to export an overview (boolean or format string).
%   'zscale': Boolean or numeric value for z-scale setting.
%
% Global Variables:
%   leda2: Struct containing current and internal state of the analysis.
%
% Example:
%   leda_batchanalysis('dir', 'data/', 'analyze', 'CDA', 'optimize', 3);

    global leda2 %#ok<*GVMIS> 

    valid_analysis_methods = {'none', 'CDA', 'DDA'};

    % Parse batch-mode arguments and check their validity
    p = inputParser();
    p.KeepUnmatched = true;

    % Define parameters and their validation functions
    p.addRequired('dir', @ischar);
    p.addParameter('open', 'leda', @ischar);
    p.addParameter('filter', [0, 0], checkfn(@isnumeric, ...
        'Filter settings require 2 numeric arguments (filter order, and lower cutoff, e.g. [1 5])'));
    p.addParameter('downsample', 0, checkfn(@isnumeric, ...
        'Downsample option requires numeric argument (downsample factor)'));
    p.addParameter('smooth', 0, checkfn(@(arg) isequal(arg, 0) || (iscell(arg) && any(strcmpi(arg{1}, {'hann', 'mean', 'gauss', 'adapt'}))), ...
        'Smooth option requires cell; first argument is ''hann'', ''mean'', ''gauss'', or ''adapt'', second argument is width'));
    p.addParameter('analyze', 'none', @(arg) any(validatestring(arg, valid_analysis_methods)));
    p.addParameter('optimize', 2, checkfn(@isnumeric, ...
        'Optimize option requires numeric argument (# of initial values for optimization)'));
    p.addParameter('export_era', [0, 0, 0, 0], checkfn(isminsizenumeric(3), ...
        'Export requires numeric argument (respwin_start respwin_end amp_threshold [filetype])'));
    p.addParameter('export_scrlist', [0, 0], checkfn(isminsizenumeric(1), ...
        'Export requires numeric argument (amp_threshold [filetype])'));
    p.addParameter('overview', 0);
    p.addParameter('zscale', 0, checkfn(@isboolornumeric, 'zscale requires boolean or numeric argument (1 = true, 0 = false)'));

    % Parse input arguments
    p.parse(varargin{:});
    args = p.Results;

    % Validate analysis method
    analysis_method = find(strcmpi(args.analyze, valid_analysis_methods)) - 1;
    if isempty(analysis_method)
        warning('No valid analysis method found');
        return;
    end
    args.analyze = analysis_method;

    % Get list of files in the specified directory
    dirL = dir(args.dir);
    dirL = dirL(~[dirL.isdir]);
    nFile = length(dirL);

    % Log the start of the batch analysis
    add2log(1, ['Starting Ledalab batch for ', args.dir, ' (', num2str(nFile), ' file/s)'], 1, 0, 0, 1);
    pathname = fileparts(args.dir);
    leda2.current.batchmode.file = [];
    leda2.current.batchmode.command = args;
    leda2.current.batchmode.start = datestr(now, 21); %#ok<TNOW1,DATST> 
    leda2.current.batchmode.version = leda2.intern.version;
    leda2.current.batchmode.settings = leda2.set;
    leda2.set.export.zscale = args.zscale;
    tic;

    % Process each file in the directory
    for iFile = 1:nFile
        filename = dirL(iFile).name;
        leda2.current.batchmode.file(iFile).name = filename;
        disp(' ');
        add2log(1, ['Batch-Analyzing ', filename], 1, 0, 0, 1);

        % Open file
        if strcmp(args.open, 'leda')
            open_ledafile(0, pathname, filename);
        else
            import_data(args.open, pathname, filename);
        end
        if ~leda2.current.fileopen_ok
            disp('Unable to open file!');
            continue;
        end

        % Apply filter if specified
        if args.filter(1) > 0
            leda_filter(args.filter);
        end

        % Downsample if specified
        if args.downsample > 1
            leda_downsample(args.downsample, 'mean');
        end

        % Apply smoothing if specified
        if iscell(args.smooth)
            if strcmpi(args.smooth{1}, 'adapt')
                adaptive_smoothing();
            else
                smooth_data(args.smooth{2}, args.smooth{1});
            end
        end

        % Perform analysis if specified
        if analysis_method > 0
            delete_fit();
            if analysis_method == 1
                sdeco(args.optimize);
            elseif analysis_method == 2
                nndeco(args.optimize);
            end
            leda2.current.batchmode.file(iFile).tau = leda2.analysis.tau;
            leda2.current.batchmode.file(iFile).error = leda2.analysis.error;
        end

        % Export ERA if specified
        if any(args.export_era)
            leda2.set.export.SCRstart = args.export_era(1);
            leda2.set.export.SCRend = args.export_era(2);
            leda2.set.export.SCRmin = args.export_era(3);
            if length(args.export_era) > 3
                leda2.set.export.savetype = args.export_era(4);
            else
                leda2.set.export.savetype = 1;
            end
            export_era();
        end

        % Export SCR list if specified
        if any(args.export_scrlist)
            leda2.set.export.SCRmin = args.export_scrlist(1);
            if length(args.export_scrlist) > 1
                leda2.set.export.savetype = args.export_scrlist(2);
            else
                leda2.set.export.savetype = 1;
            end
            export_scrlist();
        end

        % Save overview if specified
        if args.overview
            % Legacy behavior: if 'overview' is set to 1, assume
            % a tif file should be exported
            if args.overview == 1
                args.overview = 'tif';
            end
            analysis_overview(args.overview);
        end

        % Save file if any processing was done
        if args.filter(1) > 0 || args.downsample > 0 || analysis_method || iscell(args.smooth)
            save_ledafile(0);
        end
    end

    % Log processing time and save protocol
    leda2.current.batchmode.processing_time = toc;
    protocol = leda2.current.batchmode;
    save([pathname, filesep, 'batchmode_protocol'], 'protocol');
end

function flag = maybeError(flag, errormsg)
% MAYBEERROR Throws an error if the flag is false, else returns true.
%
% Usage:
%   flag = maybeError(flag, errormsg)
%
% Parameters:
%   flag: Logical value indicating success (true) or failure (false).
%   errormsg: String containing the error message to display if flag is false.
%
% Returns:
%   flag: Returns true if the input flag is true, otherwise throws an error.

    if ~flag
        error(errormsg);
    end
end

function fn = isminsizenumeric(minsize)
% ISMINSIZENUMERIC Creates a function to check if a numeric array has a minimum size.
%
% Usage:
%   fn = isminsizenumeric(minsize)
%
% Parameters:
%   minsize: Minimum size required for the numeric array.
%
% Returns:
%   fn: Function handle that checks if an array is numeric and has at least minsize elements.

    fn = @(arg) isnumeric(arg) && length(arg) >= minsize;
end

function res = isboolornumeric(arg)
% ISBOOLORNUMERIC Checks if the input is boolean or numeric.
%
% Usage:
%   res = isboolornumeric(arg)
%
% Parameters:
%   arg: Input argument to check.
%
% Returns:
%   res: True if the input is boolean or numeric, otherwise false.

    res = isnumeric(arg) || islogical(arg);
end

function fun = checkfn(fn, errormsg)
% CHECKFN Creates a validation function that throws an error if the check fails.
%
% Usage:
%   fun = checkfn(fn, errormsg)
%
% Parameters:
%   fn: Function handle to a validation function.
%   errormsg: String containing the error message to display if validation fails.
%
% Returns:
%   fun: Function handle that performs the validation and throws an error if it fails.

    fun = @(arg) maybeError(fn(arg), errormsg);
end

function analysis_overview(format)
% ANALYSIS_OVERVIEW Generates and saves an overview of the analysis.
%
% Usage:
%   analysis_overview(format)
%
% Parameters:
%   format: String specifying the file format to save the overview (e.g., 'tif', 'png').
%
% Global Variables:
%   leda2: Struct containing current and internal state of the analysis.

    global leda2

    t = leda2.data.time.data;
    analysis = leda2.analysis;
    events = leda2.data.events;

    % Correct for extended data range of older versions
    if leda2.file.version < 3.12
        n_offset = length(analysis.time_ext);
        remainder = analysis.remainder(n_offset + 1:end);
        driver = leda2.analysis.driver(n_offset + 1:end);
    else
        remainder = analysis.remainder;
        driver = leda2.analysis.driver;
    end

    figure('Units', 'normalized', 'Position', [0 0.05 1 .9], 'MenuBar', 'none', 'NumberTitle', 'off', 'Visible', 'off');

    % Decomposition
    subplot(2, 1, 1);
    cla; hold on;
    title('SC Data')
    if leda2.file.version < 3.12 || strcmp(leda2.analysis.method, 'nndeco')
        if length(analysis.phasicRemainder) * length(analysis.tonicData) < 4 * 10^6
            for i = 2:length(analysis.phasicRemainder)
                plot(t, analysis.tonicData + analysis.phasicRemainder{i})
            end
        end
    end

    plot(t, leda2.data.conductance.data, 'k', 'Linewidth', 2);
    plot(t, analysis.tonicData + analysis.phasicData, 'k:', 'Linewidth', 2);
    plot(t, analysis.tonicData, 'Color', [.6 .6 .6], 'Linewidth', 2);

    % Ensure minimum scaling of 2 μS
    yl = get(gca, 'YLim');
    if abs(diff(yl)) < 2
        yl(2) = yl(1) + 2;
    end
    set(gca, 'XLim', [t(1), t(end)], 'Ylim', yl);

    % Events
    yl = ylim;
    for i = 1:events.N
        plot([events.event(i).time, events.event(i).time], yl, 'r')
    end
    set(gca, 'YLim', yl);

    if strcmp(analysis.method, 'nndeco')
        l = legend('SC Data', 'Decomposition Fit', 'Tonic Data', ...
            sprintf('tau = %4.2f, %4.2f,  dist0 = %4.4f', analysis.tau, analysis.dist0), ...
            sprintf('RMSE = %4.2f', analysis.error.RMSE));
    else
        l = legend('SC Data', 'Decomposition Fit', 'Tonic Data', ...
            sprintf('tau = %4.2f, %4.2f', analysis.tau), ...
            sprintf('RMSE = %4.2f', analysis.error.RMSE));
    end
    set(l, 'FontSize', 8, 'Location', 'NorthEast');
    xlabel('Time [s]'); ylabel('[\muS]');

    % Driver
    subplot(2, 1, 2);
    cla; hold on;
    title('Phasic Driver');
    plot(t, driver, 'k', 'LineWidth', 1);
    plot(t, -2 * remainder, 'b', 'LineWidth', 1);
    set(gca, 'XLim', [t(1), t(end)], 'YLim', [min(min(driver), min(-2 * remainder)) * 1.2, max(1, max(driver) * 1.2)]);

    % Events
    yl = ylim;
    for i = 1:events.N
        plot([events.event(i).time, events.event(i).time], yl, 'r');
    end
    set(gca, 'YLim', yl);

    l = legend('Driver', 'Remainder', ...
        sprintf('Error-compound = %5.2f', analysis.error.compound), ...
        sprintf('Error-discr = %4.2f,  %4.2f', analysis.error.discreteness), ...
        sprintf('Error-neg = %4.2f', analysis.error.negativity));
    set(l, 'FontSize', 8, 'Location', 'NorthEast');
    xlabel('Time [s]'); ylabel('[\muS]');

    % Save the overview
    saveas(gcf, leda2.file.filename(1:end-4), format);

    close(gcf);
    drawnow;
end
