function [b,a] = CreateFilter(Band,sr,freq,att)
    nyq = sr/2;
    lsH = 1.1;
    lsL = 2.0;
    
    switch lower(Band)
        case 'high' % "high cutoff" = low-pass (keeps frequencies below freq)
            [n, Wn] = buttord((lsH*freq)/nyq,((1/lsH)*freq)/nyq,5,att);
            [b,a] = butter(n,Wn, 'low'); %pass
        case 'low' % "low cutoff" = high-pass (keeps frequencies above freq)
            [n, Wn] = buttord(((1/lsL)*freq)/nyq,(lsL*freq)/nyq,10,att);
            [b,a] = butter(n,Wn, 'high'); %pass
        case 'stop'
            Wp = [.98*freq 1.02*freq]/nyq;
            Ws = [.96*freq 1.042*freq]/nyq;
            [n, Wn] = buttord(Wp,Ws,.1,att);
            [b,a] = butter(n,Wn, 'stop');
        case ''
        otherwise
            ME = MException('Alakazam:IIRFilter','Problem in Filter: no such filter: ');
            throw(ME);
    end
end

