function elcFile = Dipfit1005File(errorId)
%DIPFIT1005FILE  Absolute path to dipfit's standard 10-5 electrode template.
%   ELCFILE = DIPFIT1005FILE(ERRORID) resolves the 343-electrode 10-5 system
%   template (an .elc file, ASA format, precomputed via OpenMEEG -- the same
%   provenance as GEDAI's own bundled copy, see GedaiElcFile) bundled with
%   the dipfit plugin, via fileparts(which('dipfitdefs')): pop_chanedit's
%   'lookup' only special-cases a couple of specific filenames by name (see
%   pop_chanedit.m), so a full path is needed regardless of which template
%   is used.
%
%   Used by AutoEyeICA, which is independent of GEDAI and so uses dipfit's
%   copy rather than reaching into GEDAI's plugin folder for one.
%
%   See also: FillChanlocs, EnsureChanlocs, AutoEyeICA.

    dipfitRoot = fileparts(which('dipfitdefs'));
    if isempty(dipfitRoot)
        throw(MException(errorId, ...
            ['Cannot auto-fill electrode positions: the dipfit plugin ' ...
             '(which ships the standard 10-5 template) was not found on ' ...
             'the MATLAB path.']));
    end
    elcFile = fullfile(dipfitRoot, 'standard_BEM', 'elec', 'standard_1005.elc');
    if exist(elcFile, 'file') ~= 2
        throw(MException(errorId, ...
            'Cannot auto-fill electrode positions: %s was not found.', elcFile));
    end
end
