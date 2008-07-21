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

int generateSize(int mean=4,int hardMin=0,int hardMax=mean*3)(Rand r) {
    int res=r.gamma(cast(float)mean);
    res+=hardMin;
    if (hardMax>0 && res>hardMax) return hardMax;
    return res;
}

T[] mkRandomArray(T)(T[] array){
    foreach (ref x;array){
        x=generateRandom!(S)(r);
    }
    return array;
}

T generateRandom(T:int)(Rand r)  { return r.uniform!(T); }
T generateRandom(T:uint)(Rand r) { return r.uniform!(T); }
T generateRandom(T:long)(Rand r) { return r.uniform!(T); }
T generateRandom(T:ulong)(Rand r) { return r.uniform!(T); }
T generateRandom(T:byte)(Rand r) { return r.uniform!(T); }
T generateRandom(T:ubyte)(Rand r) { return r.uniform!(T); }
T generateRandom(T:char)(Rand r) { return r.uniform!(T); } // avoid null char? restrict to letters?
T generateRandom(T:float)(Rand r) { return r.uniformRSymm(1.5f); }
T generateRandom(T:double)(Rand r) { return r.uniformRSymm(1.5); }
T generateRandom(T:real)(Rand r) { return r.uniformRSymm(1.5L); }

dynArray!(T) generateRandom(T:T[])(Rand r) {
    static if (isStaticArray!(T)){
        int size=staticArraySize!(T);
    } else {
        int size=generateSize(10);
    }
    dynArray!(T) res=new dynArray!(T)(size);
    return mkRandomArray(res);
}
