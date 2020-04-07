function [jFrame, jContentPane] = getJavaFrame(hFig) 
    wrn = warning('off','MATLAB:HandleGraphics:ObsoletedProperty:JavaFrame'); 
    jFrame = get(hFig,'JavaFrame'); 
    jContentPane = jFrame.fHG2Client.getContentPane(); 
    warning(wrn); 
end
