/// tests for the smp queues
/// author: fawzi
//
// Copyright 2010 the blip developer group
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
module blip.test.parallel.smp.QueueTests;
import blip.parallel.smp.PriQueue;
import blip.sync.Atomic;
import blip.rtest.RTest;
import blip.container.GrowableArray;
import blip.io.BasicIO;
import tango.core.Array;
//import blip.io.Console;

void testPriQueue(size_t[] els){
    auto queue=new PriQueue!(void*)();
    sort(els);
    auto sortedEls=els.dup;
    sort(sortedEls,delegate bool(size_t e1,size_t e2){
        auto l1=cast(byte)(e1&0xFF);
        auto l2=cast(byte)(e2&0xFF);
        return l1>l2 || ((l1==l2) && e1<e2);
    });
    auto levels=new int[](els.length);
    foreach(i,e;els){
        levels[i]=cast(int)cast(byte)(e & 0xFF);
    }
    foreach(i,e;els){
        queue.insert(levels[i],cast(void*)e);
    }
    foreach(e;sortedEls){
        if ((cast(size_t)(queue.popNext(true)))!=e) throw new Exception("error",__FILE__,__LINE__);
    }
    foreach(i,e;els){
        queue.insert(levels[i],cast(void*)e);
    }
    if (els.length>0){
        auto popped=new bool[](els.length);
        popped[]=false;
        void markPopped(size_t el){
            size_t from=0;
            while(true){
                auto pos=find(els[from..$],el)+from;
                if (pos>=els.length)  throw new Exception("error",__FILE__,__LINE__);
                if (!popped[pos]){
                    popped[pos]=true;
                    break;
                }
                from=pos+1;
                if (pos>=els.length) throw new Exception("error",__FILE__,__LINE__);
            }
        }
        size_t last=cast(size_t)(queue.popNext(true));
        markPopped(last);
        for (size_t i=1;i<els.length;++i){
            auto nextP=cast(size_t)(queue.popNext(true));
            markPopped(nextP);
            auto l1=cast(byte)(last&0xFF);
            auto l2=cast(byte)(nextP&0xFF);
            if (!(l1>l2||(l1==l2 && last<nextP))) throw new Exception("error",__FILE__,__LINE__);
        }
        if (!(queue.nEntries==0)) throw new Exception("error",__FILE__,__LINE__);
        foreach(b;popped){
            if (!b) throw new Exception("error",__FILE__,__LINE__);
        }
    }
    foreach(i,e;els){
        queue.insert(levels[i],cast(void*)e);
    }
    size_t toSkip=sortedEls.length;
    foreach_reverse(i,e;sortedEls){
        if ((e&1)==0){
            toSkip=i;
            break;
        }
    }
    void* poppedEl;
    if (queue.popBack(poppedEl,delegate bool(void*v){
            return (((cast(size_t)v)&1)==0);
        }))
    {
        if (!(toSkip<sortedEls.length && (cast(size_t)poppedEl)==sortedEls[toSkip]))  throw new Exception("error",__FILE__,__LINE__);
    } else {
        if (!(toSkip==sortedEls.length)) throw new Exception("error",__FILE__,__LINE__);
    }
    foreach(i,e;sortedEls){
        if (i!=toSkip)
            if (!((cast(size_t)(queue.popNext(true)))==e)) throw new Exception("error",__FILE__,__LINE__);
    }
}

/// all queue tests
TestCollection queueTests(TestCollection superColl=null){
    TestCollection coll=new TestCollection("Queue",__LINE__,__FILE__,superColl);
    autoInitTst.testNoFailF("testPriQueue",&testPriQueue,__LINE__,__FILE__,coll);
    return coll;
}
