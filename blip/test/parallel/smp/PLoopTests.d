/// tests for the parallel foreach loops
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
module blip.test.parallel.smp.PLoopTests;
import blip.parallel.smp.PLoopHelpers;
import blip.sync.Atomic;
import blip.rtest.RTest;
import blip.container.GrowableArray;
import blip.io.BasicIO;
import tango.core.Array;
//import blip.io.Console;

void testPLoopArray(T)(T[] arr1,SizeLikeNumber!(3,1) blockSize){
    T[] copyArr=new T[](arr1.length);
    shared size_t nEl=0;
    foreach(i,ref e;pLoopArray(arr1,blockSize.val)){
        copyArr[i]=e;
        atomicAdd(nEl,cast(size_t)1);
    }
    if (nEl!=arr1.length) throw new Exception("wrong size",__FILE__,__LINE__);
    foreach(i,e;arr1){
        if (copyArr[i] !is e){
            throw new Exception(collectIAppender(delegate void(scope CharSink sink){
                dumper(sink)("parallel copy failed, generated ")(copyArr)(" which differs at ")(i);
            }),__FILE__,__LINE__);
        }
    }
    nEl=0;
    foreach(ref a;pLoopArray(copyArr,blockSize.val)){
        a=a+1;
        atomicAdd(nEl,cast(size_t)1);
    }
    if (nEl!=arr1.length) throw new Exception("wrong size",__FILE__,__LINE__);
    foreach(i,e;arr1){
        if (copyArr[i] !is e+1){
            throw new Exception(collectIAppender(delegate void(scope CharSink sink){
                dumper(sink)("pLoop modification failed, generated ")(copyArr)(" which differs from orig+1 at ")(i);
            }),__FILE__,__LINE__);
        }
    }
    delete copyArr;
}

struct ArrayIter(T){
    T[] arr;
    size_t ii;
    bool iter(ref T*el){
        if (ii<arr.length){
            el=&(arr[ii]);
            ++ii;
            return true;
        }
        return false;
    }
}
void testPLoopIter(T)(T[] arr1){
    T[] copyArr=new T[](arr1.length);
    shared size_t nEl=0;
    size_t ii=0;
    auto iter=new ArrayIter!(T);
    iter.arr=arr1;
    iter.ii=0;
    foreach(i,ref e;pLoopIter(&iter.iter)){
        copyArr[i]=e;
        atomicAdd(nEl,cast(size_t)1);
    }
    if (copyArr!=arr1) throw new Exception("copy failed!",__FILE__,__LINE__);
    if (nEl!=arr1.length) throw new Exception("wrong size",__FILE__,__LINE__);
    foreach(size_t i,T e;arr1){
        if (copyArr[i] !is e){
            throw new Exception(collectIAppender(delegate void(scope CharSink sink){
                dumper(sink)("pLoopIter copy failed, generated ")(copyArr)(" which differs at ")(i);
            }),__FILE__,__LINE__);
        }
    }
    nEl=0;
    ii=0;
    // scope delegates to work around dmd bug
    scope dlg1=delegate bool(ref T*el){
        if (ii<copyArr.length){
            el= &(copyArr[ii]);
            ++ii;
            return true;
        }
        return false;
    };
    foreach(ref T e;pLoopIter(dlg1)){
        e=e+1;
        atomicAdd(nEl,cast(size_t)1);
    }
    if (nEl!=arr1.length) throw new Exception("wrong size",__FILE__,__LINE__);
    foreach(i,e;arr1){
        if (copyArr[i] !is e+1){
            throw new Exception(collectIAppender(delegate void(scope CharSink sink){
                dumper(sink)("pLoopIter modification failed, generated ")(copyArr)(" which differs from orig+1 at ")(i);
            }),__FILE__,__LINE__);
        }
    }
    //--------------
    nEl=0;
    ii=0;
    scope dlg2=delegate bool(ref T el){
        if (ii<arr1.length){
            el= arr1[ii];
            ++ii;
            return true;
        }
        return false;
    };
    foreach(i,ref e;pLoopIter(dlg2)){
        copyArr[i]=e;
        atomicAdd(nEl,cast(size_t)1);
    }
    if (nEl!=arr1.length)throw new Exception("wrong length",__FILE__,__LINE__);
    if (copyArr!=arr1) throw new Exception("copy is different",__FILE__,__LINE__);
    foreach(i,e;arr1){
        if (copyArr[i] !is e){
            throw new Exception(collectIAppender(delegate void(scope CharSink sink){
                dumper(sink)("pIter2 copy failed, generated ")(copyArr)(" which differs at ")(i);
            }),__FILE__,__LINE__);
        }
    }
    nEl=0;
    ii=0;
    scope dlg3=delegate bool(ref T el){
        if (ii<copyArr.length){
            el=copyArr[ii];
            ++ii;
            return true;
        }
        return false;
    };
    foreach(e;pLoopIter(dlg3)){
        synchronized{
            auto idx=find(copyArr,e);
            if (idx==copyArr.length){
                throw new Exception(collectIAppender(delegate void(scope CharSink sink){
                    dumper(sink)("pLoopIter2 modification failed, generated ")(e)(" which which was not found in ")(copyArr);
                }),__FILE__,__LINE__);
            }
            copyArr[idx]=0;
        }
        atomicAdd(nEl,cast(size_t)1);
    }
    if (nEl!=arr1.length) throw new Exception("wrong length",__FILE__,__LINE__);
    foreach(i,e;copyArr){
        if (copyArr[i] != 0){
            throw new Exception(collectIAppender(delegate void(scope CharSink sink){
                dumper(sink)("pLoopIter2 modification failed, it was not fully nullified at ")(i)(":")(copyArr);
            }),__FILE__,__LINE__);
        }
    }
    delete copyArr;
}

void testLoopIRange(T,LoopType lType)(T from, SizeLikeNumber!() dim){
    T to=cast(T)(from+dim.val);
    if (to<from) {
        foreach(i;loopIRange!(lType,T)(from,to)){
            assert(0,"loopIRange iterated with to<=from");
        }
    } else {
        scope arr=new int[](dim.val);
        foreach (i;loopIRange!(lType,T)(from,to)){
            if (i<from || i>=to)
                assert(0,"out of bounds");
            if (atomicAdd(*cast(shared int *)&arr[i-from],1)!=0)
                throw new Exception(collectIAppender(delegate void(scope CharSink s){
                    dumper(s)("testLoopIRange double loop for ")(i);
                }));
        }
        foreach (i,v;arr){
            if (v!=1){
                throw new Exception(collectIAppender(delegate void(scope CharSink s){
                            dumper(s)("testLoopIRange missing loop for ")(from)("+")(i);
                }));
            }
        }
    }
}

/// all ploop tests (a template to avoid compilation and instantiation unless really requested)
TestCollection pLoopTests(TestCollection superColl=null){
    TestCollection coll=new TestCollection("PLoop",__LINE__,__FILE__,superColl);
    autoInitTst.testNoFailF("testPLoopArray",&testPLoopArray!(int),__LINE__,__FILE__,coll);
    autoInitTst.testNoFailF("testPLoopIter",&testPLoopIter!(int),__LINE__,__FILE__,coll);
    autoInitTst.testNoFailF("testSLoopIRange",&testLoopIRange!(int,LoopType.Sequential),__LINE__,__FILE__,coll);
    autoInitTst.testNoFailF("testPLoopIRange",&testLoopIRange!(int,LoopType.Parallel),__LINE__,__FILE__,coll);
    return coll;
}
