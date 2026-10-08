function written = writeExportSidecars(folder, sidecars)
%WRITEEXPORTSIDECARS  Write the files an exported script reads, into FOLDER.
%   WRITTEN = writeExportSidecars(FOLDER, SIDECARS) writes each element of
%   SIDECARS (.name, .content): text as it is, a struct as a .mat file of its
%   fields. WRITTEN lists the files. An export's script reads them from its
%   own folder, so they go where the script goes.
%
%   See also EXPORTFIELDTRIPSCRIPT, ALAKAZAM.ONEXPORTFIELDTRIPSCRIPT.
    written = cell(1, numel(sidecars));
    for k = 1:numel(sidecars)
        file = fullfile(folder, sidecars(k).name);
        content = sidecars(k).content;
        if isstruct(content)
            save(file, '-struct', 'content');
        else
            fid = fopen(file, 'w');
            if fid < 0
                throw(MException('Alakazam:writeExportSidecars', ...
                    'I couldn''t open "%s" for writing.', file));
            end
            fwrite(fid, content, 'char');
            fclose(fid);
        end
        written{k} = file;
    end
end
