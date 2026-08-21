function tl = toFieldTripTimelock(EEG, binLabel)
%TOFIELDTRIPTIMELOCK  One subject's Averaged bin waveform, reshaped into a
%   FieldTrip "timelock" struct (ft_datatype_timelock: .label, .time, .avg,
%   .dimord = 'chan_time'), the shape ft_timelockstatistics expects for one
%   subject's own subject-level average.
%
%   EEG is an Alakazam Averaged dataset (EEG.data: channels x samples x
%   bins, EEG.bindesc(b).label, EEG.times in MILLISECONDS -- see Average.m).
%   BINLABEL selects which bin's waveform to convert; unlike Measure (which
%   measures every bin uniformly), a cluster test always contrasts two
%   specific things, so the caller picks the bin explicitly.
%
%   .time is converted to SECONDS (FieldTrip's own convention throughout
%   its timelock/statistics functions), not left in Alakazam's native ms.
%
%   This is deliberately pure data reshaping with no FieldTrip functions
%   called -- see ClusterStatsTest.m, which exercises it without FieldTrip
%   (or even EEGLAB) on the path, the same "calculation code should not
%   need the heavy optional toolkit just to be tested" reasoning
%   tests/fixtures/makeTestEEG.m's own header describes.
    labels = {EEG.bindesc.label};
    match = find(strcmp(labels, binLabel), 1);
    if isempty(match)
        throw(MException('Alakazam:ClusterStats', sprintf( ...
            'Bin "%s" was not found on "%s" (bins present: %s).', ...
            binLabel, EEG.id, strjoin(labels, ', '))));
    end

    tl = struct();
    tl.label  = reshape({EEG.chanlocs.labels}, [], 1);
    tl.time   = reshape(EEG.times, 1, []) / 1000; % ms -> s
    tl.avg    = EEG.data(:, :, match);
    tl.dimord = 'chan_time';
end
