module blip.test.parallel.ParallelTests;
import blip.test.parallel.smp.PLoopTests:pLoopTests;
import blip.rtest.RTest;

/// all parallel tests (a template to avoid compilation and instantiation unless really requested)
TestCollection parallelTests()(TestCollection superColl=null){
    TestCollection coll=new TestCollection("parallel",__LINE__,__FILE__,superColl);
    pLoopTests(coll);
    return coll;
}
