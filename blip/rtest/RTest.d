/// A module to perform random tests (the text that follows should be copied to the README.txt file)
///
/// = RTest =
/// == Quick Overview: RTest a random testing framework (from blip.rtest.RTest) ==
///
/// A framework to quickly write tests that check property/functions using randomly
/// generated data or all combinations of some values.
///
/// I wrote this framework inspired by Haskell's Quickcheck, but the result is a rather 
/// different (but still shares the main philosophy).
///
/// The idea is to be able to write tests as quickly and as painlessly as possible.
/// Typical use would be for example:
/// You have a function that solves linear systems of equations, and you want to test it.
/// The matrix should be square, and the b vector should have the same size as the matrix dimension.
/// So either you define  an ad-hoc structure, or you write a custom generator for it
/// (it is quite unlikely that the constraint are satisfied just by chance and you would
/// spend all your time waiting for a valid test case).
/// Then (if detA>0) you can check that the solution really solves the system of equations 
/// with a small residual error.
/// Your test can fail in many ways also due to the internal checks of the equation solver,
/// and you want to  always have a nice report that lets you reproduce the problem.
/// Another typical use case is when you have a slow reference implementation for something
/// and a fast one, and you want to be sure they are the same.
///
/// For simplicity here we use really simple tests, in this case a possible use is:
/// {{{
///     module tstMod;
///     import blip.rtest.RTest;
///     import blip.io.Console;
///     import blip.math.random.Random;
///     
///     bool functionToTest() {return true;}
///     
///     TestCollection myTests(TestCollection superColl=null){
///         // define a collection for my tests
///         TestCollection myTests=new TestCollection("myTests",__LINE__,__FILE__,superColl);
///     
///         // define a test with a test function (note the F in the name)
///         autoInitTst.testTrueF("testName",&functionToTest,__LINE__,__FILE__,myTests);
///         // an explicit case using a delegate (no final F)
///         autoInitTst.testTrue("(2*x)%2==0",delegate bool(int x){ return ((2*x)%2==0);},__LINE__,__FILE__,myTests);
///     
///         return myTests;
///     }
///     
///     class A{
///         static A randomGenerate(Rand r){
///             // generate an instance and returns it
///             return new A;
///         }
///     }
///     class B{
///         static B randomGenerate(Rand r){
///             // generate an instance and returns it
///             return new B;
///         }
///         void push(A a){ /+ add a on the stack +/ }
///         A pop(){ /+ gives back the top instance +/ return new A; }
///     }
///     
///     struct SpecialAB{
///         A a;
///         B b;
///         static SpecialAB randomGenerate(Rand r){
///             SpecialAB res;
///             // generate special a,b pair
///             return res;
///         }
///     }
///     
///     void testBStack(B b,A[] as){
///         foreach(a;as) b.push(a);
///         foreach_reverse(a;as){
///             assert(a==b.pop());
///         }
///     }
///     
///     void testSpecial(SpecialAB sAb){
///         // test sAb.a and sAb.b...
///     }
///     
///     // a normal non random test
///     void normalTest(){ }
///     
///     // this can be a template if you want to avoid allocation when not needed...
///     TestCollection abTests(TestCollection superColl=null){
///         TestCollection coll=new TestCollection("ABTests",__LINE__,__FILE__,superColl);
///         autoInitTst.testNoFailF("testBStack",&testBStack,__LINE__,__FILE__,coll);
///         autoInitTst.testNoFailF("testSpecial",&testSpecial,__LINE__,__FILE__,coll);
///         autoInitTst.testNoFailF("normalTest",&normalTest,__LINE__,__FILE__,coll);
///         return coll;
///     }
///     
///     /// myModule tests
///     TestCollection allTests(TestCollection superColl=null){
///         TestCollection coll=new TestCollection("myModule",__LINE__,__FILE__,superColl);
///         abTests(coll);
///         myTests(coll);
///         return coll;
///     }
///     
///     void main(string [] args){
///         sout(rand.toString()); sout("\n");
///         auto tests=allTests();
///         // it would be possible to simply call
///         // tests.runTests();
///         // but it is nicer to use mainTestFun that creates a command line utility that can
///         // re-run a test, or run a subset of the tests
///         mainTestFun(args,tests);
///     }
/// }}}
/// The main function shows how to make a program that creates an executable that will perform the tests.
/// The program lets you re-execute a test, or execute only a subset of the tests, and always
/// gives you enough information to reproduce the test runs.
/// If everything goes well the output will be something like
/// {{{
///     SyncCMWC+KISS99000000003ade6df6_00000020_9e1eea7c_315c04d6_983cb309_4f0a27b2_70796712_30441827_5789bc75_1799db5b_5cbebbd8_fc540d2d_3a50f6a6_56f3d5e1_bf450e7a_734e21d3_47a47ad2_ac7ffd34_52ff8217_0bf3fb03_27c70b1c_3c25d4e7_81283378_8073186e_2f9b1eea_40f7a829_a6d75629_8d990330_8c74c5c4_ddd5e44b_ef0f3c04_c476864e_3cc5af5e_ad8e39e7_0000000e_373679ad_00000000_00000000_40e05b40_2a100202_9bbe625f_12b8d071
///     test`myModule/myTests/(2*x)%2==0`                        0-100/100-100
///     test`myModule/ABTests/testBStack`                        0-100/100-100
///     test`myModule/ABTests/testSpecial`                       0-100/100-100
///     test`myModule/myTests/testName`                          0-1/1-1
///     test`myModule/myTests`                                   0-2/2-1
///     test`myModule/ABTests/normalTest`                        0-1/1-1
///     test`myModule/ABTests`                                   0-3/3-1
///     test`myModule`                                           0-7/7-1
///     
/// }}}
/// whereas if a test fails then it will print out something like this
/// {{{
///    test`myModule/ABTests/testBStack` failed with exception
///    tango.core.Exception.AssertException@tstMod(48): Assertion failure
///    ----------------
///    arg0: tstMod.B
///    arg1: [tstMod.A,tstMod.A,tstMod.A,tstMod.A,tstMod.A,tstMod.A,tstMod.A,tstMod.A,tstMod.A,tstMod.A,tstMod.A,tstMod.A,tstMod.A,tstMod.A]
///    test failed in collection`myModule/ABTests` created at `/Users/fawzi/d/blip/tstMod.d:61`
///    test failed in collection`myModule` created at `/Users/fawzi/d/blip/tstMod.d:70`
///
///    To reproduce:
///    ./tstMod.dbg --test='myModule/ABTests/testBStack' --counter='[0, 0]' --seed='CMWC+KISS99000000003ade6df6_00000020_21fbefdb_098b076c_7141f7c9_efcd27ac_f263306f_7ae1fd7b_a951d311_44a69d9e_32924c00_69ca7851_b475cfca_b147313a_88ee5415_00c7f4f7_5cc041eb_be68dd44_f715251b_649d63ba_46ba01bb_6497e1de_07277ba2_61ef65da_5825166c_53db8c1f_321c6da0_18b9f7e1_ca2d2ef5_a3d26eed_d319fbd7_48eecaf4_94d223cf_9f6a8ed6_0000001f_34c58f50_00000000_00000000_243c0339_476217a0_09c29624_15095711'
///    ERROR test `myModule/ABTests/testBStack` from `/Users/fawzi/d/blip/tstMod.d:62` FAILED!!-----------------------------------------------------------
///    test`myModule/ABTests/testBStack`                        1-0/1-1
/// }}}
/// from it you should see the arguments that made the test fail, and you can re-run it.
///
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
module blip.rtest.RTest;
public import blip.rtest.BasicGenerators;
public import blip.rtest.RTestFramework;
import tango.util.Convert;
import tango.core.Version;
static if (Tango.Major==1){
    import tango.text.Arguments;
} else {
    import tango.util.ArgParser;
}
import tango.text.Util;
import blip.io.Console;
import blip.io.BasicIO;
import blip.stdc.stdlib: exit;
import blip.parallel.smp.WorkManager;
import blip.Comp;

