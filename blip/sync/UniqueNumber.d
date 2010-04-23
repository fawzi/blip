/**
 * Implements a fast global counters
 *
 * Copyright: Copyright (C) 2009 Fawzi Mohamed.  All rights reserved.
 * License:   BSD style: $(LICENSE)
 * Authors:   Fawzi Mohamed
 */
module blip.sync.UniqueNumber;
import blip.sync.Atomic;
import blip.t.core.sync.Mutex;

static if (LockVersion){
    /// fast unique number (that handles well the absence of atomic ops)
    struct UniqueNumber(T){
        T _val;
        Mutex m;
        
        /// creates a unique number object with the given initial value
        static UniqueNumber opCall(T firstVal=cast(T)0){
            UniqueNumber res;
            res._val=firstVal;
            res.m=new Mutex();
            return res;
        }
        
        /// returns the next unique value
        T next(){
            if (m is null){
                synchronized{
                    if (m is null){
                        m=new Mutex();
                    }
                }
            }
            T oldVal;
            synchronized(m){
                oldVal=_val;
                ++_val;
            }
            return oldVal;
        }
        /// grows the number to at least the given value
        void ensure(T minVal){
            synchronized(m){
                if (minVal>_val) _val=minVal;
            }
        }
        /// increases the stored number by the given number
        void opAddAssign(T v){
            synchronized(m){
                _val+=v;
            }
        }
    }
} else {
    /// fast unique number (that handles well the absence of atomic ops)
    struct UniqueNumber(T){
        T _val;
        /// creates a unique number object with the given initial value
        static UniqueNumber opCall(T firstVal=cast(T)0){
            UniqueNumber res;
            res._val=firstVal;
            return res;
        }

        /// returns the next unique value
        T next(){
            return nextValue(_val);
        }
        /// grows the number to at least the given value
        void ensure(T minVal){
            atomicOp(_val,delegate T(T oV){ if (oV<minVal) return minVal; return oV; });
        }
        /// increases the stored number by the given number
        void opAddAssign(T val){
            atomicAdd(_val,val);
        }
    }
}
