/// Implements a fast object used as a flag (to communicate state between threads)
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
module blip.sync.Flag;
import blip.sync.Atomic;
import blip.core.sync.Mutex;

static if (LockVersion){
    /// Flag that can be used to communicate that data is ready between threads
    /// (handles well the absence of atomic ops)
    struct Flag(T){
        T _val;
        Mutex m;
        
        /// creates a unique number object with the given initial value
        static Flag opCall(T firstVal){
            Flag res;
            res._val=firstVal;
            res.m=new Mutex();
            return res;
        }
        
        private Mutex m(){
            if (_m is null){
                synchronized{
                    if (_m is null){
                        _m=new Mutex();
                    }
                }
            }
            return _m;
        }
        
        static if (is(typeof(T.init+T.init))){
            /// adds to the flag
            T opAddAssign(T incV=cast(T)1){
                T oldVal;
                synchronized(m){
                    oldVal=_val;
                    _val+=incV;
                }
                return oldVal;
            }

            /// subtracts from the flag
            T opSubAssign(T incV=cast(T)1){
                T oldVal;
                synchronized(m){
                    oldVal=_val;
                    _val-=incV;
                }
                return oldVal;
            }
        }
        
        /// sets the value of the flag
        T opAssign(T val){
            T oldVal;
            synchronized(m){
                oldVal=_val;
                _val+=incV;
            }
            return oldVal;
        }

        /// gets the value of the flag
        T opCall(){
            T oldVal;
            synchronized(m){
                oldVal=_val;
            }
            return oldVal;
        }
        
        /// applies a pure function to the flag, returns the old value
        T opCall(T delegate(T)op){
            T oldVal;
            synchronized(m){
                oldVal=_val;
                _val=op(oldVal);
            }
            return oldVal;
        }
    }
} else {
    /// Flag that can be used to communicate that data is ready between threads
    /// (handles well the absence of atomic ops)
    struct Flag(T){
        T _val;
        
        /// creates a unique number object with the given initial value
        static Flag opCall(T firstVal){
            Flag res;
            res._val=firstVal;
            return res;
        }
        
        static if (is(typeof(T.init+T.init))){
            /// adds to the flag
            T opAddAssign(T incV=cast(T)1){
                return flagAdd(_val,incV);
            }
            /// subtracts from the flag
            T opSubAssign(T incV=cast(T)1){
                return flagAdd(_val,-incV);
            }
        }
        
        /// sets the value of the flag
        T opAssign(T newVal){
            return flagSet(_val,newVal);
        }

        /// gets the value of the flag
        T opCall(){
            return flagGet(_val);
        }
        
        /// applies a pure function to the flag, returns the old value
        T opCall(T delegate(T)op){
            return flagOp(_val,op);
        }
    }
}

