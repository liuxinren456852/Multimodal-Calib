#include "Kernel.h"
#include <vector_types.h>
//#include "CI.h"

__global__ void generateOutputKernel(float* locs, float* vals, float* out, size_t width, size_t height, size_t numPoints){
	unsigned int i = blockDim.x * blockIdx.x + threadIdx.x;

	if(i >= numPoints){
		return;
	}

	int2 loc;
	loc.x = floor(locs[i]+0.5f);
	loc.y = floor(locs[i + numPoints]+0.5f);

	bool inside =
		((0 <= loc.x) && (loc.x < width) &&
		(0 <= loc.y) && (loc.y < height));

	if (inside){
		out[loc.x + width*loc.y] = vals[i];
	}
}

__global__ void DenseImageNNKernel(cudaPitchedPtr in, const float* locIn, float* valsOut, const size_t numPoints){
	unsigned int i = blockDim.x * blockIdx.x + threadIdx.x;

	if(i >= numPoints){
		return;
	}

	int2 loc;
	loc.x = floor(locIn[i]+0.5f);
	loc.y = floor(locIn[i + numPoints]+0.5f);

	int2 maxSize;
	maxSize.x = in.xsize/sizeof(float);
	maxSize.y = in.ysize;

	bool inside =
		0 <= loc.x && loc.x < maxSize.x &&
		0 <= loc.y && loc.y < maxSize.y;

	if (!inside){
		valsOut[i] = 0.0f;
	}
	else{
		valsOut[i] = ((float*)(in.ptr))[loc.x + (in.pitch/sizeof(float))*loc.y];
	}
}

__global__ void DenseImageLinKernel(cudaPitchedPtr in, const float* locIn, float* valsOut, const size_t numPoints){
	unsigned int i = blockDim.x * blockIdx.x + threadIdx.x;

	if(i >= numPoints){
		return;
	}

	int2 locF, locC;
	locF.x = floor(locIn[i]);
	locF.y = floor(locIn[i + numPoints]);
	locC.x = ceil(locIn[i]);
	locC.y = ceil(locIn[i + numPoints]);
	
	float2 loc;
	loc.x = locIn[i];
	loc.y = locIn[i + numPoints];

	int2 maxSize;
	maxSize.x = in.xsize/sizeof(float);
	maxSize.y = in.ysize;

	bool inside =
		0 <= locC.x && locF.x < maxSize.x &&
		0 <= locC.y && locF.y < maxSize.y;

	if (!inside){
		valsOut[i] = 0.0f;
	}
	else{
		float ff = ((float*)(in.ptr))[locF.x + (in.pitch/sizeof(float))*locF.y];
		float cf = ((float*)(in.ptr))[locC.x + (in.pitch/sizeof(float))*locF.y];
		float fc = ((float*)(in.ptr))[locF.x + (in.pitch/sizeof(float))*locC.y];
		float cc = ((float*)(in.ptr))[locC.x + (in.pitch/sizeof(float))*locC.y];

		ff *= (loc.x - ((float)locF.x))*(loc.y - ((float)locF.y));
		if(ff == 0){
			valsOut[i] = cc;
			return;
		}

		cf *= (((float)locC.x)- loc.x)*(loc.y - ((float)locF.y));
		fc *= (loc.x - ((float)locF.x))*(((float)locC.y) - loc.y);
		cc *= (((float)locC.x) - loc.x)*(((float)locC.y) - loc.y);

		valsOut[i] = ff + cf + fc + cc;
	}
}

__global__ void DenseImageInterpolateKernel(const size_t width, const size_t height, const float* locIn, float* valsOut, const size_t numPoints){
	unsigned int i = blockDim.x * blockIdx.x + threadIdx.x;

	if(i >= numPoints){
		return;
	}

	float2 loc;
	loc.x = locIn[i + numPoints]+0.5f;
	loc.y = locIn[i]+0.5f;

	bool inside =
		0 < loc.x && loc.x < width &&
		0 < loc.y && loc.y < height;

	if (!inside){
		valsOut[i] = 0.0f;
	}
	else{
		valsOut[i] = tex2D(tex, loc.x,loc.y);
	}
}

__global__ void AffineTransformKernel(const float* tform, const float* pointsIn, float* pointsOut, const size_t numPoints){
	
	unsigned int i = blockDim.x * blockIdx.x + threadIdx.x;

	if(i >= numPoints){
		return;
	}

	//make it a bit clearer which are x and y points
	const float xIn = pointsIn[i];
	const float yIn = pointsIn[i + numPoints];

	//transform points
	float xOut = xIn*tform[0] + yIn*tform[3] + tform[6];
	float yOut = xIn*tform[1] + yIn*tform[4] + tform[7];

	pointsOut[i] = xOut;
	pointsOut[i + numPoints] = yOut;

}

__global__ void CameraTransformKernel(const float* tform, const float* cam, const float* pointsIn, float* pointsOut, const size_t numPoints, const bool panoramic){
	
	unsigned int i = blockDim.x * blockIdx.x + threadIdx.x;

	if(i >= numPoints){
		return;
	}

	const float xIn = pointsIn[i + 0*numPoints];
	const float yIn = pointsIn[i + 1*numPoints];
	const float zIn = pointsIn[i + 2*numPoints];

	//transform points
	float x = xIn*tform[0] + yIn*tform[4] + zIn*tform[8] + tform[12];
	float y = xIn*tform[1] + yIn*tform[5] + zIn*tform[9] + tform[13];
	float z = xIn*tform[2] + yIn*tform[6] + zIn*tform[10] + tform[14];

	if((z <= 0) && !panoramic){
		x = -1;
		y = -1;
	}
	else{

		

		if(panoramic){
			//panoramic camera model
			y = (y/sqrt(z*z + x*x));
			x = atan2(x,z);

			//apply projective camera matrix
			x = cam[0]*x + cam[6];
			y = cam[4]*y + cam[7];

		}
		else{
			//apply projective camera matrix
			x = cam[0]*x + cam[3]*y + cam[6]*z + cam[9];
			y = cam[1]*x + cam[4]*y + cam[7]*z + cam[10];
			z = cam[2]*x + cam[5]*y + cam[8]*z + cam[11];

			//pin point camera model
			y = y/z;
			x = x/z;
		}
	}

	//output points
	pointsOut[i + 0*numPoints] = x;
	pointsOut[i + 1*numPoints] = y;
}

__global__ void GOMKernel(const float* A, const float* B, const size_t length, float* phaseOut, float* magOut){
	
	unsigned int i = blockDim.x * blockIdx.x + threadIdx.x;

	if(i >= length){
		return;
	}

	const float* magA = &A[0];
	const float* magB = &B[0];
	const float* phaseA = &A[length];
	const float* phaseB = &B[length];
	
	float phase = PI*abs(phaseA[i] - phaseB[i])/180;

    phase = (cos(2*phase)+1)/2;
    float mag = magA[i]*magB[i];

	//ignore zeros
	if((phaseA[i] == 0) || (phaseB[i] == 0)){
		mag = 0;
	}

    phaseOut[i] =  mag*phase;
	magOut[i] =  mag;
}

void RunBSplineKernel(float* volume, size_t width, size_t height){
	//CubicBSplinePrefilter2D(volume, sizeof(float), width,height);
}

