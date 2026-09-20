classdef FakeApp < handle & dynamicprops
%FAKEAPP  A stand-in for the Alakazam object, whose members are whatever a
%   test gives it. Each field of the struct passed in becomes a property, and a
%   property that holds a function handle is called like a method:
%   app.persistResultNode(a, b) runs the handle with (a, b).
%
%   See also METHODCOPY, FAKETREE.
    methods
        function this = FakeApp(members)
            if nargin < 1
                return;
            end
            for name = fieldnames(members)'
                this.addprop(name{1});
                this.(name{1}) = members.(name{1});
            end
        end
    end
end
