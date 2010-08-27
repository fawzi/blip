/// compile time ranges
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
module blip.omg.util.Meta;

import tango.core.Tuple;

private template RangeImpl(int i, T ...) {
    static if (i > 0) {
        alias .RangeImpl!(i-1, i-1, T) RangeImpl;
    } else {
        alias T RangeImpl;
    }
}


template Range(int i) {
    alias RangeImpl!(i) Range;
}


template Repeat(T, int count) {
    static if (!count) {
        alias Tuple!() Repeat;
    } else {
        alias Tuple!(T, Repeat!(T, count-1)) Repeat;
    }
}
