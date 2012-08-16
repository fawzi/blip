/// Some generators for the basic types and other useful things to generate
/// random objects
/// 
/// Both classes and structs can simply implement one of the following static
/// methods
///     static typeof(this)randomGenerate(Rand r,int idx, ref int nEl, ref bool acceptable)
///     static typeof(this)randomGenerate(Rand r, ref bool acceptable)
///     static typeof(this)randomGenerate(Rand r)
/// these methods
/// should generate a value of type T and return it.
/// The generation can use the random number generator r, but also the non random
/// number idx. Idx is positive and scans all possible values
/// sequentially, but it can be bigger than what you expect, you are supposed to
/// take the modulo of it.
/// nEl can be set, and if set, it should be a constant value for that generator.
/// abs(nEl) gives the number of values of idx that are scanned.
/// if nEl>=0 then the values are assumed to be non random, otherwise a random
/// component is assumed.
/// acceptable can be set to false if the current value should be skipped.
/// 
/// It is possible to add a generator also by specializing
///     T generateRandom(T:int)   (Rand r,int idx,ref int nEl, ref bool acceptable)
/// But beware of compiler bugs like 2246.
///     
/// Using a generator (if needed defining an ad-hoc structure/class/typedef)
/// is considered better style (because reusing is easier, and clearer)
/// than defining a mixin of testInit with string mixins, and is exactly as powerful.
/// 
/// If a type implements more than one method the following sequence is choosen:
/// static randomGenerate (from the most complete to the least complete),
/// generateRandom template specialization.
/// 
/// The main method then is the genRandom template (and simpleRandom)
///
/// There is another way to use different generators, but it is less flexible and thus
/// it is better to use a custom object as explained previously.
/// Still if wanted a custom generator can be defined like this:
/// {{{
///     private mixin testInit!(checkInit,manualInit) customTst;
/// }}}
/// in manualInit you have the following variables:
///   arg0,arg1,... : variable of the first,second,... argument that you can initialize
///     (if you use it you are supposed to initialize it)
///   arg0_i,arg1_i,... : index variable for combinatorial (extensive) coverage.
///     if you use it you probably want to initialize the next variable
///   arg0_nEl, arg1_nEl,...: variable that can be initialized to an int and defaults to -1 
///     abs(argI_nEl) gives the number of elements of argI_i, if argI_nEl>=0 then a purely
///     combinatorial generation is assumed, and does not set test.hasRandom to true for
///     this variable whereas if argI_nEl<0 a random component in the generation is assumed
/// If the argument argI is not used in manualInit the default generation procedure
/// {{{
///     Rand r=...;
///     argI=generateRandom!(typeof(argI))(r,argI_i,argI_nEl,acceptable);
/// }}}
/// is used.
/// checkInit can be used if the generation of the random configurations is mostly good,
/// but might contain some configurations that should be skipped. In checkInit one
/// should set the boolean variable "acceptable" to false if the configuration
/// should be skipped.
///
/// For example:
/// {{{
///     private mixin testInit!("acceptable=(arg0%3!=0);","arg0=r.uniformR(10);") smallIntTst;
/// }}}
/// then gets used as follow:
/// {{{
///     smallIntTst.testTrue("x*x<100",(int x){ return (x*x<100);},__LINE__,__FILE__).runTests();
/// }}}
/// by the way this is also a faster way to perform a test, as you can see you don't
/// need to define a collection (but probably it is a good idea to define one)
///
/// author: fawzi
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
module blip.rtest.BasicGenerators;
import blip.core.Traits;
import blip.util.TemplateFu;
import blip.math.Math;
import blip.math.random.Random: Rand=Random;
import blip.io.BasicIO;
import blip.Comp;

/// returns a positive number, most likely mean+hardMin, in [hardMin,hardMax]
int generateSize(Rand r,int mean=4,int hardMin=0,int hardMax=-3) {
    if (hardMax<0) hardMax=-hardMax*mean;
    int res=cast(int)r.gamma(cast(float)mean);
    res+=hardMin;
    if (hardMax>0 && res>hardMax) return hardMax;
    return res;
}

struct SizeLikeNumber(int mean=4,int hardMin=0,int hardMax=-3){
    int val;
    static SizeLikeNumber randomGenerate(Rand r){
        SizeLikeNumber res;
        res.val=generateSize(r,mean,hardMin,hardMax);
        return res;
    }
    void desc(void delegate(cstring)sink){
        writeOut(sink,this.val);
    }
}

/// randomizes the contents of the array
T[] mkRandomArray(T)(Rand r,T[] array,ref bool acceptable){
    int idx,nEl;
    foreach (ref x;array){
        if (!simpleRandom!(T)(r,x)) acceptable=false;
    }
    return array;
}

/// adds random entries to an associative array
V[K] addRandomEntriesToAA(V,K)(Rand r,V[K]a){
    int idx,nEl;
    bool acceptable;
    int size=generateSize(r,10);
    for (int i=0;i<size;++i){
        K k;
        V v;
        for (int j=0;j<10;++j){
            acceptable=true;
            nEl=-1;
            r(idx); // use purely random generation for elements of arrays
            k=genRandom!(K)(r,idx,nEl,acceptable);
            if (acceptable) break;
        }
        if (!acceptable) continue;
        for (int j=0;j<10;++j){
            acceptable=true;
            nEl=-1;
            r(idx); // use purely random generation for elements of arrays
            v=genRandom!(V)(r,idx,nEl,acceptable);
            if (acceptable) break;
        }
        if (acceptable){
            a[k]=v;
        }
    }
    return a;
}

