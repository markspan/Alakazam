function p = templateParams(~, p)
%TEMPLATEPARAMS  PARAMS as saved into a template file (see
%   onSaveTemplate): drops any field that is purely a compiled
%   cache derived from another field also present, so applying the
%   template later re-derives it fresh instead of depending on the
%   cache surviving a jsonencode/jsondecode round trip with its
%   exact original MATLAB types intact.
%
%   Today this only ever matches DefineBins: .bins is a compiled
%   expression tree derived entirely from .script (DefineBins.m's
%   own "script mode" branch already re-parses from .script alone
%   whenever .bins is absent -- see its nargin==2 dispatch), so
%   dropping .bins here makes DefineBins take that same code path
%   on Apply Template. Concretely, .bins' nested 'codes' fields are
%   `string` arrays in DefineBins' own native output, but decode
%   from JSON as a `cell` array of char (or, for a single-code
%   matcher, a bare char row vector) -- both harmless for
%   DefineBins' evaluator (matchCode normalises either shape), but
%   only after that normalisation was added specifically because a
%   bare-char single-code matcher silently matched nothing at all
%   pre-fix, turning every next()/prev() relation using it into an
%   unbounded full-recording scan. Re-parsing the original script
%   text sidesteps the whole class of such shape mismatches, not
%   just the ones already found -- keeping matchCode's own
%   normalisation too is still worthwhile defence in depth (a
%   hand-edited template, or a future transform with a similar
%   compiled-plan field, would not otherwise benefit from this).
%   No other current transformation's params has this "editable
%   source text plus a separately compiled plan" shape (the rest
%   are flat settings structs, or -- ReRef/SelectData -- a single
%   EEGLAB history command string with nothing compiled to keep in
%   sync), so this only ever fires for DefineBins in practice.
    if isstruct(p) && isfield(p, 'script') && isfield(p, 'bins')
        p = rmfield(p, 'bins');
    end
end
