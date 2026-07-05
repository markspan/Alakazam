classdef hEEG < handle
    %UNTITLED Summary of this class goes here
    %   Detailed explanation goes here

    properties
        EEG
    end

    methods
        function obj = toHandle(obj, vEEG)
            %UNTITLED Construct an instance of this class
            %   Detailed explanation goes here
            obj.EEG = vEEG;
        end
    end
end