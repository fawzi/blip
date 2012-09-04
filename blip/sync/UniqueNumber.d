/// Implements a fast global (to a process) counters
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
module blip.sync.UniqueNumber;
import blip.sync.Atomic;
import blip.core.sync.Mutex;
import blip.io.BasicIO;

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
        void desc(scope CharSink s){
            T mVal;
            synchronized(m){
                mVal=_val;
            }
            dumper(s)("<UniqueNumber@")(cast(void*)&_val)(" nextValue:")(mVal)(">");
        }
    }
} else {
    /// fast unique number (that handles well the absence of atomic ops)
    struct UniqueNumber(T){
        shared T _val;
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
        void desc(scope CharSink s){
            auto mVal=_val;
            dumper(s)("<UniqueNumber@")(cast(void*)&_val)(" nextValue:")(mVal)(">");
        }
    }
}
