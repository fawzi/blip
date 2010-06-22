module blip.test.ContainerTests;
import blip.io.Console;
import blip.io.BasicIO;
import blip.rtest.RTest;
import blip.test.narray.NArraySupport;
import tango.math.random.Random;
import blip.container.GrowableArray;
import blip.container.BulkArray;
import blip.sync.Atomic;
import blip.container.Pool;

void testLoop(T)(T[] arr1,SizeLikeNumber!(3,1) s){
    BulkArray!(T) barr;
    barr=BulkArray!(T)(arr1.length);
    foreach(i,v;arr1){
        barr[i]=v;
    }
    foreach(i,v;arr1){
        assert(barr[i]==v,"BulkArray indexing test");
    }
    size_t ii=0;
    foreach(v;barr){
        assert(arr1[ii]==v,"BulkArray no index loop");
        ++ii;
    }
    foreach(i,v;barr){
        assert(arr1[i]==v,"BulkArray index loop");
    }
    foreach(i,v;barr.pLoop(s.val)){
        assert(arr1[i]==v,"BulkArray parallel index loop");
    }
    static if(is(typeof(T.init+T.init))){
        size_t count=0;
        foreach(ref v;barr.pLoop(s.val)){
            v=v+v;
            atomicAdd!(size_t)(count,1);
        }
        assert(count==arr1.length,"no index loop has wrong length");
        foreach(i,v;barr.pLoop(s.val)){
            assert(arr1[i]+arr1[i]==v,"BulkArray parallel no index loop update");
        }
        if (arr1.length>0){
            barr[]=arr1[0];
            foreach(i,ref v;barr.pLoop(s.val)){
                v=v+arr1[i];
            }
            foreach(i,v;arr1){
                assert(barr[i]==v+arr1[0],"BulkArray indexing test");
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

/// all container tests (a template to avoid compilation and instantiation unless really requested)
TestCollection containerTests()(TestCollection superColl=null){
    TestCollection coll=new TestCollection("container",__LINE__,__FILE__,superColl);
    autoInitTst.testNoFailF("BulkArrayLoop",&testLoop!(int),__LINE__,__FILE__,coll);
    autoInitTst.testNoFailF("Pool!(void*,16)",&testPool,__LINE__,__FILE__,coll);
    autoInitTst.testNoFailF("PoolNext!(NextI)",&testPoolNext,__LINE__,__FILE__,coll);
    return coll;
}
