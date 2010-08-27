/// some constants and quick sqrt...
///
/// These files are a sligthly modified version of xf.omg available from http://team0xf.com:1024/omg/
///
/// author: Tomasz Stachowiak (h3r3tic)
//
// Copyright 2008-2010 the blip developer group
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
module xf.omg.core.Misc;

public {
    import blip.math.Math : min, max, floor, ceil, sin, cos, tan, atan, atan2, rndint, pow, abs, exp, sqrt;
}


const real deg2rad  = 0.0174532925199432957692369076848861;
const real rad2deg  = 57.2957795130823208767981548141052;
const real pi           = 3.1415926535897932384626433832795;

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
