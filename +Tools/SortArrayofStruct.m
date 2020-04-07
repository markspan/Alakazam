function outStructArray = SortArrayofStruct( structArray, fieldName )
    %UNTITLED2 Summary of this function goes here
    %   Detailed explanation goes here
    if ( ~isempty(structArray) &&  length (structArray) > 0)
      [~,I] = sort(arrayfun (@(x) x.(fieldName), structArray)) ;
      outStructArray = structArray(I) ;        
    else 
        disp ('Array of struct is empty');
    end      
end