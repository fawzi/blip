/// module with various array utilities
///
/// wrapping of a tango module
module blip.core.Array;
public import tango.core.Array;

/// compresses in place an array removing consecutive copies of the same element
T[] compress(T)(T[]a){
    if (a.length==0) return a;
    size_t i=0,j=1,len=a.length;
    while(j<len){
        if (a[i]!=a[j]){
            a[++i]=a[j];
        }
        ++j;
    }
    return a[0..i+1];
}

/// compresses in place an array removing consecutive copies of the elements that
/// return true with cmpOp
T[] compress(T)(T[]a,bool delegate(T x,T y)cmpOp){
    if (a.length==0) return a;
    size_t i=0,j=1,len=a.length;
    while(j<len){
        if (!cmpOp(a[i],a[j])){
            a[++i]=a[j];
        }
        ++j;
    }
    return a[0..i+1];
}

size_t findFirstPred(T)(T[]arr,bool delegate(T) pred){
    auto len=arr.length;
    for (size_t i=0;i<len;++i){
        if (pred(arr[i])) return i;
    }
    return len;
}