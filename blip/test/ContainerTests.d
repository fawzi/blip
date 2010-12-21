/// tests for blip.container
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
module blip.test.ContainerTests;
import blip.io.Console;
import blip.io.BasicIO;
import blip.rtest.RTest;
import blip.test.narray.NArraySupport;
import blip.math.random.Random;
import blip.container.GrowableArray;
import blip.container.BulkArray;
import blip.sync.Atomic;
import blip.container.Pool;
import blip.container.Deque;
import blip.container.BatchedGrowableArray;

void testDeque(uint startPos,int[] arr1,int[] arr2){
    Deque!(int) d=new Deque!(int)(2);
    d.start=(startPos%d.baseArr.length);
    foreach(e;arr1){
        d.pushFront(e);
    }
    foreach(e;arr2){
        d.pushFront(e);
        if (e!=d.popFront) throw new Exception("error",__FILE__,__LINE__);
    }
    foreach(e;arr2){
        d.pushBack(e);
        if (e!=d.popBack) throw new Exception("error",__FILE__,__LINE__);
    }
    foreach(e;arr1){
        if (e!=d.popBack) throw new Exception("error",__FILE__,__LINE__);
    }
    int i;
    if (d.popFront(i)) throw new Exception("error",__FILE__,__LINE__);
    d.start=(startPos%d.baseArr.length);
    arr1~=arr2;
    foreach(e;arr1){
        d.pushFront(e);
    }
    foreach_reverse(e;arr1){
        if (e!=d.popFront) throw new Exception("error",__FILE__,__LINE__);
    }
    if (d.popBack(i)) throw new Exception("error",__FILE__,__LINE__);
    d.start=(startPos%d.baseArr.length);
    foreach(e;arr1){
        d.pushFront(e);
    }
    {
        bool popped=d.popBack(i,delegate bool(int i){ return (cast(uint)i)%2==0; });
        size_t pos=size_t.max;
        foreach(ii,e;arr1){
            if ((cast(uint)e)%2==0){
                pos=ii;
                break;
            }
        }
        if (popped){
            if (pos==size_t.max) throw new Exception("error",__FILE__,__LINE__);
            if (i!=arr1[pos]) throw new Exception("error",__FILE__,__LINE__);
        } else {
            if (pos!=size_t.max) throw new Exception("error",__FILE__,__LINE__);
        }
        size_t ii=0;
        while (ii<arr1.length){
            if (ii!=pos) {
                if (d.popBack()!=arr1[ii]) throw new Exception("error",__FILE__,__LINE__);
            }
            ++ii;
        }
        if (d.popBack(i)) throw new Exception("error",__FILE__,__LINE__);
        d.start=(startPos%d.baseArr.length);
    }
    foreach(e;arr1){
        d.pushFront(e);
    }
    {
        bool popped=d.popFront(i,delegate bool(int i){ return (cast(uint)i)%2==0; });
        size_t pos=size_t.max;
        foreach_reverse(ii,e;arr1){
            if ((cast(uint)e)%2==0){
                pos=ii;
                break;
            }
        }
        if (popped){
            if (pos==size_t.max) throw new Exception("error",__FILE__,__LINE__);
            if (i!=arr1[pos]) throw new Exception("error",__FILE__,__LINE__);
        } else {
            if (pos!=size_t.max) throw new Exception("error",__FILE__,__LINE__);
        }
        size_t ii=arr1.length;
        while (ii!=0){
            --ii;
            if (ii==pos) {
                if (ii==0) break;
            } else {
                if (d.popFront()!=arr1[ii]) throw new Exception("error",__FILE__,__LINE__);
            }
        }
        if (d.popFront(i)) throw new Exception("error",__FILE__,__LINE__);
        d.start=(startPos%d.baseArr.length);
    }
    foreach(e;arr1){
        d.pushFront(e);
    }
    {
        d.filterInPlace(delegate bool(int i){ return (cast(uint)i)%2==0; });
        size_t ii=0;
        while (ii<arr1.length){
            if ((cast(uint)arr1[ii])%2==0) {
                auto el=d.popBack();
                if (el!=arr1[ii]) throw new Exception(collectAppender(delegate void(CharSink s){
                    dumper(s)(el)(" vs ")(arr1[ii])("\n");
                }),__FILE__,__LINE__);
            }
            ++ii;
        }
        if (d.popFront(i)) throw new Exception("error",__FILE__,__LINE__);
        d.start=(startPos%d.baseArr.length);
    }
}

