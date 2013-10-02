%% Setup
loadPaths;
set(0,'DefaultFigureWindowStyle','normal');
clc;

global DEBUG_LEVEL
DEBUG_LEVEL = 1;

if(~exist('FIG','var'))
    global FIG
    FIG.fig = figure;
    FIG.count = 0;
end

%% input values

%how often to display an output frame
FIG.countMax = 0;

%inital guess of parameters (x, y ,z, rX, rY, rZ) (rotate then translate,
%rotation order ZYX)
tform = [0 0 0 -95 0 -15 500];
tform(4:6) = pi.*tform(4:6)./180;

%number of images
numMove = 1;
numBase = 1;

%pairing [base image, move scan]
pairs = [1 1];

%metric to use
metric = 'MI';

%if camera panoramic
panoramic = 0;

%% setup transforms and images
SetupCamera(panoramic);

SetupCameraTform();

Initilize(numMove,numBase);

%% setup Metric
if(strcmp(metric,'MI'))
    SetupMIMetric();
elseif(strcmp(metric,'GOM'))   
    SetupGOMMetric();
else
    error('Invalid metric type');
end

%% get Data

if(~exist('move','var'))
    move = getPointClouds(numMove);
    base = getImagesC(numBase, true);
end


for i = 1:numMove
    m = filterScan(move{i}, metric, tform);
    LoadMoveScan(i-1,m,3);
end

for i = 1:numBase
    b = filterImage(base{i}, metric);
    LoadBaseImage(i-1,b);
end

%% get image alignment
f = alignPoints(base, move, pairs, tform);    

%% cleanup
ClearLibrary;
rmPaths;