mixin testInit!() autoInitTst; 

int[] parseIArray(cstring str){
    uint start=locate(str,'[');
    uint end=locate(str,']');
    if (start==str.length || end==str.length || start>=end){
        sout("'")(str)("'"); writeOut(sout.call,start); sout(" ")(end)("\n");
        throw new Exception("IArray parsing failed");
    }
    cstring core=str[start+1..end];
    return to!(int[])(split(core,","));
}

int mainTestFun(string [] argStr,SingleRTest testSuite){
    string cmdName="./test";
    if (argStr.length>0 && argStr[0].length>0) cmdName=argStr[0];
    string helpStr=cmdName~` [--help] [--runs=n] [--trace] [--test='testName'] [--counter='[n,...]'] 
        [--seed='seed'] [--on-failure=[continue|stop-test|stop-all|throw]]
        [--print-level=[error|skip|all-short|all-verbose]]
     --help print this message
     --runs defines the number of test runs (default 1)
     --trace writes the initial seed before each test group
     --test runs only the given test
     --counter sets the initial counter of the test
     --seed defines the seed for the test
     --on-failure sets the action to perform after a test fails (default stop-test)
     --print-level sets the print level (default all-short)`;

    string seed=null;
    string test=null;
    int runs=1;
    int[] counter=null;
    bool help=false;
    bool trace=false;
    TextController.OnFailure onFailure=TextController.OnFailure.StopTest;
    TextController.PrintLevel printLevel=TextController.PrintLevel.AllShort;
    
    static if (Tango.Major==1){
        auto args=new Arguments;
        args("help").bind(delegate void(){ help=true; });
        args("runs").bind(delegate string (string arg){ runs=to!(int)(arg[1..$]); return null; });
        args("trace").bind(delegate void(){ trace=true; });
        args("seed").bind(delegate string (string arg){ seed=arg[1..$].dup; return null; });
        args("counter").bind(delegate string (string arg){ counter=parseIArray(arg[1..$]); return null; });
        args("test").bind(delegate string (string arg){ test=arg[1..$].dup; return null; });
        args("on-failure").bind(delegate string (string arg){
            if (arg.length==0) throw new Exception("expected an argument after --on-failure");
            if (arg[0]=='=') arg=arg[1..$];
            switch(arg){
                case "Continue","continue" : onFailure=TextController.OnFailure.Continue; break;
                case "StopTest","stoptest","stop-test": onFailure=TextController.OnFailure.StopTest; break;
                case "stop-all","StopAllTests","StopAll","stopall","stopalltests","stop-all-tests":
                onFailure=TextController.OnFailure.StopAllTests; break;
                case "Throw","throw": onFailure=TextController.OnFailure.Throw; break;
                default:
                    // use Stderr?
                    sout("ERROR invalid options for on-failure: '")(arg)("'\n");
                    sout(helpStr)("\n");
                    exit(-1);
            }
            return null;
        });
        args("print-level").bind(delegate string (string arg){
            if (arg[0]=='=') arg=arg[1..$];
            switch(arg){
                case "Error", "error": printLevel=TextController.PrintLevel.Error; break;
                case "Skip","skip": printLevel=TextController.PrintLevel.Skip; break;
                case "AllShort", "allshort", "all-short", "short": printLevel=TextController.PrintLevel.AllShort; break;
                case "AllVerbose","allverbose","all","all-verbose","verbose":
                    printLevel=TextController.PrintLevel.AllVerbose; break;
                default:
                    serr("ERROR invalid options for print-level: '")(arg)("'\n");
                    sout(helpStr)("\n");
                    exit(-2);
            }
            return null;
        });
    
        args.parse(argStr[1..$]);
    } else {
        ArgParser args = new ArgParser();
        args.bind("--","help",delegate void(){ help=true; });
        args.bind("--","runs",delegate(cstring arg){ runs=to!(int)(arg[1..$]); });
        args.bind("--","trace",delegate void(){ trace=true; });
        args.bind("--","seed",delegate(cstring arg){ seed=arg[1..$].dup; });
        args.bind("--","counter",delegate(cstring arg){ counter=parseIArray(arg[1..$]); });
        args.bind("--","test",delegate void(cstring arg){ test=arg[1..$].dup; });
        args.bind("--","on-failure",delegate void(cstring arg){
            if (arg.length==0) throw new Exception("expected an argument after --on-failure");
            if (arg[0]=='=') arg=arg[1..$];
            switch(arg){
                case "Continue","continue" : onFailure=TextController.OnFailure.Continue; break;
                case "StopTest","stoptest","stop-test": onFailure=TextController.OnFailure.StopTest; break;
                case "stop-all","StopAllTests","StopAll","stopall","stopalltests","stop-all-tests":
                onFailure=TextController.OnFailure.StopAllTests; break;
                case "Throw","throw": onFailure=TextController.OnFailure.Throw; break;
                default:
                    // use Stderr?
                    sout("ERROR invalid options for on-failure: '")(arg)("'\n");
                    sout(helpStr)("\n");
                    exit(-1);
            }
        });
        args.bind("--","print-level",delegate void(cstringarg){
            if (arg[0]=='=') arg=arg[1..$];
            switch(arg){
                case "Error", "error": printLevel=TextController.PrintLevel.Error; break;
                case "Skip","skip": printLevel=TextController.PrintLevel.Skip; break;
                case "AllShort", "allshort", "all-short", "short": printLevel=TextController.PrintLevel.AllShort; break;
                case "AllVerbose","allverbose","all","all-verbose","verbose":
                    printLevel=TextController.PrintLevel.AllVerbose; break;
                default:
                    serr("ERROR invalid options for print-level: '")(arg)("'\n");
                    sout(helpStr)("\n");
                    exit(-2);
            }
        });
    
        args.parse(argStr[1..$]);
    }
    
    if (help){
        sout(helpStr)("\n");
        return 0;
    }
    
    SingleRTest.defaultTestController=new TextController(argStr[0],
        onFailure, printLevel,sout.call,sout.call,1,trace);
    if (test.length==0){
        // testSuite.runTests(runs,seed,counter);
        testSuite.runTestsTask(runs,seed,counter).autorelease.submit(defaultTask).wait();
    } else{
        auto tst=testSuite.findTest(test);
        if (tst is null){
            sout("ERROR test '")(test)("' not found!\n");
            return -3;
        }
        //tst.runTests(runs,seed,counter);
        tst.runTestsTask(runs,seed,counter).autorelease.submit(defaultTask).wait();
        return tst.stat.failedTests;
    }
    return testSuite.stat.failedTests;
}

debug(UnitTest){
    private int[4] specialNrs=[0,2,5,8];

    private mixin testInit!("acceptable= int.max/2>=arg0 && arg0>=0;","") posArg0Tst; 
    private mixin testInit!("","arg0=r.uniformRSymm(10);") smallIntTst;
    private mixin testInit!("acceptable= 10>arg0 && arg0>-10;") smallIntSkipTst; // very unlikely
    private mixin testInit!("",`arg0=specialNrs[arg0_i]; arg0_nEl=specialNrs.length;
    arg1=specialNrs[arg1_i]; arg1_nEl=specialNrs.length;`) combNrTst; // combinatorial cases

    unittest{
        CharSink nullPrt=delegate void(cstring){};
        // nullPrt=sout;
        SingleRTest.defaultTestController=new TextController("",TextController.OnFailure.StopTest,
            TextController.PrintLevel.AllShort,nullPrt,nullPrt);
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
    }

}