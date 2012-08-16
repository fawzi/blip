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
import blip.io.BasicIO;

/// inserts newHead before head, and returns the value at head when the insertion took place
T insertAt(T)(ref shared T head,T newHead){
    static if(is(typeof(newHead is null))){
        assert(!(newHead is null),"cannot add a null head");
    }
    memoryBarrier!(false,false,false,true)();
    return atomicOp(head,delegate T(T val){
        newHead.next=val;
        return newHead;
    });
}

/// removes one element from the top of list
T popFrom(T)(ref shared T list){
    return atomicOp(list,delegate T(T val){
	    if (val is null) {
		return null;
	    } else {
		/+ do we really need a barrier? only alpha needed a barrier for dependent loads... +/
		memoryBarrier!(true,false,false,false)();
		return val.next;
	    }
	});
}

/// very basic single linked list structure
struct SLinkT(T){
    T val;
    SLinkT* next;
    static SLinkT* opCall(T v,SLinkT* next=null){
        auto res=new SLinkT;
        res.val=v;
        res.next=next;
        return res;
    }
    void desc(void delegate(const(char)[])sink){
        sink("SLinkT@");
        writeOut(sink,cast(void*)this);
        sink("{");
        static if (is(typeof(writeOut(sink,val)))){
            sink("{ res:");
            writeOut(sink,res);
            sink(",");
        }
        sink(" next:@");
        writeOut(sink,cast(void*)next);
        sink(" }");
    }
}

