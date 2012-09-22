/// performace tests of NArray
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
module testNArrayPerf;
import blip.io.Console;
import blip.io.BasicIO;
import tango.core.Exception;
import tango.time.StopWatch;
import tango.math.Math;
import blip.narray.NArray;
import blip.container.GrowableArray;
version(NoTrace){} else { import blip.core.stacktrace.TraceExceptions; }
import blip.Comp;

version(multiarray){
    import murray.multiarray: ndarray,ones,zeros;

    alias ndarray!(double) array;
}

alias ubyte[3] v3;

struct ATst{
    int startIdx;
    int[3] strides;
    int[3] dims;
    double[] m_data;
    double opIndex(int i,int j, int k){
        int i1,i2;
        i1=startIdx+i*strides[0];
        i2=i1+j*strides[1];
        return m_data[i2+k*strides[2]];
    }
}

class ATst2{
    const int s1,s2,s3;
    int[3] dims;
    double[] m_data;
    final double opIndex(int i,int j, int k){
        int i1,i2;
        i1=i*s1;
        i2=i1+j*s2;
        return m_data[i2+k*s3];
    }
    this(int[3] a, int[3] b){
        s1=a[0];
        s2=a[1];
        s3=a[2];
        dims[]=b;
    }
}

long timerT()
{
     asm
     {   naked                   ;
         rdtsc                   ;
         ret                     ;
     }
}

