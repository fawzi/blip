module xf.omg.core.Misc;

public {
	import tango.math.Math : min, max, floor, ceil, sin, cos, tan, atan, atan2, rndint, pow, abs, exp, sqrt;
}


const real deg2rad	= 0.0174532925199432957692369076848861;
const real rad2deg	= 57.2957795130823208767981548141052;
const real pi			= 3.1415926535897932384626433832795;

// for unitness tests
const real unitSqNormEpsilon = 0.001;



// Stolen from Beyond3D
// Modified magical constant based on Chris Lomont's paper
float invSqrt(float x) {
    float xhalf = 0.5f * x;
    int i = *cast(int*)&x;
    i = 0x5f375a86 - (i >> 1);
    x = *cast(float*)&i;
    x = x*(1.5f - xhalf * x * x);
    return x;
}
