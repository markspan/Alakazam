function component = RESSComponent(X, weights)
%RESSCOMPONENT Apply a RESS spatial filter: one time series per trial.
%   COMPONENT = RESSComponent(X, WEIGHTS) is WEIGHTS' * X for every trial of X
%   (channels x samples x trials), returned 1 x samples x trials. The filter
%   is applied to the data as they are, not to the narrow-band data it was
%   built from, so the component keeps the fluctuations of the response over
%   time (Cohen & Gulbinaite, 2017). A trial with NaN stays NaN.
%
%   See also RESSFILTER.
    [nChan, nSamp, nTrials] = size(X);
    component = reshape(weights(:)' * reshape(double(X), nChan, []), 1, nSamp, nTrials);
end
