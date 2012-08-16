/// thread local storage.
///
/// Very often TLS is not the correct answer, try to avoid it if possible, either by
/// having storage that maps to your parallelization approach (storing things for example in a task
/// object,...), or using a Cache object for pools.
///
/// This tries to give the most efficient thread local storage available for a type T
/// It might use costly resources, so use it sparingly
/// At the moment it is used for default Cache and the actual task.
///
/// For portability: no deallocator, no removal of variable, this is effectively a *global* tls variable
/// declared in such a way that tls storage might be used with little overhead if the compiler supports it.
/// supports only types smaller or equal to a pointer
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
module blip.parallel.smp.Tls;
import blip.core.Thread;
import blip.Comp;

version(Win32){
    import tango.sys.win32.UserGdi;
    const DWORD TLS_OUT_OF_INDEXES  = 0xFFFFFFFF;
}
version(Posix){
    extern(C) {
        alias void function(void*) TlsDeallocator;
    }
    import tango.stdc.posix.pthread;
}

/// adds a thread local variable that can be accessed with varName(), and set with varName(x)
string tlsMixin(string type,string varName){
    version(TlsSupport){
        return `
        static __thread `~type~` _`~varName~`;
        final `~type~` `~varName~`(){
            return _`~varName~`;
        }
        final void `~varName~`(`~type~` nV){
            _`~varName~`=nV;
        }
        `;
    } else {
        return `
        __gshared static TlsClass!(`~type~`) _`~varName~`;
        static this(){
            _`~varName~`=new TlsClass!(`~type~`)();
        }
        final `~type~` `~varName~`(){
            return _`~varName~`.val;
        }
        final void `~varName~`(`~type~` nV){
            _`~varName~`.val=nV;
        }
        `;
    }
}

/// a class that implements a Tls storage of type T in its attribute val
class TlsClass(T){
    union ElStorage{
        T val;
        void* ptr;
    }
    void*[long] gcVals;
    
    version(Posix){
        pthread_key_t key;
    
        /// this needs to be called once by one thread before using the variable
        /// (probably you want to call this from a static this)
        this(){
            auto err=pthread_key_create(&key,cast(TlsDeallocator)null);
            if (err!=0){
                throw new Exception("pthread_key_create",__FILE__,__LINE__);
            }
        }
    
        T val(){
            ElStorage res;
            res.ptr=pthread_getspecific(key);
            return res.val;
        }
    
        void val(T newV){
            ElStorage res;
            res.val=newV;
            synchronized(this){ // kills update speed and auto collection of ended threads :(
                auto pid=Thread.getThis().m_addr;
                assert((cast(typeof(pid))cast(long)pid)==pid,"thread addr cannot be stored in long...");
                gcVals[cast(long)pid]=res.ptr;
            }
            auto err=pthread_setspecific(key,res.ptr);
            if (err!=0){
                throw new Exception("error in pthread_setspecific",__FILE__,__LINE__);
            }
        }
    } else version (Win32){
        DWORD key;
        
        /// this needs to be called once by one thread before using the variable
        /// (probably you want to call this from a static this)
        this(){
            key=TlsAlloc();
            if (key==TLS_OUT_OF_INDEXES){
                throw new Exception("TlsAlloc",__FILE__,__LINE__);
            }
        }
    
        T val(){
            ElStorage res;
            res.ptr=TlsGetValue(key);
            return res.val;
        }
    
        void val(T newV){
            ElStorage res;
            res.val=newV;
            synchronized(this){ // kills update speed and auto collection of ended threads, store in thread m_local?
                auto pid=Thread.getThis().m_addr;
                assert((cast(typeof(pid))cast(long)pid)==pid,"thread addr cannot be stored in long...");
                gcVals[cast(long)pid]=res.ptr;
            }
            auto err=TlsSetValue(key,res.ptr);
            if (err!=0){
                throw new Exception("error in TlsSetValue",__FILE__,__LINE__);
            }
        }
    } else {
        static assert(0,"TlsClass not implemented");
    }
}

