/// quick test of the RTest facilities
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
module testRTest;
import blip.io.Console;
import blip.rtest.RTest;
import blip.io.NullStream;
import blip.util.TemplateFu;
import blip.parallel.smp.WorkManager;
import blip.util.TangoLogConfig;
import blip.util.TangoLog;
import blip.io.BasicIO;
import blip.io.Console;
import blip.Comp;
version(Trace){ import blip.core.stacktrace.TraceExceptions; }

private int[4] specialNrs=[0,2,5,8];

private mixin testInit!() autoInitTst; 
private mixin testInit!("acceptable= int.max/2>=arg0 && arg0>=0;") posArg0Tst; 
private mixin testInit!("","arg0=r.uniformRSymm(10);") smallIntTst;
private mixin testInit!("acceptable= 10>arg0 && arg0>-10;") smallIntSkipTst; // very unlikely
private mixin testInit!("",`arg0=specialNrs[arg0_i]; arg0_nEl=specialNrs.length;
arg1=specialNrs[arg1_i]; arg1_nEl=specialNrs.length;`) combNrTst; // combinatorial cases

void main(string []argv){
    sout("blip.parallel.smp:")(Log.lookup("blip.parallel.smp").level)("\n");
    sout("blip.parallel.smp.queue:")(Log.lookup("blip.parallel.smp.queue").level)("\n");
    CharSink nullPrt=delegate void(string s){};
    nullPrt=sout.call;
    SingleRTest.defaultTestController=new TextController("",TextController.OnFailure.StopTest,
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
    autoInitTst.testNoFail("assert((2*x)%2==0)",(int x){ if ((2*x)%2!=0) throw new Exception("error",__FILE__,__LINE__);},
        __LINE__,__FILE__),
    autoInitTst.testNoFail("assert((2*x)%4==0) (should fail)",(int x){ if ((2*x)%4!=0) throw new Exception("error",__FILE__,__LINE__);},
        __LINE__,__FILE__),
    smallIntTst.testNoFail("assert(x*x<100)",(int x){ if (x*x>=100) throw new Exception("error",__FILE__,__LINE__);},
        __LINE__,__FILE__),
    smallIntSkipTst.testNoFail("assert(x*x<100)",(int x){ if (x*x>=100) throw new Exception("error",__FILE__,__LINE__);},
        __LINE__,__FILE__),
    autoInitTst.testFail("assert((2*x)%2!=0)",(int x){ if ((2*x)%2==0) throw new Exception("error",__FILE__,__LINE__);},
        __LINE__,__FILE__,failTests),
    autoInitTst.testFail("assert((2*x)%4==0) (should fail)",(int x){ if ((2*x)%4!=0) throw new Exception("error",__FILE__,__LINE__); },
        __LINE__,__FILE__,failTests),
    smallIntTst.testFail("assert(x*x>100)",(int x){ if (x*x<=100) throw new Exception("error",__FILE__,__LINE__); },
        __LINE__,__FILE__,failTests),
    smallIntSkipTst.testFail("assert(x*x>100)",(int x){ if (x*x<=100) throw new Exception("error",__FILE__,__LINE__); },
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
        t.runTestsTask().submit(immediateTask);
        if(t.stat.failedTests!=expectedFailures[i]){
            throw new Exception("test `"~t.testName~"` had "~ctfe_i2a(t.stat.failedTests)~" failures, expected "~ctfe_i2a(expectedFailures[i]));
        }
    }
    sout("\n=============================================================\n\n");
    mainTestFun(argv,failTests);
    sout("test finished!\n");
}

