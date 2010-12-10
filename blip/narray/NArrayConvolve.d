/// Implements convolution on NArrays
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
module blip.narray.NArrayConvolve;
import blip.narray.NArrayType;
import blip.narray.NArrayBasicOps;
import blip.util.TemplateFu;
import blip.core.Traits;
import blip.math.Math:min;
import blip.Comp;
debug(ConvolveCheckAccess) import blip.container.GrowableArray;
/+ --------- convolution --------- +/
// convolution base in 2d: 3 streams (minus,zero,plus), kernel[imin..imax,jmin..jmax] in aij
// i setup is: (vertical bar read, horizontal write, columns are the three streams)
//  -  |  
//  |  +  |
//     |  +
string convolveBase(string indent,bool istream_m=true, bool istream_z=true, bool istream_p=true,
        int jshift=0, int jmin=0, int jmax=3, int imin=0,int imax=3){
    string res="";
    if (istream_m && imin<=1 && 1<imax){
        res~=indent;
        debug (ConvolveCheckAccess) res~="safeOut(cast(T*)(cast(size_t)resPtr0-resStrideI),__LINE__);";
        res~="*cast(T*)(cast(size_t)resPtr0-resStrideI)+="; // [i-1,j]
        bool shouldAdd=false;
        for (int j=jmin;j<jmax;++j){
            if (shouldAdd) res~="+";
            res~="c0"~ctfe_i2a(2-j)~"*a1"~ctfe_i2a((j+jshift)%3);
            shouldAdd=true;
        }
        res~=";\n";
    }
    if (istream_z && imin<imax){
        res~=indent;
        debug (ConvolveCheckAccess) res~="safeOut(resPtr0,__LINE__);";
        res~="*resPtr0+="; // [i,j]
        bool shouldAdd=false;
        for (int i=imin;i<imax;++i){
            for (int j=jmin;j<jmax;++j){
                if (shouldAdd) res~="+";
                res~="c"~ctfe_i2a(2-i)~ctfe_i2a(2-j)~"*a"~ctfe_i2a(i)~ctfe_i2a((j+jshift)%3);
                shouldAdd=true;
            }
        }
        res~=";\n";
    }
    if (istream_p && ((imin<=1 && 1<imax) || (imin<=2 && 2<imax))){
        res~=indent;
        debug (ConvolveCheckAccess) res~="safeOut(cast(T*)(cast(size_t)resPtr0+resStrideI),__LINE__);";
        res~="*cast(T*)(cast(size_t)resPtr0+resStrideI)+=";// [i+1,j]
        bool shouldAdd=false;
        if (imin<=1 && 1<imax){
            for (int j=jmin;j<jmax;++j){
                if (shouldAdd) res~="+";
                res~="c2"~ctfe_i2a(2-j)~"*a1"~ctfe_i2a((j+jshift)%3);
                shouldAdd=true;
            }
        }
        if (imin<=2 && 2<imax){
            for (int j=jmin;j<jmax;++j){
                if (shouldAdd) res~="+";
                res~="c1"~ctfe_i2a(2-j)~"*a2"~ctfe_i2a((j+jshift)%3);
                shouldAdd=true;
            }
        }
        res~=";\n";
    }
    return res;
}

//pragma(msg,"convolveBase(string indent,bool istream_m=true, bool istream_z=true, bool istream_p=true,
//        int jshift=0, int jmin=0, int jmax=3, int imin=0,int imax=3)");
//pragma(msg,convolveBase("   "));
//pragma(msg,"------");

enum Border:int{
    Decrease=-1, Same=0, Increase=1
}

string incrementA(string indent,int imin,int imax,int jshift){
    string res="".dup;
    string aPtrName="";
    for (int i=imin;i<imax;++i){
        if (i==0) aPtrName="aPtrMenoI";
        if (i==1) aPtrName="aPtr0";
        if (i==2) aPtrName="aPtrPiuI";
        debug (ConvolveCheckAccess) res~="safeIn("~aPtrName~",__LINE__);";
        res~=indent~"a"~ctfe_i2a(i)~ctfe_i2a(jshift)~"= *"~aPtrName~";\n";
        res~=indent~aPtrName~"=cast(T*)(cast(size_t)"~aPtrName~"+aStrideJ);\n";
    }
    return res;
}

