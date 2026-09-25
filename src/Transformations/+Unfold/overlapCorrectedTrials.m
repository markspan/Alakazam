function [trials, usable] = overlapCorrectedTrials(data, model, owner, anchors, excluded)
%OVERLAPCORRECTEDTRIALS  Each trial with every other event's fitted response
%   taken out of it.
%   [TRIALS, USABLE] = Unfold.overlapCorrectedTrials(DATA, MODEL, OWNER,
%   ANCHORS, EXCLUDED) returns channels x samples x trials: for each trial,
%   the recording around its own event, minus what the fitted model
%   attributes to every OTHER event whose response reaches into that window.
%   What is left is the trial's own response plus whatever the model does not
%   explain, which is the tutorial's "modelled plus residuals" ERP image
%   (uf_erpimage with addResiduals, Unfold tutorial 7), for every channel at
%   once and as data rather than a picture.
%
%   Arguments:
%     DATA      channels x samples, the continuous recording the model was
%               fitted to.
%     MODEL     the Unfold struct after uf_glmfit: .Xdc (samples x
%               lags*predictors, sparse), .Xdc_terms2cols (for each column
%               of Xdc, the column of X it belongs to), .X (modelled events
%               x predictors), .beta_dc (channels x lags x predictors), and
%               .timelimits and .srate, which place each lag on the
%               recording exactly as uf_timeexpandDesignmat placed it.
%               Stick (identity) time expansion, which is what Deconvolve
%               asks for: one lag per column.
%     OWNER     one value per row of .X: the trial that modelled event belongs
%               to, or 0 for an event that is only a neighbour (a nuisance
%               event, whose response is removed but which is not a trial).
%               An event in two bins has two rows with the same owner, and
%               both are the trial's own.
%     ANCHORS   one latency per trial, in samples, of the event it is locked to.
%     EXCLUDED  logical, one per sample: true where the design was zeroed
%               (artefact or a cut). A trial whose window touches one is not
%               usable, because the model was told nothing about those samples
%               and so removed nothing from them.
%
%   THE ARITHMETIC. The model predicts the whole recording as Xdc * beta,
%   every event's response added up. The trial's own share of that is its
%   own design row times beta, lag by lag. So
%
%       corrected = data - Xdc*beta + own = own + residual
%
%   which is the recording with the neighbours subtracted, written the way
%   that is cheap to compute: one sparse product over the trial's window
%   rather than one per neighbour.
%
%   WHY THE TRIALS AVERAGE BACK TO THE FIT. At a least-squares solution the
%   residual is orthogonal to every column of the design, and an intercept
%   column is the sum over one event type's events of a stick at one lag.
%   So the residuals of a bin's events, averaged at any lag, are zero, and
%   the mean of its corrected trials is the mean of their own predictions.
%   That is exactly the bin's fitted waveform whenever the bin's own values
%   of its continuous terms are the ones its waveform is evaluated at: with
%   y ~ 1, or a covariate no other bin uses. Where bins share a covariate,
%   Unfold.fitBins evaluates them all at the pooled values, and the trials
%   average to the bin's own instead, which is what an average of those
%   trials should give. That holds up to the solver's convergence, for events
%   in one bin only, and for the trials that are usable. It is the property
%   the tests hold the arithmetic to.
%
%   THE SAMPLES ARE UNFOLD'S OWN. uf_timeexpandDesignmat puts lag k of an
%   event at latency L on row round(round(L) + k + tmin*srate - 1), and the
%   k-th beta belongs to that row. Epoching the same trial by Alakazam's own
%   rule (floor, see DefineBins) would put the data one sample away from the
%   beta it is paired with whenever a latency is fractional, so the rows are
%   computed with the toolbox's formula instead.
%
%   See also UNFOLD.FITBINS, DECONVOLVE.
    [nchan, npnts] = size(data);
    [~, nlags, npred] = size(model.beta_dc);
    ntrials = numel(anchors);
    trials = nan(nchan, nlags, ntrials);
    usable = false(1, ntrials);
    if ntrials == 0
        return;
    end

    shift = (1:nlags) + model.timelimits(1) * model.srate - 1;
    rows = round(round(reshape(anchors, [], 1)) + shift);      % trials x lags
    inside = all(rows >= 1 & rows <= npnts, 2).';
    usable = inside;
    for t = find(inside)
        usable(t) = ~any(excluded(rows(t, :)));
    end

    % The betas as one column per channel in Xdc's own column order, and as
    % one row per (channel, lag) for the trials' own shares.
    flat = xdcBetas(model);
    perLag = reshape(model.beta_dc, nchan * nlags, npred);
    ownRows = sparse(owner(owner > 0), find(owner > 0), 1, ntrials, numel(owner));
    ownDesign = full(ownRows * model.X);                         % trials x predictors

    % In chunks: the prediction for a few hundred trials at a time is a few
    % hundred windows of samples by every channel, which stays small however
    % long the recording is.
    chunk = 256;
    kept = find(usable);
    for first = 1:chunk:numel(kept)
        batch = kept(first:min(first + chunk - 1, numel(kept)));
        batchRows = reshape(rows(batch, :).', [], 1);
        predicted = model.Xdc(batchRows, :) * flat;              % (lags*batch) x channels
        observed = double(data(:, batchRows)).';
        residual = reshape((observed - predicted).', nchan, nlags, numel(batch));
        own = reshape(perLag * ownDesign(batch, :).', nchan, nlags, numel(batch));
        trials(:, :, batch) = own + residual;
    end
end

% ======================================================================= %
function flat = xdcBetas(model)
%XDCBETAS  One row of betas per column of Xdc, channels across: read through
%   Xdc_terms2cols, EEG.unfold's own record of which column of X each column
%   of Xdc belongs to, rather than an assumed column order. Within a term the
%   columns run over the lags in order.
    terms = reshape(model.Xdc_terms2cols, 1, []);
    flat = zeros(numel(terms), size(model.beta_dc, 1));
    for p = unique(terms)
        cols = find(terms == p);
        flat(cols, :) = permute(model.beta_dc(:, 1:numel(cols), p), [2 1]);
    end
end