void tst()
{
    int ndim=100;
    int nrep=10;
    auto fEig=&eig!(float);
    ATst a1,a2;
    foreach (t;a1.dims) t=ndim;
    a1.strides[]=[ndim*ndim,ndim,1];
    a1.dims[]=ndim;
    a1.m_data=new double[ndim*ndim*ndim];
    a2.dims[]=ndim;
    a2.dims[0]=1;
    a2.strides[]=[ndim*ndim,ndim,1];
    a2.m_data=new double[ndim*ndim];
    StopWatch timer;
    ATst2 b1,b2;
    b1=new ATst2([ndim*ndim,ndim,1],[ndim,ndim,ndim]);
    b2=new ATst2([ndim*ndim,ndim,1],[1,ndim,ndim]);
    b1.m_data=a1.m_data;
    b2.m_data=a2.m_data;
    
    a1.m_data[]=1.0L;
    a2.m_data[]=1.0L;
    for (int mX=3;mX!=0;--mX){
    double[] res2=new double[ndim];
    res2[]=0.0L;
    timer.start;
    for (int irep=nrep;irep!=0;--irep){
        double *p1,p2,p2End,p3,p3End;
        p2End=a2.m_data.ptr+ndim*ndim;
        p3=res2.ptr;
        p3End=p3+ndim;
        p1=a1.m_data.ptr;
        for (;p3!=p3End;++p3){
            for (p2=a2.m_data.ptr;p2!=p2End;++p2,++p1)
                *p3+=(*p1)*(*p2);
        }
    }
    auto tref=timer.stop();

    double[] res=new double[ndim];
    res[]=0.0L;
    timer.start();
    for (int irep=nrep;irep!=0;--irep){
        for (int i=0;i!=ndim;++i)
        for (int j=0;j!=ndim;++j)
        for (int k=0;k!=ndim;++k){
            res[i]+=a1[i,j,k]*a2[0,j,k];
        }
    }
    auto t1=timer.stop();
    
    foreach(i,t;res)
        if (!(abs(t-res2[i])<1.0e-12)) {
            sout(collectAppender(delegate void(scope CharSink s){
                s("error1"); writeOut(s,i); s(" "); writeOut(s,t); s(" "); writeOut(s,res2[i]); s("\n");
            }));
        }
        
    res[]=0.0L;
    timer.start();
    for (int irep=nrep;irep!=0;--irep){
        for (int i=0;i!=ndim;++i)
        for (int j=0;j!=ndim;++j)
        for (int k=0;k!=ndim;++k){
            res[i]+=b1[i,j,k]*b2[0,j,k];
        }
    }
    auto t2=timer.stop();
    foreach(i,t;res)
        if (!(abs(t-res2[i])<1.0e-12)) {
            sout(collectAppender(delegate void(scope CharSink s){
                s("error2"); writeOut(s,i); s(" "); writeOut(s,t); s(" "); writeOut(s,res2[i]); s("\n");
            }));
        }

    version(multiarray){
        array c1=ones!(double)([ndim,ndim,ndim]);
        array c2=ones!(double)([1,ndim,ndim]);
        res[]=0.0L;
        timer.start();
        for (int irep=nrep;irep!=0;--irep){
            for (int i=0;i!=ndim;++i)
            for (int j=0;j!=ndim;++j)
            for (int k=0;k!=ndim;++k){
                res[i]+=c1.get([i,j,k])*c2.get([0,j,k]);
            }
        }
        auto t3=timer.stop();
        foreach(i,t;res)
            if (!(abs(t-res2[i])<1.0e-12)) {
                sout(collectAppender(delegate void(scope CharSink s){
                    s("error3"); writeOut(s,i); s(" "); writeOut(s,t); s(" "); writeOut(s,res2[i]); s("\n");
                }));
            }
    
        res[]=0.0L;
        timer.start();
        for (int irep=nrep;irep!=0;--irep){
            auto i1=c1.flat_iter;
            for (int i=0;i!=ndim;++i){
                for (auto i2=c2.flat_iter;!i2.end;++i1,++i2){
                    res[i]+=i1.value*i2.value;
                }
            }
        }
        auto t4=timer.stop();
        foreach(i,t;res)
            if (!(abs(t-res2[i])<1.0e-12)) {
                sout(collectAppender(delegate void(scope CharSink s){
                    s("error4"); writeOut(s,i); s(" "); writeOut(s,t); s(" "); writeOut(s,res2[i]); s("\n");
                }));
            }
    
        res[]=0.0L;
        timer.start();
        for (int irep=nrep;irep!=0;--irep){
            foreach (i,ii;c1.iter){
                i1=ii.flat_iter;
                auto i2=c2.flat_iter;
                for (;!i2.end;++i1,++i2){
                    res[i]+=i1.value*i2.value;
                }
                ++i;
            }
        }
        auto t5=timer.stop();
        foreach(i,t;res)
            if (!(abs(t-res2[i])<1.0e-12)) {
                sout(collectAppender(delegate void(scope CharSink s){
                    s("error5"); writeOut(s,i); s(" "); writeOut(s,t); s(" "); writeOut(s,res2[i]); s("\n");
                }));
            }
    } else {
        double t3=0.0,t4=0.0,t5=0.0;
    }
    // smart compiler
    res[]=0.0L;
    timer.start();
    for (int irep=nrep;irep!=0;--irep){
        for (int i=0;i!=ndim;++i){
            int ii1=i*a1.strides[0];
            for (int j=0;j!=ndim;++j){
                int jj1=ii1+j*a1.strides[1];
                int jj2=j*a2.strides[1];
                for (int k=0;k!=ndim;++k){
                    res[i]+=a1.m_data[jj1+k*a1.strides[2]]*a2.m_data[jj2+k*a2.strides[2]];
                }
            }
        }
    }
    auto t6=timer.stop();
    foreach(i,t;res)
        if (!(abs(t-res2[i])<1.0e-12)) {
            sout(collectAppender(delegate void(scope CharSink s){
                s("error6"); writeOut(s,i); s(" "); writeOut(s,t); s(" "); writeOut(s,res2[i]); s("\n");
            }));
        }
    
    res[]=0.0L;
    timer.start();
    for (int irep=nrep;irep!=0;--irep){
        for (int i=0;i!=ndim;++i){
            int ii1=i*b1.s1;
            for (int j=0;j!=ndim;++j){
                int jj1=ii1+j*b1.s2;
                int jj2=j*b2.s2;
                for (int k=0;k!=ndim;++k){
                    res[i]+=b1.m_data[jj1+k*b1.s3]*b2.m_data[jj2+k*b2.s3];
                }
            }
        }
    }
    auto t7=timer.stop();
    foreach(i,t;res)
        if (!(abs(t-res2[i])<1.0e-12)) {
            sout(collectAppender(delegate void(scope CharSink s){
                s("error7"); writeOut(s,i); s(" "); writeOut(s,t); s(" "); writeOut(s,res2[i]); s("\n");
            }));
        }

    // check removal of multiplication by compiler
    res[]=0.0L;
    timer.start();
    for (int irep=nrep;irep!=0;--irep){
        int ii1=0;
        for (int i=0;i!=ndim;++i){
            int jj1=ii1;
            int jj2=0;
            for (int j=0;j!=ndim;++j){
                int kk1=jj1;
                int kk2=jj2;
                for (int k=0;k!=ndim;++k){
                    res[i]+=a1.m_data[kk1]*a2.m_data[kk2];
                    kk1+=a1.strides[2];
                    kk2+=a2.strides[2];
                }
                jj1+=a1.strides[1];
                jj2+=a2.strides[1];
            }
            ii1+=a1.strides[0];
        }
    }
    auto t8=timer.stop();
    foreach(i,t;res)
        if (!(abs(t-res2[i])<1.0e-12)) {
            sout(collectAppender(delegate void(scope CharSink s){
                s("error8"); writeOut(s,i); s(" "); writeOut(s,t); s(" "); writeOut(s,res2[i]); s("\n");
            }));
        }
    
    res[]=0.0L;
    alias NArray!(double,3) NArr;
    NArr d1=NArr.ones([ndim,ndim,ndim]),d2=NArr.ones([1,ndim,ndim]);
    auto resNArr=a2NA(res);
    timer.start();
    for (int irep=nrep;irep!=0;--irep){
        for (int i=0;i<ndim;i++)
        for (int j=0;j<ndim;j++)
        for (int k=0;k<ndim;k++){
            resNArr[i]=resNArr[i]+d1[i,j,k]*d2[0,j,k];
        }
    }
    auto t9=timer.stop();
    foreach(i,t;res)
        if (!(abs(t-res2[i])<1.0e-12)) {
            sout(collectAppender(delegate void(scope CharSink s){
                s("error9"); writeOut(s,i); s(" "); writeOut(s,t); s(" "); writeOut(s,res2[i]); s("\n");
            }));
        }
    
    res[]=0.0L;
    timer.start();
    for (int irep=nrep;irep!=0;--irep){
        auto sc2=d2[0];
        int iii;
        void sumRes(double a,double b){ res[iii]+=a*b; }
        for (iii=0;iii<ndim;iii++){
	    auto aa=d1[iii];
            binaryOp!(sumRes,typeof(d1[iii]),typeof(sc2))(aa,sc2);
        }
    }
    auto t10=timer.stop();
    foreach(i,t;res)
        if (!(abs(t-res2[i])<1.0e-12)) {
            sout(collectAppender(delegate void(scope CharSink s){
                s("error10"); writeOut(s,i); s(" "); writeOut(s,t); s(" "); writeOut(s,res2[i]); s("\n");
            }));
        }
    
    res[]=0.0L;
    timer.start();
    for (int irep=nrep;irep!=0;--irep){
        NArray!(double,2) sc3=d2[0];
        double *resPtr=res.ptr;
        for (int i=0;i<ndim;i++){
            NArray!(double,2) d1i=d1[i];
            index_type optimalChunkSize_j=NArray!(double,2).defaultOptimalChunkSize;
            mixin(pLoopPtr(2,["d1i","sc3"],"*resPtr+=(*d1iPtr0)*(*sc3Ptr0);","j"));
            ++resPtr;
        }
    }
    auto t11=timer.stop();
    foreach(i,t;res)
        if (!(abs(t-res2[i])<1.0e-12)) {
            sout(collectAppender(delegate void(scope CharSink s){
                s("error11"); writeOut(s,i); s(" "); writeOut(s,t); s(" "); writeOut(s,res2[i]); s("\n");
            }));
        }
    
    res[]=0.0L;
    timer.start();
    for (int irep=nrep;irep!=0;--irep){
        long ta,tb;
        NArray!(double,2) sc3=d2[0];
        for (int i=0;i<ndim;i++){
            NArray!(double,2) d1i=d1[i];
            index_type optimalChunkSize_k=NArray!(double,2).defaultOptimalChunkSize;
            mixin(pLoopIdx(2,["d1i","sc3"],
                "res[i]+=(*d1iPtr0)*(*sc3Ptr0);","k"));
        }
    }
    auto t12=timer.stop();
    foreach(i,t;res)
        if (!(abs(t-res2[i])<1.0e-12)) {
            sout(collectAppender(delegate void(scope CharSink s){
                s("error12"); writeOut(s,i); s(" "); writeOut(s,t); s(" "); writeOut(s,res2[i]); s("\n");
            }));
        }


    // check removal of multiplication by compiler, ptr + fast striding
    res[]=0.0L;
    timer.start();
    for (int irep=nrep;irep!=0;--irep){
        size_t a1PtrL=cast(size_t)a1.m_data.ptr, a2PtrL=cast(size_t)a2.m_data.ptr;
        size_t resPtrL=cast(size_t)res.ptr;
        ptrdiff_t a1Strides0=a1.strides[0]*double.sizeof,
            a1Strides1=a1.strides[1]*double.sizeof,
            a1Strides2=a1.strides[2]*double.sizeof;
        ptrdiff_t a2Strides0=a2.strides[0]*double.sizeof,
            a2Strides1=a2.strides[1]*double.sizeof,
            a2Strides2=a2.strides[2]*double.sizeof;
        for (int i=0;i!=ndim;++i){
            size_t a22Ptr=a2PtrL;
            size_t a11Ptr=a1PtrL;
            for (int j=0;j!=ndim;++j){
                size_t a222Ptr=a22Ptr;
                size_t a111Ptr=a11Ptr;
                for (int k=0;k!=ndim;++k){
                    *(cast(double *)resPtrL)+=(*cast(double*)a111Ptr)*(*cast(double*)a222Ptr);
                    a111Ptr+=a1Strides2;
                    a222Ptr+=a2Strides2;
                }
                a11Ptr+=a1Strides1;
                a22Ptr+=a2Strides1;
            }
            a1PtrL+=a1Strides0;
            resPtrL+=double.sizeof;
        }
    }
    auto t13=timer.stop();
    foreach(i,t;res)
        if (!(abs(t-res2[i])<1.0e-12)) {
            sout(collectAppender(delegate void(scope CharSink s){
                s("error13"); writeOut(s,i); s(" "); writeOut(s,t); s(" "); writeOut(s,res2[i]); s("\n");
            }));
        }

    res[]=0.0L;
    timer.start();
    for (int irep=nrep;irep!=0;--irep){
        double *a1Ptr=a1.m_data.ptr, a2Ptr=a2.m_data.ptr;
        double *resPtr=res.ptr;
        index_type a1Strides0=a1.strides[0];
        index_type a1Strides1=a1.strides[1];
        index_type a1Strides2=a1.strides[2];
        index_type a2Strides0=a2.strides[0];
        index_type a2Strides1=a2.strides[1];
        index_type a2Strides2=a2.strides[2];
        for (int i=0;i!=ndim;++i){
            double * a22Ptr=a2Ptr;
            double * a11Ptr=a1Ptr;
            for (int j=0;j!=ndim;++j){
                double * a222Ptr=a22Ptr;
                double * a111Ptr=a11Ptr;
                for (int k=0;k!=ndim;++k){
                    *resPtr+=(*a111Ptr)*(*a222Ptr);
                    a111Ptr+=a1Strides2;
                    a222Ptr+=a2Strides2;
                }
                a11Ptr+=a1Strides1;
                a22Ptr+=a2Strides1;
            }
            a1Ptr+=a1Strides0;
            ++resPtr;
        }
    }
    auto t14=timer.stop();
    foreach(i,t;res)
        if (!(abs(t-res2[i])<1.0e-12)) {
            sout(collectAppender(delegate void(scope CharSink s){
                s("error14"); writeOut(s,i); s(" "); writeOut(s,t); s(" "); writeOut(s,res2[i]); s("\n");
            }));
        }

    sout("tref:")(tref)(" t1:")(t1)(" t2:")(t2)(" t3:")(t3)(" t4:")(t4)(" t5:")(t5)(" t6:")(t6)
        (" t7:")(t7)(" t8:")(t8)(" t9:")(t9)(" t10:")(t10)(" t11:")(t11)(" t12:")(t12)
        (" t13:")(t13)(" t14:")(t14)("\n");
    sout("tref:")(tref/tref)(" t1:")(t1/tref)(" t2:")(t2/tref)(" t3:")(t3/tref)(" t4:")(t4/tref)(" t5:")(t5/tref)(" t6:")(t6/tref)
        (" t7:")(t7/tref)(" t8:")(t8/tref)(" t9:")(t9/tref)(" t10:")(t10/tref)(" t11:")(t11/tref)(" t12:")(t12/tref)
        (" t13:")(t13/tref)(" t14:")(t14/tref)("\n");
}
sout("tref: contiguous pointer loop\n");
sout("t1: index loop on struct\n");
sout("t2: index loop on class (const strides)\n");
sout("t3: Multiarray index loop\n");
sout("t4: Multiarray flat iter\n");
sout("t5: Multiarray foreach + flat iter\n");
sout("t6: index op floated to outer loops on struct (smart compiler)\n");
sout("t7: index op floated to outer loops on class (smart compiler)\n");
sout("t8: index op floated to outer loops and removal of multiplication on struct (smart compiler)\n");
sout("t9: index loop on NArray\n");
sout("t10: loop+binaryOp on NArray\n");
sout("t11: loop+mixin pLoopPtr on NArray\n");
sout("t12: loop+mixin pLoopIdx on NArray\n");
sout("t13: index op floated to outer loops and removal of multiplication on struct without *T.sizeof(smart compiler)\n");
sout("t14: index op floated to outer loops and removal of multiplication on struct with (no native,w var )\n");

} 

void main(string [] argv) 
{
    tst();
}
