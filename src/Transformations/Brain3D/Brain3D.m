function [EEG, opts] = Brain3D(input, varargin)
%% Brain3D  Resolve scalp positions for a rotatable 3D brain-mesh ERP projection.
%
%   A normal, persisted transformation (Alakazam.onTransformation), exactly
%   like ScalpDistribution.m -- same tree-node/tab treatment, drawn instead
%   by Brain3DView. Delegates the actual resolving work to
%   TransTools.ResolveScalpDistribution, which ScalpDistribution.m also
%   uses: both need the identical EEG.ScalpChanlocs/.ScalpHasPos/
%   .ScalpMapLimit/.ScalpSourceFile: the difference between this
%   transformation and ScalpDistribution is entirely in the view, not in
%   what gets resolved here -- Brain3DView projects the interpolated
%   values onto a real 3D ICBM152 brain surface (TransTools.ReadBrainMeshNV
%   / TransTools.DrawBrainMap) instead of drawing a flat 2D topoplot.
%
%   Works on either a per-subject Average or a Grand Average, same as
%   ScalpDistribution.
%
%   TOOLBOX OR OWN CODE. As ScalpDistribution: only the electrode positions
%   are resolved here, from EEGLAB's readlocs and the 10-5 template; the brain
%   projection is drawn by Brain3DView, and its source-estimate mode is
%   FieldTrip's (SourceEstimate).
%
%   Signature (Alakazam transformation contract, matching Average.m):
%   Brain3D has no real options, so OPTS is accepted and returned
%   unchanged, purely to satisfy the two-output/replay contract.
%     [EEG, opts] = Brain3D(input, opts)
%
%   See also SCALPDISTRIBUTION, BRAIN3DVIEW, TRANSTOOLS.RESOLVESCALPDISTRIBUTION.

opts = TransTools.InitGuard(nargin, 'Alakazam:Brain3D', varargin{:});

EEG = TransTools.ResolveScalpDistribution(input, 'Alakazam:Brain3D');
