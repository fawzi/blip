module blip.test.BlipTests;
import blip.test.narray.NArrayTests:narrayTests;
import blip.io.Console;
import blip.rtest.RTest;
import blip.test.ContainerTests;
import blip.test.parallel.ParallelTests:parallelTests;

TestCollection blipTests()(TestCollection superColl=null){
    TestCollection coll=new TestCollection("blip",__LINE__,__FILE__,superColl);
    
    // narrayTests!()(coll); // deactivate this expensive test for now...
    containerTests!()(coll);
    parallelTests!()(coll);
    
    return coll;
}
