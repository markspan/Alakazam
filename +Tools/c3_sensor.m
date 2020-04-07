classdef c3_sensor < handle
    properties
        data
        dataRaw
        fs
        samplenum
        filepath
    end
    
    methods               
        function remove_jitter(this, filter_length)
            if nargin < 2
                filter_length = 20;
            end
            % Sensor filter. Filter sensor data to remove jitter
            filter_coeff = ones(1,filter_length)./filter_length;
            gd = ceil(mean(grpdelay(filter_coeff)));
            
            tmp = filter(filter_coeff, [1], vertcat(...
            bsxfun(@times,ones(filter_length,size(this.data,2)),this.data(1,:)),... 
            this.data,... 
            bsxfun(@times,ones(filter_length+gd,size(this.data,2)),this.data(end,:))));
        
            this.data = tmp(filter_length+gd+1:end-filter_length,:);
        end
        
        function filter(this, B, A)
            % @Override filter(B,A,X)
            this.data = filter(B, A, this.data);
        end
    end
    
end