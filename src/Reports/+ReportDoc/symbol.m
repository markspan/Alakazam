function s = symbol(name)
%SYMBOL  A statistical symbol as the reports print it: plain Unicode text.
%   S = ReportDoc.symbol(NAME) returns the characters for NAME, one of
%
%     'alpha'   the significance level, the Greek small letter alpha
%     'chi2'    the chi-square statistic, chi followed by a superscript two
%
%   so a generator writes sprintf('%s = .05', ReportDoc.symbol('alpha'))
%   and the reader sees the letter, in any viewer, with nothing to render.
%
%   NOT TEX MATH, and that is the whole point of this function. The reports
%   used to write $\alpha$. Pandoc turns that into \(\alpha\) inside a
%   <span class="math">, and leaves drawing the letter to MathJax, a script
%   the page fetches from the web when it opens. The app's own report viewer
%   does not run it (MATLAB serves the page under a Content-Security-Policy
%   that refuses it), and neither does a reader who is offline, so both saw
%   the delimiters as text: "significance at \(\alpha\) = .05". The escaping
%   in the generator had been fixed twice by then, correctly both times,
%   which is how a symptom in the viewer passed for a bug in the string.
%
%   Plain Unicode needs no script, survives the conversion to Word as
%   ordinary text rather than as an equation object, and is what APA style
%   prints: Greek letters upright, not italic. The R templates write the same
%   characters as \u escapes ("χ²"), which R's parser turns into
%   the letters, for the same reason; ReportTemplatesTest fails on any TeX
%   math in a template, and ClusterStatsReportTest on any in a document.
%
%   Built from code points so that this file, and every generator calling
%   it, stays ASCII whatever encoding an editor saves it in.
%
%   See also REPORTDOC.APAHELPERS, GENERATECLUSTERSTATSREPORT.
    switch lower(char(name))
        case 'alpha'
            s = char(945);              % U+03B1 GREEK SMALL LETTER ALPHA
        case 'chi2'
            s = char([967 178]);        % U+03C7 GREEK SMALL LETTER CHI, U+00B2 SUPERSCRIPT TWO
        otherwise
            throw(MException('Alakazam:ReportDoc:unknownSymbol', ...
                'I am afraid the reports have no symbol called "%s".', char(name)));
    end
end
