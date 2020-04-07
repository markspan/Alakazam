# Alakazam
Modular EEG analysis software package in MATLAB

![Screenshot](/ScreenShot.jpg)

The general idea is to create a user interface to do EEG analysis. This is work in progress!

The interface is based on the [Toolgroup](http://undocumentedmatlab.com/articles/matlab-toolstrip-part-2-toolgroup-app) demo, and is vey much influenced by the "[Brainvision Analyser](https://www.brainproducts.com/promo_analyzer2.php)" interface.
Timeseries plotting based on [plotECG](https://nl.mathworks.com/matlabcentral/fileexchange/59296-daniel-frisch-kit-plot-ecg)  by Daniel Frisch. 
The generic data object used for a study is the [EEGLAB](https://sccn.ucsd.edu/eeglab/index.php) "EEG" structure. Alakazam does put some extra info in this structure when it writes its own .mat files.
Take a look at the "Transformations" directory to get the idea of how to add computations to the package.

``` Matlab
function [EEG, options] = SelectData(input,opts)
%% Example Transformation simply calling EEGLAB function
% Transformations should return the transformed data in the EEG structure, 
% and an options variable ("options") it can understand. In this case, as
% we use the EEGLAB function, the commandline history is returned.
% Input must (in principle) contain a data structure (EEG), and optionally 
% the options variable obtained from a previous call. If this second
% variable is availeable, no user interaction takes place, but the
% Transformation is performed based op the given options. This second form
% occurs when the transformation is dragged in th tree upto another
% dataset.

%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:SelectData','Problem in SelectData: No Data Supplied');
    throw(ME);
end

%% Was this a call from the menu? 
if (nargin == 1)
    options = 'Init';
else
    options = opts;
end

EEG = input;
%% if it was, call the interactive version of the Transformation
% in this case the pop_select version.
if (ischar(options))
    if (strcmpi(options, 'Init'))
        [EEG, options] = pop_select(input);
        % in EEGLAB, the second return value is the function call to recreate the
        % transformation.
    end
else
    eval(options.Param)
    % so, when we evaluate this return value, it will recreate the
    % transformation on the "EEG" structure.
end

