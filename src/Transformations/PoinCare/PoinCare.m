function [pfigure, ropts] = PoinCare(input,~)
    % PoinCare - Create a Poincare plot for the IBI series
    %
    % Syntax: [pfigure, ropts] = PoinCare(input, ~)
    %
    % Inputs:
    %   input - Structure containing the IBI data and related event information
    %       .IBIevent - Cell array of structures with IBI data
    %       .filename - Name of the file containing the data
    %       .event - Array of event structures
    %           .type - Type of the event
    %           .latency - Latency of the event
    %           .duration - Duration of the event
    %       .srate - Sampling rate of the data
    %
    % Outputs:
    %   pfigure - Handle to the created Poincare plot figure
    %   ropts - String indicating the type of plot created ('graph')

    % Set default return options
    ropts = 'graph';

    % Check for the EEG dataset input
    if (nargin < 1)
        ME = MException('Alakazam:PoinCare','Problem in PoinCare: No Data Supplied');
        throw(ME);
    end
    if ~isfield(input, 'IBIevent')
        ME = MException('Alakazam:PoinCare','Problem in PoinCare: No IBIS available (yet)');
        throw(ME);
    end

    [~, name, ~] = fileparts(input.filename);
    pfigure = uifigure('Name', name, 'Visible', false, 'Units', 'normalized');

    % Extract event types
    evc = [];
    if isfield(input, 'event') && isfield(input.event, 'type') && ~isempty({input.event.type})
        evc = unique({input.event.type}, 'stable');
    end

    % Define all events that are IBI
    events = input.IBIevent{1};

    % Select the normals
    normals = events.classID == 'N';
    events.ibis = events.ibis(normals(1:end-1));
    ibix = events.ibis(1:end-1);
    ibiy = events.ibis(2:end);
    ibit = events.RTopTime(1:end-2);

    % Create the Poincare plot
    PoinCarePlot(pfigure, ibix, ibiy, ibit, evc, input);
    pfigure.Visible = true;
end

function PoinCarePlot(fig, ibix, ibiy, ibit, evc, input)
    % Create table array
    [x, y, tRR, metricsTable, nEVC] = createMetricsTable(ibix, ibiy, ibit, evc, input);

    % Create UI elements
    gl = uigridlayout(fig, [3 2]);

    % Create table UI component
    uit = uitable(gl, 'Data', metricsTable, 'Layout', struct('Row', [1,2], 'Column', 2));
    uit.ColumnSortable = false;
    uit.ColumnEditable = [true false false false false false false false false];
    uit.BackgroundColor = [.91 .91 .91; .98 .98 .98];
    uit.DisplayDataChangedFcn = @(~,~) updatePlot(uit, ax, x, y, tRR, ibix, ibiy, input);

    style = uistyle('HorizontalAlignment', 'right');
    addStyle(uit, style, 'table', '');

    % Create PoinCare chart
    ax = uiaxes(gl, 'Layout', struct('Row', [1,3], 'Column', 1));
    lPoincarePlot(ax, metricsTable, x, y, tRR, input.IBIevent{1}.classID(1:end-2));
end

