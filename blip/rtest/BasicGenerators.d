/*******************************************************************************
    Some generators for the basic types and other useful things to generate
    random objects
    
    Both classes and structs can simply implement one of the following static
    methods
        static typeof(this)randomGenerate(Rand r,int idx, ref int nEl, ref bool acceptable)
        static typeof(this)randomGenerate(Rand r, ref bool acceptable)
        static typeof(this)randomGenerate(Rand r)
    these methods
    should generate a value of type T and return it.
    The generation can use the random number generator r, but also the non random
    number idx. Idx is positive and scans all possible values
    sequentially, but it can be bigger than what you expect, you are supposed to
    take the modulo of it.
    nEl can be set, and if set, it should be a constant value for that generator.
    abs(nEl) gives the number of values of idx that are scanned.
    if nEl>=0 then the values are assumed to be non random, otherwise a random
    component is assumed.
    acceptable can be set to false if the current value should be skipped.
    
    It is possible to add a generator also by specializing
        T generateRandom(T:int)   (Rand r,int idx,ref int nEl, ref bool acceptable)
    But beware of compiler bugs like 2246.
        
    Using a generator (if needed defining an ad-hoc structure/class/typedef)
    is considered better style (because reusing is easier, and clearer)
    than defining a mixin of testInit with string mixins, and is exactly as powerful.
    
    If a type implements more than one method the following sequence is choosen:
    static randomGenerate (from the most complete to the least complete),
    generateRandom template specialization.
    
    The main method then is the genRandom template (and simpleRandom)
    
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.rtest.BasicGenerators;
import blip.rtest.RTestFramework: Rand;
import tango.core.Traits;
import blip.TemplateFu;
import tango.math.Math;

/// returns a positive number, most likely mean+hardMin, in [hardMin,hardMax]
int generateSize(Rand r,int mean=4,int hardMin=0,int hardMax=-3) {
    if (hardMax<0) hardMax=-hardMax*mean;
    int res=cast(int)r.gamma(cast(float)mean);
    res+=hardMin;
    if (hardMax>0 && res>hardMax) return hardMax;
    return res;
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
private char[] valid_chars=
    "abcdefghijklmnopqrstuwxyzABCDEFGHIJKLMNOPQRSTUWXYZ0123456789_+-*%&/()=?!$`'\"\\[]{}<>.:;, \t\n";

/// utility method for random generation
/// this is the main method, it checks things in the following order:
/// static method with full interface, static methods with reduced interface,
/// and finally template specialization of generateRandom
T genRandom(T)(Rand r,int idx,ref int nEl, ref bool acceptable){
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
            ~" you should implement one of the static methods generateRandom, the RandGen interface or a specialization of generateRandom, unfortunately due to compiler limitations (or design choice) specializations external to this module are not picked up by this utility wrapper.");
    }
}
T genRandom2(T)(Rand r,ref T t,int idx,ref int nEl, ref bool acceptable){
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
        return *this;
    }
    void end(ref int nEl, ref bool acceptable){
        nEl=this.nEl;
        acceptable=this.acceptable;
    }
}
