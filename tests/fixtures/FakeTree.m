classdef FakeTree < handle
%FAKETREE  The parts of WorkSpaceTree that the loading and recalculation code
%   uses, recording what it is asked to add. Nodes are struct(Id, Name,
%   UserData, IsRoot), as WorkSpaceTree hands them out.
%
%   See also FAKEAPP, METHODCOPY.
    properties
        Nodes = struct('Id', {}, 'Name', {}, 'UserData', {}, 'IsRoot', {})
        Added = {}          % one {label, parentId, icon, file, opts} per addNode
    end

    methods
        function this = FakeTree(files)
            if nargin < 1
                return;
            end
            for k = 1:numel(files)
                this.Nodes(end + 1) = struct('Id', sprintf('n%d', k), ...
                    'Name', sprintf('node%d', k), 'UserData', files{k}, 'IsRoot', k == 1);
            end
        end

        function node = addNode(this, label, parentId, icon, file, opts)
            this.Added(end + 1, :) = {label, parentId, icon, file, opts};
            node = struct('Id', sprintf('a%d', size(this.Added, 1)), 'Name', label, ...
                'UserData', file, 'IsRoot', false);
        end

        function nodes = allNodes(this)
            nodes = this.Nodes;
            if isempty(nodes)
                nodes = [];
            end
        end
    end
end
