/// Basic mixin to add simple reference counting to a class
///
/// author: Fawzi
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
module blip.util.RefCount;
public import blip.sync.Atomic;

/// adds reference counting, calls release0() (that should be implemented by the user)
/// when the reference count becomes 0
template RefCountMixin(){
    size_t refCount=1;
    
    void retain(){
        if (atomicAdd(refCount,cast(size_t)1)==0){
            throw new Exception("refCount was 0 in retain",__FILE__,__LINE__);
        }
    }
    void release(){
        size_t oldVal=atomicAdd(refCount,-cast(size_t)1);
        if (oldVal==0){
            throw new Exception("refCount was 0 in release",__FILE__,__LINE__);
        }
        if (oldVal==1){
            release0();
        }
    }
}
