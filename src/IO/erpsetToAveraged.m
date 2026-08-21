function EEG = erpsetToAveraged(ERP)
%ERPSETTOAVERAGED  Map an ERPLAB erpset (ERP struct) to an Alakazam Averaged
%   dataset. The two are structurally the same thing -- an averaged, binned,
%   time-domain waveform set -- so this is essentially a field rename, with no
%   unit conversion: ERPLAB and Alakazam both keep ERP.times / EEG.times in
%   milliseconds and xmin/xmax in seconds (see DefineBins, which sets exactly
%   that on the epoched data Average later reduces).
%
%   ERP.bindata (nchan x pnts x nbin) becomes EEG.data, one averaged waveform
%   per bin -- the same shape and DataFormat ("Averaged") that Average.m
%   produces, so the ERP-domain tools (Measure, ScalpDistribution, Grand
%   Average, plotting, export) all consume it unchanged. The reverse is
%   averagedToErpset.
%
%   See also AVERAGEDTOERPSET, AVERAGE, LOADERPFILE.
    if ~isstruct(ERP) || ~isfield(ERP, 'bindata') || isempty(ERP.bindata)
        error('Alakazam:erpsetToAveraged', 'Not a valid erpset: no bindata field.');
    end

    data = double(ERP.bindata);
    [nchan, npnts, nbin] = size(data);

    EEG = struct();
    EEG.setname    = TransTools.FieldOr(ERP, 'erpname', '');
    EEG.erpname    = EEG.setname;
    EEG.subject    = TransTools.FieldOr(ERP, 'subject', '');
    EEG.nbchan     = firstNonEmpty(TransTools.FieldOr(ERP, 'nchan', []), nchan);
    EEG.pnts       = firstNonEmpty(TransTools.FieldOr(ERP, 'pnts', []), npnts);
    EEG.trials     = 1;                    % averaged: one "trial" (waveform) per bin
    EEG.srate      = TransTools.FieldOr(ERP, 'srate', NaN);
    EEG.xmin       = TransTools.FieldOr(ERP, 'xmin', NaN);   % seconds
    EEG.xmax       = TransTools.FieldOr(ERP, 'xmax', NaN);   % seconds
    EEG.times      = reshape(double(TransTools.FieldOr(ERP, 'times', [])), 1, []); % ms
    if isempty(EEG.times) && isfinite(EEG.srate)
        % Reconstruct a millisecond time vector from srate/xmin when absent.
        EEG.times = (EEG.xmin + (0:npnts - 1) / EEG.srate) * 1000;
    end
    EEG.data       = data;
    EEG.stErr      = errorOrZeros(ERP, size(data));
    EEG.chanlocs   = TransTools.FieldOr(ERP, 'chanlocs', struct([]));
    EEG.chaninfo   = TransTools.FieldOr(ERP, 'chaninfo', struct());
    EEG.ref        = TransTools.FieldOr(ERP, 'ref', '');
    EEG.event      = [];                   % averaged data carries no events
    EEG.epoch      = [];
    EEG.DataType   = 'TIMEDOMAIN';
    EEG.DataFormat = 'Averaged';

    % Bin descriptors: ERPLAB's bindescr (cell of labels, with bindescription
    % as an older alias) plus the per-bin accepted-trial counts. Combo/
    % difference metadata does not survive an erpset (ERPLAB does not store it),
    % so bins come back as plain bins.
    labels = binLabels(ERP, nbin);
    accepted = acceptedTrials(ERP, nbin);
    bindesc = repmat(struct('index', 0, 'label', '', 'n', 0, 'combo', [], 'trials', []), 1, nbin);
    for b = 1:nbin
        bindesc(b).index = b;
        bindesc(b).label = labels{b};
        bindesc(b).n     = accepted(b);
    end
    EEG.bindesc = bindesc;
    EEG.ntrials = sum(accepted(isfinite(accepted)));
end

% TransTools.FieldOr used to be duplicated locally here as getField (same
% logic, module the isstruct(s) guard TransTools.FieldOr adds -- isfield()
% on a non-struct already returns false safely, so this is not a
% behavioural change). firstNonEmpty (src/Support/) used to be duplicated
% locally here too.

function e = errorOrZeros(ERP, sz)
    if isfield(ERP, 'binerror') && ~isempty(ERP.binerror) && isequal(size(ERP.binerror), sz)
        e = double(ERP.binerror);
    else
        e = zeros(sz);
    end
end

function labels = binLabels(ERP, nbin)
    raw = {};
    if isfield(ERP, 'bindescr') && ~isempty(ERP.bindescr)
        raw = ERP.bindescr;
    elseif isfield(ERP, 'bindescription') && ~isempty(ERP.bindescription)
        raw = ERP.bindescription;
    end
    if ischar(raw); raw = {raw}; end
    labels = cell(1, nbin);
    for b = 1:nbin
        if b <= numel(raw) && ~isempty(raw{b})
            labels{b} = char(string(raw{b}));
        else
            labels{b} = sprintf('Bin %d', b);
        end
    end
end

function acc = acceptedTrials(ERP, nbin)
    acc = zeros(1, nbin);
    if isfield(ERP, 'ntrials') && isstruct(ERP.ntrials) && isfield(ERP.ntrials, 'accepted')
        a = double(ERP.ntrials.accepted);
        m = min(numel(a), nbin);
        acc(1:m) = a(1:m);
    end
end