//pragma(msg,"incrementA(string indent,int imin,int imax,int jshift)");
//pragma(msg,incrementA("  ",0,3,0));
//pragma(msg,"----");

// inner convolution loop (for 2d convolve)
// convolveBase+code to do the j border correctly
// jOut=outA.shape[rank-1]
// jcore=the length in j dir without any partially evaluated border
//       jOut-(0 if Decrease, 2 if Same, 4 if Increase))
// jcore=3*junloop+jrest
// if (jrest<0) jOut=-jrest
string convolveJLoop(string indent0,int jrest=0,bool istream_m=true, bool istream_z=true,
    bool istream_p=true,int imin=0,int imax=3,Border border=Border.Same){
    string res="";
    res~=indent0~"{\n";
    string indent=indent0~"    ";
    res~=indent~"T* resPtr0=resPtr0I;\n";
    res~=indent~"T* aPtr0=aPtr0I;\n";
    if (jrest<0){
        // no loop (few elements)
        int jstart=0;
        int jInStart=0,jInEnd=-jrest;
        if (border==Border.Increase) {
            jstart=-1;
            jInEnd-=2;
        }
        int jend=jstart-jrest;
        if (border==Border.Decrease){
            --jInStart; ++jInEnd;
        }
        for (int istream=-1;istream<2;++istream){
            for (int j=jstart;j<jend;++j){
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
                if (iStart>=iEnd || jInStart>=jInEnd) continue;
                debug (ConvolveCheckAccess) {
                    res~="safeOut(cast(T*)(cast(size_t)resPtr0+("~ctfe_i2a(istream)~")*resStrideI+("
                        ~ctfe_i2a(j)~")*resStrideJ),__LINE__);\n";
                    for (int i=iStart;i<iEnd;++i){
                        for (int diff=-1;diff<2;++diff){
                            if (jInStart<=j+diff && j+diff<jInEnd){
                                res~="safeIn(cast(T*)(cast(size_t)aPtr0+"~ctfe_i2a(i-1)~"*aStrideI+"~ctfe_i2a(j+diff)~"*aStrideJ),__LINE__);\n";
                            }
                        }
                    }
                }
                res~=indent~"*cast(T*)(cast(size_t)resPtr0+("~ctfe_i2a(istream)~")*resStrideI+("
                    ~ctfe_i2a(j)~")*resStrideJ)+=";
                bool shouldAdd=false;
                for (int i=iStart;i<iEnd;++i){
                    for (int diff=-1;diff<2;++diff){
                        if (jInStart<=j+diff && j+diff<jInEnd){
                            if (shouldAdd) res~="+";
                            res~="c"~ctfe_i2a(2-i+istream)~ctfe_i2a(1-diff)~
                                "*(*cast(T*)(cast(size_t)aPtr0+"~ctfe_i2a(i-1)~"*aStrideI+"~ctfe_i2a(j+diff)~"*aStrideJ))";
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
            res~=indent~"T ";
            for (int j=0;j<3;++j){
                if (j!=0)
                    res~=", ";
                res~="a"~ctfe_i2a(i)~ctfe_i2a(j);
            }
            res~=";\n";
        }
        for (int jshift=0;jshift<2;++jshift){
            res~=incrementA(indent,imin,imax,jshift);
        }
        // set partial border
        if (border==Border.Increase){
            res~=indent~"resPtr0=cast(T*)(cast(size_t)resPtr0-resStrideJ);\n";
            res~=convolveBase(indent,istream_m,istream_z,istream_p,1,2,3,imin,imax);
            res~=indent~"resPtr0=cast(T*)(cast(size_t)resPtr0+resStrideJ);\n";
            res~=convolveBase(indent,istream_m,istream_z,istream_p,2,1,3,imin,imax);
            res~=indent~"resPtr0=cast(T*)(cast(size_t)resPtr0+resStrideJ);\n";
        } else if (border==Border.Same){
            res~=convolveBase(indent,istream_m,istream_z,istream_p,2,1,3,imin,imax);
            res~=indent~"resPtr0=cast(T*)(cast(size_t)resPtr0+resStrideJ);\n";
        }
        res~=indent;
        res~="for (j=junloop;j!=0;--j){\n";
        string indent2=indent~"    ";
        for (int jshift=0;jshift<3;++jshift){
            res~=incrementA(indent2,imin,imax,(jshift+2)%3);
            res~=convolveBase(indent2,istream_m,istream_z,istream_p,jshift,0,3,imin,imax);
            res~=indent2~"resPtr0=cast(T*)(cast(size_t)resPtr0+resStrideJ);\n";
        }
        res~=indent~"}\n";
        // jrest=jcore%3
        for (int jshift=0;jshift<jrest;++jshift){
            res~=incrementA(indent,imin,imax,(jshift+2)%3);
            res~=convolveBase(indent,istream_m,istream_z,istream_p,jshift,0,3,imin,imax);
            res~=indent~"resPtr0=cast(T*)(cast(size_t)resPtr0+resStrideJ);\n";
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
    res~=indent0~"}\n";
    return res;
}

//pragma(msg,"convolveJLoop(string indent0,int jrest=0,bool istream_m=true, bool istream_z=true,
//    bool istream_p=true,int imin=0,int imax=3,Border border=Border.Same)");
//pragma(msg,convolveJLoop("    "));
//pragma(msg,"----");

// outer loop for 2d convolve
// iOut=outA.shape[rank-2]
// icore=the length in i dir without border - 2 = min(iIn,iOut)-2
// icore=2*iunloop+irest
// if (irest<0) -irest=min(inA.shape[rank-2],outA.shape[rank-2]) (only -1 implemented)
string convolveILoop(string indent,int jrest,int irest,Border border){
    string res="";
    res~=indent~"T* resPtr0I=pOutAPtr0;\n";
    res~=indent~"T* aPtr0I=pInAPtr0;\n";
    if (irest<0){
        if (irest==-1) {
            if (border==Border.Same){
                res~=convolveJLoop(indent,jrest,false,true,false,1,2,border);
            } else if (border==Border.Increase){
                res~=convolveJLoop(indent,jrest,true,true,true,1,2,border);                
            } else {
                res~=convolveJLoop(indent,jrest,false,true,false,0,3,border);                
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
        res~=indent~"resPtr0I=cast(T*)(cast(size_t)resPtr0I+2*resStrideI);\n";
        res~=indent~"aPtr0I=cast(T*)(cast(size_t)aPtr0I+2*aStrideI);\n";
        // bulk calc
        res~=indent~"for (index_type i=iunloop;i!=0;--i){\n";
        string indent2=indent~"    ";
        res~=convolveJLoop(indent2,jrest,true,true,true,0,3,border);
        res~=indent2~"resPtr0I=cast(T*)(cast(size_t)resPtr0I+2*resStrideI);\n";
        res~=indent2~"aPtr0I=cast(T*)(cast(size_t)aPtr0I+2*aStrideI);\n";
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

//pragma(msg,"convolveILoop(string indent,int jrest,int irest,Border border");
//pragma(msg,convolveILoop("    ",0,0,Border.Same));
//pragma(msg,"-------");

/// operations to do before convolveIJ
string preConvolveIJSetup(string indent,string inAName,string outAName,Border border,bool jOnly=false)
{
    string res="".dup;
    res~="/+ line 0 +/ long convolveStartLine=__LINE__; /+ line 0 +/\n";
    res~=indent~"index_type jIn="~inAName~".shape[rank-1];\n";
    res~=indent~"index_type jOut="~outAName~".shape[rank-1];\n";
    res~=indent~"index_type jmin=((jIn<jOut)?jIn:jOut);\n";
    res~=indent~"index_type jcore=jOut";
    if (border==Border.Same) res~="-2";
    if (border==Border.Increase) res~="-4";
    res~=";\n";
    res~=indent~"index_type junloop=jcore/3;\n";
    res~=indent~"index_type jrest=jcore%3;\n";
    res~=indent~"if(jmin<3) jrest=-jOut;\n";
    res~=indent~"index_type resStrideJ="~outAName~".bStrides[rank-1];\n";
    res~=indent~"index_type aStrideJ="~inAName~".bStrides[rank-1];\n";
    
    if (jOnly){
        res~=indent~"int switchTag=jrest;\n";
        res~=indent~"if (jmin<=0) switchTag=-1000;\n";
        res~=indent~"index_type resStrideI=0;\n";
        res~=indent~"index_type aStrideI=0;\n";
    } else {
        res~=indent~"index_type iIn="~inAName~".shape[rank-2];\n";
        res~=indent~"index_type iOut="~outAName~".shape[rank-2];\n";
        res~=indent~"index_type imin=((iIn<iOut)?iIn:iOut);\n";
        res~=indent~"index_type icore=imin-2;\n";
        res~=indent~"index_type iunloop=icore/2;\n";
        res~=indent~"index_type irest=icore%2;\n";
    
        res~=indent~"if (imin==1)\n";
        res~=indent~"    irest=-1;\n";
        res~=indent~"int switchTag=jrest;\n";
        res~=indent~"if (irest==-1) switchTag-=10;\n";
        res~=indent~"if (imin<=0 || jmin<=0) switchTag=-1000;\n";
        res~=indent~"index_type resStrideI="~outAName~".bStrides[rank-2];\n";
        res~=indent~"index_type aStrideI="~inAName~".bStrides[rank-2];\n";
    }
    debug(ConvolveCheckAccess){
        res~=indent~"T[] inBaseSlice="~inAName~".data;\n";
        res~=indent~"T[] outBaseSlice="~outAName~".data;\n";
        res~=indent~"void safeOut(T* ptr,long lineNr){\n";
        res~=indent~"    if (ptr<outBaseSlice.ptr || ptr>=(outBaseSlice.ptr+outBaseSlice.length)){\n";
        res~=indent~"        string msg=collectAppender(void delegate(CharSink sink){\n";
        res~=indent~"            sink(\"ERROR convolve kernel invalid write\\n\");\n";
        res~=indent~"            dumper(sink)(\" invalid access of out array in convolution kernel, T=\")\n";
        res~=indent~"            (T.stringof)(\",rank=\")(rank)(\",switchTag=\")(switchTag)(\", line=\")\n";
        res~=indent~"            (lineNr-convolveStartLine)(\"\\n\")));\n";
        res~=indent~"        throw new Exception(msg);\n";
        res~=indent~"    }\n";
        res~=indent~"}\n";
        res~=indent~"void safeIn(T* ptr,long lineNr){\n";
        res~=indent~"    if (ptr<inBaseSlice.ptr || ptr>=(inBaseSlice.ptr+inBaseSlice.length)){\n";
        res~=indent~"        string msg=collectAppender(void delegate(CharSink sink){\n";
        res~=indent~"            dumper(s)(\"ERROR convolve kernel invalid read\\n\")\n";
        res~=indent~"            (\" invalid access of in array in convolution kernel, T=\")\n";
        res~=indent~"            (T.stringof)(\",rank=\")(rank)(\",switchTag=\")(switchTag)(\", line=\")\n";
        res~=indent~"            (lineNr-convolveStartLine)(\"\\n\"));\n";
        res~=indent~"        throw new Exception(msg);\n";
        res~=indent~"    }\n";
        res~=indent~"}\n";
    }
    return res;
}

//pragma(msg,"preConvolveIJSetup(string indent,string inAName,string outAName,Border border,bool jOnly=false)");
//pragma(msg,preConvolveIJSetup("    ","inA","outA",Border.Same));
//pragma(msg,"------");

/// 2d convolution with nearest neighbors
/// the variables of preConvolveIJSetup and T*pOutAPtr0,pInAPtr0 have to be defined
string convolveIJ(string indent,Border border){
    string res="".dup;
    res~=indent~"switch (switchTag){\n";
    string indent2=indent~"    ";
    foreach (ires;[-1,0]){
        foreach (jres;[-4,-3,-2,-1,0,1,2]){
            res~=indent~"case "~ctfe_i2a(10*ires+jres)~":\n";
            res~=indent~"  {\n";
            res~=convolveILoop(indent2,jres,ires,border);
            res~=indent~"  }\n";
            res~=indent~"break;\n";
        }
    }
    res~=indent~"case -1000: break;\n";
    res~=indent2~"default: assert(0,\"invalid switchTag \"~ctfe_i2a(switchTag));\n";
    res~=indent~"}\n";
    return res;
}
//pragma(msg,"----------");
//pragma(msg,convolveIJ("    ",Border.Same));
//pragma(msg,"==========");

/// 2d convolution with nearest neighbors
/// the variables of preConvolveIJSetup and T*pOutAPtr0,pInAPtr0 have to be defined
string convolveJOnly(string indent,Border border){
    string res="".dup;
    res~=indent~"T* resPtr0I=pOutAPtr0;\n";
    res~=indent~"T* aPtr0I=pInAPtr0;\n";
    res~=indent~"switch (switchTag){\n";
    string indent2=indent~"    ";
    foreach (jres;[-4,-3,-2,-1,0,1,2]){
        res~=indent~"case "~ctfe_i2a(jres)~":\n";
        res~=indent~"  {\n";
        res~=convolveJLoop(indent2,jres,false,true,false,1,2,border);
        res~=indent~"  }\n";
        res~=indent~"break;\n";
    }
    res~=indent~"case -1000: break;\n";
    res~=indent2~"default: assert(0,\"invalid switchTag \"~ctfe_i2a(switchTag));\n";
    res~=indent~"}\n";
    return res;
}

/// performs a convolution using the given (full) kernel
NArray!(T,rank) convolveNNRef(T,int rank,Border border=Border.Same)
    (NArray!(T,rank) kernel,NArray!(T,rank)inA,NArray!(T,rank)outA=nullNArray!(T,rank))
in {
    for (int i=0;i<rank;++i){
        assert(kernel.shape[i]==3,"kernel must have 3 elements in each dimension"); // relax?
    }
    if (!isNullNArray!(T,rank,true)(outA) && (!(inA.flags & ArrayFlags.Zero))){
        for (int i=0;i<rank;++i){
            index_type inI=inA.shape[i];
            index_type outI=outA.shape[i];
            static if (border==Border.Decrease) {
                if (inI<2) inI=cast(index_type)0; else inI-=cast(index_type)2;
            } else {
                inI+=cast(index_type)2*cast(index_type)cast(int)border;
            }
            assert(outI==inI,"outA should have the same shape as inA (+2 with Border.Increase, -2 with Border.Decrease)");
        }
    }
}
body{
    if (inA.flags & ArrayFlags.Zero) return outA;
    if (isNullNArray!(T,rank,true)(outA)){
        index_type[rank] outShape=inA.shape;
        foreach(ref el;outShape){
            static if (border==Border.Decrease){
                if (el<2)  el=cast(index_type)0; else el-=cast(index_type)2;
            } else {
                el+=cast(index_type)2*cast(index_type)cast(int)border;
            }
        }
        outA=zeros!(T)(outShape);
    }
    if (outA.flags & ArrayFlags.Zero) return outA;
    index_type iG=cast(index_type)cast(int)border-cast(index_type)1;
    static if(rank==1){
        for (index_type iIn=0;iIn<inA.shape[0];++iIn)
        for (index_type iKernel=0;iKernel<3;++iKernel){
            index_type iOut=iIn+iKernel+iG;
            if (iOut>=0 && iOut<outA.shape[0]){
                outA[iOut]=outA[iOut]+inA[iIn]*kernel[iKernel];
            }
        }
    } else static if(rank==2){
        for (index_type iIn=0;iIn<inA.shape[0];++iIn)
        for (index_type iKernel=0;iKernel<3;++iKernel){
            index_type iOut=iIn+iKernel+iG;
            if (iOut>=0 && iOut<outA.shape[0])
            for (index_type jIn=0;jIn<inA.shape[1];++jIn)
            for (index_type jKernel=0;jKernel<3;++jKernel){
                index_type jOut=jIn+jKernel+iG;
                if (jOut>=0 && jOut<outA.shape[1]){
                    outA[iOut,jOut]=outA[iOut,jOut]+inA[iIn,jIn]*kernel[iKernel,jKernel];
                }
            }
        }
    } else static if(rank==3){
        for (index_type iIn=0;iIn<inA.shape[0];++iIn)
        for (index_type iKernel=0;iKernel<3;++iKernel){
            index_type iOut=iIn+iKernel+iG;
            if (iOut>=0 && iOut<outA.shape[0])
            for (index_type jIn=0;jIn<inA.shape[1];++jIn)
            for (index_type jKernel=0;jKernel<3;++jKernel){
                index_type jOut=jIn+jKernel+iG;
                if (jOut>=0 && jOut<outA.shape[1])
                for (index_type kIn=0;kIn<inA.shape[2];++kIn)
                for (index_type kKernel=0;kKernel<3;++kKernel){
                    index_type kOut=kIn+kKernel+iG;
                    if (kOut>=0 && kOut<outA.shape[2]){
                        outA[iOut,jOut,kOut]=outA[iOut,jOut,kOut]+inA[iIn,jIn,kIn]*kernel[iKernel,jKernel,kKernel];
                    }
                }
            }
        }
    } else {
        static assert(0,"unimplemented");
    }
    return outA;
}

/// performs a convolution using the given (full) kernel
NArray!(T,rank) convolveNN(T,int rank,Border border=Border.Same)
    (NArray!(T,rank) kernel,NArray!(T,rank)inA,NArray!(T,rank)outA=nullNArray!(T,rank))
in {
    for (int i=0;i<rank;++i){
        assert(kernel.shape[i]==3,"kernel must have 3 elements in each dimension"); // relax?
    }
    if (!isNullNArray!(T,rank,true)(outA) && (!(inA.flags & ArrayFlags.Zero))){
        for (int i=0;i<rank;++i){
            index_type inI=inA.shape[i];
            static if (border==Border.Decrease) {
                if (inI<2) inI=cast(index_type)0; else inI-=cast(index_type)2;
            } else {
                inI+=cast(index_type)2*cast(index_type)cast(int)border;
            }
            index_type outI=outA.shape[i];
            assert(outI==inI,"outA should have the same shape as inA (+2 with Border.Increase, -2 with Border.Decrease)");
        }
    }
}
body{
    //pragma(msg,"convolveNN, rank="~ctfe_i2a(rank)~", border="~ctfe_i2a(cast(int)border));
    if (inA.flags & ArrayFlags.Zero) return outA;
    if (isNullNArray!(T,rank,true)(outA)){
        index_type[rank] outShape=inA.shape;
        foreach(ref el;outShape){
            static if (border==Border.Decrease){
                if (el<2)  el=cast(index_type)0; else el-=cast(index_type)2;
            } else {
                el+=cast(index_type)2*cast(index_type)cast(int)border;
            }
        }
        outA=zeros!(T)(outShape);
    }
    if (outA.flags & ArrayFlags.Zero) return outA;
    static if(rank==1){
        static if (border==Border.Increase){
            const istring startPStr
            ="    T* pOutAPtr0=cast(T*)(cast(size_t)outA.startPtrArray+outA.bStrides[0]);\n"
            ~"    T* pInAPtr0=inA.startPtrArray;\n";
        } else static if (border==Border.Same){
            const istring startPStr="    T* pOutAPtr0=outA.startPtrArray,pInAPtr0=inA.startPtrArray;\n";
        } else {
            const istring startPStr
            ="    T* pOutAPtr0=outA.startPtrArray;\n"
            ~"    T* pInAPtr0=cast(T*)(cast(size_t)inA.startPtrArray+inA.bStrides[0]);\n";
        }
        const istring loopStr
            ="    T c10=kernel[0],c11=kernel[1],c12=kernel[2];\n"
            ~"    T c00,c01,c02,c20,c21,c22;\n"
            ~preConvolveIJSetup("    ","inA","outA",border,true)
            ~startPStr
            ~convolveJOnly("    ",border);
//        pragma(msg,"convolveNN("~T.stringof~","~ctfe_i2a(rank)~","~ctfe_i2a(cast(int)border)~")");
//        pragma(msg,loopStr);
        mixin(loopStr);
//        pragma(msg,"----");
    } else static if (rank==2){
        T c00=kernel[0,0],c01=kernel[0,1],c02=kernel[0,2];
        T c10=kernel[1,0],c11=kernel[1,1],c12=kernel[1,2];
        T c20=kernel[2,0],c21=kernel[2,1],c22=kernel[2,2];
        static if (border==Border.Increase){
            const istring startPStr
            ="    T* pOutAPtr0=cast(T*)(cast(size_t)outA.startPtrArray+outA.bStrides[0]+outA.bStrides[1]);\n"
            ~"    T* pInAPtr0=inA.startPtrArray;\n";
        } else static if (border==Border.Same){
            const istring startPStr="    T* pOutAPtr0=outA.startPtrArray,pInAPtr0=inA.startPtrArray;\n";
        } else {
            const istring startPStr
            ="    T* pOutAPtr0=outA.startPtrArray;\n"
            ~"    T* pInAPtr0=cast(T*)(cast(size_t)inA.startPtrArray+inA.bStrides[0]+inA.bStrides[1]);\n";
        }
        const istring loopStr
        =startPStr
        ~preConvolveIJSetup("    ","inA","outA",border)
        ~convolveIJ("    ",border);
        //pragma(msg,"convolveNN("~T.stringof~","~ctfe_i2a(rank)~","~ctfe_i2a(cast(int)border)~")");
        //pragma(msg,loopStr);
        mixin(loopStr);
        //pragma(msg,"--------");
    } else static if (rank==3){
        mixin(preConvolveIJSetup("    ","inA","outA",border));
        index_type partialShape=min(inA.shape[0],outA.shape[0]);
        NArray!(T,1) partialInA=NArray!(T,1)([inA.bStrides[0]], [partialShape], 
            cast(T*)(cast(size_t)inA.startPtrArray
                +((inA.shape[0]-partialShape)/2)*(inA.bStrides[0]+inA.bStrides[1]+inA.bStrides[2])),
            inA.newFlags, inA.newBase);
        NArray!(T,1) partialOutA=NArray!(T,1)([outA.bStrides[0]], [partialShape], 
            cast(T*)(cast(size_t)outA.startPtrArray
                +((outA.shape[0]-partialShape)/2)*(outA.bStrides[0]+outA.bStrides[1]+outA.bStrides[2])),
            outA.newFlags, outA.newBase);
        const istring intConvolveStr=convolveIJ("    ",border);
        static if (border==Border.Increase){
            const loopBody=`
            for (index_type kDiff=-1;kDiff<2;++kDiff){
                T* pOutAPtr0=cast(T*)(cast(size_t)partialOutAPtr0+kDiff*partialOutAStride0);
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
            const loopBody=`/+ line 0_new +/ convolveStartLine=__LINE__; /+ line 0_new +/
            for (index_type kDiff=-1;kDiff<2;++kDiff){
                if (ii_0_==0 && kDiff==-1 || ii_0_==maxK && kDiff==1) continue;
                T* pOutAPtr0=cast(T*)(cast(size_t)partialOutAPtr0+kDiff*partialOutAStride0);
                T* pInAPtr0=partialInAPtr0;
                T c00=kernel[kDiff+1,0,0],c01=kernel[kDiff+1,0,1],c02=kernel[kDiff+1,0,2];
                T c10=kernel[kDiff+1,1,0],c11=kernel[kDiff+1,1,1],c12=kernel[kDiff+1,1,2];
                T c20=kernel[kDiff+1,2,0],c21=kernel[kDiff+1,2,1],c22=kernel[kDiff+1,2,2];
            `~intConvolveStr~`
            }`;
        }
        //pragma(msg,"convolveNN("~T.stringof~","~ctfe_i2a(rank)~","~ctfe_i2a(cast(int)border)~")");
        //pragma(msg,loopBody);
        //pragma(msg,"------");
        index_type optimalChunkSize_ii=NArray!(T,rank).defaultOptimalChunkSize;
        mixin(pLoopIdx(1,["partialInA","partialOutA"],loopBody,"ii"));
    }
    return outA;
}

/+ --------------------------------------------- +/
