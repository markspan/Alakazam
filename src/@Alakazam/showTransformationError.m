function showTransformationError(this, transformId, ME, varargin)
%SHOWTRANSFORMATIONERROR  Calm, explanatory report of a failed
%   transformation, instead of MATLAB's default raw stack trace.
%
%   showTransformationError(THIS, ID, ME) reports ME, raised while running
%   transformation ID. Name-value options say when it was raised and what
%   became of the result ('Phase', 'Dataset', 'Kept'); they are those of
%   explainTransformationError, which writes the text, so the wording can
%   be tested without a figure.
%
%   The error is not rethrown. This is the top of the callback chain from
%   the ribbon, so there is nothing above it to handle it, and rethrowing is
%   what used to dump the full stack trace into the command window on top of
%   the dialog.
%
%   See also EXPLAINTRANSFORMATIONERROR, ONTRANSFORMATION.
    [title, message] = explainTransformationError(transformId, ME, varargin{:});
    uialert(this.MainFigure, message, title, 'Icon', 'warning');
end
