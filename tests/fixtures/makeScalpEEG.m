function EEG = makeScalpEEG(varargin)
%MAKESCALPEEG  A synthetic EEGLAB dataset on a real 10-20 montage, with a
%   spatially smooth signal, for the tests of methods that reconstruct a
%   channel from its neighbours (interpolation, ASR, PREP, AutoReject).
%
%   makeTestEEG's channels are independent sines, which is right for a
%   threshold and wrong for anything spatial: interpolating one of them from
%   the others produces nonsense, and a method that learns what the scalp
%   looks like has nothing to learn. Here every scalp channel mixes a few
%   shared sources, each weighted by the channel's distance on the sphere to
%   the source's direction, plus a little independent noise, so neighbouring
%   channels are correlated the way real ones are.
%
%   Name-value options:
%     'labels'      scalp labels (default: the 19 channels of the 10-20 system)
%     'extra'       peripheral labels appended after them, e.g. {'VEOG'}; an
%                   EOG-like label is typed EOG, anything else MISC
%     'srate'       sampling rate in Hz (default 128)
%     'DataFormat'  'EPOCHED' (default) or 'CONTINUOUS'
%     'trials'      epochs, when epoched (default 60)
%     'epochMs'     epoch limits in ms, when epoched (default [-200 800])
%     'seconds'     length, when continuous (default 60)
%     'noise'       independent noise per channel, uV SD (default 1)
%     'seed'        random seed (default 1); the caller's stream is restored
%
%   Times follow Alakazam's convention: milliseconds when epoched, seconds
%   when continuous. Needs EEGLAB (eeg_emptyset, and pop_chanedit through
%   TransTools.FillChanlocs), so a test using it should assume EEGLAB.
%
%   See also MAKETESTEEG, TRANSTOOLS.SCALPCHANNELS.
    p = inputParser;
    p.addParameter('labels', {'Fp1', 'Fp2', 'F7', 'F3', 'Fz', 'F4', 'F8', 'T7', 'C3', 'Cz', ...
        'C4', 'T8', 'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'O2'});
    p.addParameter('extra', {});
    p.addParameter('srate', 128);
    p.addParameter('DataFormat', 'EPOCHED');
    p.addParameter('trials', 60);
    p.addParameter('epochMs', [-200, 800]);
    p.addParameter('seconds', 60);
    p.addParameter('noise', 1);
    p.addParameter('seed', 1);
    p.parse(varargin{:});
    o = p.Results;

    previous = rng;
    restore = onCleanup(@() rng(previous));
    rng(o.seed, 'twister');

    labels = [cellstr(o.labels), cellstr(o.extra)];
    nScalp = numel(o.labels);
    nChan = numel(labels);
    epoched = strcmpi(o.DataFormat, 'EPOCHED');

    EEG = eeg_emptyset();
    EEG.setname = 'makeScalpEEG';
    EEG.srate = o.srate;
    EEG.nbchan = nChan;
    EEG.chanlocs = struct('labels', labels);
    EEG.DataType = 'TIMEDOMAIN';
    if epoched
        EEG.DataFormat = 'EPOCHED';
        pnts = round(diff(o.epochMs) / 1000 * o.srate) + 1;
        EEG.times = linspace(o.epochMs(1), o.epochMs(2), pnts);
        EEG.trials = o.trials;
        EEG.xmin = o.epochMs(1) / 1000;
        EEG.xmax = o.epochMs(2) / 1000;
    else
        EEG.DataFormat = 'CONTINUOUS';
        pnts = round(o.seconds * o.srate);
        EEG.times = (0:pnts - 1) / o.srate;
        EEG.trials = 1;
        EEG.xmin = 0;
        EEG.xmax = (pnts - 1) / o.srate;
    end
    EEG.pnts = pnts;

    EEG = TransTools.FillChanlocs(EEG, 'Alakazam:makeScalpEEG', ...
        TransTools.Template1005File('Alakazam:makeScalpEEG'));
    for c = 1:nChan
        if c <= nScalp
            EEG.chanlocs(c).type = 'EEG';
        elseif ~isempty(regexpi(labels{c}, 'EOG', 'once'))
            EEG.chanlocs(c).type = 'EOG';
        else
            EEG.chanlocs(c).type = 'MISC';
        end
    end

    % Shared sources, weighted by angular distance on the sphere.
    xyz = [[EEG.chanlocs(1:nScalp).X]; [EEG.chanlocs(1:nScalp).Y]; [EEG.chanlocs(1:nScalp).Z]].';
    xyz = xyz ./ vecnorm(xyz, 2, 2);
    nSources = 4;
    directions = randn(nSources, 3);
    directions(:, 3) = abs(directions(:, 3));        % upper hemisphere, under the cap
    directions = directions ./ vecnorm(directions, 2, 2);
    % Squared chord distance on the unit sphere, through a kernel broad
    % enough that every channel carries a real share of the signal: a
    % channel of noise alone would be (rightly) called bad by every method
    % tested with this fixture, which is not what the fixture is for.
    weights = exp(-(2 - 2 * xyz * directions.') / 1.0);   % nScalp x nSources

    nTrials = EEG.trials;
    t = (0:pnts - 1) / o.srate;
    data = zeros(nChan, pnts, nTrials);
    for tr = 1:nTrials
        sources = zeros(nSources, pnts);
        for k = 1:nSources
            f = 4 + 8 * rand;
            sources(k, :) = 10 * sin(2 * pi * f * t + 2 * pi * rand) + 3 * randn(1, pnts);
        end
        data(1:nScalp, :, tr) = weights * sources;
    end
    data = data + o.noise * randn(size(data));
    EEG.data = data;
end
