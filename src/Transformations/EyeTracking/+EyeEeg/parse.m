function et = parse(ascFile, matFile, keyword)
%PARSE  Read an EyeLink .asc file with EYE-EEG's parser.
%   ET = EyeEeg.parse(ASCFILE, MATFILE, KEYWORD) runs parseeyelink, which
%   also saves ET to MATFILE for pop_importeyetracker to read.
%
%   AN EMPTY KEYWORD IS NOT PASSED ON. parseeyelink reads triggers either
%   from messages carrying a keyword ("MYKEYWORD 123") or, when it is given
%   no keyword at all, from the parallel-port INPUT lines. Passing '' would
%   be neither, so '' here means the second.
%
%   See also EYETRACKING, EYEEEG.FINDEYEFILE.
    if nargin < 3 || isempty(strtrim(char(string(keyword))))
        et = parseeyelink(ascFile, matFile);
    else
        et = parseeyelink(ascFile, matFile, char(string(keyword)));
    end
end
