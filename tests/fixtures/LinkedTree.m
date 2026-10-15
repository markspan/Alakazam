classdef LinkedTree < handle
%LINKEDTREE  The parts of WorkSpaceTree that walk a node's ancestry:
%   allNodes, findByFile, lineageOf, rootOf and parentFile, over nodes added
%   with their parents. Nodes are struct(Id, Name, UserData, IsRoot), as
%   WorkSpaceTree hands them out.
%
%       tree = LinkedTree();
%       s01 = tree.add('S01', '', rawFile);
%       avg = tree.add('Average', s01, averageFile);
%
%   See also FAKETREE, FAKEAPP, METHODCOPY.
    properties
        Nodes = struct('Id', {}, 'Name', {}, 'UserData', {}, 'IsRoot', {})
        Parents = {}
    end

    methods
        function id = add(this, name, parentId, file)
            id = sprintf('n%d', numel(this.Nodes) + 1);
            this.Nodes(end + 1) = struct('Id', id, 'Name', name, 'UserData', file, ...
                'IsRoot', isempty(parentId));
            this.Parents{end + 1} = parentId;
        end

        function nodes = allNodes(this)
            nodes = this.Nodes;
            if isempty(nodes)
                nodes = [];
            end
        end

        function id = findByFile(this, file)
            id = '';
            k = find(strcmp({this.Nodes.UserData}, char(file)), 1);
            if ~isempty(k)
                id = this.Nodes(k).Id;
            end
        end

        function nodes = lineageOf(this, id)
            nodes = this.Nodes([]);
            k = this.index(id);
            while ~isempty(k)
                nodes = [this.Nodes(k), nodes]; %#ok<AGROW>
                k = this.index(this.Parents{k});
            end
        end

        function node = rootOf(this, id)
            lineage = this.lineageOf(id);
            node = [];
            if ~isempty(lineage)
                node = lineage(1);
            end
        end

        function file = parentFile(this, id)
            file = '';
            k = this.index(id);
            if ~isempty(k)
                p = this.index(this.Parents{k});
                if ~isempty(p)
                    file = this.Nodes(p).UserData;
                end
            end
        end
    end

    methods (Access = private)
        function k = index(this, id)
            k = [];
            if ~isempty(id)
                k = find(strcmp({this.Nodes.Id}, id), 1);
            end
        end
    end
end
