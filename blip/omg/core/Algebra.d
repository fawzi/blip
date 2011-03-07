/// basic algebra (type independent definitions) of scalars, basick ops anche checks
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
module blip.omg.core.Algebra;

private {
    import blip.core.Traits;
}



template cscalar(T, real value) {
        static if (is(typeof(T.fracBits))){ // hack for http://d.puremagic.com/issues/show_bug.cgi?id=3792
      //static assert (val >= T.minInt && val <= cast(real))T.maxInt);
      const T cscalar = { store : cast(int)(value * (1 << T.fracBits)) };
        } else static if (is(typeof(T.ctFromReal!(value)) == T)) {      // compile-time version
        const T cscalar = T.ctFromReal!(value);
    } else static if (is(typeof(T.fromReal(value)) == T)) {
        const T cscalar = T.fromReal(value);
    } else {
        const T cscalar = cast(T)value;
    }
}


template scalar(T) {
    T scalar(S)(S value) {
        static if (is(T == S)) {
            return value;
        } else static if (is(typeof(T.fromReal(value)) == T)) {
            return T.fromReal(value);
        } else {
            return cast(T)value;
        }
    }
}


template negativeMax(T) {
    static if (isFloatingPointType!(T)) {
        const T negativeMax = -T.max;
    } else {
        const T negativeMax = T.min;
    }
}


template _TypeInstance(T) {
    T _TypeInstance;
}


/**
    Checks whether the type supports multiplication, addition and subtraction.
    This slightly differs from the theory, where a field must only support multiplication
    and addition. In maths, they must also support opposite elements, so
    this is more or less the same
*/
template isRingType(T) {
    static if (
        is(typeof(T.init * T.init) : T) &&
        is(typeof(T.init + T.init) : T) &&
        is(typeof(T.init - T.init) : T) &&
        is(typeof(_TypeInstance!(T) *= T.init)) &&
        is(typeof(_TypeInstance!(T) += T.init)) &&
        is(typeof(_TypeInstance!(T) -= T.init))
    ) {
        const bool isRingType = true;
    } else {
        const bool isRingType = false;
    }
}


/**
    Checks whether the type supports multiplication, division, addition and subtraction.
    This slightly differs from the theory, where a field must only support multiplication
    and addition. In maths, they must also support inverse and opposite elements, so
    this is more or less the same
*/
template isFieldType(T) {
    static if (
        isRingType!(T) &&
        is(typeof(T.init / T.init) : T) &&
        is(typeof(_TypeInstance!(T) /= T.init))
    ) {
        const bool isFieldType = true;
    } else {
        const bool isFieldType = false;
    }
}


template isVectorType(T, int dim) {
    static if (
        is(typeof(T.dim)) &&
        is(typeof(T.dim == dim)) &&
        T.dim == dim
    ) {
        const bool isVectorType = true;
    } else {
        const bool isVectorType = false;
    }
}



static assert (isFieldType!(float));
static assert (isFieldType!(double));
static assert (isFieldType!(real));
static assert (isRingType!(int));
static assert (isRingType!(long));
static assert (isRingType!(ubyte));
static assert (!isRingType!(Object));



template opXAssign(char[] op) {
    void opXAssign(T1, T2)(ref T1 lhs, T2 rhs) {
        static if (mixin("is(typeof(lhs "~op~"= rhs))")) {
            mixin("lhs "~op~"= rhs;");
        } else {
            mixin("lhs = lhs "~op~" rhs;");
        }
    }
}


/+T oppositeElement(T)(T a) {
    static if (is(typeof(-a) : T)) {
        return -a;
    } else {
        return cscalar!(T, 0) - a;
    }
}+/



bool isNaN(T)(T a) {
    static if (is(typeof(T.init.isNaN()) : bool)) {
        return a.isNaN();
    } else static if (isFloatingPointType!(T)) {
        return a !<>= 0;
    } else static if(isIntegerType!(T)) {
        return false;
    } else {
        return true;
    }
}



template optimizeDivWithReciprocalMul(T) {
    const bool optimizeDivWithReciprocalMul = isFloatingPointType!(T);
}
