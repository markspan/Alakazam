classdef MethodCopy
%METHODCOPY  Run a real @Alakazam / @WorkSpace method against a fake `this`.
%
%   The methods that replay and recalculate branches are files in a class
%   folder, callable only on a live Alakazam (a uifigure, a ribbon, a tree).
%   Their logic is orchestration, and it is the part that decides how often a
%   node is read from disk. MethodCopy copies the method's own source into a
%   folder on the path under a new name, so a test can call the REAL code with a
%   FakeApp in place of `this`. The copy is made at test time from the file in
%   src, so it cannot drift from it.
%
%   See also FAKEAPP, FAKETREE.
    methods (Static)
        function name = make(folder, classFolder, methodName, newName)
        %MAKE  Copy src/<classFolder>/<methodName>.m into FOLDER as NEWNAME.m.
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            source = fullfile(root, 'src', classFolder, [methodName '.m']);
            text = fileread(source);
            pattern = ['(function\s+(?:\[[^\]]*\]\s*=\s*|\w+\s*=\s*)?)' methodName '\('];
            renamed = regexprep(text, pattern, ['$1' newName '('], 'once');
            if strcmp(renamed, text)
                error('MethodCopy:noMatch', 'No function line named %s in %s.', methodName, source);
            end
            fid = fopen(fullfile(folder, [newName '.m']), 'w');
            fwrite(fid, renamed);
            fclose(fid);
            name = newName;
        end
    end
end
