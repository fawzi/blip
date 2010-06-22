module blip.t.math.Math;
public import tango.math.Math;

/// integer power
T powI(T)(T v,int exponent){
    T myV=v;
    T res=1;
    if (exponent<0){
        myV=1.0/v;
        exponent=-(exponent+1);
    }
    T pAtt=myV;
    while(exponent>0){
        if ((exponent&1)!=0) pAtt+=pAtt;
        exponent>>=1;
        if (exponent==0) break;
        pAtt*=pAtt;
    }
}
/// square of the argument
T pow2(T)(T v){
    return v*v;
}
