module blip.parallel.smp.DataFlowVar;
/+
// use atomic...
struct DataFlowVarBool{
    size_t val;
    TaskI[] waiting;
    
    DataFlowVar opAssign(bool newVal){
        if (val==2 || val==cast(int)newVal){
            val=newVal;
            //exeWaiting()
        }
    }
}

class DataFlowVarInt{
    long val;
    TaskI[] waiting;
    
}

class DataFlowVarNonNull(T){
    T val;
    static assert(T.init is null,"only objects that can be null can use this");
    TaskI[] waiting;
}

class DataFlowVarGeneric(T){
    
    int set;
    T val;
    TaskI[] waiting;
}
+/

/+class DataFlowVar(T:bool){
    int val;
    TaskI[] waiting;
    
    DataFlowVar opAssign(T newVal){
        if (_wasSet){
            static if (is(typeof(val is null))){
                if (val is null && newVal !is null){
                    return this;
                }
            }
            static if(is(typeof(val.unifyWith(newVal)))){
                val.unifyWith(newVal);
            } else {
                if (val){
                    val=0;
                }
            }
        }
        return this;
    }
    DataFlowVar opAssign(T val){
        
    }
}+/