void testLoop(T)(T[] arr1,SizeLikeNumber!(3,1) s){
    BulkArray!(T) barr;
    barr=BulkArray!(T)(arr1.length);
    foreach(i,v;arr1){
        barr[i]=v;
    }
    foreach(i,v;arr1){
        if (barr[i]!=v) throw new Exception("BulkArray indexing test",__FILE__,__LINE__);
    }
    size_t ii=0;
    foreach(v;barr){
        if (arr1[ii]!=v) throw new Exception("BulkArray no index loop",__FILE__,__LINE__);
        ++ii;
    }
    foreach(i,v;barr){
        if (arr1[i]!=v) throw new Exception("BulkArray index loop",__FILE__,__LINE__);
    }
    foreach(i,v;barr.pLoop(s.val)){
        if (arr1[i]!=v) throw new Exception("BulkArray parallel index loop",__FILE__,__LINE__);
    }
    static if(is(typeof(T.init+T.init))){
        size_t count=0;
        foreach(ref v;barr.pLoop(s.val)){
            v=v+v;
            atomicAdd!(size_t)(count,1);
        }
        if (count!=arr1.length) throw new Exception("no index loop has wrong length",__FILE__,__LINE__);
        foreach(i,v;barr.pLoop(s.val)){
            if (arr1[i]+arr1[i]!=v) throw new Exception("BulkArray parallel no index loop update",__FILE__,__LINE__);
        }
        if (arr1.length>0){
            barr[]=arr1[0];
            foreach(i,ref v;barr.pLoop(s.val)){
                v=v+arr1[i];
            }
            foreach(i,v;arr1){
                if (barr[i]!=v+arr1[0]) throw new Exception("BulkArray indexing test",__FILE__,__LINE__);
            }
        }
    }
    
}

/// tests the Pool
void testPool(){
    void* base=cast(void*)100;
    auto iPool=new Pool!(void*)(delegate void*(PoolI!(void*)p){ return base-2; } );
    for (int i=0;i<iPool.maxEl+1;++i){
        iPool.giveBack(base+i);
    }
    for (int i=iPool.maxEl;i!=0;--i){
        auto el=iPool.getObj();
        if (el!=base+(i-1)){
            throw new Exception(collectAppender(delegate void(CharSink s){
                dumper(s)("unexpected value in pool 1:")(el-base)(" vs ")(i);
            }),__FILE__,__LINE__);
        }
    }
    {
        auto el=iPool.getObj();
        if (el!=base-2){
            throw new Exception(collectAppender(delegate void(CharSink s){
                dumper(s)("unexpected value in pool 2:")(el-base)(" vs ")(-2);
            }),__FILE__,__LINE__);
        }
    }
    for (int i=0;i<iPool.maxEl+1;++i){
        iPool.giveBack(base+i);
    }
    for (int i=iPool.maxEl;i!=iPool.maxEl/2;--i){
        auto el=iPool.getObj();
        if (el!=base+i-1){
            throw new Exception("unexpected value in pool 3",__FILE__,__LINE__);
        }
    }
    for (int i=0;i<iPool.maxEl+1;++i){
        iPool.giveBack(base+i);
    }
    for (int i=(iPool.maxEl+1)/2;i!=0;--i){
        auto el=iPool.getObj();
        if (el!=base+i-1){
            throw new Exception("unexpected value in pool 4",__FILE__,__LINE__);
        }
    }
    for (int i=iPool.maxEl/2;i!=0;--i){
        auto el=iPool.getObj();
        if (el!=base+i-1){
            throw new Exception("unexpected value in pool 5",__FILE__,__LINE__);
        }
    }
    {
        auto el=iPool.getObj();
        if (el!=base-2){
            throw new Exception(collectAppender(delegate void(CharSink s){
                dumper(s)("unexpected value in pool 6:")(el-base)(" vs ")(-2);
            }),__FILE__,__LINE__);
        }
    }
}

struct NextI{
    int i;
    NextI *next;
}