function [x, y, tRR, metricsTable, nEVC] = createMetricsTable(ibix, ibiy, ibit, evc, input)
    RMSSD = []; SDNN = []; mIBI = []; SD1 = []; SD2 = [];
    x = {}; y = {}; tRR = {}; N = []; nEVC = strings(0, 0);

    if (~isempty(evc))
        for i = 1:length(evc)
            label = evc(i);
            event = [strcmp([input.event.type], label)];
            idx = ibit < 0;
            for e1 = 1:length(input.event(event))
                elist = [input.event(event)];
                ev = elist(e1);
                idx = idx | (ibit > ev.latency / input.srate) & (ibit < ((ev.latency + ev.duration) / input.srate));
            end
            if sum(idx > 0)
                nEVC(end + 1) = evc(i);
                idx = idx(1:length(ibix));
                x{end + 1} = ibix(idx);
                y{end + 1} = ibiy(idx);
                tRR{end + 1} = ibit(idx);
                SD1(end + 1) = round((sqrt(2) / 2.0) * std(ibix(idx) - ibiy(idx)), 3);
                SD2(end + 1) = round(sqrt(2 * std(ibix(idx))^2) - (.5 * std(ibix(idx) - ibiy(idx))^2), 3);
                RMSSD(end + 1) = calculateMetric(@Tools.HRV.RMSSD, ibix(idx));
                SDNN(end + 1) = 1000 * Tools.HRV.SDNN(ibix(idx));
                mIBI(end + 1) = 1000 * mean(ibix(idx));
                N(end + 1) = sum(idx);
            end
        end
    else
        x{end + 1} = ibix(:);
        y{end + 1} = ibiy(:);
        tRR{end + 1} = ibit(:);
        SD1(end + 1) = round((sqrt(2) / 2.0) * std(ibix(:) - ibiy(:)), 3);
        SD2(end + 1) = round(sqrt(2 * std(ibix(:))^2) - (.5 * std(ibix(:) - ibiy(:))^2), 3);
        RMSSD(end + 1) = calculateMetric(@Tools.HRV.RMSSD, ibix(:));
        SDNN(end + 1) = 1000 * Tools.HRV.SDNN(ibix(:));
        mIBI(end + 1) = 1000 * mean(ibix(:));
        N(end + 1) = length(x);
        nEVC = "full epoch";
    end

    pSD1SD2 = SD1 ./ SD2;
    cRMSSD = 1000 * (RMSSD ./ mIBI);
    Plotted = mIBI > 0;

    metricsTable = table(Plotted', N', mIBI', SD1', SD2', pSD1SD2', RMSSD', cRMSSD', SDNN', ...
        'VariableNames', ["Plot", "N", "mean(IBI)", "SD1", "SD2", "SD1/SD2", "RMSSD", "cRMSSD", "SDNN"], ...
        'RowNames', nEVC);

    fn = input.filename;
    [~, name, ~] = fileparts(fn);
    writetable(metricsTable, ['./Data/' name '.csv'], 'WriteRowNames', true);
end

function value = calculateMetric(metricFunc, data)
    if isempty(metricFunc(data))
        value = nan;
    else
        value = 1000 * metricFunc(data);
    end
end

function updatePlot(uit, ax, x, y, tRR, ibix, ibiy, input)
    t = uit.DisplayData;
    lx = xlim(ax);
    ly = ylim(ax);
    lPoincarePlot(ax, t, x, y, tRR, input.IBIevent{1}.classID(1:end-2));
    xlim(ax, lx);
    ylim(ax, ly);
end

function lPoincarePlot(ax, t, xibis, yibis, tibis, labs)
    cla(ax);
    xlabel(ax, "IBI(t)");
    ylabel(ax, "IBI(t+1)");
    m = ceil(10 * max(cell2mat(xibis))) / 10;
    xlim(ax, [0 m]);
    ylim(ax, [0 m]);
    grid(ax, 'on');

    for ii = 1:length(t.Plot)
        if t.Plot(ii)
            col = ax.ColorOrder(mod(ii - 1, 7) + 1, :);
            hold(ax, 'on');
            h = scatter(ax, xibis{ii}, yibis{ii}, 'MarkerEdgeColor', col, 'DisplayName', char(t.Row{ii}));

            Labels = repmat({t.Row{ii}}, 1, length(tibis{ii}));
            h.DataTipTemplate.DataTipRows(1) = dataTipTextRow("Period:", Labels);
            h.DataTipTemplate.DataTipRows(3) = dataTipTextRow("IBI(t):", 'XData');
            h.DataTipTemplate.DataTipRows(2) = dataTipTextRow("Label", labs);
            h.DataTipTemplate.DataTipRows(4) = dataTipTextRow("IBI(t+1):", 'YData');
            h.DataTipTemplate.DataTipRows(5) = dataTipTextRow("Time(s):", double(tibis{ii}));

            el = plot_ellipse(ax, 2 * t.SD1(ii), 2 * t.SD2(ii), mean(xibis{ii}), mean(yibis{ii}), 45, col);
            dt = datatip(el, 0, 0, 'Visible', 'off');
            el.DataTipTemplate.DataTipRows(1) = dataTipTextRow("", Labels);
            el.DataTipTemplate.DataTipRows(2) = [];
        end
    end
end

function h = plot_ellipse(ax, a, b, cx, cy, angle, color)
    % Plot an ellipse on the given axes
    angle = angle / 180 * pi;
    r = 0:0.1:2 * pi + 0.1;
    p = [(a * cos(r))' (b * sin(r))'];

    alpha = [cos(angle) -sin(angle); sin(angle) cos(angle)];
    p1 = p * alpha;

    h = patch(ax, cx + p1(:, 1), cy + p1(:, 2), color, 'EdgeColor', color);
    h.FaceAlpha = .05;
end
