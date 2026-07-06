function [EEG, opts] = Average(input,opts)
% Average - Compute the trial average of epoched EEG data.
%
% Syntax: [EEG, opts] = Average(input, opts)
%
% Inputs:
%   input - EEG structure containing the epoched data
%       .data - 3D matrix of EEG data (channels x samples x epochs)
%       .DataFormat - Format of the data, must be 'EPOCHED'
%       .trials - Number of trials (epochs)
%       .bindesc - (optional) per-bin descriptors written by DefineBins; when
%                  present, the average is computed separately per bin.
%   opts - Options for the function, default is 'Init' if not provided
%
% Outputs:
%   EEG - Modified EEG structure with averaged data
%       .data  - averaged EEG data: channels x samples (no bins) or
%                channels x samples x bins (one average per bin)
%       .stErr - Standard error of the mean, matching .data
%       .DataFormat - Set to 'Averaged'
%       .ntrials - Original number of trials
%       .trials - Set to 1 indicating the data is now averaged
%   opts - Options for the function, returned unchanged
%
% Description:
%   Computes the average of epoched EEG data along the third (epoch)
%   dimension. When the dataset carries bin membership (EEG.bindesc / the
%   per-epoch .bini tags produced by DefineBins), each bin is averaged over
%   just the trials that belong to it, giving one channels x samples slice per
%   bin plus a matching standard error and per-bin trial count. Without bins it
%   averages across all trials, as before. A trial in several bins contributes
%   to each of them.
%
%% Check for the EEG dataset input:
if (nargin < 1)
    throw(MException('Alakazam:Average','Problem in Average: No Data Supplied'));
end

if (nargin == 1)
    opts = 'Init';
end
% Validate input data
if ~isfield(input, 'data')
    throw(MException('Alakazam:Average','Problem in Average: No Correct Data Supplied'));
end

if (length(size(input.data)) < 3 || ~strcmpi(input.DataFormat, 'EPOCHED'))
    throw(MException('Alakazam:Average','Problem in Average: Data not Segmented'));
end

if ~isfield(input, 'trials')
    throw(MException('Alakazam:Average','Problem in Average: Trials not specified'));
end

EEG = input;
[nchan, npnts, ntrials] = size(input.data);
EEG.ntrials = ntrials;
EEG.trials  = 1;
EEG.DataFormat = "Averaged";

if isfield(input, 'bindesc') && ~isempty(input.bindesc)
    % Bin-aware: one average per bin, over the trials that belong to it.
    nbin  = numel(input.bindesc);
    data  = nan(nchan, npnts, nbin);
    stErr = nan(nchan, npnts, nbin);
    for b = 1:nbin
        idx = binTrials(input, b);
        EEG.bindesc(b).n = numel(idx);
        if isempty(idx)
            continue;
        end
        data(:, :, b)  = mean(input.data(:, :, idx), 3, 'omitnan');
        stErr(:, :, b) = std(input.data(:, :, idx), 0, 3, 'omitnan') / sqrt(numel(idx));
    end

    % Second pass: combination (difference) bins defined in DefineBins with
    % "bin N = bin A - bin B". They have no trials of their own; their average
    % is the signed sum of the referenced bins' averages, and the standard
    % error propagates as the root of the summed squared errors.
    pos = containers.Map('KeyType', 'double', 'ValueType', 'double');
    for b = 1:nbin; pos(input.bindesc(b).index) = b; end
    for b = 1:nbin
        if ~isfield(input.bindesc, 'combo') || isempty(input.bindesc(b).combo)
            continue;
        end
        combo   = input.bindesc(b).combo;
        acc     = zeros(nchan, npnts);
        varAcc  = zeros(nchan, npnts);
        ok = true;
        for t = 1:numel(combo)
            if ~isKey(pos, combo(t).bin); ok = false; break; end
            r      = pos(combo(t).bin);
            acc    = acc    + combo(t).coeff * data(:, :, r);
            varAcc = varAcc + (combo(t).coeff * stErr(:, :, r)).^2;
        end
        if ok
            data(:, :, b)  = acc;
            stErr(:, :, b) = sqrt(varAcc);
        end
    end

    EEG.data  = data;
    EEG.stErr = stErr;
else
    % No bins: average across every trial.
    EEG.data  = mean(input.data, 3, 'omitnan');
    EEG.stErr = std(input.data, 0, 3, 'omitnan') / sqrt(ntrials);
end
end

function idx = binTrials(EEG, b)
%BINTRIALS  Trial indices (into the epoch stack) belonging to bin b.
%   Prefers the explicit trial list DefineBins stores on each bin; falls back
%   to scanning the per-epoch .bini membership tags.
    idx = [];
    if isfield(EEG.bindesc, 'trials') && ~isempty(EEG.bindesc(b).trials)
        idx = EEG.bindesc(b).trials;
    elseif isfield(EEG, 'epoch') && ~isempty(EEG.epoch) && isfield(EEG.epoch, 'bini')
        binIndex = EEG.bindesc(b).index;
        idx = find(arrayfun(@(e) any(e.bini == binIndex), EEG.epoch));
    end
end
