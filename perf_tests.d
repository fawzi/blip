module perf_tests;
import tango.io.Stdout;
import murray.multiarray: ndarray,ones,zeros;
import tango.core.Exception;
import tango.time.StopWatch;
import tango.math.Math;
import frm.narray.NArray;

alias ndarray!(double) array;
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

void main(char [][] argv) 
{
    int ndim=250;
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
    
    double[] res2=new double[ndim];
    res2[]=0.0L;
    timer.start;
    double *p1,p2,p2End,p3,p3End;
    p2End=a2.m_data.ptr+ndim*ndim;
    p3=res2.ptr;
    p3End=p3+ndim;
    p1=a1.m_data.ptr;
    for (;p3!=p3End;++p3){
        for (p2=a2.m_data.ptr;p2!=p2End;++p2,++p1)
            *p3+=(*p1)*(*p2);
    }
    auto tref=timer.stop();

    double[] res=new double[ndim];
    res[]=0.0L;
    timer.start();
    for (int i=0;i!=ndim;++i)
    for (int j=0;j!=ndim;++j)
    for (int k=0;k!=ndim;++k){
        res[i]+=a1[i,j,k]*a2[0,j,k];
    }
    auto t1=timer.stop();
    
    foreach(i,t;res)
        if (abs(t-res2[i])>1.e-13) Stdout.format("error1 {} {} {}",i,t,res2[i]).newline;
        
    res[]=0.0L;
    timer.start();
    for (int i=0;i!=ndim;++i)
    for (int j=0;j!=ndim;++j)
    for (int k=0;k!=ndim;++k){
        res[i]+=b1[i,j,k]*b2[0,j,k];
    }
    auto t2=timer.stop();
    foreach(i,t;res)
        if (abs(t-res2[i])>1.e-13) Stdout.format("error2 {} {} {}",i,t,res2[i]).newline;
    
    array c1=ones!(double)([ndim,ndim,ndim]);
    array c2=ones!(double)([1,ndim,ndim]);
    res[]=0.0L;
    timer.start();
    for (int i=0;i!=ndim;++i)
    for (int j=0;j!=ndim;++j)
    for (int k=0;k!=ndim;++k){
        res[i]+=c1.get([i,j,k])*c2.get([0,j,k]);
    }
    auto t3=timer.stop();
    foreach(i,t;res)
        if (abs(t-res2[i])>1.e-13) Stdout.format("error3 {} {} {}",i,t,res2[i]).newline;
    
    res[]=0.0L;
    timer.start();
    auto i1=c1.flat_iter;
    for (int i=0;i!=ndim;++i){
        for (auto i2=c2.flat_iter;!i2.end;++i1,++i2){
            res[i]+=i1.value*i2.value;
        }
    }
    auto t4=timer.stop();
    foreach(i,t;res)
        if (abs(t-res2[i])>1.e-13) Stdout.format("error4 {} {} {}",i,t,res2[i]).newline;
    
    res[]=0.0L;
    timer.start();
    foreach (i,ii;c1.iter){
        i1=ii.flat_iter;
        auto i2=c2.flat_iter;
        for (;!i2.end;++i1,++i2){
            res[i]+=i1.value*i2.value;
        }
        ++i;
    }
    auto t5=timer.stop();
    foreach(i,t;res)
        if (abs(t-res2[i])>1.e-13) Stdout.format("error5 {} {} {}",i,t,res2[i]).newline;
    
    // smart compiler
    res[]=0.0L;
    timer.start();
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
    auto t6=timer.stop();
    foreach(i,t;res)
        if (abs(t-res2[i])>1.e-13) Stdout.format("error6 {} {} {}",i,t,res2[i]).newline;
    
    res[]=0.0L;
    timer.start();
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
    auto t7=timer.stop();
    foreach(i,t;res)
        if (abs(t-res2[i])>1.e-13) Stdout.format("error7 {} {} {}",i,t,res2[i]).newline;

    // check removal of multiplication by compiler
    res[]=0.0L;
    timer.start();
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
    auto t8=timer.stop();
    foreach(i,t;res)
        if (abs(t-res2[i])>1.e-13) Stdout.format("error8 {} {} {}",i,t,res2[i]).newline;
    
    res[]=0.0L;
    alias NArray!(double,3) NArr;
    NArr d1=NArr.ones([ndim,ndim,ndim]),d2=NArr.ones([1,ndim,ndim]);
    Stdout("d1=")(&d1.desc).newline;
    timer.start();
    for (int i=0;i<ndim;i++)
    for (int j=0;j<ndim;j++)
    for (int k=0;k<ndim;k++){
        res[i]+=d1[i,j,k]*d2[0,j,k];
    }
    auto t9=timer.stop();
    foreach(i,t;res)
        if (abs(t-res2[i])>1.e-13) Stdout.format("error9 {} {} {}",i,t,res2[i]).newline;
    
    res[]=0.0L;
    timer.start();
    auto sc2=d2[0];
    int iii;
    void sumRes(double a,double b){ res[iii]+=a*b; }
    for (iii=0;iii<ndim;iii++){
        binaryOp!(sumRes,2,double,double)(d1[iii],sc2);
    }
    auto t10=timer.stop();
    foreach(i,t;res)
        if (abs(t-res2[i])>1.e-13) Stdout.format("error10 {} {} {}",i,t,res2[i]).newline;
    
    res[]=0.0L;
    timer.start();
    NArray!(double,2) sc3=d2[0];
    for (int i=0;i<ndim;i++){
        NArray!(double,2) d1i=d1[i];
        mixin(pLoopPtr(2,["d1i","sc3"],[],"res[i]+=(*d1iPtr0)*(*sc3Ptr0);","j"));
    }
    auto t11=timer.stop();
    foreach(i,t;res)
        if (abs(t-res2[i])>1.e-13) Stdout.format("error11 {} {} {}",i,t,res2[i]).newline;
    
    res[]=0.0L;
    timer.start();
    //NArray!(double,2) sc3=d2[0];
    for (int i=0;i<ndim;i++){
        NArray!(double,2) d1i=d1[i];
        mixin(pLoopIdx(2,["d1i","sc3"],[],
            "res[i]+=(*(d1iBasePtr+d1iIdx0))*(*(sc3BasePtr+sc3Idx0));","k"));
    }
    auto t12=timer.stop();
    foreach(i,t;res)
        if (abs(t-res2[i])>1.e-13) Stdout.format("error11 {} {} {}",i,t,res2[i]).newline;

    Stdout("tref: contiguous pointer loop").newline;
    Stdout("t1: index loop on struct").newline;
    Stdout("t2: index loop on class (const strides)").newline;
    Stdout("t3: Multiarray index loop").newline;
    Stdout("t4: Multiarray flat iter").newline;
    Stdout("t5: Multiarray foreach + flat iter").newline;
    Stdout("t6: index op floated to outer loops on struct (smart compiler)").newline;
    Stdout("t7: index op floated to outer loops on class (smart compiler)").newline;
    Stdout("t8: index op floated to outer loops and removal of multiplication on struct (smart compiler)").newline;
    Stdout("t9: index loop on NArray").newline;
    Stdout("t10: loop+binaryOp on NArray").newline;
    Stdout("t11: loop+mixin pLoopPtr on NArray").newline;
    Stdout("t12: loop+mixin pLoopIdx on NArray").newline;
    Stdout.format("tref: {} t1:{} t2:{} t3:{} t4:{} t5:{} t6:{} t7:{} t8:{} t9:{} t10:{}, t11:{} t12:{}",tref,t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12).newline;
    Stdout.format("tref: {} t1:{} t2:{} t3:{} t4:{} t5:{} t6:{} t7:{} t8:{} t9:{} t10:{}, t11:{}, t12:{}",tref/tref,t1/tref,t2/tref,t3/tref,t4/tref,t5/tref,t6/tref,t7/tref,t8/tref,
    t9/tref,t10/tref,t11/tref,t12/tref).newline;
} 
