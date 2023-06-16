
figure; 
[spectrum,freqs] = pop_spectopo(EEG, 1, [EEG.xmin EEG.xmax]*1000, 'EEG' , 'percent', 100, 'freq', [6 10 22]);

[tmp,minind] = min(abs(freqs-4));
[tmp,maxind] = min(abs(freqs-7));

thetaPower = mean(spectrum(:, minind:maxind),2);
figure('Name', 'thetaPower'); 
topoplot(thetaPower, EEG.chanlocs, 'maplimits', 'maxmin', 'electrodes', 'ptslabels'); cbar;

[tmp,minind] = min(abs(freqs-13));
[tmp,maxind] = min(abs(freqs-30));
betaPower  = mean(spectrum(:, minind:maxind),2);

figure('Name', 'betaPower'); 
topoplot(betaPower, EEG.chanlocs, 'maplimits', 'maxmin', 'electrodes', 'ptslabels'); cbar;

electrodes = {EEG.chanlocs.labels};