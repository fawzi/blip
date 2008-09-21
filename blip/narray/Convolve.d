/*******************************************************************************
    Implements convolution on NArrays
    
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.narray.Convolve;
import blip.narray.BasicTypes;
import blip.narray.BasicOps;
import blip.TemplateFu;
/+ --------- convolution --------- +/
// convolution base in 2d: 3 streams (minus,zero,plus), kernel[imin..imax,jmin..jmax] in aij
// i setup is: (vertical bar read, horizontal write, columns are the three streams)
//  -  |  
//  |  +  |
//     |  +
char[] convolveBase(char[] indent,bool istream_m=true, bool istream_z=true, bool istream_p=true,
        int jshift=0, int jmin=0, int jmax=3, int imin=0,int imax=3){
    char [] res="".dup;
    if (istream_m){
        res~=indent;
        res~="*resPtrMenoI+="; // [i-1,j]
        bool shouldAdd=false;
        for (int i=2;i<imax;++i){
            for (int j=jmin;j<jmax;++j){
                if (shouldAdd) res~="+";
                res~="c2"~ctfe_i2a(j)~"*a1"~ctfe_i2a((j+jshift)%3);
                shouldAdd=true;
            }
        }
        res~=";\n";
    }
    if (istream_z){
        res~=indent;
        res~="*resPtr0+="; // [i,j]
        bool shouldAdd=false;
        for (int i=imin;i<imax;++i){
            for (int j=jmin;j<jmax;++j){
                if (shouldAdd) res~="+";
                res~="c"~ctfe_i2a(i)~ctfe_i2a(j)~"*a"~ctfe_i2a(i)~ctfe_i2a((j+jshift)%3);
                shouldAdd=true;
            }
        }
        res~=";\n";
    }
    if (istream_p){
        res~=indent;
        res~="*resPtrPiuI+=";// [i+1,j]
        bool shouldAdd=false;
        for (int i=imin;i<2;++i){
            for (int j=jmin;j<jmax;++j){
                if (shouldAdd) res~="+";
                res~="c"~ctfe_i2a(i)~ctfe_i2a(j)~"*a"~ctfe_i2a(i+1)~ctfe_i2a((j+jshift)%3);
                shouldAdd=true;
            }
        }
        res~=";\n";
    }
    return res;
}

//pragma(msg,"convolveBase(char[] indent,bool istream_m=true, bool istream_z=true, bool istream_p=true,
//        int jshift=0, int jmin=0, int jmax=3, int imin=0,int imax=3)");
//pragma(msg,convolveBase("   "));
//pragma(msg,"------");

enum Border:int{
    Decrease=-1, Same=0, Increase=1
}

char[] incrementA(char[] indent,int imin,int imax,int jshift){
    char[] res="".dup;
    char[] aPtrName="";
    for (int i=imin;i<imax;++i){
        if (i==0) aPtrName="aPtrMenoI";
        if (i==1) aPtrName="aPtr0";
        if (i==0) aPtrName="aPtrPiuI";
        res~=indent~aPtrName~"=cast(T*)(cast(size_t)"~aPtrName~"+aStrideJ);\n";
        res~=indent~"a"~ctfe_i2a(i)~ctfe_i2a(jshift)~"= *"~aPtrName~";\n";
    }
    return res;
}

//pragma(msg,"incrementA(char[] indent,int imin,int imax,int jshift)");
//pragma(msg,incrementA("  ",0,3,0));
//pragma(msg,"----");

// inner convolution loop (for 2d convolve)
// convolveBase+code to do the j border correctly
// jout=outA.shape[rank-1]
// jcore=the length in j dir without any partially evaluated border
//       jout-(0 if Decrease, 2 if Same, 4 if Increase))
// jcore=3*junloop+jrest
// if (jrest<0) jout=-jrest
char[] convolveJLoop(char[] indent0,int jrest=0,bool istream_m=true, bool istream_z=true,
    bool istream_p=true,int imin=0,int imax=3,Border border=Border.Same){
    char [] res="".dup;
    res~=indent0~"{";
    char[] indent=indent0~"    ";
    res~=indent~"T* resPtr0=resPtr0I;\n";
    res~=indent~"T* aPtr0=aPtr0I;\n";
    if (jrest<0){
        // no loop (few elements)
        int jstart=0;
        if (border==Border.Increase) {
            jstart=-1;
        }
        int jend=jstart-jrest;
        for (int j=jstart;j<jend;++j){
            for (int istream=-1;istream<2;++istream){
                int iStart=imin, iEnd=imax;
                if (istream==-1) {
                    if (!istream_m) continue;
                    if (iStart<1) iStart=1;
                    if (2<iEnd) iEnd=2;
                }
                if (istream==0 && (!istream_z)) continue;
                if (istream==1) {
                    if (!istream_p) continue;
                    if (iStart<1) iStart=1;
                }
                if (iStart>=iEnd) continue;
                res~=indent~"*cast(T*)(cast(size_t)resPtr0+("~ctfe_i2a(istream)~")*resStrideI+("
                    ~ctfe_i2a(j)~")*resStrideJ)+=";
                for (int i=iStart;i<iEnd;++i){
                    bool shouldAdd=false;
                    for (int diff=-1;diff<2;++diff){
                        if (0<=j+diff && j+diff<-jrest){
                            if (shouldAdd) res~="+";
                            res~="c"~ctfe_i2a(i-istream)~ctfe_i2a(1+diff)~
                                "*cast(T*)(cast(size_t)aPtr0+"~ctfe_i2a(i-1)~"*aStrideI+"~ctfe_i2a(j+diff)~"*aStrideJ)";
                            shouldAdd=true;
                        }
                    }
                }
                res~=";\n";
            }
        }
    } else {        
        // loop (>3 elements)
        res~=indent~"index_type j=jmin;\n";
        if (border==Border.Decrease)
            res~=indent~"aPtr0=cast(T*)(cast(size_t)aPtr0-resStrideJ);\n";
        res~=indent~"T* aPtrMenoI=cast(T*)(cast(size_t)aPtr0-aStrideI);\n";
        res~=indent~"T* aPtrPiuI=cast(T*)(cast(size_t)aPtr0+aStrideI);\n";
        for (int i=imin;i<imax;++i){
            res~="T ";
            for (int j=0;j<2;++j){
                if (j!=0)
                    res~=", ";
                res~="a"~ctfe_i2a(i)~ctfe_i2a(j);
            }
            res~=";\n";
        }
        if (border==Border.Decrease) {
            for (int jshift=1;jshift<3;++jshift){
                res~=incrementA(indent,imax,imax,jshift);
            }
        } else {
            for (int jshift=0;jshift<2;++jshift){
                res~=incrementA(indent,imax,imax,jshift);
            }
        }
        // set partial border
        if (border==Border.Increase){
            res~=indent~"resPtr0=cast(T*)(cast(size_t)resPtr0-resStrideJ);\n";
            res~=convolveBase(indent,istream_m,istream_z,istream_p,1,2,3,imin,imax);
            res~=indent~"resPtr0=cast(T*)(cast(size_t)resPtr0+resStrideJ);\n";
            res~=convolveBase(indent,istream_m,istream_z,istream_p,2,1,3,imin,imax);
        } else if (border==Border.Same){
            res~=convolveBase(indent,istream_m,istream_z,istream_p,2,1,3,imin,imax);
        }
        res~=indent;
        res~="for (j=junloop;j!=0;--j){\n";
        char[] indent2=indent~"    ";
        for (int jshift=0;jshift<3;++jshift){
            res~=incrementA(indent2,imin,imax,(jshift+2)%3);
            res~=indent~"resPtr0=cast(T*)(cast(size_t)resPtr0+resStrideJ);\n";
            res~=convolveBase(indent2,istream_m,istream_z,istream_p,jshift,0,3,imin,imax);
        }
        res~=indent~"}\n";
        // jrest=jcore%3
        for (int jshift=0;jshift<jrest;++jshift){
            res~=incrementA(indent2,imin,imax,(jshift+2)%3);
            res~=indent~"resPtr0=cast(T*)(cast(size_t)resPtr0+resStrideJ);\n";
            res~=convolveBase(indent,istream_m,istream_z,istream_p,jshift,0,3,imin,imax);
        }
        // set partial border
        if (border==Border.Same){
            res~=convolveBase(indent,istream_m,istream_z,istream_p,jrest,0,2,imin,imax);
        } else if (border==Border.Increase){
            res~=convolveBase(indent,istream_m,istream_z,istream_p,jrest,0,2,imin,imax);
            res~=indent~"resPtr0=cast(T*)(cast(size_t)resPtr0+resStrideJ);\n";
            res~=convolveBase(indent,istream_m,istream_z,istream_p,(jrest+1)%3,0,1,imin,imax);
        }
    }
    res~=indent~"}\n";
    return res;
}

//pragma(msg,"convolveJLoop(char[] indent0,int jrest=0,bool istream_m=true, bool istream_z=true,
//    bool istream_p=true,int imin=0,int imax=3,Border border=Border.Same)");
//pragma(msg,convolveJLoop("    "));
//pragma(msg,"----");

// outer loop for 2d convolve
// iOut=outA.shape[rank-2]
// icore=the length in i dir without border - 2 = min(iIn,iOut)-2
// icore=2*iunloop+irest
// if (irest<0) -irest=min(inA.shape[rank-2],outA.shape[rank-2]) (only -1 implemented)
char[] convolveILoop(char[]indent,int jrest,int irest,Border border){
    char [] res="".dup;
    char [] incrementI=`
    resPtr0I=cast(T*)(cast(size_t)resPtr0I+resStrideI);
    aPtr0I=cast(T*)(cast(size_t)aPtr0I+aStrideI);
`;
    char [] increment2I=`
    resPtr0I=cast(T*)(cast(size_t)resPtr0I+2*resStrideI);
    aPtr0I=cast(T*)(cast(size_t)aPtr0I+2*aStrideI);
`;
    
    if (irest<0){
        res~=indent~"index_type iRest=maxi;\n";
        res~="T* resPtr0I=pOutAPtr0;\n";
        res~="T* aPtr0I=pInAPtr0;\n";
        if (irest==-1) {
            if (border==Border.Same){
                res~=convolveJLoop(indent,jrest,false,true,false,1,2,border);
            } else if (border==Border.Increase){
                res~=convolveJLoop(indent,jrest,true,true,true,1,2,border);                
            }
        } else {
            assert(0,"explicit i loops with min(iIn,iOut)=1 implemented without i loop");
        }
    } else {
        //first load
        if (border==Border.Decrease){
            res~=convolveJLoop(indent,jrest,false,true,true,0,3,border);
        } else if (border==Border.Increase){
            res~=convolveJLoop(indent,jrest,true,true,true,1,3,border);
        } else {
            res~=convolveJLoop(indent,jrest,false,true,true,1,3,border);
        }
        res~=increment2I;
        // bulk calc
        res~=indent~"for (i=iunloop;i!=0;--i){\n";
        char[] indent2=indent~"    ";
        res~=convolveJLoop(indent2,jrest,true,true,true,0,3,border);
        res~=increment2I;
        res~=indent~"}\n";
        // final set
        if (border==Border.Same){
            res~=indent~"if (irest==1){\n";
            res~=convolveJLoop(indent2,jrest,true,true,false,0,2,border);
            res~=indent~"}\n";
        } else if (border==Border.Increase){
            res~=indent~"if (irest==1){\n";
            res~=convolveJLoop(indent2,jrest,true,true,true,0,2,border);
            res~=indent~"} else {\n";
            res~=convolveJLoop(indent2,jrest,false,true,false,0,1,border);
            res~=indent~"}\n";
        } else {
            res~=indent~"if (irest==1){\n";
            res~=convolveJLoop(indent2,jrest,true,true,false,0,3,border);
            res~=indent~"} else {\n";
            res~=convolveJLoop(indent2,jrest,true,false,false,0,2,border);
            res~=indent~"}\n";
        }
    }
    return res;
}

//pragma(msg,"convolveILoop(char[]indent,int jrest,int irest,Border border");
//pragma(msg,convolveILoop("    ",0,0,Border.Same));
//pragma(msg,"-------");

/// operations to do before convolveIJ
char[] preConvolveIJSetup(char[]indent,char[]inAName,char[]outAName,Border border,bool jOnly=false)
{
    char[] res="".dup;
    res~=indent~"index_type jIn="~inAName~".shape[rank-1];\n";
    res~=indent~"index_type jOut="~outAName~".shape[rank-1];\n";
    res~=indent~"index_type jmin=((jIn<jOut)?jIn:jOut);\n";
    res~=indent~"index_type jcore=jOut";
    if (border==Border.Same) res~="-2";
    if (border==Border.Increase) res~="-4";
    res~=";\n";
    res~=indent~"index_type junloop=jcore/3;\n";
    res~=indent~"index_type jrest=jcore%3;\n";
    
    if (jOnly){
        res~=indent~"index_type iIn=1;\n";
        res~=indent~"index_type iOut=1;\n";
    } else {
        res~=indent~"index_type iIn="~inAName~".shape[rank-2];\n";
        res~=indent~"index_type iOut="~outAName~".shape[rank-2];\n";
    }
    res~=indent~"index_type imin=((iIn<iOut)?iIn:iOut);\n";
    res~=indent~"index_type icore=imin-2;\n";
    res~=indent~"index_type iunloop=icore/2;\n";
    res~=indent~"index_type irest=icore%2;\n";
    
    res~=indent~"if(jmin<3)\n";
    res~=indent~"    jrest=-jout;\n";
    res~=indent~"if (imin==1)\n";
    res~=indent~"    ires=-1;\n";
    res~=indent~"int switchTag=10*ires+jrest;\n";
    res~=indent~"if (imin<=0 || jmin<=0){\n";
    res~=indent~"    switchTag=-1000;\n";
    res~=indent~"}\n";
    res~=indent~"index_type resStrideJ="~outAName~".shape[rank-1];\n";
    res~=indent~"index_type aStrideJ="~inAName~".shape[rank-1];\n";
    if (jOnly){
        res~=indent~"index_type resStrideI=0;\n";
        res~=indent~"index_type aStrideI=0;\n";
    } else {
        res~=indent~"index_type resStrideI="~outAName~".shape[rank-2];\n";
        res~=indent~"index_type aStrideI="~inAName~".shape[rank-2];\n";
    }
    return res;
}

//pragma(msg,"preConvolveIJSetup(char[]indent,char[]inAName,char[]outAName,Border border,bool jOnly=false)");
//pragma(msg,preConvolveIJSetup("    ","inA","outA",Border.Same));
//pragma(msg,"------");

/// 2d convolution with nearest neighbors
/// the variables of preConvolveIJSetup and T*pOutAPtr0,pInAPtr0 have to be defined
char[] convolveIJ(char[] indent,Border border){
    char[] res="".dup;
    res~=indent~"switch (switchTag){\n";
    char[] indent2=indent~"    ";
    foreach (ires;[-1,0]){
        foreach (jres;[-4,-3,-2,-1,0,1,2]){
            res~=indent~"case "~ctfe_i2a(10*ires+jres)~":\n";
            res~=indent~"  {\n";
            res~=convolveILoop(indent2,jres,ires,border);
            res~=indent~"  }\n";
            res~=indent~"break;\n";
        }
    }
    res~=indent~"case(-1000) break;\n";
    res~=indent2~"default: assert(0);\n";
    res~=indent~"}\n";
    return res;
}
//pragma(msg,"----------");
//pragma(msg,convolveIJ("    ",Border.Same));
//pragma(msg,"==========");

/// performs a convolution using the given (full) kernel
NArray!(T,rank) convolveNNRef(T,int rank,Border border=Border.Same)
    (NArray!(T,rank) kernel,NArray!(T,rank)inA,NArray!(T,rank)outA=null)
in {
    for (int i=0;i<rank;++i){
        assert(kernel.shape[i]==3,"kernel must have 3 elements in each dimension"); // relax?
    }
    if (outA !is null && (!(inA.flags & ArrayFlags.Zero))){
        for (int i=0;i<rank;++i){
            index_type inI=inA.shape[i];
            index_type outI=outA.shape[i];
            inI+=2*cast(index_type)cast(int)border;
            assert(outI==inI,"outA should have the same shape as inA (+2 with Border.Increase, -2 with Border.Decrease)");
        }
    }
}
body{
    if (inA.flags & ArrayFlags.Zero) return outA;
    if (outA is null){
        index_type[rank] outShape=inA.shape;
        foreach(ref el;outShape){
            el+=2*cast(index_type)cast(int)border;
        }
        outA=zeros!(T)(outShape);
    }
    if (outA.flags & ArrayFlags.Zero) return outA;
    index_type iG=cast(index_type)cast(int)border-cast(index_type)1;
    static if(rank==1){
        for (index_type iIn=0;iIn<inA.shape[0];++iIn)
        for (index_type iKernel=0;iKernel<3;++iKernel){
            iOut=iIn+iKernel+iG;
            if (iOut>=0 && iOut<outA.shape[0]){
                outA[iOut]+=inA[iIn]*kernel[iKernel];
            }
        }
    } else static if(rank==2){
        for (index_type iIn=0;iIn<inA.shape[0];++iIn)
        for (index_type iKernel=0;iKernel<3;++iKernel){
            iOut=iIn+iKernel+iG;
            if (iOut>=0 && iOut<outA.shape[0])
            for (index_type jIn=0;jIn<inA.shape[1];++jIn)
            for (index_type jKernel=0;jKernel<3;++jKernel){
                jOut=jIn+jKernel+iG;
                if (jOut>=0 && jOut<outA.shape[1]){
                    outA[iOut,jOut]+=inA[iIn,jIn]*kernel[iKernel,jKernel];
                }
            }
        }
    } else static if(rank==3){
        for (index_type iIn=0;iIn<inA.shape[0];++iIn)
        for (index_type iKernel=0;iKernel<3;++iKernel){
            iOut=iIn+iKernel+iG;
            if (iOut>=0 && iOut<outA.shape[0])
            for (index_type jIn=0;jIn<inA.shape[1];++jIn)
            for (index_type jKernel=0;jKernel<3;++jKernel){
                jOut=jIn+jKernel+iG;
                if (jOut>=0 && jOut<outA.shape[1])
                for (index_type kIn=0;kIn<inA.shape[2];++kIn)
                for (index_type kKernel=0;kKernel<3;++kKernel){
                    kOut=kIn+kKernel+iG;
                    if (kOut>=0 && kOut<outA.shape[2]){
                        outA[iOut,jOut]+=inA[iIn,jIn]*kernel[iKernel,jKernel,kKernel];
                    }
                }
            }
        }
    } else {
        static assert(0,"unimplemented");
    }
}

/// performs a convolution using the given (full) kernel
void convolveNN(T,int rank,Border border)
    (NArray!(T,rank) kernel,NArray!(T,rank)inA,NArray!(T,rank)outB)
in {
    for (int i=0;i<rank;++i){
        assert(kernel.shape[i]==3,"kernel must have 3 elements in each dimension"); // relax?
    }
    if (outA !is null && (!(inA.flags & ArrayFlags.Zero))){
        for (int i=0;i<rank;++i){
            index_type inI=inA.shape[i]-2*cast(index_type)cast(int)border;
            index_type outI=outA.shape[i];
            assert(outI==inI,"outA should have the same shape as inA (+2 with Border.Increase, -2 with Border.Decrease)");
        }
    }
}
body{
    //pragma(msg,"convolveNN, rank="~ctfe_i2a(rank)~", border="~ctfe_i2a(cast(int)border));
    if (inA.flags & ArrayFlags.Zero) return outA;
    if (outA is null){
        T c10=kernel[0],c11=kernel[1],c12=kernel[2];
        index_type[rank] outShape=inA.shape;
        foreach(ref el;outShape){
            el+=2*cast(index_type)cast(int)border;
        }
        outA=zeros!(T)(outShape);
    }
    if (outA.flags & ArrayFlags.Zero) return outA;
    static if(rank==1){
        //pragma(msg,preConvolveIJSetup("    ","inA","outA",border,true));
        mixin(preConvolveIJSetup("    ","inA","outA",border,true));
        T* pOutAPtr0=outA.startPtrArray,pInAPtr0=inA.startPtrArray;
        mixin(convolveIJ("    "));
    } else static if (rank==2){
        T c00=kernel[0,0],c01=kernel[0,1],c02=kernel[0,2];
        T c10=kernel[1,0],c11=kernel[1,1],c12=kernel[1,2];
        T c20=kernel[2,0],c21=kernel[2,1],c22=kernel[2,2];
        mixin(preConvolveIJSetup("    ","inA","outA",border));
        T* pOutAPtr0=outA.startPtrArray,pInAPtr0=inA.startPtrArray;
        mixin(convolveIJ("    "));
    } else static if (rank==3){
        mixin(preConvolveIJSetup("    ","inA","outA",border,true));
        index_type partialShape=min(inA.shape[0],outA.shape[0]);
        NArray!(T,1) partialInA=NArray!(T,1)([inA.strides[0]], [partialShape], 
            cast(T*)(cast(size_t)inA.startPtrArray+((inA.shape[0]-partialShape)/2)*inA.strides[0]),
            inA.newFlags, inA.newBase);
        NArray!(T,1) partialOutA=NArray!(T,1)([outA.strides[0]], [partialShape], 
            cast(T*)(cast(size_t)outA.startPtrArray+((outA.shape[0]-partialShape)/2)*outA.strides[0]),
            outA.newFlags, outA.newBase);
        const char[] intConvolveStr=convolveIJ("    ");
        static if (border==Border.Increase){
            const loopBody=`
            for (index_type kDiff=-1;kDiff<2;++kDiff){
                T* pOutAPtr0=cast(T)(cast(size_t)partialOutAPtr0+kDiff*partialOutAStride0);
                T* pInAPtr0=partialInAPtr0;
                T c00=kernel[kDiff+1,0,0],c01=kernel[kDiff+1,0,1],c02=kernel[kDiff+1,0,2];
                T c10=kernel[kDiff+1,1,0],c11=kernel[kDiff+1,1,1],c12=kernel[kDiff+1,1,2];
                T c20=kernel[kDiff+1,2,0],c21=kernel[kDiff+1,2,1],c22=kernel[kDiff+1,2,2];
            `~intConvolveStr~`
            }`;
        } else static if (border==Border.Decrease){
            const loopBody=`
            for (index_type kDiff=-1;kDiff<2;++kDiff){
                T* pOutAPtr0=partialOutAPtr0;
                T* pInAPtr0=cast(T*)(cast(size_t)partialInAPtr0-kDiff*partialInAStride0);
                T c00=kernel[kDiff+1,0,0],c01=kernel[kDiff+1,0,1],c02=kernel[kDiff+1,0,2];
                T c10=kernel[kDiff+1,1,0],c11=kernel[kDiff+1,1,1],c12=kernel[kDiff+1,1,2];
                T c20=kernel[kDiff+1,2,0],c21=kernel[kDiff+1,2,1],c22=kernel[kDiff+1,2,2];
            `~intConvolveStr~`
            }`;
        } else static if (border==Border.Same){
            index_type maxK=partialShape-1;
            const loopBody=`
            for (index_type kDiff=-1;kDiff<2;++kDiff){
                if (ii_0_==0 && kDiff==-1 || ii_0_==maxK && kDiff==1) continue;
                T* pOutAPtr0=cast(T)(cast(size_t)partialOutAPtr0+kDiff*partialOutAStride0);
                T* pInAPtr0=partialInAPtr0;
                T c00=kernel[kDiff+1,0,0],c01=kernel[kDiff+1,0,1],c02=kernel[kDiff+1,0,2];
                T c10=kernel[kDiff+1,1,0],c11=kernel[kDiff+1,1,1],c12=kernel[kDiff+1,1,2];
                T c20=kernel[kDiff+1,2,0],c21=kernel[kDiff+1,2,1],c22=kernel[kDiff+1,2,2];
            `~intConvolveStr~`
            }`;
        }
        //pragma(msg,loopBody);
        //pragma(msg,"------");
        mixin(pLoopIdx(rank,["partialInA","partialOutA"],loopBody,"ii"));
    }
    return outA;
}

/+ --------------------------------------------- +/
