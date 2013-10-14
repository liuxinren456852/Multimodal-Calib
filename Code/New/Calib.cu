#include "Calib.h"
#include <algorithm>
#include <string> 

Calib::Calib(std::string metricType){
	checkForCUDA();
}

size_t Calib::getImageDepth(size_t idx){
	return baseStore.getDepth(idx);
}

size_t Calib::getNumCh(size_t idx){
	return moveStore.getNumCh(idx);
}

void Calib::clearScans(void){
	moveStore.removeAllScans();
}

void Calib::clearImages(void){
	baseStore.removeAllImages();
}

void Calib::clearTforms(void){
	tformStore.removeAllTforms();
}

void Calib::clearExtras(void){
	return;
}

void Calib::clearIndices(void){
	tformIdx.clear();
	scanIdx.clear();
}

void Calib::addScan(std::vector<thrust::host_vector<float>>& scanLIn, std::vector<thrust::host_vector<float>>& scanIIn){
	moveStore.addScan(scanLIn, scanIIn);
}

void Calib::addImage(thrust::host_vector<float>& imageIn, size_t height, size_t width, size_t depth){
	baseStore.addImage(imageIn, height, width, depth);
}

void Calib::addTform(thrust::host_vector<float>& tformIn, size_t tformSizeX, size_t tformSizeY){
	tformStore.addTforms(tformIn, tformSizeX, tformSizeY);
}

float Calib::evalMetric(void){
	return 0;
}

void Calib::addTformIndices(std::vector<size_t>& tformsIdxIn){
	tformIdx.insert(tformIdx.end(), tformsIdxIn.begin(), tformsIdxIn.end());
}

void Calib::addScanIndices(std::vector<size_t>& scansIdxIn){
	scanIdx.insert(scanIdx.end(),scansIdxIn.begin(), scansIdxIn.end());
}

size_t Calib::allocateGenMem(ScanList points, ImageList images, std::vector<std::vector<float*>>& genL, std::vector<std::vector<float*>>& genI, size_t startIdx){
	
	cudaError_t err = cudaSuccess;
	size_t i;

	genL.resize(images.getNumImages());
	genI.resize(images.getNumImages());

	for(i = startIdx; i < images.getNumImages(); i++){

		genL[i].resize(IMAGE_DIM);
		for(size_t j = 0; j < IMAGE_DIM; j++){
			cudaError_t currentErr = cudaMalloc(&genL[i][j], sizeof(float)*points.getNumPoints(scanIdx[i]));
			if(currentErr != cudaSuccess){
				err = cudaErrorMemoryAllocation;
				break;
			}
		}
		genI[i].resize(images.getDepth(i));
		for(size_t j = 0; j < images.getDepth(i); j++){
			cudaError_t currentErr = cudaMalloc(&genI[i][j], sizeof(float)*points.getNumPoints(scanIdx[i]));
			if(currentErr != cudaSuccess){
				err = cudaErrorMemoryAllocation;
				break;
			}
		}

		if(err == cudaErrorMemoryAllocation){
			break;
		}
	}

	if(err == cudaErrorMemoryAllocation){
		for(i = startIdx; i < images.getNumImages(); i++){
			for(size_t j = 0; j < IMAGE_DIM; j++){
				cudaFree(&genL[i][j]);
			}
			for(size_t j = 0; j < images.getDepth(i); j++){
				cudaFree(&genI[i][j]);
			}
			break;
		}
	}

	return i;
}

void Calib::clearGenMem(ImageList images, std::vector<std::vector<float*>>& genL, std::vector<std::vector<float*>>& genI, size_t startIdx){
	
	size_t i;

	for(i = startIdx; i < images.getNumImages(); i++){
		for(size_t j = 0; j < IMAGE_DIM; j++){
			cudaFree(&genL[i][j]);
		}
		for(size_t j = 0; j < images.getDepth(i); j++){
			cudaFree(&genI[i][j]);
		}
	}
}

void Calib::setSSDMetric(void){
	metric = new SSD();
}

void Calib::setGOMMetric(void){
	metric = new GOM();
}

void Calib::addCameraIndices(std::vector<size_t>& cameraIdxIn){
	mexErrMsgTxt("Attempted to setup camera for use with non-camera calibration");
	return;
}

void Calib::addCamera(thrust::host_vector<float>& cameraIn, boolean panoramic){
	mexErrMsgTxt("Attempted to setup camera for use with non-camera calibration");
	return;
}

void Calib::generateImage(thrust::device_vector<float>& image, size_t width, size_t height, size_t dilate, size_t idx, bool imageColour){
	return;
}

CameraCalib::CameraCalib(std::string metricType) : Calib(metricType){}

void CameraCalib::clearExtras(void){
	cameraStore.removeAllCameras();
	return;
}

void CameraCalib::clearIndices(void){
	tformIdx.clear();
	scanIdx.clear();
	cameraIdx.clear();
}

void CameraCalib::addTform(thrust::host_vector<float>& tformIn){
	tformStore.addTforms(tformIn);
}

void CameraCalib::addCameraIndices(std::vector<size_t>& cameraIdxIn){
	cameraIdx.insert(cameraIdx.end(),cameraIdxIn.begin(), cameraIdxIn.end());
}

