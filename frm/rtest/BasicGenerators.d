/*******************************************************************************
    Some generators for the basic types and other useful things to generate
    random objects
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module frm.rtest.BasicGenerators;
import frm.rtest.RTestFramework: Rand;


/// returns a positive number, most likely mean+hardMin, in [hardMin,hardMax]
int generateSize(Rand r,int mean=4,int hardMin=0,int hardMax=-3) {
    if (hardMax<0) hardMax=-hardMax*mean;
    int res=cast(int)r.gamma(cast(float)mean);
    res+=hardMin;
    if (hardMax>0 && res>hardMax) return hardMax;
    return res;
}

/// randomizes the contents of the array
T[] mkRandomArray(T)(Rand r,T[] array){
    uint idx,nEl;
    foreach (ref x;array){
        x=generateRandom!(S)(r,idx,nEl);
        assert(nEl==0,"combinatorial generation in an array, this is probably not what you want...");
    }
    return array;
}

// valid chars (restrict to alphanumeric chars?)
private char[] valid_chars=
    "abcdefghijklmnopqrstuwxyzABCDEFGHIJKLMNOPQRSTUWXYZ0123456789_+-*%&/()=?!$`'\"\\[]{}<>.:;, \t\n";
/// generation of a random object
T generateRandom(T:int)   (Rand r,uint idx,ref uint nEl) { nEl=0; return r.uniform!(T); }
/// ditto
T generateRandom(T:uint)  (Rand r,uint idx,ref uint nEl) { nEl=0; return r.uniform!(T); }
/// ditto
T generateRandom(T:long)  (Rand r,uint idx,ref uint nEl) { nEl=0; return r.uniform!(T); }
/// ditto
T generateRandom(T:ulong) (Rand r,uint idx,ref uint nEl) { nEl=0; return r.uniform!(T); }
/// ditto
T generateRandom(T:byte)  (Rand r,uint idx,ref uint nEl) { nEl=0; return r.uniform!(T); }
/// ditto
T generateRandom(T:ubyte) (Rand r,uint idx,ref uint nEl) { nEl=0; return r.uniform!(T); }
/// ditto
T generateRandom(T:char)  (Rand r,uint idx,ref uint nEl) { nEl=0; return r.uniformEl!(valid_chars); }
/// ditto
T generateRandom(T:float) (Rand r,uint idx,ref uint nEl) { nEl=0; return r.normalSigma(1.5f); }
/// ditto
T generateRandom(T:double)(Rand r,uint idx,ref uint nEl) { nEl=0; return r.normalSigma(1.5); }
/// ditto
T generateRandom(T:real)  (Rand r,uint idx,ref uint nEl) { nEl=0; return r.normalSigma(1.5L); }
/// ditto
dynArray!(T) generateRandom(T:T[])(Rand r,uint idx, ref uint nEl) {
    nEl=0;
    static if (isStaticArray!(T)){
        int size=staticArraySize!(T);
    } else {
        int size=generateSize(10);
    }
    dynArray!(T) res=new dynArray!(T)(size);
    return mkRandomArray(res,idx,nEl);
}

/// interface for objects that can generate random elements of themselves
/// (useful to work around bugs/limitations of the specializations of templates
/// like bug 2246)
interface RandGen{
    /// generate a random element of the current object
    static RandGen randomGenerate(Rand r,uint idx,ref uint nEl);
}
/// generator for objects that have the RandGen interface
T generateRandom(T:RandGen) (Rand r,uint idx,ref uint nEl) {
    return cast(T)T.randomGenerate(r,idx,nEl);
}