/// tests the PoolNext
void testPoolNext(){
    auto iPool=new PoolNext!(NextI*)(delegate NextI*(PoolI!(NextI*)p){
        auto el=new NextI; el.i=-2; return el;
    });
    enum{ maxEl=10 }
    for (int i=0;i<maxEl;++i){
        auto el=new NextI;
        el.i=i;
        iPool.giveBack(el);
    }
    for (int i=maxEl;i!=0;--i){
        auto el=iPool.getObj();
        if (el.i!=i-1){
            throw new Exception(collectAppender(delegate void(CharSink s){
                dumper(s)("unexpected value in pool 1:")(el.i)(" vs ")(i);
            }),__FILE__,__LINE__);
        } else if (i==1|| i==2){
            auto el2=el;
            iPool.giveBack(el2);
            auto el3=iPool.getObj();
            if (el3!is el){
                throw new Exception(collectAppender(delegate void(CharSink s){
                    dumper(s)("unexpected value when adding and getting back:")(el2.i)(" vs ")(el3.i);
                }),__FILE__,__LINE__);
            }
        }
        delete el;
    }
    {
        auto el=iPool.getObj();
        if (el.i!=-2){
            throw new Exception(collectAppender(delegate void(CharSink s){
                dumper(s)("unexpected value in pool 2:")(el.i)(" vs ")(-2);
            }),__FILE__,__LINE__);
        }
        delete el;
    }
}

void testBatchedGrowableArray(T=int,int bSize=2)(T[] arr,T[] arr2){
    auto bArr=new BatchedGrowableArray!(T,bSize)();
    foreach(el;arr){
        bArr.appendEl(el);
    }
    size_t nEl=0;
    foreach(el;bArr.view){
        if (arr[nEl]!=el) throw new Exception("error1",__FILE__,__LINE__);
        if (el!=bArr[nEl]) throw new Exception("error2",__FILE__,__LINE__);
        ++nEl;
    }
    if (nEl!=arr.length) throw new Exception("error3",__FILE__,__LINE__);
    bArr.appendArr(arr);
    nEl=0;
    foreach(i,el;bArr.view){
        if (arr[i%arr.length]!=el) {
            throw new Exception(collectAppender(delegate void(CharSink s){
                dumper(s)("error4  bArr[")(i)("]=")(el)("vs")(arr[i%arr.length]);
            }),__FILE__,__LINE__);
        }
        if (el!=bArr[i]) throw new Exception("error5",__FILE__,__LINE__);
        ++nEl;
    }
    if (nEl!=2*arr.length) throw new Exception("error6",__FILE__,__LINE__);
    if (arr2.length>0){
        auto newC=arr2[0]%(nEl*2);
        bArr.growCapacityTo(newC);
        bArr.appendArr(arr2);
        foreach(i,el;arr){
            if (bArr[i]!=el) throw new Exception("error7",__FILE__,__LINE__);
            if (bArr[i+arr.length]!=el) throw new Exception("error8",__FILE__,__LINE__);
        }
        foreach(i,el;arr2){
            if (bArr[i+nEl]!=el) throw new Exception("error9",__FILE__,__LINE__);
        }
        if (bArr.length!=nEl+arr2.length) throw new Exception("error10",__FILE__,__LINE__);
    }
    if (nEl>0){
        auto idx=(cast(size_t)arr[0])%bArr.length;
        bArr[idx]=arr[0]+1;
        if (bArr[idx]!=arr[0]+1) throw new Exception("error11",__FILE__,__LINE__);
    }
    
}

/// all container tests (a template to avoid compilation and instantiation unless really requested)
TestCollection containerTests()(TestCollection superColl=null){
    TestCollection coll=new TestCollection("container",__LINE__,__FILE__,superColl);
    autoInitTst.testNoFailF("Deque",&testDeque,__LINE__,__FILE__,coll);
    autoInitTst.testNoFailF("BulkArrayLoop",&testLoop!(int),__LINE__,__FILE__,coll);
    autoInitTst.testNoFailF("Pool!(void*,16)",&testPool,__LINE__,__FILE__,coll);
    autoInitTst.testNoFailF("PoolNext!(NextI)",&testPoolNext,__LINE__,__FILE__,coll);
    autoInitTst.testNoFailF("BatchedGrowableArray!(int,2)",&testBatchedGrowableArray!(int,2),__LINE__,__FILE__,coll);
    return coll;
}
