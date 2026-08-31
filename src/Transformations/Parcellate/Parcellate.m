function [EEG, options] = Parcellate(input, varargin)
%% Parcellate  Turn an averaged ERP into anatomical region time courses.
%
%   Estimates cortical sources for every bin, then reduces the 20484-vertex
%   estimate to one signed time course per anatomical region. The result is
%   an ordinary Alakazam dataset whose "channels" ARE the regions.
%
%   THAT LAST POINT IS THE WHOLE DESIGN. Nothing downstream of a dataset
%   assumes "channel" means "electrode": ERP Measure, grand averaging, the
%   ERP plot, the measurements CSV and the report pipeline all treat a
%   channel as a named spatial unit with one waveform per bin. So a region
%   dataset flows through every one of them unchanged, and region time
%   courses become measurable, exportable and reportable without a parallel
%   code path existing anywhere.
%
%   SIGNED, NOT MAGNITUDE. A free-orientation inverse gives three dipole
%   components per vertex. The 3-D brain view collapses them to their L2
%   norm, which is always positive -- fine for a picture, wrong for a
%   measurement, because an ERP's polarity then has no expression at all.
%   This projects onto the cortical normal instead, keeping the sign (see
%   TransTools.SurfaceNormals for why that direction specifically).
%
%   WHAT THE SIGN MEANS is worth being precise about, because it is easy to
%   overclaim: it is relative to each region's own dominant cortical normal,
%   which is a convention. It is NOT comparable between regions. It IS
%   comparable across bins, conditions and subjects within a region, because
%   every subject shares the same template source model, so the flips are
%   identical for everyone -- which is exactly the comparison a
%   within-subjects design asks for.
%
%   SCALP VIEWS WILL REFUSE THE RESULT, correctly. Region names do not match
%   10-5 nomenclature, so ScalpDistribution/Brain3D find no positioned
%   channels and say so. A region dataset has no scalp geometry; there is
%   nothing for a topography to draw.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = Parcellate(input)        % interactive dialog
%     [EEG, options] = Parcellate(input, opts)  % replay stored settings
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:Parcellate', varargin{:});

if ~isfield(input, 'data') || isempty(input.data)
    throw(MException('Alakazam:Parcellate', ...
        'Problem in Parcellate: this dataset has no data to estimate sources from.'));
end
if ~isfield(input, 'chanlocs') || isempty(input.chanlocs)
    throw(MException('Alakazam:Parcellate', ...
        ['Problem in Parcellate: this dataset has no channel structure, so I cannot ' ...
         'work out where its electrodes were.']));
end
if isfield(input, 'isParcellated') && input.isParcellated
    throw(MException('Alakazam:Parcellate', ...
        ['Problem in Parcellate: this dataset is already parcellated -- its channels ' ...
         'are anatomical regions, not electrodes, so there are no scalp signals left ' ...
         'to estimate sources from.']));
end

if interactive
    options = ParcellateDialog(input);
    if isempty(options)
        EEG = [];            % cancelled -- no node, no compute
        options = [];
        return;
    end
    TransformSettings.set('Parcellate', options);
else
    options = opts;
end

if ~isstruct(options)
    EEG = input;             % nothing recorded
    return;
end

method = TransTools.FieldOr(options, 'Method', 'mne');

% Relabel the app's own busy indicator for each slow phase. Building the
% forward model takes about twenty seconds on a first run and dwarfs
% everything after it; left under the generic "Running Parcellate...", that
% stretch reads as a hang rather than as progress.
TransTools.BusyGate('message', 'Building the head model...');
[leadfield, sourcemodel, resolvedLabels, elec, headmodel] = ...
    TransTools.BuildSourceForwardModel({input.chanlocs.labels});
normals = TransTools.SurfaceNormals(sourcemodel);
TransTools.BusyGate('message', 'Estimating sources and parcellating...');

% Reorder to the leadfield's own channel order -- REQUIRED, not optional:
% see BuildSourceForwardModel's header for why getting this wrong scrambles
% the result silently.
labels = {input.chanlocs.labels};
[tf, reorder] = ismember(lower(resolvedLabels), lower(labels));
if ~all(tf)
    throw(MException('Alakazam:Parcellate', ...
        ['Problem in Parcellate: a channel the forward model resolved is missing from ' ...
         'this dataset, which should not be possible. I would rather stop than guess.']));
