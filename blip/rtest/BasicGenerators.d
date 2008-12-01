/*******************************************************************************
    Some generators for the basic types and other useful things to generate
    random objects
    
    A generator 
        T generateRandom(T:int)   (Rand r,int idx,ref int nEl, ref bool acceptable)
    should generate a value of type T and return it.
    The generation can use the random number generator r, but also the non random
    number idx. Idx is guaranteed to be in 0..abs(nEl), and scans all possible values
    sequentially.
    nEl can be set, and if set, it should be a constant value for that generator.
    abs(nEl) gives the number of values of idx that are scanned.
    if nEl>=0 then the values are assumed to be non random, otherwise a random
    component is assumed.
    acceptable can be set to false if the current value should be skipped.
    
    Classes can implement the interface RandGen instead of a template specialization
    This is useful to avoid specialization related compiler bugs like 2246.
    
    Using a generator (if needed defining an ad-hoc structure/class/typedef)
    is considered better style (because reusing is easier, and clearer)
    than defining a mixin of testInit with string mixins, and is exactly as powerful.
    
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.rtest.BasicGenerators;
import blip.rtest.RTestFramework: Rand;


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
        x=generateRandom!(S)(r,idx,nEl,acceptable);
        assert(abs(nEl)>1,"combinatorial generation in an array, this is probably not what you want...");
    }
    return array;
}

// valid chars (restrict to alphanumeric chars?)
private char[] valid_chars=
    "abcdefghijklmnopqrstuwxyzABCDEFGHIJKLMNOPQRSTUWXYZ0123456789_+-*%&/()=?!$`'\"\\[]{}<>.:;, \t\n";
/// returns the actual random generator
T generateRandom(T:Rand)   (Rand r,int idx,ref int nEl, ref bool acceptable) { return r; }
/// generation of a random object
T generateRandom(T:int)   (Rand r,int idx,ref int nEl, ref bool acceptable) { return r.uniform!(T); }
/// ditto                                                
T generateRandom(T:uint)  (Rand r,int idx,ref int nEl, ref bool acceptable) { return r.uniform!(T); }
/// ditto                                                
T generateRandom(T:long)  (Rand r,int idx,ref int nEl, ref bool acceptable) { return r.uniform!(T); }
/// ditto                                                
T generateRandom(T:ulong) (Rand r,int idx,ref int nEl, ref bool acceptable) { return r.uniform!(T); }
/// ditto                                                
T generateRandom(T:byte)  (Rand r,int idx,ref int nEl, ref bool acceptable) { return r.uniform!(T); }
/// ditto                                                
T generateRandom(T:ubyte) (Rand r,int idx,ref int nEl, ref bool acceptable) { return r.uniform!(T); }
/// ditto                                                
T generateRandom(T:char)  (Rand r,int idx,ref int nEl, ref bool acceptable) { return r.uniformEl!(valid_chars); }
/// ditto                                                
T generateRandom(T:float) (Rand r,int idx,ref int nEl, ref bool acceptable) { return r.normalSigma(1.5f); }
/// ditto                                                
T generateRandom(T:double)(Rand r,int idx,ref int nEl, ref bool acceptable) { return r.normalSigma(1.5); }
/// ditto                                                
T generateRandom(T:real)  (Rand r,int idx,ref int nEl, ref bool acceptable) { return r.normalSigma(1.5L); }
/// ditto
DynamicArrayType!(T) generateRandom(T:T[])(Rand r,int idx, ref int nEl, ref bool acceptable) {
    static if (isStaticArrayType!(T)){
        int size=staticArraySize!(T);
    } else {
        int size=generateSize(10);
    }
    DynamicArrayType!(T) res=new DynamicArrayType!(T)(size);
    return mkRandomArray(res,idx,nEl,acceptable);
}

/// interface for objects that can generate random elements of themselves
/// (useful to work around bugs/limitations of the specializations of templates
/// like bug 2246)
interface RandGen{
    /// generate a random element of the current object
    static RandGen randomGenerate(Rand r,int idx,ref int nEl, ref bool acceptable);
}
/// generator for objects that have the RandGen interface
T generateRandom(T:RandGen) (Rand r,int idx,ref int nEl, ref bool acceptable) {
    return cast(T)T.randomGenerate(r,idx,nEl,acceptable);
}
