function [ mag, phase ] = Get2DGradient( in, tform )
%GETGRADIENT Calculates an estimate of the gradients at each point

cloud = in(:,1:3);
cloud(:,4) = 1;

%transform points
tform = double(tform);   

tformMat = CreateTformMat(tform);

vals = in(:,4);
cloud = (tformMat*(cloud'))';

%project points onto sphere
sphere = zeros(size(cloud,1),2);
sphere(:,1) = atan2(cloud(:,1), cloud(:,3));
sphere(:,2) = atan(cloud(:,2)./ sqrt(cloud(:,1).^2 + cloud(:,3).^2));

kdTree = KDTreeSearcher(sphere(:,1:2),'distance','euclidean');

%get nearest neighbours
idx = knnsearch(kdTree,kdTree.X,'k',9);

%remove self
idx = idx(:,2:end);

dVals = repmat(vals,1,8);
dVals(:) = dVals(:) - vals(idx(:));

xLocs = kdTree.X(:,1);
dxLocs = repmat(xLocs,1,8);
dxLocs(:) = dxLocs(:) - xLocs(idx(:));

yLocs = kdTree.X(:,2);
dyLocs = repmat(yLocs,1,8);
dyLocs(:) = dyLocs(:) - yLocs(idx(:));

%dxLocs = sum(dxLocs.*dVals,2) /8;
%dyLocs = sum(dyLocs.*dVals,2) /8;

dLocs = sqrt(dxLocs.^2 + dyLocs.^2);
phase = atan2(dyLocs,dxLocs);

dVals = dVals./dLocs;
dxLocs = sum(dVals.*cos(phase),2)/8;
dyLocs = sum(dVals.*sin(phase),2)/8;

%mag = sum(abs(dVals),2) /8;

mag = sqrt(dxLocs.^2 + dyLocs.^2);
%phase = 180*atan2(-dxLocs,-dyLocs)/pi;
phase = 180*atan2(dxLocs,dyLocs)/pi;
phase = mod(phase+180,180);


phase(isnan(phase)) = 0;
mag(isnan(mag)) = 0;
phase(isinf(phase)) = 0;
mag(isinf(mag)) = 0;

mag = mag - min(mag);
mag = mag / max(mag);

end

