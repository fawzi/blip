module test;
import frm.random.Random;
import frm.random.engines.CMWC;
import tango.io.Stdout;


class TC{
    int line;
    char[] file;
    void delegate() op;
    this(void delegate() opV){
        op=opV;
    }
    static TC opCall(void delegate() opV){
        return new TC(opV);
    }
}

TC mkOp(){
    return TC((){ Stdout("ciao").newline; });
}

void main(){
    TC rr=mkOp;
    rr.op();
    CMWC!() c;
    Stdout(c.next()).newline;
    int i,j;
    float t;
    real[5] kk;
    real[] k=kk[];
    rand(i)(j)(k)(t);
    Stdout("pippo")(i)(" ")(j)(" ")(k)(" ")(t).newline;
/*    NormalSource!(typeof(rand),float)  normalFloat=new NormalSource!(typeof(rand),float)(rand);
    normalFloat(i)(j)(k)(t);
    Stdout("pippo2")(i)(" ")(j)(" ")(k)(" ")(t).newline;
    ExpSource!(typeof(rand),float)  expFloat=new ExpSource!(typeof(rand),float)(rand);
    expFloat(i)(j)(k)(t);*/
    Stdout("pippo3")(i)(" ")(j)(" ")(k)(" ")(t).newline;
    auto r=new Random();
    r.uniform!(uint)();
}