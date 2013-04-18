function [ out ] = OutputImage(width, height, moveNum)
%GETMOVE outputs moving image imNum from scan

%check inputs
if((width ~= round(width)) || (width < 0))
    TRACE_ERROR('width must be a positive integer, returning');
    return;
end
if((height ~= round(height)) || (height < 0))
    TRACE_ERROR('height must be a positive integer, returning');
    return;
end
if((moveNum ~= round(moveNum)) || (moveNum < 0))
    TRACE_ERROR('moveNum must be a positive integer, returning');
    return;
end

%ensures the library is loaded
CheckLoaded();

%get image
out = calllib('LibCal','outputImage', width, height, moveNum);

setdatatype(out,'singlePtr',width,height);

%get data
out = get(out);
out = out.Value;

out = out';

end

