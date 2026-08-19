function EEG = makeTestEEG(varargin)
%MAKETESTEEG  A small, valid synthetic EEG struct for transformation unit tests.
%   Defaults: 3 channels, 250 Hz, epoched -200..596 ms (200 samples), 4
%   trials, EPOCHED. Every channel/trial is a deterministic signal (a sine
%   plus a per-trial offset), not random noise, so a test can compute the
%   exact expected result rather than just checking "it changed somehow".
%   Override any default via name-value pairs, e.g.
%   makeTestEEG('nbchan', 1, 'trials', 1, 'DataFormat', 'CONTINUOUS').
%
%   Deliberately built by hand, field by field, not via EEGLAB's own
%   eeg_emptyset()/pop_*: most of the "calculation" transformations
%   (Baseline, ArtefactDetect, DefineBins) never call EEGLAB themselves, so
%   their tests should not need EEGLAB on the path either. A transformation
%   that DOES call an EEGLAB pop_* function under the hood (Filter wraps
%   firfilt) still needs EEGLAB initialised in that test class's own
%   TestClassSetup -- this fixture does not attempt to hide that.
%
%   See also BASELINETEST.
    p = inputParser;
    p.addParameter('nbchan', 3);
    p.addParameter('srate', 250);
    p.addParameter('trials', 4);
    p.addParameter('epochMs', [-200, 596]);
    p.addParameter('DataFormat', 'EPOCHED');
    p.addParameter('labels', {});
    p.parse(varargin{:});
    o = p.Results;

    EEG = struct();
    EEG.srate      = o.srate;
    EEG.nbchan     = o.nbchan;
    EEG.DataFormat = o.DataFormat;
    EEG.DataType   = 'TimeDomain';

    nSamples  = round((o.epochMs(2) - o.epochMs(1)) / 1000 * o.srate) + 1;
    EEG.times = linspace(o.epochMs(1), o.epochMs(2), nSamples);
    EEG.pnts  = nSamples;

    if isempty(o.labels)
        labels = arrayfun(@(c) sprintf('Ch%d', c), 1:o.nbchan, 'UniformOutput', false);
    else
        labels = o.labels;
    end
    EEG.chanlocs = struct('labels', labels);

    if strcmpi(o.DataFormat, 'CONTINUOUS')
        EEG.trials = 1;
        t = (0:nSamples - 1) / o.srate;
        EEG.data = zeros(o.nbchan, nSamples);
        for c = 1:o.nbchan
            EEG.data(c, :) = c * sin(2 * pi * 10 * t);
        end
    else
        EEG.trials = o.trials;
        t = EEG.times / 1000;
        EEG.data = zeros(o.nbchan, nSamples, o.trials);
        for tr = 1:o.trials
            for c = 1:o.nbchan
                % +5 per trial so there is a real, nonzero baseline offset
                % for a Baseline-correction test to remove.
                EEG.data(c, :, tr) = c * sin(2 * pi * 10 * t + tr) + 5;
            end
        end
    end
end
