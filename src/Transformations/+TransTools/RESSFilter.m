function result = RESSFilter(X, srate, freq, opts)
%RESSFILTER  Rhythmic entrainment source separation: the weighted combination
%   of channels that carries the most power at a stimulation frequency.
%
%   RESULT = TransTools.RESSFilter(X, SRATE, FREQ, OPTS) takes X (channels x
%   samples x trials, the trials that build the filter), the sampling rate
%   and the stimulation frequency in Hz, and returns
%     .weights      channels x 1 spatial filter, unit length, sign fixed
%     .map          channels x 1 forward model (the component's scalp map)
%     .eigenvalues  every generalized eigenvalue, largest first; the first
%                   is the ratio of power at FREQ to power at the neighbours
%                   the filter achieves, the rest show whether it stands out
%     .shrinkage    the shrinkage applied to the reference covariance
%     .rank         the numerical rank of the reference covariance
%     .trialsUsed   which pages of X entered the covariances
%   Apply it with TransTools.RESSComponent.
%
%   THE METHOD (Cohen & Gulbinaite, 2017, NeuroImage 147, 43-56). Two channel
%   covariance matrices are formed from the same samples: S from the data
%   filtered narrowly at FREQ, R as the mean of the covariances at FREQ -
%   and FREQ + OPTS.NeighbourDistance, filtered more broadly. The generalized
%   eigenvector of (S, R) with the largest eigenvalue maximizes the ratio of
%   power at FREQ to power beside it, which is what a response to flicker has
%   and ongoing activity mostly does not. The filters are the Gaussians of
%   TransTools.GaussianBandpass, applied to the whole epoch before the window
%   is taken, so the circular filter's wrap-around stays outside it.
%
%   AS IN THE REFERENCE CODE (github.com/mikexcohen/RESS), with one fix. The
%   covariances pool the windowed samples of all trials, each channel
%   demeaned over the pool; the forward model is S w / (w' S w), which holds
%   for rank-deficient data where inv(W') does not. The sign is fixed so the
%   channel with the largest forward-model magnitude is positive, and here
%   the WEIGHTS are flipped with it: the reference flips only the map, which
%   leaves the component's sign, and so its phase, arbitrary. The phase lag
%   of a component to a photodiode depends on it.
%
%   SHRINKAGE. An average reference, an interpolated channel or a removed
%   ICA component each lower the rank of the data, and a singular R has no
%   well-defined generalized eigenvectors. R is therefore shrunk towards a
%   multiple of the identity, (1 - g) R + g * mean(eig(R)) * I, with g =
%   OPTS.Shrinkage (default 0.01). The article used none on full-rank data;
%   0 reproduces that.
%
%   OPTS (all optional):
%     PeakFWHM           width of the filter at FREQ, Hz          (0.5)
%     NeighbourDistance  distance of the neighbours from FREQ, Hz  (1)
%     NeighbourFWHM      width of the filters at the neighbours, Hz (1)
%     Window             logical 1 x samples: the samples used (all)
%     Shrinkage          g above, 0 to 1                          (0.01)
%   The defaults are the reference code's. A trial with a NaN in the window
%   (a rejected epoch is blanked to NaN) is left out of the covariances.
%
%   See also TRANSTOOLS.RESSCOMPONENT, TRANSTOOLS.GAUSSIANBANDPASS, RESS.
    if nargin < 4 || isempty(opts)
        opts = struct();
    end
    peakFwhm   = TransTools.FieldOr(opts, 'PeakFWHM', 0.5);
    neighDist  = TransTools.FieldOr(opts, 'NeighbourDistance', 1);
    neighFwhm  = TransTools.FieldOr(opts, 'NeighbourFWHM', 1);
    shrinkage  = TransTools.FieldOr(opts, 'Shrinkage', 0.01);
    [nChan, nSamp, ~] = size(X);
    window = logical(TransTools.FieldOr(opts, 'Window', true(1, nSamp)));
    if numel(window) ~= nSamp || ~any(window)
        throw(MException('Alakazam:RESSFilter', ...
            'The window must be one logical value per sample, with at least one true.'));
    end
    if freq - neighDist <= 0
        throw(MException('Alakazam:RESSFilter', ...
            'The lower neighbour, %g Hz, must be above 0 Hz.', freq - neighDist));
    end
    if freq + neighDist >= srate / 2
        throw(MException('Alakazam:RESSFilter', ...
            'The upper neighbour, %g Hz, must be below the Nyquist frequency, %g Hz.', ...
            freq + neighDist, srate / 2));
    end

    X = double(X);
    usable = squeeze(all(all(isfinite(X(:, window, :)), 1), 2));
    usable = reshape(usable, 1, []);
    if nnz(usable) < 1
        throw(MException('Alakazam:RESSFilter', ...
            'No trial has finite data in the window, so there is nothing to build the filter from.'));
    end
    X = X(:, :, usable);

    S = bandCovariance(X, srate, freq, peakFwhm, window);
    R = (bandCovariance(X, srate, freq - neighDist, neighFwhm, window) + ...
         bandCovariance(X, srate, freq + neighDist, neighFwhm, window)) / 2;

    eigR = eig(R);
    result.rank = nnz(eigR > max(eigR) * nChan * eps(1) * 1e3);
    if shrinkage > 0
        R = (1 - shrinkage) * R + shrinkage * mean(eigR) * eye(nChan);
    elseif result.rank < nChan
        % Refused on the measured rank, not left to eig: rounding makes a
        % singular R look barely positive definite, and eig then returns
        % a filter along the direction the data do not have.
        throw(MException('Alakazam:RESSFilter', ...
            ['The reference covariance has rank %d of %d channels (an average reference, an ' ...
             'interpolated channel or a removed ICA component lowers it), so the filter is not ' ...
             'defined without shrinkage. Please set a shrinkage above 0.'], result.rank, nChan));
    end
    try
        [W, L] = eig(S, R, 'chol');   % S symmetric, R positive definite: real, R-orthogonal
    catch err
        throw(MException('Alakazam:RESSFilter', ...
            ['The reference covariance is not positive definite (its rank is %d of %d channels), ' ...
             'so the filter is not defined without shrinkage. Please set a shrinkage above 0. (%s)'], ...
            result.rank, nChan, err.message));
    end
    [values, order] = sort(real(diag(L)), 'descend');
    w = W(:, order(1));
    w = w / norm(w);

    map = S * w / (w' * S * w);
    [~, biggest] = max(abs(map));
    flip = sign(map(biggest));
    if flip == 0
        flip = 1;
    end

    result.weights = flip * w;
    result.map = flip * map;
    result.eigenvalues = values;
    result.shrinkage = shrinkage;
    result.trialsUsed = usable;
end

function C = bandCovariance(X, srate, freq, fwhm, window)
%BANDCOVARIANCE  Channel covariance of X filtered at FREQ, over WINDOW,
%   pooled across trials.
    F = TransTools.GaussianBandpass(X, srate, freq, fwhm);
    F = reshape(F(:, window, :), size(F, 1), []);
    F = F - mean(F, 2);
    C = (F * F') / size(F, 2);
    C = (C + C') / 2;
end