// valid chars (restrict to alphanumeric chars?)
private string valid_chars=
    "abcdefghijklmnopqrstuwxyzABCDEFGHIJKLMNOPQRSTUWXYZ0123456789_+-*%&/()=?!$`'\"\\[]{}<>.:;, \t\n";

template NonStaticArray(T){
  static if (isStaticArrayType!(T)){
    alias typeof(T.dup) NonStaticArray;
  }else{
    alias T NonStaticArray;
  }
}
/// utility method for random generation
/// this is the main method, it checks things in the following order:
/// static method with full interface, static methods with reduced interface,
/// and finally template specialization of generateRandom
NonStaticArray!(T) genRandom(T)(Rand r,int idx,ref int nEl, ref bool acceptable){
    static if (is(typeof(T.randomGenerate(r,idx,nEl,acceptable))==T)){
        return T.randomGenerate(r,idx,nEl,acceptable);
    } else static if (is(typeof(T.randomGenerate(r,acceptable))==T)){
        return T.randomGenerate(r,acceptable);
    } else static if (is(typeof(T.randomGenerate(r))==T)){
        return T.randomGenerate(r);
    } else static if (is(T==Rand)||is(T U:RandomG!(U))) {
        return r;
    } else static if (is(T==int)||is(T==uint)||is(T==long)||is(T==ulong)||is(T==bool)||
        is(T==byte)||is(T==ubyte)){
        return r.uniform!(T);
    } else static if (is(T==short)||is(T==ushort)){
        union U{T s; uint ui;}
        U a;
        a.ui=r.uniform!(uint);
        return a.s;
    } else static if (is(T==char)||is(T==wchar)||is(T==dchar)){
        return cast(T)r.uniformEl(valid_chars);
    } else static if (is(T==float)||is(T==double)||is(T==real)){
        return r.normalSigma(cast(T)1.5);
    } else static if (is(T==ifloat)||is(T==idouble)||is(T==ireal)){
        return cast(T)(r.normalSigma(cast(RealTypeOf!(T))1.5)*1i);
    } else static if (is(T==cfloat)||is(T==cdouble)||is(T==creal)){
        return cast(T)(r.normalSigma(cast(RealTypeOf!(T))1.5)+1i*r.normalSigma(cast(RealTypeOf!(T))1.5));
    } else static if (is(T U:U[])){
        static if (isStaticArrayType!(T)){
            int size=staticArraySize!(T);
        } else {
            int size=generateSize(r,10);
        }
        auto res=new U[size];
        return mkRandomArray!(U)(r,res,acceptable);
    } else static if (isAssocArrayType!(T)) {
        alias KeyTypeOfAA!(T) K;
        alias ValTypeOfAA!(T) V;
        T res;
        return addRandomEntriesToAA!(V,K)(r,res);
    } else static if (is(typeof(generateRandom!(T)(r,idx,nEl,acceptable)))){
        return generateRandom!(T)(r,idx,nEl,acceptable);
    } else {
        static assert(0,"cannot generate random object for type "~T.stringof
            ~" you should implement one of the static randomGenerate methods, the RandGen interface or a specialization of generateRandom, unfortunately due to compiler limitations (or design choice) specializations external to this module are not picked up by this utility wrapper.");
    }
}
NonStaticArray!(T) genRandom2(T)(Rand r,ref T t,int idx,ref int nEl, ref bool acceptable){
    t=genRandom!(T)(r,idx,nEl,acceptable);
}
/// utility method for purely random generation
bool simpleRandom(T)(Rand r,ref T t){
    int idx, nEl;
    bool acceptable;
    for (int i=10;i!=0;--i){
        acceptable=true;
        r(idx);
        t=genRandom!(T)(r,idx,nEl,acceptable);
        if (acceptable) break;
    }
    return acceptable;
}

/// a struct to combine generators for different objects into one
/// can be used like this
/// Randomizer.init(r,idx,nEl,acceptable)(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)(l)
///    (m)(n)(o)(p)(q)(r)(s)(t)(u)(v)(z).end(nEl,acceptable);
/// this would initialize a..z randomly or combinatorially (depending on which type they are)
/// it does assume that if idx is larger than nEl idx%nEl is taken.
struct Randomizer {
    Rand r;
    int idx, nEl;
    bool acceptable;
    
    static Randomizer init(Rand r,int idx,ref int nEl, ref bool acceptable){
        Randomizer res;
        res.r=r;
        res.idx=idx;
        res.nEl=nEl;
        res.acceptable=acceptable;
        return res;
    }
    void add(T)(ref T t){
        int newEl=1;
        if (acceptable){
            t=genRandom!(T)(r,idx,newEl,acceptable);
            if (newEl>0){
                nEl*=newEl;
                if (newEl<0 && nEl>0) nEl=-nEl;
                idx/=newEl;
            }
        }
    }
    Randomizer opCall(T)(ref T t){
        add(t);
        return this;
    }
    void end(ref int nEl, ref bool acceptable){
        nEl=this.nEl;
        acceptable=this.acceptable;
    }
}
