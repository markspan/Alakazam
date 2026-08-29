function marker = rawCode(expression)
%RAWCODE  Wrap EXPRESSION so matlabLiteral emits it as code, not as a value.
%
%   Lets a caller substitute an expression where a stored option value would
%   otherwise be written out literally:
%
%       params.script = rawCode('binScript1');
%
%   emits `'script', binScript1` instead of a kilobyte of escaped text. Used
%   by exportAnalysisScript to keep each DefineBins bin script in its own
%   .binscript file, in the form the analyst wrote it, rather than inlining
%   it into the generated .m where it can no longer be read or edited as a
%   bin script.
%
%   See also MATLABLITERAL, EXPORTANALYSISSCRIPT.
    marker = struct('Alakazam_rawCode__', char(expression));
end
