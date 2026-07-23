function ERP = averagedToErpset(EEG)
%AVERAGEDTOERPSET  Map an Alakazam Averaged dataset to an ERPLAB erpset (ERP
%   struct), ready to save as a .erp file (a plain MAT-file holding ERP) and
%   reopen in ERPLAB. The inverse of erpsetToAveraged; like it, a field rename
%   with no unit conversion (times in ms, xmin/xmax in seconds on both sides).
%
%   Only Averaged datasets can be exported -- an erpset IS averaged, binned,
%   time-domain data. EEG.data (nchan x pnts x nbin) becomes ERP.bindata, and
%   EEG.stErr (if present) becomes ERP.binerror. Combination/difference bins
%   built in DefineBins export as ordinary bins (ERPLAB has no notion of them);
%   their reported trial count -- a string like "68-74" -- is not numeric, so
%   ERP.ntrials.accepted records 0 for those bins.
%
%   See also ERPSETTOAVERAGED, ONEXPORTERPSET.
    if ~isfield(EEG, 'DataFormat') || ~strcmpi(char(string(EEG.DataFormat)), 'Averaged')
        error('Alakazam:averagedToErpset', ...
            ['Only an averaged dataset can be exported as an erpset. Run Average ' ...
             '(on segmented data) first, then export its result.']);
    end
    if ~isfield(EEG, 'data') || isempty(EEG.data)
        error('Alakazam:averagedToErpset', 'This dataset has no data to export.');
    end

    data = double(EEG.data);
    if ismatrix(data)
        data = reshape(data, size(data, 1), size(data, 2), 1); % single-bin average
    end
    [nchan, npnts, nbin] = size(data);

    name = firstNonEmpty(getField(EEG, 'erpname', ''), ...
           firstNonEmpty(getField(EEG, 'setname', ''), getField(EEG, 'id', 'erpset')));

    ERP = struct();
    ERP.erpname   = char(string(name));
    ERP.filename  = '';
    ERP.filepath  = '';
    ERP.workfiles = {};
    ERP.subject   = char(string(getField(EEG, 'subject', '')));
    ERP.nchan     = nchan;
    ERP.nbin      = nbin;
    ERP.pnts      = npnts;
    ERP.srate     = getField(EEG, 'srate', NaN);
    ERP.xmin      = getField(EEG, 'xmin', NaN);   % seconds
    ERP.xmax      = getField(EEG, 'xmax', NaN);   % seconds
    ERP.times     = reshape(double(getField(EEG, 'times', [])), 1, []); % ms
    if isempty(ERP.times) && isfinite(ERP.srate)
        ERP.times = (ERP.xmin + (0:npnts - 1) / ERP.srate) * 1000;
    end
    ERP.bindata   = data;
    ERP.binerror  = binError(EEG, size(data));
    ERP.datatype  = 'ERP';
    ERP.chanlocs  = getField(EEG, 'chanlocs', struct([]));
    ERP.chaninfo  = getField(EEG, 'chaninfo', struct());
    ERP.ref       = char(string(getField(EEG, 'ref', '')));
    ERP.bindescr  = binLabels(EEG, nbin);

    accepted = acceptedCounts(EEG, nbin);
    ERP.ntrials = struct('accepted', accepted, ...
        'rejected', zeros(1, nbin), 'invalid', zeros(1, nbin), ...
        'arflags', zeros(nbin, 8));
    ERP.pexcludedartifacts = zeros(1, nbin);

    ERP.isfilt     = 0;
    ERP.history    = '';
    ERP.saved      = 'no';
    ERP.version    = 'Alakazam';
    ERP.splinefile = '';
    ERP.EVENTLIST  = [];
end

% ----------------------------------------------------------------------- %
function v = getField(s, name, default)
    if isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end

function v = firstNonEmpty(a, b)
    if ~isempty(a); v = a; else; v = b; end
end

function e = binError(EEG, sz)
    if isfield(EEG, 'stErr') && ~isempty(EEG.stErr) && isequal(size(EEG.stErr), sz)
        e = double(EEG.stErr);
    else
        e = zeros(sz);
    end
end

function labels = binLabels(EEG, nbin)
    labels = arrayfun(@(b) sprintf('Bin %d', b), 1:nbin, 'UniformOutput', false);
    if isfield(EEG, 'bindesc') && ~isempty(EEG.bindesc) && isfield(EEG.bindesc, 'label')
        for b = 1:min(nbin, numel(EEG.bindesc))
            if ~isempty(EEG.bindesc(b).label)
                labels{b} = char(string(EEG.bindesc(b).label));
            end
        end
    end
end

function acc = acceptedCounts(EEG, nbin)
    acc = zeros(1, nbin);
    if isfield(EEG, 'bindesc') && ~isempty(EEG.bindesc) && isfield(EEG.bindesc, 'n')
        for b = 1:min(nbin, numel(EEG.bindesc))
            n = EEG.bindesc(b).n;
            if isnumeric(n) && isscalar(n) && isfinite(n)
                acc(b) = n;   % combo bins report a string like "68-74" -> left 0
            end
        end
    end
end
