/*******************************************************************************
    Support functions for Tests involving NArray, mainly various
    random generators
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        Apache 2.0
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.narray.TestSupport;
import blip.narray.NArray;
import blip.narray.Convolve;
import blip.TemplateFu;
import tango.io.Stdout;
import blip.text.Stringify;
import tango.math.Math: abs,min,max;
import blip.rtest.RTest;
import blip.parallel.WorkManager;

/// creates arrays that can be dotted with each other along the given axis
/// useful mainly for random tests
/// startAxis1 defalt should be -1, but negative default values have a bug with gdc (#2291)
/// the array are stored in the attributes .a and .b; .axis1 and .axis2 
class Dottable(T,int rank1,S,int rank2,bool scanAxis=false, bool randomLayout=false,
    bool square1=false,int startAxis1=0,int startAxis2=0){
    static assert(rank1>0 && rank2>0,"ranks must be strictly positive");
    static assert(-rank1<=startAxis1 && startAxis1<rank1,"startAxis1 out of bounds");
    static assert(-rank2<=startAxis2 && startAxis2<rank2,"startAxis2 out of bounds");
    index_type k;
    int axis1,axis2;
    NArray!(T,rank1) a;
    NArray!(S,rank2) b;
    this(NArray!(T,rank1) a,NArray!(S,rank2) b,int axis1=startAxis1,int axis2=startAxis2)
    {
        assert(-rank1<=axis1 && axis1<rank1,"axis1 out of bounds");
        assert(-rank2<=axis2 && axis2<rank2,"axis2 out of bounds");
        assert(a.shape[((axis1<0)?(rank1+axis1):axis1)]==b.shape[((axis2<0)?(rank2+axis2):axis2)],
            "incompatible sizes");
        this.a=a;
        this.b=b;
        this.axis1=axis1;
        this.axis2=axis2;
        this.k=a.shape[((axis1<0)?(rank1+axis1):axis1)];
    }
    /// returns a random array (here with randNArray & co due to bug 2246)
    static Dottable randomGenerate(Rand r,int idx,ref int nEl,ref bool acceptable){
        const index_type maxSize=1_000_000;
        float mean=10.0f;
        index_type[rank1+rank2-1] dims;
        index_type totSize;
        do {
            static if (square1){
                index_type sz=cast(index_type)(r.gamma(mean));
                foreach (ref el;dims){
                    el=sz;
                }
            } else {
                foreach (ref el;dims){
                    el=cast(index_type)(r.gamma(mean));
                }
            }
            totSize=1;
            foreach (el;dims)
                totSize*=el;
            mean*=(cast(float)maxSize)/(cast(float)totSize);
        } while (totSize>maxSize)
        static if(scanAxis){
            int axis1=-rank1+(idx % (2*rank1));
            int axis2=-rank2+((idx / (2*rank1))%(2*rank2));
            nEl=-(4*rank1*rank2);
        } else {
            int axis1=startAxis1;
            int axis2=startAxis2;
        }
        index_type[rank1] dims1=dims[0..rank1];
        auto a=randNArray(r,NArray!(T,rank1).empty(dims1));
        static if (randomLayout) {
            if (r.uniform!(bool)()) a=randLayout(r,a);
        }
        index_type[rank2] dims2;
        int ii=rank1;
        for (int i=0;i<rank2;++i){
            if (i!=axis2 && i!=rank2+axis2){
                dims2[i]=dims[ii];
                ++ii;
            } else {
                dims2[i]=dims[((axis1<0)?(rank1+axis1):axis1)];
            }
        }
        auto b=randNArray(r,NArray!(S,rank2).empty(dims2));
        static if (randomLayout) {
            if (r.uniform!(bool)()) b=randLayout(r,b);
        }
        return new Dottable(a,b,axis1,axis2);
    }
    char[] toString(){
        return getString(printData(new Stringify()));
    }
    FormatOutput!(char) printData(FormatOutput!(char)s,char[] formatEl="{,10}", index_type elPerLine=10,
        char[] indent=""){
        s(indent)("Dottable{").newline;
        s(indent)("axis1=")(axis1).newline;
        s(indent)("axis2=")(axis2).newline;
        s(indent)("k    =")(k).newline;
        a.desc(s(indent)("a:")).newline;
        a.printData(s,formatEl,elPerLine,indent~"  ").newline;
        b.desc(s(indent)("b:")).newline;
        b.printData(s,formatEl,elPerLine,indent~"  ").newline;
        s(indent)("}").newline;
        return s;
    }
}

/// a random 1D NArray type T and dimension i (in the arr attribute)
class SizedRandomNArray(T,int i){
    static const int rank=1;
    NArray!(T,rank) arr;
    this(){
        arr=zeros!(T)([i]);
    }
    static SizedRandomNArray randomGenerate(Rand r){
        auto res=new SizedRandomNArray();
        randNArray(r,res.arr);
        return res;
    }
    char[] toString(){
        return arr.toString();
    }
}
/// a random 2D NArray type T and dimension i,j (in the arr attribute)
class SizedRandomNArray(T,int i,int j){
    static const int rank=2;
    NArray!(T,rank) arr;
    this(){
        arr=zeros!(T)([i,j]);
    }
    static SizedRandomNArray randomGenerate(Rand r){
        auto res=new SizedRandomNArray();
        randNArray(r,res.arr);
        return res;
    }
    char[] toString(){
        return arr.toString();
    }
}
/// a random 3D NArray type T and dimension i,j,k (in the arr attribute)
class SizedRandomNArray(T,int i,int j,int k){
    static const int rank=3;
    NArray!(T,rank) arr;
    this(){
        arr=zeros!(T)([i,j,k]);
    }
    static SizedRandomNArray randomGenerate(Rand r){
        auto res=new SizedRandomNArray();
        randNArray(r,res.arr);
        return res;
    }
    char[] toString(){
        return arr.toString();
    }
}
