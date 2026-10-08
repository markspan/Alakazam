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
% fminsearch, MATLAB's own, rather than FieldTrip's default fminunc,
% which needs the Optimization Toolbox: where that is missing or broken
% FieldTrip catches the failure and returns the grid point, unfitted.
cfg.dipfit      = struct('display', 'off', 'checkinside', true, ...
    'optimfun', 'fminsearch'); %#ok<STRNU> used in evalc
[~, source] = evalc('ft_dipolefitting(cfg, timelock);');
if ~isfield(source.dip, 'rv')
    throw(MException('Alakazam:DipoleFit', ['I am afraid the dipole fit for bin "%s" ' ...
        'did not converge, so there is only the grid search''s starting point. A ' ...
        'wider window, or a finer grid, may help.'], binLabel));
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
