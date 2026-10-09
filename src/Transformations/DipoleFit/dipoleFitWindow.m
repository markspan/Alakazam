function fit = dipoleFitWindow(values, times, labels, elec, headmodel, opts, binLabel)
%DIPOLEFITWINDOW  FieldTrip's dipole fit to one bin over one window: what
%   DipoleFit does for each bin it is asked to fit.
%
%   FIT = dipoleFitWindow(VALUES, TIMES, LABELS, ELEC, HEADMODEL, OPTS, BINLABEL)
%   fits VALUES (channels x samples, rows in the order of LABELS, which must
%   be ELEC's channels) over TIMES (ms), with OPTS.WindowStart and
%   OPTS.WindowStop (ms), OPTS.Model ('One dipole' | 'Mirrored pair') and
%   OPTS.GridResolution (in HEADMODEL's unit, mm for the template). BINLABEL
%   names the bin in the result and in errors. FIT is one element of
%   EEG.dipoleFit (see DIPOLEFIT).
%
%   DipoleFit always passes FieldTrip's template head model and electrodes.
%   It is a function of its own so that the fit can be checked against
%   FieldTrip's tutorial on the tutorial's own head model
%   (FieldTripTutorialDipoleTest).
%
%   See also DIPOLEFIT, FT_DIPOLEFITTING.
timelock = struct('label', {labels(:)}, 'time', reshape(times, 1, []) / 1000, ...
    'avg', values, 'dimord', 'chan_time', 'elec', elec); %#ok<NASGU> used in evalc
pair = strcmpi(opts.Model, 'Mirrored pair');
cfg = struct();
cfg.numdipoles = 1 + pair;
if pair
    cfg.symmetry = 'x';
end
cfg.gridsearch  = 'yes';
cfg.nonlinear   = 'yes';
cfg.model       = 'regional';
cfg.latency     = [opts.WindowStart, opts.WindowStop] / 1000;
cfg.headmodel   = headmodel;
cfg.elec        = elec;
cfg.resolution  = opts.GridResolution;   % mm, the head model's unit
cfg.feedback    = 'no';
% The fit itself is FieldTrip's, with its own defaults, as in a script: it
% does not confine the dipole to the source compartment while optimising
% (checkinside false), and by default it chooses the optimiser itself,
% fminunc where it finds the Optimization Toolbox and fminsearch otherwise.
% OPTS.Optimiser 'fminsearch' sets FieldTrip's documented
% cfg.dipfit.optimfun instead, for a MATLAB where fminunc is found but
% cannot run (a shared copy without the Optimization Toolbox's message
% catalog, for one). Only the progress display is switched off, which
% changes nothing but the output.
cfg.dipfit      = struct('display', 'off');
if strcmpi(char(string(TransTools.FieldOr(opts, 'Optimiser', ''))), 'fminsearch')
    cfg.dipfit.optimfun = 'fminsearch'; %#ok<STRNU> used in evalc
end
[~, source] = evalc('ft_dipolefitting(cfg, timelock);');
if ~isfield(source.dip, 'rv')
    % FieldTrip returns the grid search's starting point, without a
    % residual variance, when its optimiser stops with an error.
    throw(MException('Alakazam:DipoleFit', '%s', sprintf(['I am afraid the dipole fit ' ...
        'for bin "%s" did not finish, so there is only the grid search''s starting point. ' ...
        'FieldTrip''s optimiser stopped: with "FieldTrip''s choice" that is fminunc ' ...
        'wherever MATLAB reports the Optimization Toolbox, and it cannot run where only ' ...
        'part of that toolbox is installed. Would you set the Optimiser to fminsearch? ' ...
        'Otherwise a wider window, or a finer grid, may help.'], binLabel)));
end

% ONE RESIDUAL VARIANCE FOR THE WINDOW: FieldTrip's dip.rv is one per
% sample (its rv() works column by column), so the window's is taken
% from the data and the model over all of it, and the per-sample values
% are kept beside it.
residual = source.Vdata - source.Vmodel;
rv = sum(residual(:) .^ 2) / sum(source.Vdata(:) .^ 2);
fit = struct('bin', binLabel, 'window', [opts.WindowStart, opts.WindowStop], ...
    'model', opts.Model, 'pos', source.dip.pos, 'region', {TransTools.AtlasRegionsAt(source.dip.pos)}, ...
    'mom', source.dip.mom, 'time', reshape(source.time, 1, []) * 1000, ...
    'rv', rv, 'gof', 1 - rv, 'rvTime', reshape(source.dip.rv, 1, []));
end
