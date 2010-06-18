module blip.test.parallel.smp.PLoopTests;
import blip.parallel.smp.PLoopHelpers;
import blip.sync.Atomic;
import blip.rtest.RTest;
import blip.container.GrowableArray;
import blip.io.BasicIO;
//import blip.io.Console;

void testPLoopArray(T)(T[] arr1,SizeLikeNumber!(3,1) blockSize){
    T[] copyArr=new T[](arr1.length);
    size_t nEl=0;
    foreach(i,ref e;pLoopArray(arr1,blockSize.val)){
        copyArr[i]=e;
        atomicAdd(nEl,cast(size_t)1);
    }
    assert(nEl==arr1.length);
    foreach(i,e;arr1){
        if (copyArr[i] !is e){
            throw new Exception(collectAppender(delegate void(CharSink sink){
                dumper(sink)("parallel copy failed, generated ")(copyArr)(" which differs at ")(i);
            }),__FILE__,__LINE__);
        }
    }
    nEl=0;
    foreach(ref a;pLoopArray(copyArr,blockSize.val)){
        a=a+1;
        atomicAdd(nEl,cast(size_t)1);
    }
    assert(nEl==arr1.length);
    foreach(i,e;arr1){
        if (copyArr[i] !is e+1){
            throw new Exception(collectAppender(delegate void(CharSink sink){
                dumper(sink)("pLoop modification failed, generated ")(copyArr)(" which differs from orig+1 at ")(i);
            }),__FILE__,__LINE__);
        }
    }
    delete copyArr;
}

void testPLoopIter(T)(T[] arr1){
    T[] copyArr=new T[](arr1.length);
    size_t nEl=0;
    size_t ii=0;
    foreach(i,ref e;pLoopIter(delegate bool(ref T*el){
        if (ii<arr1.length){
            el=&(arr1[ii]);
            ++ii;
            return true;
        }
        return false;
    })){
        copyArr[i]=e;
        atomicAdd(nEl,cast(size_t)1);
    }
    assert(nEl==arr1.length);
    foreach(i,e;arr1){
        if (copyArr[i] !is e){
            throw new Exception(collectAppender(delegate void(CharSink sink){
                dumper(sink)("pLoopIter copy failed, generated ")(copyArr)(" which differs at ")(i);
            }),__FILE__,__LINE__);
        }
    }
    nEl=0;
    ii=0;
    foreach(ref e;pLoopIter(delegate bool(ref T*el){
        if (ii<copyArr.length){
            el= &(copyArr[ii]);
            ++ii;
            return true;
        }
        return false;
    })){
        e=e+1;
        atomicAdd(nEl,cast(size_t)1);
    }
    assert(nEl==arr1.length);
    foreach(i,e;arr1){
        if (copyArr[i] !is e+1){
            throw new Exception(collectAppender(delegate void(CharSink sink){
                dumper(sink)("pLoopIter modification failed, generated ")(copyArr)(" which differs from orig+1 at ")(i);
            }),__FILE__,__LINE__);
        }
    }
    //--------------
    nEl=0;
    ii=0;
    foreach(i,ref e;pLoopIter(delegate bool(ref T el){
        if (ii<arr1.length){
            el=arr1[ii];
            ++ii;
            return true;
        }
        return false;
    })){
        copyArr[i]=e;
        atomicAdd(nEl,cast(size_t)1);
    }
    assert(nEl==arr1.length);
    foreach(i,e;arr1){
        if (copyArr[i] !is e){
            throw new Exception(collectAppender(delegate void(CharSink sink){
                dumper(sink)("pIter2 copy failed, generated ")(copyArr)(" which differs at ")(i);
            }),__FILE__,__LINE__);
        }
    }
    nEl=0;
    ii=0;
    foreach(e;pLoopIter(delegate bool(ref T el){
        if (ii<copyArr.length){
            el=copyArr[ii];
            ++ii;
            return true;
        }
        return false;
    })){
        synchronized{
            auto idx=find(copyArr,e);
            if (idx==copyArr.length){
                throw new Exception(collectAppender(delegate void(CharSink sink){
                    dumper(sink)("pLoopIter2 modification failed, generated ")(e)(" which which was not found in ")(copyArr);
                }),__FILE__,__LINE__);
            }
            copyArr[idx]=0;
        }
        atomicAdd(nEl,cast(size_t)1);
    }
    assert(nEl==arr1.length);
    foreach(i,e;copyArr){
        if (copyArr[i] != 0){
            throw new Exception(collectAppender(delegate void(CharSink sink){
                dumper(sink)("pLoopIter2 modification failed, it was not fully nullified at ")(i)(":")(copyArr);
            }),__FILE__,__LINE__);
        }
    }
    delete copyArr;
}

/// all ploop tests (a template to avoid compilation and instantiation unless really requested)
TestCollection pLoopTests(TestCollection superColl=null){
    TestCollection coll=new TestCollection("PLoop",__LINE__,__FILE__,superColl);
    autoInitTst.testNoFailF("testPLoopArray",&testPLoopArray!(int),__LINE__,__FILE__,coll);
    autoInitTst.testNoFailF("testPLoopIter",&testPLoopIter!(int),__LINE__,__FILE__,coll);
    return coll;
}
