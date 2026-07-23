function rText = generateRScript(csvFileName)
%GENERATERSCRIPT  R analysis script for an exported measurements CSV.
%   RTEXT = GENERATERSCRIPT(CSVFILENAME) returns a ready-to-run R script
%   (tidyverse + rstatix + ggpubr) that reads the long-format measurement CSV
%   named CSVFILENAME and, for each measure_type x window x channel, runs a
%   repeated-measures ANOVA across bins plus Holm-corrected pairwise paired
%   t-tests, and draws a ggplot per group (subjects, group mean, SE,
%   significance brackets). The script text comes from the maintained template
%   statsTemplate.R (sibling of this file); only the CSV name is filled in.
    here = fileparts(mfilename('fullpath'));
    template = fileread(fullfile(here, 'statsTemplate.R'));
    rText = strrep(template, '__CSVFILE__', char(csvFileName));
end
