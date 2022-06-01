function varargout = FourierGui(varargin)
% FOURIERGUI M-file for FourierGui.fig
%      FOURIERGUI, by itself, creates a new FOURIERGUI or raises the existing
%      singleton*.
%
%      H = FOURIERGUI returns the handle to a new FOURIERGUI or the handle to
%      the existing singleton*.
%
%      FOURIERGUI('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in FOURIERGUI.M with the given input arguments.
%
%      FOURIERGUI('Property','Value',...) creates a new FOURIERGUI or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before FourierGui_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to FourierGui_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
% 
% See also: GUIDE, GUIDATA, GUIHANDLES

% Edit the above text to modify the response to help FourierGui

% Last Modified by GUIDE v2.5 16-Aug-2009 21:35:12

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @FourierGui_OpeningFcn, ...
                   'gui_OutputFcn',  @FourierGui_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT


% --- Executes just before FourierGui is made visible.
function FourierGui_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to FourierGui (see VARARGIN)

% Choose default command line output for FourierGui
%handles.output = hObject;

% Update handles structure

handles.options.Name            = 'Fourier';
handles.options.Resolution      = 'Max';
handles.options.ResVal          = 1;
handles.options.Output          = 'Voltage';
handles.options.Complex         = 'On';
handles.options.FullSpectrum    = 'On';
handles.options.Normalize       = 'On';
handles.options.Interval        = [0.5 125];
handles.options.Window          = 'Hanning';
handles.options.Window_Length   = 100;
handles.options.Compression     = 'On';
handles.options.CompRes         = 10;

if ~isempty(varargin)
    handles.options = varargin{1};
end


handles.output = handles.options;

handles = TransTools.SelectWindow(handles);
guidata(handles.figure1,handles);

%handles = SelectWindow(handles);
guidata(hObject, handles);
% UIWAIT makes FourierGui wait for user response (see UIRESUME)
uiwait(handles.figure1);


% --- Outputs from this function are returned to the command line.
function varargout = FourierGui_OutputFcn(hObject, eventdata, handles) 
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
varargout{1} = handles.options;
delete(handles.figure1);


% --- Executes on button press in OK_Button.
function OK_Button_Callback(hObject, eventdata, handles)
% hObject    handle to OK_Button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

ResObj = get(handles.ResolutionRadio,'SelectedObject');
handles.options.Resolution = get(ResObj, 'Tag');
OutObj = get(handles.OutPutRadio,'SelectedObject');
handles.options.Output      = get(OutObj, 'Tag');

if (get(handles.ComplexBox, 'Value'))
    handles.options.Complex = 'On';
else
    handles.options.Complex = 'Off';
end
if (get(handles.SpecBox, 'Value'))
    handles.options.FullSpectrum = 'On';
else
    handles.options.FullSpectrum = 'Off';
end
if (get(handles.NormBox, 'Value'))
    handles.options.Normalize = 'On';
else
    handles.options.Normalize = 'Off';
end
handles.options.Interval(1) = str2double(get(handles.IntStart,'String'));
handles.options.Interval(2) = str2double(get(handles.IntEnd,'String'));

guidata(hObject,handles);
uiresume;


% --- Executes on button press in Cancel_Button.
function Cancel_Button_Callback(hObject, eventdata, handles)
% hObject    handle to Cancel_Button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
handles.options = [];
guidata(hObject,handles);
uiresume;


% --- Executes on button press in ComplexBox.
function ComplexBox_Callback(hObject, eventdata, handles)
% hObject    handle to ComplexBox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of ComplexBox


% --- Executes on button press in SpecBox.
function SpecBox_Callback(hObject, eventdata, handles)
% hObject    handle to SpecBox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of SpecBox


% --- Executes on button press in NormBox.
function NormBox_Callback(hObject, eventdata, handles)
% hObject    handle to NormBox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of NormBox



function IntStart_Callback(hObject, eventdata, handles)
% hObject    handle to IntStart (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of IntStart as text
%        str2double(get(hObject,'String')) returns contents of IntStart as a double


% --- Executes during object creation, after setting all properties.
function IntStart_CreateFcn(hObject, eventdata, handles)
% hObject    handle to IntStart (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function IntEnd_Callback(hObject, eventdata, handles)
% hObject    handle to IntEnd (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of IntEnd as text
%        str2double(get(hObject,'String')) returns contents of IntEnd as a double


% --- Executes during object creation, after setting all properties.
function IntEnd_CreateFcn(hObject, eventdata, handles)
% hObject    handle to IntEnd (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function OtherResolutionValue_Callback(hObject, eventdata, handles)
% hObject    handle to OtherResolutionValue (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of OtherResolutionValue as text
%        str2double(get(hObject,'String')) returns contents of OtherResolutionValue as a double
handles.options.ResVal          = str2double(get(hObject,'String'));
guidata(handles.figure1,handles);

% --- Executes during object creation, after setting all properties.
function OtherResolutionValue_CreateFcn(hObject, eventdata, handles)
% hObject    handle to OtherResolutionValue (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes when user attempts to close figure1.
function figure1_CloseRequestFcn(hObject, eventdata, handles)
% hObject    handle to figure1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: delete(hObject) closes the figure
%delete(hObject);



function WinLen_Callback(hObject, eventdata, handles)
% hObject    handle to WinLen (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of WinLen as text
%        str2double(get(hObject,'String')) returns contents of WinLen as a double
handles = TransTools.SelectWindow(handles);
guidata(handles.figure1,handles);

% --- Executes during object creation, after setting all properties.
function WinLen_CreateFcn(hObject, eventdata, handles)
% hObject    handle to WinLen (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes when selected object is changed in DataWindowRadio.
function DataWindowRadio_SelectionChangeFcn(hObject, eventdata, handles)
% hObject    handle to the selected object in DataWindowRadio 
% eventdata  structure with the following fields (see UIBUTTONGROUP)
%	EventName: string 'SelectionChanged' (read only)
%	OldValue: handle of the previously selected object or empty if none was selected
%	NewValue: handle of the currently selected object
% handles    structure with handles and user data (see GUIDATA)
handles = TransTools.SelectWindow(handles);
guidata(handles.figure1,handles);


% --- Executes on selection change in OtherWindowType.
function OtherWindowType_Callback(hObject, eventdata, handles)
% hObject    handle to OtherWindowType (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: contents = get(hObject,'String') returns OtherWindowType contents as cell array
%        contents{get(hObject,'Value')} returns selected item from OtherWindowType
handles = TransTools.SelectWindow(handles);
guidata(handles.figure1,handles);


% --- Executes during object creation, after setting all properties.
function OtherWindowType_CreateFcn(hObject, eventdata, handles)
% hObject    handle to OtherWindowType (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end
