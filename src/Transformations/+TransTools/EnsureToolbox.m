function EnsureToolbox(spec)
%ENSURETOOLBOX  Make a pinned, consent-gated toolbox usable, installing it
%   with the user's agreement when it is not there.
%
%   TransTools.EnsureToolbox(SPEC) returns quietly when the toolbox is on
%   the path, or installed from an earlier session (it is then reattached).
%   Otherwise it asks, once, whether to download it, and throws
%   Alakazam:ToolboxMissing if the answer is no. SPEC is a struct:
%
%     .Name        what the dialog calls it ('The PREP pipeline')
%     .Feature     the transformation that needs it ('PREP')
%     .Probe       a function it provides ('prepPipeline')
%     .ProbeFile   the file that function lives in ('prepPipeline.m')
%     .Folder      its install folder under Documents/MATLAB ('PrepPipeline')
%     .Url         the pinned archive
%     .Version     the pinned version, for the dialog ('0.56.0')
%     .About       one sentence: who made it, under what licence, what for
%     .Subfolders  true when its subfolders must be on the path too
%
%   ONE FUNCTION FOR EVERY SUCH TOOLBOX. Unfold, EYE-EEG, FieldTrip and GEDAI
%   each carry their own copy of this pattern (find it, reattach it, ask,
%   download, attach), which is four places to fix the same bug. A toolbox
%   added after them describes itself in a SPEC and calls this, so the
%   pattern lives once and the description is data a test can read.
%
%   PINNED, for the reason every downloaded dependency here is: an analysis
%   whose numbers change because of when someone happened to install is not
%   reproducible. Update the SPEC by hand when a refresh is wanted, and
%   re-run the suite against it.
%
%   See also TRANSTOOLS.TOOLBOXAVAILABLE, EEGLABENVIRONMENT.INSTALLFROMZIP.
    if TransTools.ToolboxAvailable(spec)
        return;
    end

    % LEGACY-JAVA-GUI: questdlg, matching the other consent-gated installs
    % (Unfold.ensure, EyeEeg.ensure, ensureFieldTrip, AutoGEDAI).
    answer = questdlg([ ...
        spec.Feature ' needs ' spec.Name ', which was not found on the MATLAB path.', ...
        newline, newline, spec.About, ' This downloads version ', spec.Version, ...
        ' into your Documents/MATLAB folder.', newline, newline, ...
        'Download and install it now?'], ...
        [spec.Name ' not found'], ...
        'Download and install', 'Cancel', 'Download and install');

    if ~strcmp(answer, 'Download and install')
        throw(MException('Alakazam:ToolboxMissing', '%s', sprintf([ ...
            'I''m afraid %s needs %s, which could not be found on the MATLAB path. As its ' ...
            'installation was declined, would you install it yourself from %s (and add it to ' ...
            'the MATLAB path), or run %s again and accept the download?'], ...
            spec.Feature, spec.Name, spec.Url, spec.Feature)));
    end

    EEGLabEnvironment.installFromZip(spec.Url, spec.Folder, spec.ProbeFile);
    if ~TransTools.ToolboxAvailable(spec)   % attaches the subfolders when it needs them
        throw(MException('Alakazam:ToolboxMissing', ['I downloaded %s, but cannot find %s ' ...
            'in it afterwards, so I am not confident the install worked. Would you look in ' ...
            'Documents/MATLAB/%s?'], spec.Name, spec.Probe, spec.Folder));
    end
end
