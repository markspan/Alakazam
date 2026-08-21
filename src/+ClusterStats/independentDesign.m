function [design, ivar] = independentDesign(groupOfEachSubject)
%INDEPENDENTDESIGN  FieldTrip cfg.design/cfg.ivar for an independent-samples
%   (between-subjects) two-group cluster test -- ft_timelockstatistics with
%   cfg.statistic = 'indepsamplesT' expects DESIGN as 1 x nSubjects, one
%   numeric group code per subject, in the SAME order as the timelock cell
%   array passed alongside it.
%
%   GROUPOFEACHSUBJECT is a cellstr/string array of each subject's own group
%   label (e.g. from WorkSpace.groupFor); mapped here to numeric codes 1/2
%   in the order the labels are first seen, so callers never have to
%   hand-assign numbers themselves. Exactly two distinct groups are
%   required -- ft_statfun_indepsamplesT is a two-sample test, not an
%   omnibus one; see ClusterStats's own header for why 3+ groups are out of
%   scope for now.
    groupOfEachSubject = cellstr(groupOfEachSubject);
    labels = unique(groupOfEachSubject, 'stable');
    if numel(labels) ~= 2
        throw(MException('Alakazam:ClusterStats', sprintf( ...
            'An independent-samples cluster test needs exactly 2 groups; found %d (%s).', ...
            numel(labels), strjoin(labels, ', '))));
    end
    design = zeros(1, numel(groupOfEachSubject));
    design(strcmp(groupOfEachSubject, labels{1})) = 1;
    design(strcmp(groupOfEachSubject, labels{2})) = 2;
    ivar = 1;
end
