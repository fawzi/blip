module blip.test.ContainerTests;
import blip.io.Console;
import blip.rtest.RTest;
import blip.test.narray.NArraySupport;
import tango.math.random.Random;
import blip.container.GrowableArray;
import blip.container.BulkArray;

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
    barr.pLoop(s.val).opApply(delegate int(ref size_t i,ref T v){
        assert(arr1[i]==v,"BulkArray parallel index loop");
        return 0;
    });
    static if(is(typeof(T.init+T.init))&&false){
        foreach(ref v;barr.pLoop(s.val)){
            v=v+v;
        }
        foreach(i,v;barr.pLoop(s.val)){
            assert(arr1[i]+arr1[i]==v,"BulkArray parallel no index loop update");
        }
        if (arr1.length>0){
            barr[]=arr1[0];
            foreach(i,v;barr.pLoop(s.val)){
                v=v+arr1[i];
            }
            foreach(i,v;arr1){
                assert(barr[i]==v+v,"BulkArray indexing test");
            }
        }
    }
    
}

/// all container tests (a template to avoid compilation and instantiation unless really requested)
TestCollection containerTests()(TestCollection superColl=null){
    TestCollection coll=new TestCollection("container",__LINE__,__FILE__,superColl);
    autoInitTst.testNoFailF("BulkArrayLoop",&testLoop!(int),__LINE__,__FILE__,coll);
    return coll;
}
