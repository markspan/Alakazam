 Fs = 44.1e3; N = 1000;
 x = sin(2*pi*(1:N)/N + (10*(1:N)/N).^2);
 findpeaks(x,Fs, ...
           'Annotate','extents')
