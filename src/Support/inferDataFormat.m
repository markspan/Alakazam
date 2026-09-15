function fmt = inferDataFormat(EEG)
%INFERDATAFORMAT  'CONTINUOUS', 'EPOCHED' or 'AVERAGED', derived from EEG's
%   own shape -- not trusted from a DataFormat field that might not exist at
%   all (a file not created by Alakazam: a plain EEGLAB .set, or a .mat
%   someone else saved) or might be stale.
%
%   EEGLAB itself tells epoched data from continuous by SHAPE (channels x
%   samples x trials, ndims(EEG.data)==3) or a non-empty .epoch struct array
%   (pop_epoch's own marker, which survives even when a single-trial result
%   has been squeezed back to 2 dimensions) -- EEG.trials==1 alone is NOT
%   enough to call something continuous, since a genuinely continuous
%   recording also reports trials==1. Epoched data is then EPOCHED (more
%   than one trial) or AVERAGED (exactly one: an ERP/grand-average waveform
%   set).
%
%   Reported directly: an already-epoched .set file dropped into the data
%   directory was loaded as DataFormat "CONTINUOUS" regardless of its real
%   shape (loadSETFile.m used to hard-code it), which routed it to
%   SignalView -- built for 2-D continuous data -- and SignalView's own
%   y = y.' on the 3-D result threw "TRANSPOSE does not support N-D arrays."
%
%   See also LOADSETFILE, LOADMATFILE.
    isEpoched = ndims(EEG.data) == 3 || (isfield(EEG, 'epoch') && ~isempty(EEG.epoch));
    if ~isEpoched
        fmt = 'CONTINUOUS';
    elseif isfield(EEG, 'trials') && EEG.trials > 1
        fmt = 'EPOCHED';
    else
        fmt = 'AVERAGED';
    end
end
