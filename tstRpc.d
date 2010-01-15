module tstRpc;
import blip.io.Console;
version(NoTrace){} else { import tango.core.stacktrace.TraceExceptions; }

class A{
    static A globalA;
    void b(double y){
        return 5*cast(int)y;
    }
    this(){}
    
    alias typeof(this) proxiedType;
    static class Proxy{
        union Closure{
            struct BClosure{
                int i;
                Closure *top;
                Proxy context;
                void end(){
                    context.closure=top;
                }
            }
            BClosure b;
        }
        Closure * closure;
        this(){}
        static if (is(typeof(proxiedType.b) bReturn==return)){
            static if (is(typeof(proxiedType.b) bArgs==function)){
                bReturn b(bArgs args){
                    bArgs res;
                    return globalA.b(args);
                }
            } else {
                static assert(0,"error2 "~typeof(&b).stringof);
            }
        } else {
            static assert(0,"error1");
        }
    }
}

template X(T,int n){
    class Pippo{
        T v1;
        T[n] v2;
        this(){}
    }
}
void main(){
    A.globalA=new A();
    A.Proxy o=new A.Proxy();
    o.b(4.3);
    sout("\n");
    auto a=X!(int,3).Pippo.classinfo;
    auto b=X!(int,4).Pippo.classinfo;
    writeOut(sout,a); sout("\n");
    writeOut(sout,b); sout("\n");
    writeOut(sout,cast(void*)ClassInfo.find(a.toString())); sout("\n");
    writeOut(sout,cast(void*)ClassInfo.find(b.toString())); sout("\n");
    writeOut(sout,cast(void*)a); sout("\n");
    writeOut(sout,cast(void*)b); sout("\n");
}