end

nBins = size(input.data, 3);
perBin = cell(1, nBins);
regionLabels = {};

parcelOpts = struct( ...
    'Atlas',       TransTools.FieldOr(options, 'Atlas', 'aal'), ...
    'Mode',        TransTools.FieldOr(options, 'Mode', 'mean_flip'), ...
    'MinVertices', TransTools.FieldOr(options, 'MinVertices', 20));

for b = 1:nBins
    values = double(input.data(reorder, :, b));

    signed = TransTools.InverseSolution(values, leadfield, elec, headmodel, method, ...
        struct('Orientation', 'normal', 'Normals', normals));

    [perBin{b}, labelsThisBin, parcelInfo] = ...
        TransTools.ParcellateSource(signed, sourcemodel, parcelOpts);

    if b == 1
        regionLabels = labelsThisBin;
    elseif ~isequal(labelsThisBin, regionLabels)
        % Geometry is identical across bins, so this cannot come from the
        % atlas -- only from a region being dropped for having no finite
        % values in one bin, which would silently misalign the third
        % dimension. Caught here rather than left for cat() to report as a
        % dimension mismatch, because the cause is worth naming.
        throw(MException('Alakazam:Parcellate', ...
            ['Problem in Parcellate: bin %d produced a different set of regions from ' ...
             'bin 1, so they cannot be stacked into one dataset.'], b));
    end
end

% Collected then stacked, rather than written into a preallocation the loop
% could only size on its first pass: the region count is not known until the
% first bin has been parcellated, and a preallocation inside the loop needs
% an AGROW suppression to hide growth that is not actually happening.
regionCourses = cat(3, perBin{:});

% Region selection, applied AFTER parcellation so the recorded options stay
% meaningful on replay: naming regions is stable across datasets, whereas an
% index into whatever survived MinVertices is not.
wanted = flattenNames(TransTools.FieldOr(options, 'Regions', {}));
if ~isempty(wanted)
    keep = ismember(lower(regionLabels), lower(wanted));
    if ~any(keep)
        throw(MException('Alakazam:Parcellate', ...
            ['Problem in Parcellate: none of the regions you chose came out of this ' ...
             'dataset. They may have been below the minimum vertex count, or belong ' ...
             'to a different atlas than the one selected.']));
    end
    regionCourses = regionCourses(keep, :, :);
    regionLabels  = regionLabels(keep);
end

EEG = input;
EEG.data     = regionCourses;
EEG.chanlocs = regionChanlocs(regionLabels);
EEG.nbchan   = numel(regionLabels);
EEG.isParcellated = true;
EEG.parcellation  = parcelInfo;
EEG.parcellation.Method  = method;
EEG.parcellation.Regions = regionLabels;
end

% ======================================================================= %
function chanlocs = regionChanlocs(labels)
%REGIONCHANLOCS  A chanlocs array naming regions, with NO positions.
%   Deliberately empty X/Y/Z rather than, say, each region's centroid.
%   A centroid would let scalp topographies and the 3-D brain view silently
%   accept a region dataset and draw something plausible-looking from 85
%   scattered points, which would be a picture of nothing. Empty positions
%   make those views refuse it, which is the correct answer.
    chanlocs = struct('labels', labels(:)', 'type', 'SRC', ...
        'X', [], 'Y', [], 'Z', [], ...
        'theta', [], 'radius', [], ...
        'sph_theta', [], 'sph_phi', [], 'sph_radius', []);
end

function names = flattenNames(value)
%FLATTENNAMES  A cellstr of region names, from char, string, cell or a cell
%   nested one deeper than intended.
%
%   The nesting case is not hypothetical politeness. struct('Regions', {x})
%   unwraps one cell level and plain field assignment does not, so the same
%   literal produces different shapes depending on how the options struct
%   was built -- a trap this codebase has hit repeatedly (EventEditor keeps
%   flattenTypes for exactly the same reason). Accepting both costs four
%   lines and removes a whole class of caller bug.
    names = {};
    if isempty(value)
        return;
    end
    if ischar(value) || isstring(value)
        names = cellstr(string(value(:)'));
        return;
    end
    if ~iscell(value)
        return;
    end
    for k = 1:numel(value)
        names = [names, flattenNames(value{k})]; %#ok<AGROW>
    end
end
