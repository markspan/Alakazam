function [design, ivar, uvar] = pairedDesign(nSubjects)
%PAIREDDESIGN  FieldTrip cfg.design/cfg.ivar/cfg.uvar for a dependent-samples
%   (within-subject, paired) two-condition cluster test -- ft_timelockstatistics
%   with cfg.statistic = 'depsamplesT' expects DESIGN as 2 x (2*nSubjects):
%   row 1 the condition of each column (1 for every "condition A" replicate,
%   then 2 for every "condition B" one, in the SAME subject order both
%   halves), row 2 the subject number of each column, repeated across both
%   halves -- so column i and column i+nSubjects are the same subject's two
%   conditions, which is what lets FieldTrip pair them up rather than
%   treating all 2*nSubjects columns as independent observations.
%
%   IVAR = 1 (condition is the effect of interest), UVAR = 2 (subject is
%   the "unit of observation" FieldTrip pairs on) -- ft_timelockstatistics'
%   own field names for this.
    if nSubjects < 2
        throw(MException('Alakazam:ClusterStats', ...
            'A paired cluster test needs at least 2 subjects.'));
    end
    condition = [ones(1, nSubjects), 2 * ones(1, nSubjects)];
    subject   = [1:nSubjects, 1:nSubjects];
    design = [condition; subject];
    ivar = 1;
    uvar = 2;
end
