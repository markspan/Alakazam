function [opts, interactive] = InitGuard(nargin_, errorId, varargin)
%INITGUARD  The nargin/'Init'-sentinel dance every options-driven
%   transformation opens with. Call as the very first line, with the
%   transformation's own signature changed from a named optional
%   parameter to varargin (`function [EEG, opts] = <Name>(input, opts)`
%   becomes `function [EEG, opts] = <Name>(input, varargin)`):
%       [opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:<Name>', varargin{:});
%
%   NARGIN_ must be the CALLING function's own nargin -- MATLAB's nargin is
%   a builtin that only reflects the function it is evaluated in, so it
%   has to be passed in, not read here. VARARGIN{:} is the calling
%   function's own varargin, forwarded through: passing a possibly-unset
%   named OPTS parameter directly (instead of varargin) would error at the
%   call site whenever nargin<2, since MATLAB eagerly evaluates every
%   argument expression before a function is entered, and an unsupplied
%   named parameter cannot be referenced at all -- unlike varargin, which
%   is always defined (an empty cell array when nothing extra was passed).
%
%   Throws the standard "needs a dataset to run on, and none was given"
%   MException (prefixed "Problem in <Name>: ...", NAME taken from the
%   part of ERRORID after the colon, matching every transformation's own
%   convention) when NARGIN_ < 1. Otherwise returns OPTS (the 'Init'
%   sentinel if none was supplied) and INTERACTIVE (true exactly when OPTS
%   is that sentinel, meaning "no stored options yet -- run the
%   interactive dialog" as opposed to a replay of a stored options struct).
%
%   Previously reimplemented, identically down to the exact
%   `(ischar(opts) || isstring(opts)) && strcmpi(string(opts), "Init")`
%   formula, in ChannelEditor.m, DefineBins.m, Filter.m, Interpolate.m,
%   Measure.m, ReRef.m, RemoveComponents.m, Resample.m, SelectData.m and
%   SpectralMeasure.m (with two slightly different "No Data Supplied" /
%   "needs a dataset to run on, and none was given" throw messages between
%   them); consolidated here under the latter, more descriptive wording. A
%   second pass folded in the remaining stragglers -- Baseline.m,
%   Average.m, AutoEyeICA.m, AutoGEDAI.m, ArtefactDetect.m,
%   ScalpDistribution.m and Brain3D.m (all `function [EEG,opts] =
%   Name(input,varargin)`, forwarding `varargin{:}` here directly, same
%   shape as ReRef.m's own conversion above), plus CoherenceMap.m,
%   CoherenceTopography.m, TimeFrequency.m and Fourier.m, which instead
%   take a single `varargin` with INPUT itself as varargin{1}, so they
%   forward `varargin{2:end}` here rather than the whole varargin.
    if nargin_ < 1
        parts = strsplit(errorId, ':');
        throw(MException(errorId, sprintf( ...
            'Problem in %s: needs a dataset to run on, and none was given.', parts{end})));
    end
    if isempty(varargin)
        opts = 'Init';
    else
        opts = varargin{1};
    end
    interactive = (ischar(opts) || isstring(opts)) && strcmpi(string(opts), "Init");
end
