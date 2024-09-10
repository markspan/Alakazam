function Ledalab(varargin)
% LEDALAB Main function to initialize and run Ledalab.
%
% Usage:
%   Ledalab()          % Run Ledalab in GUI mode.
%   Ledalab('param', value, ...)  % Run Ledalab in batch mode with specified parameters.
%
% Parameters:
%   Various parameters can be specified for batch mode processing.
%
% Global Variables:
%   leda2: Struct containing current and internal state of the analysis.
%
% Example:
%   Ledalab('dir', 'data/', 'analyze', 'CDA', 'optimize', 3);

    clc;
    close all;
    clear global leda2

    global leda2

    % Initialize global structure with version information
    leda2.intern.name = 'Ledalab';
    leda2.intern.version = 3.49;
    versiontxt = num2str(leda2.intern.version,'%3.2f');
    leda2.intern.versiontxt = ['V',versiontxt(1:3),'.',versiontxt(4:end)];
    leda2.intern.version_datestr = '2016-04-18';

    % Add all subdirectories to Matlab path
    file = which('Ledalab.m');
    if isempty(file)
        errormessage('Can''t find Ledalab installation. Change to Ledalab install directory');
        return;
    end
    leda2.intern.install_dir = fileparts(file);
    addpath(genpath(leda2.intern.install_dir));

    % Load preset settings
    ledapreset;

    % Determine if running in batch mode or GUI mode based on input arguments
    if nargin > 0
        % Batch-Mode
        leda2.intern.batchmode = 1;
        leda2.intern.prompt = 0;
        leda2.pref.updateFit = 0;
        leda_batchanalysis(varargin{:});

    else
        % GUI-Mode
        leda2.intern.batchmode = 0;

        % Display the Ledalab logo
        ledalogo;
        pause(1);
        delete(leda2.gui.fig_logo);

        % Initialize and display the GUI
        ledagui;

        % Log the start of the session
        add2log(0,['>>>> ',datestr(now,31), ' Session started'],1,1);
    end
end
