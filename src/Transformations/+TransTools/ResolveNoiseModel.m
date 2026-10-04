function model = ResolveNoiseModel(requested, method, available, errorId)
%RESOLVENOISEMODEL  The noise model a source estimate will actually use.
%   MODEL = TransTools.ResolveNoiseModel(REQUESTED, METHOD, AVAILABLE, ERRORID)
%   returns 'baseline' or 'identity', from REQUESTED ('auto', 'baseline' or
%   'identity'), the inverse METHOD, and AVAILABLE, whether every dataset
%   and bin involved carries a baseline noise covariance
%   (TransTools.BinNoiseCovariance).
%
%     'auto'      the baseline when it is available, else the identity: what
%                 FieldTrip's minimum-norm tutorial does when it has trials;
%     'baseline'  the baseline, and an error naming the fix when there is
%                 none (Average again, on epochs with a baseline before zero);
%     'identity'  white noise, as before the noise covariance existed.
%
%   Only dSPM ('mne') uses a noise covariance (see TransTools.InverseSolution),
%   so any other method resolves to 'identity' whatever was asked: the
%   stored estimate's key then says what the estimate really is.
%
%   See also TRANSTOOLS.INVERSESOLUTION, TRANSTOOLS.BINNOISECOVARIANCE, SOURCECACHE.KEY.
    requested = lower(char(string(requested)));
    if ~strcmpi(char(string(method)), 'mne')
        model = 'identity';
        return;
    end
    switch requested
        case 'auto'
            if available
                model = 'baseline';
            else
                model = 'identity';
            end
        case 'baseline'
            if ~available
                throw(MException(errorId, '%s', ['I am afraid there is no baseline noise ' ...
                    'covariance to use. Average stores one when its epochs start before the ' ...
                    'event; run Average again on such epochs, or choose white noise (identity).']));
            end
            model = 'baseline';
        case 'identity'
            model = 'identity';
        otherwise
            throw(MException(errorId, ...
                'The noise covariance must be auto, baseline or identity, not "%s".', requested));
    end
end
