function [EEGclean, EEGartifacts, SENSAI_score, SENSAI_score_per_band, artifact_threshold_per_band, ...
    mean_ENOVA, ENOVA_per_epoch, com, ENOVA_per_band, ENOVA_per_channel] = GEDAI(EEGin, ...
    artifact_threshold_type, epoch_size_in_cycles, lowcut_frequency, ref_matrix_type, parallel, ...
    visualize_artifacts, ENOVA_threshold_per_epoch, ENOVA_threshold_per_channel, signal_type, ...
    smoothing_window_seconds, varargin) %#ok<INUSD>  the signature is GEDAI's own
%GEDAI  A stand-in for the GEDAI plugin, for AutoGEDAITest. Not GEDAI.
%
%   It takes GEDAI's arguments under GEDAI's own names, saves them in
%   lastCall.mat beside itself, and returns the data unchanged with the
%   outputs AutoGEDAI reads. So a test can see what AutoGEDAI handed GEDAI
%   without the plugin, and without its minutes of computation.
%
%   It also does to the warning state what GEDAI v1.7 does: switch every
%   warning off and leave it so (GEDAI.m, "warning('off')"), which is what
%   AutoGEDAI has to undo.
%
%   AutoGEDAITest copies this folder to a temporary one and adds GEDAI's
%   electrode template under auxiliaries/, where AutoGEDAI looks for it.
%   Never put this folder itself on the path: it would shadow the plugin.
%
%   See also AUTOGEDAI, AUTOGEDAITEST.

    call = struct('artifact_threshold_type', artifact_threshold_type, ...
        'epoch_size_in_cycles', epoch_size_in_cycles, ...
        'lowcut_frequency', lowcut_frequency, ...
        'ref_matrix_type', ref_matrix_type, ...
        'signal_type', signal_type, ...
        'smoothing_window_seconds', smoothing_window_seconds);
    save(fullfile(fileparts(mfilename('fullpath')), 'lastCall.mat'), 'call');

    warning('off'); %#ok<WNOFF>  GEDAI v1.7's own behaviour, on purpose

    EEGclean = EEGin;
    EEGclean.etc.GEDAI.samples_to_keep = true(1, size(EEGin.data, 2) * size(EEGin.data, 3));
    EEGartifacts = EEGin;
    EEGartifacts.data = zeros(size(EEGin.data));
    SENSAI_score = 50;
    SENSAI_score_per_band = [];
    artifact_threshold_per_band = [];
    mean_ENOVA = 0;
    ENOVA_per_epoch = zeros(1, size(EEGin.data, 3));
    com = '';
    ENOVA_per_band = [];
    ENOVA_per_channel = zeros(1, size(EEGin.data, 1));
end
