/// quick test file
module testRTest;
import tango.io.Stdout;
import blip.rtest.RTest;
import blip.NullStream;
import blip.t.io.stream.Format:FormatOut;
import blip.TemplateFu;
import blip.parallel.smp.WorkManager;
import tango.util.log.Config;
import blip.t.util.log.Log;

private int[4] specialNrs=[0,2,5,8];

private mixin testInit!() autoInitTst; 
private mixin testInit!("acceptable= int.max/2>=arg0 && arg0>=0;") posArg0Tst; 
private mixin testInit!("","arg0=r.uniformRSymm(10);") smallIntTst;
private mixin testInit!("acceptable= 10>arg0 && arg0>-10;") smallIntSkipTst; // very unlikely
private mixin testInit!("",`arg0=specialNrs[arg0_i]; arg0_nEl=specialNrs.length;
arg1=specialNrs[arg1_i]; arg1_nEl=specialNrs.length;`) combNrTst; // combinatorial cases

void main(char[][]argv){
    Stdout("blip.parallel.smp:")(Log.lookup("blip.parallel.smp").level).newline;
    Log.lookup("blip.parallel.smp").info("pippo");
    Stdout("blip.parallel.smp.queue:")(Log.lookup("blip.parallel.smp.queue").level).newline;
    Log.lookup("blip.parallel.smp.queue").info("pippo");
    FormatOut nullPrt=new FormatOut(nullStream());
    nullPrt=Stdout;
    SingleRTest.defaultTestController=new TextController(TextController.OnFailure.StopTest,
        TextController.PrintLevel.AllShort,nullPrt,nullPrt,1,false);
    TestCollection failTests=new TestCollection("failTests",__LINE__,__FILE__);

    SingleRTest[] tests=[
    autoInitTst.testTrue("(2*x)%2==0",(int x){ return ((2*x)%2==0);},
        __LINE__,__FILE__),
    autoInitTst.testTrue("(2*x)%2==0 r2",(int x){ return ((2*x)%2==0);},
        __LINE__,__FILE__),
    autoInitTst.testTrue("(2*x)%2==0 r3",(int x){ return ((2*x)%2==0);},
        __LINE__,__FILE__),
    autoInitTst.testTrue("(2*x)%4==0 (should fail)",(int x){ return ((2*x)%4==0);},
        __LINE__,__FILE__),
    autoInitTst.testTrue("(2*x)%4==0 || (2*x)%4==2 (should fail)",(int x){ return ((2*x)%4==0 || (2*x)%4==2);},
        __LINE__,__FILE__),
    posArg0Tst.testTrue("(2*x)%4==0 || (2*x)%4==2, int.max/2>=x>=0",
        (int x,uint y){ return ((2*x)%4==0 || (2*x)%4==2);},
        __LINE__,__FILE__),
    smallIntTst.testTrue("x*x<100",(int x){ return (x*x<100);},
        __LINE__,__FILE__),
    smallIntSkipTst.testTrue("x*x<100",(int x){ return (x*x<100);},
        __LINE__,__FILE__),
    autoInitTst.testFalse("!:((2*x)%2!=0)",(int x){ return ((2*x)%2!=0);},
        __LINE__,__FILE__),
    autoInitTst.testFalse("!:((2*x)%4==0) (should fail)",(int x){ return ((2*x)%4==0);},
        __LINE__,__FILE__),
    smallIntTst.testFalse("!:(x*x>100)",(int x){ return (x*x>100);},
        __LINE__,__FILE__),
    smallIntSkipTst.testFalse("!:(x*x>100)",(int x){ return (x*x>100);},
        __LINE__,__FILE__),
    autoInitTst.testNoFail("assert((2*x)%2==0)",(int x){ assert((2*x)%2==0,"error");},
        __LINE__,__FILE__),
    autoInitTst.testNoFail("assert((2*x)%4==0) (should fail)",(int x){ assert((2*x)%4==0,"error");},
        __LINE__,__FILE__),
    smallIntTst.testNoFail("assert(x*x<100)",(int x){ assert(x*x<100);},
        __LINE__,__FILE__),
    smallIntSkipTst.testNoFail("assert(x*x<100)",(int x){ assert(x*x<100);},
        __LINE__,__FILE__),
    autoInitTst.testFail("assert((2*x)%2!=0)",(int x){ assert((2*x)%2!=0,"error");},
        __LINE__,__FILE__,failTests),
    autoInitTst.testFail("assert((2*x)%4==0) (should fail)",(int x){ assert((2*x)%4==0,"error");},
        __LINE__,__FILE__,failTests),
    smallIntTst.testFail("assert(x*x>100)",(int x){ assert(x*x>100);},
        __LINE__,__FILE__,failTests),
    smallIntSkipTst.testFail("assert(x*x>100)",(int x){ assert(x*x>100);},
        __LINE__,__FILE__,failTests),
    combNrTst.testTrue("(x!=2)||(y!=1)",(int x, int y){ return (x!=2)||(y!=1); },
        __LINE__,__FILE__),
    combNrTst.testTrue("(x!=8)||(y!=5) (should fail)",(int x, int y){ return (x!=8)||(y!=5); },
        __LINE__,__FILE__),
    combNrTst.testTrue("(x!=8)||(y!=8)||(z>0) (should fail)",
        (int x, int y, int z){ return (x!=8)||(y!=8)||(z>0); },__LINE__,__FILE__)
    ];

    auto expectedFailures=[0,0,0,1,1,0,0,0,0,1,0,0,0,1,0,0,0,2,0,0,0,1,1];
    failTests.runTestsTask().autorelease.submit(defaultTask).wait();
    foreach (i,t;tests){
        t.runTestsTask().submit(sequentialTask);
        if(t.stat.failedTests!=expectedFailures[i])
            throw new Exception("test `"~t.testName~"` had "~ctfe_i2a(t.stat.failedTests)~" failures, expected "~ctfe_i2a(expectedFailures[i]));
    }
    Stdout("\n=============================================================\n").newline;
    mainTestFun(argv,failTests);
    Stdout("test finished!").newline;
}

