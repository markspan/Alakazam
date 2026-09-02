function [timelocks, design, ivar, uvar, statistic] = buildDesign(subjects, contrast, timelockFcn)
%BUILDDESIGN  Turn subjects plus a contrast into FieldTrip's own inputs.
%   [TIMELOCKS, DESIGN, IVAR, UVAR, STATISTIC] = ClusterStats.buildDesign(
%   SUBJECTS, CONTRAST) returns the cell array of timelock structs, the
%   design matrix, its independent/unit variable rows, and the name of the
%   test statistic, ready for ft_timelockstatistics.
%
%   CONTRAST.mode is one of:
%     'vsZero'      one bin against a zero waveform, paired within subject
%     'paired'      two bins against each other, paired within subject
%     'independent' one bin, compared BETWEEN groups (contrast.groupOf)
%
%   TIMELOCKFCN (optional, default @ClusterStats.toFieldTripTimelock) is
%   called as TIMELOCKFCN(subject, binLabel) and must return one FieldTrip
%   timelock struct. IT IS THE ONLY THING THAT DIFFERS BETWEEN A
%   SCALP-CHANNEL TEST AND A SOURCE-SPACE ONE.
%
%   That parameter is the whole reason this function was lifted out of
%   ClusterStats.m. The design side of a cluster test -- which conditions
%   are paired with which, what the design matrix looks like, whether the
%   statistic is dependent- or independent-samples -- is a property of the
%   EXPERIMENTAL DESIGN, and does not care whether a row of the data is an
%   electrode or a cortical vertex. Copying it to serve source space would
%   have meant two implementations of the same three cases, free to drift
%   apart on exactly the question ("is this paired?") where a silent
%   divergence would invalidate the test rather than break it.
%
%   See also CLUSTERSTATS, SOURCECLUSTERSTATS,
%   CLUSTERSTATS.TOFIELDTRIPTIMELOCK, CLUSTERSTATS.PAIREDDESIGN,
%   CLUSTERSTATS.INDEPENDENTDESIGN, CLUSTERSTATS.ZEROTIMELOCK.
    if nargin < 3 || isempty(timelockFcn)
        timelockFcn = @ClusterStats.toFieldTripTimelock;
    end

    nSubjects = numel(subjects);
    switch contrast.mode
        case 'vsZero'
            condA = cell(1, nSubjects);
            condB = cell(1, nSubjects);
            for i = 1:nSubjects
                condA{i} = timelockFcn(subjects{i}, contrast.bin);
                condB{i} = ClusterStats.zeroTimelock(condA{i});
            end
            timelocks = [condA, condB];
            [design, ivar, uvar] = ClusterStats.pairedDesign(nSubjects);
            statistic = 'depsamplesT';

        case 'paired'
            condA = cell(1, nSubjects);
            condB = cell(1, nSubjects);
            for i = 1:nSubjects
                condA{i} = timelockFcn(subjects{i}, contrast.binA);
                condB{i} = timelockFcn(subjects{i}, contrast.binB);
            end
            timelocks = [condA, condB];
            [design, ivar, uvar] = ClusterStats.pairedDesign(nSubjects);
            statistic = 'depsamplesT';

        case 'independent'
            timelocks = cell(1, nSubjects);
            for i = 1:nSubjects
                timelocks{i} = timelockFcn(subjects{i}, contrast.bin);
            end
            [design, ivar] = ClusterStats.independentDesign(contrast.groupOf);
            uvar = [];
            statistic = 'indepsamplesT';

        otherwise
            throw(MException('Alakazam:ClusterStats', sprintf( ...
                'I do not know a contrast mode called "%s".', string(contrast.mode))));
    end
end
