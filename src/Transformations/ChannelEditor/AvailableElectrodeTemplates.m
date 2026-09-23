function templates = AvailableElectrodeTemplates()
%AVAILABLEELECTRODETEMPLATES  Every electrode template Channel Editor's
%   "Look up locations" can offer, as a struct array with .name (for a
%   dropdown) and .file (a full path readlocs can open). "Standard 10-5" is
%   always first, the rest follow in alphabetical order.
%
%   NOT JUST THE 10-5 SYSTEM. The button used to be called "Look up 10-5
%   locations" and only ever offered that one template. That stopped being
%   generic the day an equidistant montage arrived
%   (src/Electrodes/standard_waveguard64_equidistant.elc): its labels carry
%   no anatomy at all (0Z, 1L, 1LB, ...), so a 10-5 lookup cannot fill it in
%   -- a different template is not an edge case for it, it is the normal
%   case. A NEW MONTAGE IS ADDED BY DROPPING ITS FILE INTO src/Electrodes,
%   not by editing this function: every recognised channel-location file
%   there (see readlocs' own list of supported extensions) is offered
%   automatically. See src/Electrodes/README.md for what is already there,
%   its provenance and its licence.
%
%   THE 10-5 ENTRY PREFERS THE INSTALLED TOOLBOX COPY, via Template1005File
%   -- the same file AutoEyeICA, RemoveComponents and every scalp-map caller
%   already resolve positions from -- so choosing "Standard 10-5" here
%   matches what the rest of the app means by that name. It falls back to
%   the vendored copy in src/Electrodes only when neither FieldTrip nor
%   dipfit is on the path (Template1005File then throws), so a checkout
%   with no EEGLAB toolbox installed still offers a 10-5 option rather than
%   silently losing it. That vendored copy is otherwise skipped, to avoid
%   listing the same 346 positions twice under two names.
%
%   See also TEMPLATE1005FILE, CHANNELEDITORDIALOG, CHANNELEDITOR.
    templates = struct('name', {}, 'file', {});

    % Three fileparts from ChannelEditor/AvailableElectrodeTemplates.m: up to
    % ChannelEditor, up to Transformations, up to src -- the same pattern
    % Brain3DView.m uses (two fileparts) to find its sibling src/Meshes,
    % adjusted for the extra transformation-folder level this file sits under.
    srcRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    vendoredDir = fullfile(srcRoot, 'Electrodes');
    vendored1005 = fullfile(vendoredDir, 'standard_1005.elc');

    skip1005 = false;
    try
        templates(end + 1) = struct('name', 'Standard 10-5', ...
            'file', TransTools.Template1005File('Alakazam:AvailableElectrodeTemplates'));
        skip1005 = true;
    catch
        % Neither toolbox installed: the vendored copy below stands in, so
        % "Standard 10-5" still appears rather than being left off entirely.
    end

    files = dir(fullfile(vendoredDir, '*.elc'));
    extra = struct('name', {}, 'file', {});
    for k = 1:numel(files)
        f = fullfile(files(k).folder, files(k).name);
        isVendored1005 = strcmpi(f, vendored1005);
        if isVendored1005 && skip1005
            continue;
        end
        if isVendored1005
            name = 'Standard 10-5';
        else
            name = prettyTemplateName(files(k).name);
        end
        extra(end + 1) = struct('name', name, 'file', f); %#ok<AGROW>
    end
    if ~isempty(extra)
        [~, order] = sort({extra.name});
        templates = [templates, extra(order)];
    end
end

% ----------------------------------------------------------------------- %
function name = prettyTemplateName(filename)
%PRETTYTEMPLATENAME  "standard_waveguard64_equidistant.elc" -> "Waveguard64
%   equidistant". Cosmetic only -- the file it points at is what matters.
    [~, stem] = fileparts(filename);
    stem = regexprep(stem, '^standard_', '');
    stem = strrep(stem, '_', ' ');
    if isempty(stem)
        name = filename;
        return;
    end
    name = [upper(stem(1)), stem(2:end)];
end
