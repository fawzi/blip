/*******************************************************************************
        copyright:      Copyright (c) 2009. Fawzi Mohamed
        license:        Apache 2.0
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.BasicModels;
import blip.t.io.stream.Format:FormatOut;
import blip.t.util.Convert: formatFloat;

/// interface of an object that can describe itself
interface BasicObjectI{
    FormatOut desc(FormatOut s);
}

/// basic interface for objects that can be copied (shallowly)
interface DuplicableI{
    DuplicableI dup();
}

/// basic interface for objects that can be copied (deeply)
interface DeepDuplicableI{
    DeepDuplicableI deepdup();
}

/// basic copiable objects
interface CopiableObjectI : BasicObjectI,DuplicableI,DeepDuplicableI { }

/// object that can do a foreach loop
interface ForeachableI(T){
    static if (is(T U:U*)){
        /// loop without index, has to be implemented
        int opApply(int delegate(ref U x) dlg);
        /// loop with index, migh not be implemented (and throw)
        int opApply(int delegate(ref size_t i,ref U x) dlg);
    } else {
        /// loop without index, has to be implemented
        int opApply(int delegate(ref T x) dlg);
        /// loop with index, migh not be implemented (and throw)
        int opApply(int delegate(ref size_t i,ref T x) dlg);
    }
}

/// forward iterator interface, and foreach support.
/// the two things cannot be mixed (begin to iterate,
/// then continue with foreach is not allowed)
interface FIteratorI(T): ForeachableI!(T){
    /// goes to the next element
    T next();
    /// true if the iterator is at the end
    bool atEnd();
    /// might make opApply parallel (if the work amount is larger than
    /// optimalChunkSize, tries to subdivide it in chunks of that size)
    ForeachableI!(T) parallelLoop(size_t optimalChunkSize);
    /// might make opApply parallel.
    ForeachableI!(T) parallelLoop();
}

/// description of an object, safe even if null
FormatOut writeDesc(T,S...)(FormatOut s,T obj, S args){
    static if (is(typeof(obj is null))){
        if (obj is null) {
            return s("<")(T.stringof)(" *NULL*>").newline;
        }
    }
    static if(is(typeof(obj.desc(s,args)))){
        return obj.desc(s,args);
    } else static if (is(typeof(obj.toString()))){
        return s(obj.toString());
    }else{
        // static assert(nArgs!(S)==0,"did not find method desc(FormatOut,"~S.stringof~") in "~T.stringof);
        return s(obj);
    }
}


alias void delegate(void delegate(char[]))   OutWriter;
alias void delegate(void delegate(void[]))  BinWriter;
alias size_t delegate(char[],ref bool more)  OutReader;
alias size_t delegate(ubyte[],ref bool more) BinReader;
/// returns the operation that writes out the first argument, with the following as format
OutWriter outWriter(T,S...)(T v,S args){
    return delegate void(void delegate(char[]) sink){
        writeOut!(T,S)(sink,v,args);
    };
}

// this is to write out a value (for debugging and similar purposes)
void writeOut(T,S...)(void delegate(char[])sink,T v,S args){
    static if (is(T S:S[])){
        sink("[");
        foreach (i,el;v){
            if (i!=0) sink(",");
            writeOut(sink,el);
        }
        sink("]");
    } else static if (is(T K:T[K])){
        sink("[");
        int notFirst=false;
        foreach (k,t;v){
            if (notFirst) sink(",");
            notFirst=true;
            writeOut(sink,k);
            sink(":");
            writeOut(sink,t);
        }
        sink("]");
    } else static if (is(T==char)){
        sink((&v)[0..1]);
    } else static if(is(T==wchar)||is(T==dchar)){
        sink(cast(char[])[v]);
    } else static if (is(T==byte)||is(T==ubyte)||is(T==short)||is(T==ushort)||
        is(T==int)||is(T==uint)||is(T==long)||is(T==ulong))
    {
        if (v<0){
            char[22] res;
            int pos=res.length-1;
            while(v<0){
                auto r=v%10;
                res[pos]=cast(char)(cast(T)'0'-r);
                v=cast(T)(v/10);
                --pos;
            }
            res[pos]='-';
            sink(res[pos..$]);
        } else if (v==0){
            sink("0");
        } else {
            char[22] res;
            int pos=res.length-1;
            while(v>0){
                auto r=v%10;
                res[pos]=cast(char)(cast(T)'0'+r);
                v=cast(T)(v/10);
                --pos;
            }
            sink(res[pos+1..$]);
        }
    } else static if (is(T==bool)){
        if (v){
            sink("1");
        } else {
            sink("0");
        }
    } else static if (is(T==float)||is(T==double)||is(T==real)){
        char[40] buf;
        sink(formatFloat(buf,v));
    } else static if (is(T==ifloat)||is(T==idouble)||is(T==ireal)){
        char[40] buf;
        sink(formatFloat(buf,v.im));
        sink("*1i");
    } else static if (is(T==cfloat)||is(T==cdouble)||is(T==creal)){
        char[40] buf;
        auto res=formatFloat(buf,v.re);
        sink(res);
        res=formatFloat(buf,v.im);
        if (res[0]=='-'||res[0]=='+'){
            sink(res);
            sink("*1i");
        } else {
            sink("+");
            sink(res);
            sink("*1i");
        }
    } else {
        static if (is(typeof(v is null))){
            if (v is null) {
                sink("<");
                sink(T.stringof);
                sink(" *NULL*>");
                return;
            }
        }
        static if(is(typeof(v.desc(sink,args)))){
            v.desc(sink,args);
        } else static if (is(typeof(v.toString()))){
            sink(v.toString);
        }else{
            assert(0,"unsupported type in writeOut "~T.stringof);
        }
    }
}
