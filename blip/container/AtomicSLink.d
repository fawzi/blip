/// atomic singly linked list ops
/// at the moment it works on any type that builds a liked list using a field called next
/// T is supposed to be a pointer to an element of the linked list.
///
/// Make this also as template with user given next field? would need mixins...
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
module blip.container.AtomicSLink;
import blip.sync.Atomic: atomicOp,memoryBarrier;

/// inserts newHead before head, and returns the value at head when the insertion took place
T insertAt(T)(ref T head,T newHead){
    static if(is(typeof(newHead is null))){
        assert(!(newHead is null),"cannot add a null head");
    }
    return atomicOp(head,delegate T(T val){
        newHead.next=val;
        memoryBarrier!(false,false,false,true)();
        return newHead;
    });
}

/// removes one element from the top of list
T popFrom(T)(ref T list){
    return atomicOp(list,delegate T(T val){ memoryBarrier!(true,false,false,false)(); return ((val is null)?null:val.next); /+ do we really need a barrier? only alpha needed a barrier for dependent loads... +/ });
}
