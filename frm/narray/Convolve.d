module frm.narray.Convolve;
import frm.narray.BasicTypes;
import frm.narray.BasicOps;
import frm.TemplateFu;
/+ --------- convolution --------- +/
// convolution base in 2d
char[] convolveBase(char[] indent,bool istream_m=true, bool istream_z=true, bool istream_p=true,
        int jshift=0, int jmin=0, int jmax=3, int imin=0,int imax=3){
    char [] res="".dup;
    if (istream_m){
        res~=indent;
        res~="res[i-1,j]+=";
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
        res~="res[i,j]+=";
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
        res~="res[i+1,j]+=";
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

// inner convolution loop (for 2d convolve)
char[] convolveJLoop(char[] indent,int jrest=0,bool istream_m=true, bool istream_z=true, bool istream_p=true,int imin=0,int imax=3){
    char [] res="".dup;
    if (jrest<0){
        // no loop (few elements)
        for (int i=imin;i<imax;++i){
            for (int j=0;j<-jrest;++j){
                res~=indent;
                res~="res[i+("~ctfe_i2a(i)~"),jmin+("~ctfe_i2a(j)~")]+=";
                bool shouldAdd=false;
                for (int diff=-1;diff<2;++diff){
                    if (0<=j+diff && j+diff<-jrest){
                        if (shouldAdd) res~="+";
                        res~="c"~ctfe_i2a(i)~ctfe_i2a(1+diff)~
                            "*a[i+("~ctfe_i2a(i-1)~"),jmin+("~ctfe_i2a(j+diff)~")]";
                        shouldAdd=true;
                    }
                }
                res~="a"~ctfe_i2a(i)~ctfe_i2a(j)~"=a[i+("~ctfe_i2a(i-1)~"),j+("~ctfe_i2a(j)~")];\n";
            } 
        }
    } else {
        // loop (>3 elements)
        res~=indent;
        res~="index_type j=jmin;\n";
        for (int i=imin;i<imax;++i){
            for (int j=0;j<2;++j){
                res~=indent;
                res~="a"~ctfe_i2a(i)~ctfe_i2a(j)~"=a[i+("~ctfe_i2a(i-1)~"),j+("~ctfe_i2a(j)~")];\n";
            } 
        }
        // set partial border
        res~=convolveBase(indent,istream_m,istream_z,istream_p,2,1,3,imin,imax);
        res~=indent;
        res~="while(j<jmax){\n";
        char[] indent2=indent~"    ";
        for (int jshift=0;jshift<3;++jshift){
            res~=indent2~"++j;\n";
            for (int i=imin;i<imax;++i){
                res~=indent2~"a"~ctfe_i2a(i)~ctfe_i2a(jshift)~"=a[i+("~ctfe_i2a(i-1)~"),j+1];\n";
            }
            res~=convolveBase(indent2,istream_m,istream_z,istream_p,jshift,0,3,imin,imax);
        }
        res~=indent~"}\n";
        // jrest=(maxj-1)%3
        for (int jshift=0;jshift<jrest;++jshift){
            res~=indent~"++j;\n";
            for (int i=imin;i<imax;++i){
                res~=indent~"a"~ctfe_i2a(i)~ctfe_i2a(jshift)~"=a[i+("~ctfe_i2a(i-1)~"),j+1];\n";
            }
            res~=convolveBase(indent,istream_m,istream_z,istream_p,jshift,0,3,imin,imax);
        }
        // set partial border
        res~=indent~"++j;\n";
        res~=convolveBase(indent,istream_m,istream_z,istream_p,jrest,0,2,imin,imax);
        res~=indent~"assert(j==maxj);\n";
    }
    return res;
}

// outer loop for 2d convolve
char[] convolveILoop(char[]indent,int jrest,int irest){
    char [] res="".dup;
    if (irest<0){
        if (irest==-1) {
            res~=indent~"index_type i=imin;\n";
            res~=convolveJLoop(indent,jrest,false,true,false,1,2);
        } else if (irest==-2) {
            res~=indent~"index_type i=imin;\n";
            res~=convolveJLoop(indent,jrest,false,true,true,1,3);
        } else {
            assert(0,"explicit i loops with more than two streams not implemented");
        }
    } else {
        //first load
        res~=indent~"index_type i=imin;\n";
        res~=convolveJLoop(indent,jrest,false,false,true,1,3);
        // bulk calc
        res~=indent~"while (i<imax){\n";
        char[] indent2=indent~"    ";
        res~=indent2~"++i;\n";
        res~=convolveJLoop(indent2,jrest,true,true,true,0,3);
        res~=indent2~"++i;\n";
        res~=indent~"}\n";
        // final set
        res~=indent~"if (maxi>i){\n";
        res~=indent2~"++i;\n";
        res~=convolveJLoop(indent2,jrest,true,true,false,0,2);
        res~=indent~"}\n";
        res~=indent~"assert(maxi==i);\n";
    }
    return res;
}

/// operations to do before convolveIJ
const char[] preConvolveIJSetup=`
    index_type jmax=maxj-4;
    int jrest=(maxj-1-minj)%3;
    index_type imax=maxi-2;
    int ires=0;
    if(jmax<=jmin)
        jrest=-jrest;
    if (imax<=imin)
        ires=mini-maxi;
    int switchTag=10*ires+jrest;
    if (maxi<=mini || maxj<=minj){
        switchTag=-1000;
    }
    `;

/// 2d convolution with nearest neighbors
char[] convolveIJ(char[] indent){
    char[] res="".dup;
    res~=indent~"switch (switchTag)\n";
    char[] indent2=indent~"    ";
    foreach (ires;[-2,-1,0]){
        foreach (jres;[-4,-3,-2,-1,0,1,2]){
            res~=indent~"case "~ctfe_i2a(10*ires+jres)~":\n";
            res~=indent~"{\n";
            res~=convolveILoop(indent2,jres,ires);
            res~=indent~"}\n";
            res~=indent~"break;\n";
        }
    }
    res~=indent~"case(-1000) break;\n";
    res~=indent2~"default: assert(0);\n";
    res~=indent~"}\n";
    return res;
}
//pragma(msg,"----------");
//pragma(msg,convolveIJ("  "));
//pragma(msg,"==========");

/+ --------------------------------------------- +/