void CameraCalib::addCamera(thrust::host_vector<float>& cameraIn, boolean panoramic){
	cameraStore.addCams(cameraIn, panoramic);
}

float CameraCalib::evalMetric(void){

	std::vector<std::vector<float*>> genL;
	std::vector<std::vector<float*>> genI;

	std::vector<float> metricVal;

	std::vector<cudaStream_t> streams;

	if(tformIdx.size() != baseStore.getNumImages()){
		std::ostringstream err; err << "Transform index has not been correctly set up";
		mexErrMsgTxt(err.str().c_str());
		return 0;
	}
	if(cameraIdx.size() != baseStore.getNumImages()){
		std::ostringstream err; err << "Camera index has not been correctly set up";
		mexErrMsgTxt(err.str().c_str());
		return 0;
	}
	if(scanIdx.size() != baseStore.getNumImages()){
		std::ostringstream err; err << "Scan index has not been correctly set up";
		mexErrMsgTxt(err.str().c_str());
		return 0;
	}

	size_t genLength = 0;
	float out = 0;
	for(size_t i = 0; i < moveStore.getNumScans(); i+= (genLength+1)){
		genLength = allocateGenMem(moveStore, baseStore, genL, genI, i);

		if(genLength == 0){
			mexErrMsgTxt("Memory allocation for generated scans failed\n");
		}
		
		streams.resize(genLength-i);
		for(size_t j = 0; j < streams.size(); j++){
			cudaStreamCreate ( &streams[j]);
			tformStore.transform(moveStore, genL[j], cameraStore, tformIdx[i+j], cameraIdx[i+j], scanIdx[i+j], streams[j]);
			cudaDeviceSynchronize();
			baseStore.interpolateImage(i+j, scanIdx[i+j], genL[j], genI[j], moveStore.getNumPoints(scanIdx[i+j]), true, streams[j]);
			cudaDeviceSynchronize();
			out += metric->evalMetric(genI[j], moveStore, scanIdx[i+j], streams[j]);
			cudaDeviceSynchronize();
		}

		clearGenMem(baseStore, genL, genI, i);
	}

	return out;
}

void CameraCalib::generateImage(thrust::device_vector<float>& image, size_t width, size_t height, size_t dilate, size_t idx, bool imageColour){

	std::vector<float*> genL;
	std::vector<float*> genI;

	if(imageColour){
		image.resize(baseStore.getDepth(idx)*width*height);
	}
	else{
		image.resize(moveStore.getNumCh(scanIdx[idx])*width*height);
	}

	genL.resize(IMAGE_DIM);
	for(size_t j = 0; j < IMAGE_DIM; j++){
		cudaError_t currentErr = cudaMalloc(&genL[j], sizeof(float)*moveStore.getNumPoints(scanIdx[idx]));
		if(currentErr != cudaSuccess){
			mexErrMsgTxt("Memory allocation error when generating image");
			break;
		}
	}
	if(imageColour){
		genI.resize(baseStore.getDepth(idx));
		for(size_t j = 0; j < baseStore.getDepth(idx); j++){
			cudaError_t currentErr = cudaMalloc(&genI[j], sizeof(float)*moveStore.getNumPoints(scanIdx[idx]));
			if(currentErr != cudaSuccess){
				mexErrMsgTxt("Memory allocation error when generating image");
				break;
			}
		}
	}

	cudaStream_t stream;
	cudaStreamCreate(&stream);
	tformStore.transform(moveStore, genL, cameraStore, tformIdx[idx], cameraIdx[idx], scanIdx[idx], stream);
	cudaDeviceSynchronize();

	if(imageColour){
		baseStore.interpolateImage(idx, scanIdx[idx], genL, genI, moveStore.getNumPoints(scanIdx[idx]), true, stream);
		cudaDeviceSynchronize();

		for(size_t i = 0; i < baseStore.getDepth(idx); i++){
			
			generateOutputKernel<<<gridSize(moveStore.getNumPoints(scanIdx[idx])) ,BLOCK_SIZE>>>(
				genL[0],
				genL[1],
				genI[i],
				thrust::raw_pointer_cast(&image[width*height*i]),
				width,
				height,
				moveStore.getNumPoints(scanIdx[idx]),
				dilate);
		}
	}
	else{
		for(size_t i = 0; i < moveStore.getNumCh(scanIdx[idx]); i++){
			generateOutputKernel<<<gridSize(moveStore.getNumPoints(scanIdx[idx])) ,BLOCK_SIZE>>>(
				genL[0],
				genL[1],
				moveStore.getIP(scanIdx[idx],i),
				thrust::raw_pointer_cast(&image[width*height*i]),
				width,
				height,
				moveStore.getNumPoints(scanIdx[idx]),
				dilate);
		}
	}

	for(size_t j = 0; j < IMAGE_DIM; j++){
		cudaFree(&genL[j]);
	}
	if(imageColour){
		genI.resize(baseStore.getDepth(idx));
		for(size_t j = 0; j < baseStore.getDepth(idx); j++){
			cudaFree(&genI[j]);
		}
	}

}

