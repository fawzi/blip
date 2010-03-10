module blip.t.core.Traits;
public import tango.core.Traits;

int cmp(T,U)(T t,U u){
    static if (is(T:Object)&&is(U:Object)){
        return t.opCmp(u);
    } else static if(is(typeof(t.opCmp(u)))){
        return t.opCmp(u);
    } else static if(is(typeof(u.opCmp(t)))){
        return u.opCmp(t);
    } else static if (is(T==U)){
        return typeid(T).compare(&t,&u);
    } else {
        static assert(0,"cannot compare "~T.stringof~" with "~U.stringof);
    }
}