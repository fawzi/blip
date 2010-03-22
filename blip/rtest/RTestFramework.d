/*******************************************************************************
    A module to perform random tests
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.rtest.RTestFramework;
import blip.t.math.random.Random: Random;
public import blip.util.TemplateFu: nArgs,ctfe_i2a,ctfe_hasToken, ctfe_replaceToken;
public import blip.t.core.Traits:isStaticArrayType;
import blip.io.BasicIO;
public import blip.io.Console;
public import blip.t.core.Variant:Variant;
import blip.t.core.Array: find,remove;
import blip.t.core.sync.Mutex: Mutex;
import blip.parallel.smp.WorkManager;
import blip.t.core.Thread;
public import blip.container.GrowableArray;

/// exception that causes a test to skip
class SkipException: Exception{
    this(char [] message){ super(message); }
}

// a reasonably collision free, fast and small (seedwise) rng
alias Random Rand;

/// replaces arg0,... with arg[0]...
char[] replaceArgI(S...)(char[] manualInit){
    char[] manualInit2=manualInit;
    foreach (i,T;S){
        char[] argName="arg"~ctfe_i2a(i);
        if (ctfe_hasToken(argName,manualInit)){
            char[] argRepl="arg["~ctfe_i2a(i)~"]";
            manualInit2=ctfe_replaceToken(argName,argRepl,manualInit2);
        }
    }
    return manualInit2;
}

/// returns a string defining the arguments arg0...argN and a function bool doSetup(SingleRTest)
/// that initializes them
char[] completeInitStr(S...)(char[] checks,char[] manualInit,char[] indent="    "){
    char[]res="".dup;
    res~=indent~"bool doSetup(SingleRTest test){\n";
    char[]indent1=indent~"    ";
    res~=indent1~"Rand r=test.r;\n";
    foreach (i,T;S){
        res~=indent1~"int arg"~ctfe_i2a(i)~"_nEl=-1;\n";
        res~=indent1~"int arg"~ctfe_i2a(i)~"_i=test.counter["~ctfe_i2a(i)~"];\n";
    }
    res~=indent1~"bool acceptable=true,acceptableAll=true;\n";
    res~=indent1;
    res~=replaceArgI!(S)(manualInit);
    res~="\n";
    foreach (i,T;S){
        char[] argName="arg"~ctfe_i2a(i);
        if (!ctfe_hasToken(argName,manualInit)){
            res~=indent1~"static if(isStaticArrayType!(S["~ctfe_i2a(i)~"])){\n";
            res~=indent1~"static if(is(typeof(genRandom!(S["~ctfe_i2a(i)~"])(new Rand(),arg0_i,arg0_nEl,acceptable)))){\n";
            res~=indent1~"    genRandom!(S["~ctfe_i2a(i)~"])(r,arg"~
                ctfe_i2a(i)~"_i,arg"~ctfe_i2a(i)~"_nEl,acceptable);\n";
            res~=indent1~"} else static if (is(typeof(generateRandom!(S["~ctfe_i2a(i)~"])(new Rand(),arg0_i,arg0_nEl,acceptable)))) {\n";
            res~=indent1~"    generateRandom!(S["~ctfe_i2a(i)~"])(r,arg"~
                ctfe_i2a(i)~"_i,arg"~ctfe_i2a(i)~"_nEl,acceptable);\n";
            res~=indent1~"} else {\n";
            res~=indent1~"    static assert(0,\""~T.stringof~" cannot be automatically generated, missing one of the generateRandom static methods or a T generateRandom(T:"~T.stringof~")(Rand r,int idx,ref int nEl, ref bool acceptable) specialization, see blip.rtest.BasicGenerators.\");\n";
            res~=indent1~"}\n";
            res~=indent1~"}else{\n";
            res~=indent1~"static if(is(typeof(genRandom!(S["~ctfe_i2a(i)~"])(new Rand(),arg0_i,arg0_nEl,acceptable)))){\n";
            res~=indent1~"    arg["~ctfe_i2a(i)~"]"~"=genRandom!(S["~ctfe_i2a(i)~"])(r,arg"~
                ctfe_i2a(i)~"_i,arg"~ctfe_i2a(i)~"_nEl,acceptable);\n";
            res~=indent1~"} else static if (is(typeof(generateRandom!(S["~ctfe_i2a(i)~"])(new Rand(),arg0_i,arg0_nEl,acceptable)))) {\n";
            res~=indent1~"    arg["~ctfe_i2a(i)~"]"~"=generateRandom!(S["~ctfe_i2a(i)~"])(r,arg"~
                ctfe_i2a(i)~"_i,arg"~ctfe_i2a(i)~"_nEl,acceptable);\n";
            res~=indent1~"} else {\n";
            res~=indent1~"    static assert(0,\""~T.stringof~" cannot be automatically generated, missing one of the generateRandom static methods or a T generateRandom(T:"~T.stringof~")(Rand r,int idx,ref int nEl, ref bool acceptable) specialization, see blip.rtest.BasicGenerators.\");\n";
            res~=indent1~"}\n";
            res~=indent1~"}\n";
            res~=indent1~"acceptableAll=acceptableAll && acceptable;\n";
        }
    }
    // updateCounter
    res~=indent1~"int increase=1;\n";
    foreach (i,T;S){
        char[] argNEl="arg"~ctfe_i2a(i)~"_nEl";
        res~=indent1~"if ("~argNEl~"<0) test.hasRandom=true;\n";
        res~=indent1~"if (increase) {\n";
        res~=indent1~"    test.newCounter["~ctfe_i2a(i)~"]=test.counter["~ctfe_i2a(i)~"]+1;\n";
        res~=indent1~"    if (test.newCounter["~ctfe_i2a(i)~"]>=("~argNEl~">0?"~argNEl~":-"~argNEl~")){\n";
        res~=indent1~"        test.newCounter["~ctfe_i2a(i)~"]=0;\n";
        res~=indent1~"        if ("~argNEl~"==0){\n"; // skip all, change behaviour, make it equivalent to -1?
        res~=indent1~"            test.didCombinations=true;\n";
        res~=indent1~"            test.hasRandom=false;\n";
        res~=indent1~"            return false;\n";
        res~=indent1~"        };\n";
        res~=indent1~"    } else {\n";
        res~=indent1~"        increase=0;\n";
        res~=indent1~"    }\n";
        res~=indent1~"} else {\n";
        res~=indent1~"    test.newCounter["~ctfe_i2a(i)~"]=test.counter["~ctfe_i2a(i)~"];\n";
        res~=indent1~"}\n";
    }
    res~=indent1~"test.didCombinations=increase;\n";
    res~=indent1~replaceArgI!(S)(checks)~"\n";
    res~=indent1~"acceptableAll=acceptableAll && acceptable;\n";
    res~=indent1~"return acceptableAll;\n";
    res~=indent~"}\n";
    return res;
}
/// calls the actual test function
char[] callF(S...)(char[] retType){
    char[] res="".dup;
    if (retType=="void") {
        res~="test.baseDelegate.get!( void delegate(";
    } else {
        res~=retType~" callRes=test.baseDelegate.get!("~retType~" delegate(";
    }
    foreach (i,T;S){
        if (i!=0) res~=",";
        res~=T.stringof;
    }
    res~="))()(arg);\n";
    return res;
}

/// tries to print the arguments of the test
char[] printArgs(int nargs,char[] printC="sout.call",char[] indent="    "){
    char[] res="".dup;
    res~=indent~"try{\n";
    for (int i=0;i<nargs;++i){
        res~=indent~"    static if(is(typeof(writeOut("~printC~",arg["~ctfe_i2a(i)~"])))){\n";
        res~=indent~"        "~printC~"(\"arg"~ctfe_i2a(i)~": \"); writeOut("~printC~",arg["~ctfe_i2a(i)~"]); "~printC~"(\"\\n\");\n";
        res~=indent~"    } else {\n";
        res~=indent~"        "~printC~"(\"non printable argument of type \"~(typeof(arg["~ctfe_i2a(i)~"]).stringof)~\" as writeOut cannot handle it.\\n\");\n";
        res~=indent~"    }\n";
    }
    res~=indent~"}catch (Exception e) {\n";
    res~=indent~"    sout.call(collectAppender(delegate void(void delegate(char[])s){ s(\"could not print arguments due to exception\"); writeOut(sout.call,e.toString); sout(\"\\n\");}));\n";
    res~=indent~"}\n";
    return res;
}

enum TestResult : int{
    Pass=1,
    Skip=0,
    Fail=-1,
}

/// a test controller that writes out text to the given CharSink
class TextController: TestControllerI{
    Mutex _writeLock;
    CharSink progressLog;
    CharSink errorLog;
    bool _isStopping,trace;
    enum PrintLevel:int{ Error, Skip, AllShort, AllVerbose}
    PrintLevel printLevel;
    Rand r;
    
    Mutex writeLock(){ return _writeLock; }
    /// what to do upon failure
    enum OnFailure : int{
        Continue, /// do no stop
        StopTest, /// stop that test, but execute the others
        StopAllTests, // stop all subsequent tests
        Throw /// throw an exception
    }
    OnFailure onFailure; /// what to do upon failure
    int testFactor; /// increase for a more throughly testing
    this(OnFailure onFailure=OnFailure.Throw,PrintLevel printLevel=PrintLevel.Skip,
        CharSink progressLog=sout.call,CharSink errorLog=sout.call,int testFactor=1,
        bool trace=false,Rand r=null){
        this._writeLock=new Mutex();
        this.progressLog=progressLog;
        this.errorLog=errorLog;
        this.onFailure=onFailure;
        this._isStopping=false;
        this.trace=trace;
        this.printLevel=printLevel;
        assert(testFactor>0,"testFactor must be positive");
        this.testFactor=testFactor;
        this.r=r;
        if (r is null)
            this.r=new Rand();
    }
    bool isStopping(){
        return _isStopping;
    }
    /// test has the object as controller
    void willControlTest(SingleRTest test) {
        if (test.r is null) {
            test.r=r.spawn();
        }
    }
    /// test does not have anymore the object as controller
    void removeTest(SingleRTest test) { }
    /// test is about to run its tests
    bool willRunTests(SingleRTest test) {
        test.failureLog=errorLog; // make a copy??
        test.testSize.nCombTestMax=test.testSize.nCombTestMax*testFactor;
        test.testSize.nSetupMax=test.testSize.nSetupMax*testFactor;
        test.testSize.budgetMax=test.testSize.budgetMax*testFactor;
        if (trace) {
            char[] state;
            if (test.initialState is null){
                if (test.r is null) test.r=r.spawn();
                state=test.r.toString;
            } else {
                state=test.initialState;
            }
            synchronized(_writeLock){
                progressLog(test.testName);
                progressLog("\ninitial rng state: ");writeOut(progressLog,state); progressLog("\n");
                progressLog(" counter: [");
                foreach (i,c;test.counter){
                    if (i!=0) progressLog(", ");
                    writeOut(progressLog,c);
                }
                progressLog("]\n");
                //progressLog.flush;
            }
        }
        if (printLevel==PrintLevel.AllVerbose) progressLog(test.testName);
        return !isStopping;
    }
    /// test did run all its tests
    void didRunTests(SingleRTest test) {
        bool shouldPrint=printLevel==PrintLevel.AllShort || printLevel==PrintLevel.AllVerbose ||
            test.stat.failedTests>0 || test.stat.passedTests==0 ||
            (printLevel==PrintLevel.Skip && test.stat.skippedTests>0);
        if (shouldPrint) {
            synchronized(_writeLock){
                if (printLevel!=PrintLevel.AllVerbose || test.stat.failedTests>0){
                    progressLog(collectAppender(delegate void(CharSink s){
                        s("test`");
                        s(test.testName);
                        s("`");
                        if (test.testName.length<50){
                            int l=50-test.testName.length;
                            auto spc="              ";
                            while(l>0){
                                auto toAdd=((l>spc.length)?spc.length:l);
                                s(spc[0..toAdd]);
                                l-=toAdd;
                            }
                        }
                    s(" "); writeOut(s,test.stat.failedTests);
                    s("-"); writeOut(s,test.stat.passedTests);
                    s("/"); writeOut(s,test.stat.nTests);
                    s("-"); writeOut(s,test.stat.nCombTest);
                    s("\n");
                    }));
                }
            }
        }
        test.testSize.nCombTestMax=test.testSize.nCombTestMax/testFactor;
        test.testSize.nSetupMax=test.testSize.nSetupMax/testFactor;
        test.testSize.budgetMax=test.testSize.budgetMax/testFactor;
    }
    /// test will run a test
    bool willRunTest(SingleRTest test) {
        if (printLevel==PrintLevel.AllVerbose) {
            synchronized(_writeLock){ progressLog("."); }
        }
        return !isStopping;
    }
    /// test has skipped one test, should return wether the testing should continue
    bool testSkipped(SingleRTest test) {
        if (printLevel==PrintLevel.AllVerbose) {
            synchronized(_writeLock) { progressLog("-"); }
        }
        return !isStopping;
    }
    /// test has passed one test, should return wether the testing should continue
    bool testPassed(SingleRTest test) {
        if (printLevel==PrintLevel.AllVerbose) {
            synchronized(_writeLock) { progressLog("+"); }
        }
        return !isStopping;
    }
    /// test has failed one test, should return wether the testing should continue
    bool testFailed(SingleRTest test){
        synchronized(_writeLock) {
            char[512] buf;
            auto arr=lGrowableArray!(char)(buf,0,GASharing.GlobalNoFree);
            progressLog("\n");
            progressLog("To reproduce:\n");
            progressLog(" testCollection\n");
            arr(" .findTest(`");
            arr(test.testName);
            arr("`)\n");
            arr(" .runTests(1,`");
            writeOut(&arr.appendArr,test.initialState); arr("`,[");
            foreach (i,c;test.counter){
                if (i!=0) arr(", ");
                writeOut(&arr.appendArr,c);
            }
            arr("]);\n");
            progressLog(arr.data);
            arr.clearData;
            progressLog("or\n");
            dumperP(&arr)("./test --test='")(test.testName)("'");
            arr(" --counter='[");
            foreach (i,c;test.counter){
                if (i!=0) arr(", ");
                writeOut(&arr.appendArr,c);
            }
            arr("]'");
            dumperP(&arr)(" --seed='")(test.initialState)("'\n");
            progressLog(arr.data);
            arr.clearData;
            
            dumperP(&arr.appendArr)("ERROR test `")(test.testName)("` from `")(test.sourceFile)(":")(test.sourceLine)("` FAILED!!");
            progressLog(arr.data);
            arr.clearData;
            progressLog("-----------------------------------------------------------\n");
            //progressLog.flush; // guarantee flush on file log
        }
        switch (onFailure){
        case OnFailure.StopTest:
            return false;
        case OnFailure.Throw:
            throw new Exception("test failure",__FILE__,__LINE__);
        case OnFailure.StopAllTests:
            this._isStopping=true;
            break;
        case OnFailure.Continue:
            break;
        default:
            throw new Exception("unknown failure",__FILE__,__LINE__);
        }
        return !isStopping;
    }
}

/// interface with the callbacks that the test controller recieves from its tests
interface TestControllerI{
    /// test has the object as controller
    void willControlTest(SingleRTest test);
    /// test does not have anymore the object as controller
    void removeTest(SingleRTest test);
    /// test is about to run its tests
    bool willRunTests(SingleRTest test);
    /// test did run all its tests
    void didRunTests(SingleRTest test);
    /// test will run a test
    bool willRunTest(SingleRTest test);
    /// test has skipped one test, should return werether the testing should continue
    bool testSkipped(SingleRTest test);
    /// test has passed one test, should return werether the testing should continue
    bool testPassed(SingleRTest test);
    /// test has failed one test, should return werether the testing should continue
    bool testFailed(SingleRTest test);
    /// if the testing is stopping
    bool isStopping();
    /// write locking (nicer output in parallel)
    Mutex writeLock();
}

/// structure describing the number of tests to perform
struct TestSize{
    int nCombTestMax=100; /// maximum number of combinatorial cycles
    int nSetupMax=100; /// maximum attempts for setup
    float setupCost=0.01; /// cost for setup
    float testCost=1.0; /// cost for single test
    float budgetMax=400.0; /// total budget for test attempts (stops when this becomes negative)
    /// constructor
    static TestSize opCall(int nCombTestMax=100,int nSetupMax=100,float budgetMax=-4.0,
        float setupCost=0.01,float testCost=1.0){
        TestSize res;
        res.nCombTestMax=nCombTestMax;
        res.nSetupMax=nSetupMax;
        res.setupCost=setupCost;
        res.testCost=testCost;
        if (budgetMax<0.0) budgetMax*=-nCombTestMax;
        res.budgetMax=budgetMax;
        return res;
    }
}

/// explicit closure for test's runTests
class RunTestsArgs{
    SingleRTest test;
    int testFactor;
    char[] rngState;
    int[] counterVal;
    bool mightYield;
    this(SingleRTest test,bool mightYield=true, int testFactor=1,char[] rngState=null,int[] counterVal=null){
        this.test=test;
        this.testFactor=testFactor;
        this.rngState=rngState;
        this.counterVal=counterVal;
        this.mightYield=mightYield;
    }
    YieldableCall yieldableCall(){
        return YieldableCall(&exec,(mightYield?TaskFlags.None:(TaskFlags.NoYield|TaskFlags.NoSpawn)));
    }
    void exec(){
        test.runTests(testFactor,rngState,counterVal);
    }
}

/// class describing a single random test
/// you are not supposed to instantiate it directly, use one of the
/// test* functions in the testInit template
class SingleRTest{
    /// the default test controller
    static TestControllerI defaultTestController;
    static this(){ defaultTestController=new TextController(); }

    /+  --- test info --- +/
    char[] testName; /// name of the current test
    char[]sourceFile; /// source file where the test was instantiated
    long sourceLine; /// source line at which the test was instantiated
    private TestResult delegate(SingleRTest) testDlg; /// the test
    /// number of tests to perform
    TestSize testSize;

    /// test controller object
    TestControllerI _testController;
    /// ditto
    TestControllerI testController(){
        if (_testController is null)
            return defaultTestController;
        else
            return _testController;
    }
    /// ditto
    void testController(TestControllerI nC){
        if (_testController !is nC){
            if (_testController !is null) _testController.removeTest(this);
            _testController=nC;
            if (_testController !is null) _testController.willControlTest(this);
        }
    }
    /// internal storage for the final test delegate
    Variant baseDelegate;
    
    /+  --- run machinery --- +/
    Rand r; /// random source
    char[] initialState; /// last Rng state
    int nArgs; /// number of arguments of the test (for counter)
    int[] counter; /// counter for exaustive (non random) coverage
    int[] newCounter; /// value of counter for the next iteration
    
    /// if the generation has a random part or only a combinatorial one
    /// (valid only after at least one test attempt)
    bool hasRandom;
    int didCombinations; /// 0: in combinatorial sequence, 1: completed combinatorial sequence
    CharSink failureLog; /// place to log failure description (if available)
    float budgetLeft; /// budget left
    
    /// structure keeping statistic info
    struct TestStats{
        int nTests; /// number of tests attempted
        int nCombTest; /// numbers of combinatorial iteration done
        int skippedTests; /// tests skipped
        int passedTests; /// tests passed
        int failedTests; /// tests failed

        /// clears the statistic stored
        void clear(){
            nTests=0;
            nCombTest=0;
            skippedTests=0;
            passedTests=0;
            failedTests=0;
        }
    }
    TestStats stat; /// statistics for the current test
    
    /// resets the test to the initial state
    SingleRTest reset(){
        counter[]=0;
        newCounter[]=0;
        hasRandom=false;
        didCombinations=0;
        stat.clear();
        return this;
    }
    // runs the tests possibly restarting them with the given rngState/counterVal
    SingleRTest runTests(int testFactor=1,char[] rngState=null,int[] counterVal=null){
        if (this is null) throw new Exception("SingleRTest run on null test");
        initialState=rngState;
        if (counterVal !is null){
            counter[]=counterVal;
        }
        assert(testFactor>0,"testFactor should be positive");
        scope(exit) testController.didRunTests(this);
        if (!testController.willRunTests(this)) return this;
        budgetLeft=testSize.budgetMax*testFactor;
        assert(r !is null,"null rng in test"); // setting it here might introduce non determinism
        if (failureLog is null) failureLog=sout.call; // use Stderr ?
        if (initialState !is null){
            r.fromString(rngState);
        }
        int myCombTest=0;
        for (int iTest=0;budgetLeft>0;++iTest){
            if (!testController.willRunTest(this)) break;
            initialState=r.toString();
            TestResult res;
            for (int iSetup=0;iSetup<testSize.nSetupMax*testFactor;++iSetup){
                res=testDlg(this);
                if (res!=TestResult.Skip || budgetLeft<0 ||
                    (!hasRandom)) break;
                budgetLeft-=testSize.setupCost;
            }
            ++stat.nTests;
            if (res!=TestResult.Skip) budgetLeft-=testSize.testCost;
            if (didCombinations){
                ++myCombTest;
                ++stat.nCombTest;
            }
            if (res==TestResult.Pass){
                ++stat.passedTests;
                if (!testController.testPassed(this)) break;
            } else if (res==TestResult.Skip){
                ++stat.skippedTests;
                if (!testController.testSkipped(this)) break;
            } else {
                ++stat.failedTests;
                if (!testController.testFailed(this)) break;
            }
            counter[]=newCounter[];
            if (didCombinations && (!hasRandom)) break;
            if (myCombTest>=testSize.nCombTestMax*testFactor) break;
        }
        return this;
    }
    /// task that executes runTests
    Task runTestsTask(int testFactor=1,char[] rngState=null,int[] counterVal=null){
        auto closure=new RunTestsArgs(this,true,testFactor,rngState,counterVal);
        return Task(testName,closure.yieldableCall());
    }
    /// constructor
    this(char[]testName,long sourceLine,char[]sourceFile,
        int nargs,TestResult delegate(SingleRTest) testDlg,
        TestSize testSize=TestSize(),TestControllerI testController=null,
        CharSink failureLog=null, Rand r=null, Variant baseDelegate=Variant(null)){
        this.testName=testName;
        this.sourceFile=sourceFile;
        this.sourceLine=sourceLine;
        this.nArgs=nargs;
        this.counter= new int[nargs];
        this.newCounter= new int[nargs];
        this.r=r;
        this.testDlg=testDlg;
        this.testSize=testSize;
        this.failureLog=failureLog;
        if (failureLog is null) this.failureLog=sout.call; // use Stderr ?
        reset;
        this.baseDelegate=baseDelegate;
        this.testController=testController;
        if (testController is null) this.testController.willControlTest(this);
    }
    
    /// finds the requested test (for completness only)
    SingleRTest findTest(char[] name){
        if (name==testName)
            return this;
        else
            return null;
    }
    
    /// initializes the current rng from the given rng
    void randomInit(Rand mR){
        if (r is null){
            r=mR.spawn();
        } else {
            assert(mR !is r);
            synchronized(mR){
                r.seed(& mR.uniform!(uint));
            }
        }
    }
}

class TestCollection: SingleRTest, TestControllerI {
    /// the tests in this collection
    SingleRTest[] subTests;
    /// lock for stats
    Mutex statLock;
    /// constructor
    this(char[]testName,long sourceLine,char[]sourceFile,TestControllerI testController=null,
        SingleRTest[] subTests=[],CharSink failureLog=null, Rand r=null)
    {
        super(testName,sourceLine,sourceFile,1,null,TestSize(1,1,1.5), testController,
            failureLog, r, Variant(null));
        statLock=new Mutex();
        subTests=[];
        this.addSubtests(subTests);
    }
    /// adds a set of subtests
    void addSubtests(SingleRTest[] subT){
        foreach(t;subT){
            if (t.testController !is this){
                t.testController=this;
            }
        }
    }
    SingleRTest findTest(char[] name){
        if (name==testName) return this;
        SingleRTest res=null;
        foreach(subT;subTests){
            SingleRTest rTmp=subT.findTest(name);
            if (rTmp !is null){
                if (res !is null && res !is rTmp){
                    sout("WARNING findTest found several tests with the same name, returning first\n");
                    return res;
                }
                res=rTmp;
            }
        }
        return res;
    }
    // runs the tests possibly restarting them with the given rngState/counterVal
    SingleRTest runTests(int testFactor=1,char[] rngState=null,int[] counterVal=null){
        if (this is null) throw new Exception("TestCollection run on null collection");
        assert(testFactor>0,"testFactor should be positive");
        if (!testController.willRunTests(this)) return this;
        version(SequentialTests){
            scope(exit)incrNCombTest();
        }
        synchronized(statLock){
            budgetLeft=testSize.budgetMax;
        }
        if (r is null) r=new Rand();
        if (failureLog is null) failureLog=sout.call; // use Stderr ?
        if (rngState !is null){
            r.fromString(rngState);
        }
        if (counterVal !is null){
            counter[]=counterVal;
        }
        foreach (t;subTests){
            t.randomInit(r);
            version(SequentialTests){
                t.runTests(testFactor);
            } else {
                t.runTestsTask(testFactor).autorelease().submitYield();
            }
            if (testController.isStopping) break;
        }
        return this;
    }
    /// increments the number of combinatorial runs
    void incrNCombTest(){
        synchronized(statLock){
            stat.nCombTest++;
            testController.didRunTests(this);
        }
    }
    /// task that executes runTests
    Task runTestsTask(int testFactor=1,char[] rngState=null,int[] counterVal=null){
        auto closure=new RunTestsArgs(this,true,testFactor,rngState,counterVal);
        auto res=Task(testName,&closure.exec,TaskFlags.TaskSet);
        res.appendOnFinish(&incrNCombTest);
        return res;
    }
    /// test has the object as controller
    void willControlTest(SingleRTest test){
        if (subTests.find(test)==subTests.length){
            subTests~=test;
            test.testName=testName~"/"~test.testName;
            if (test.r is null){
                assert(r !is null,"random source not set"); // setting it here might introduce non determinism
                test.r=r.spawn();
            }
        }
    }
    /// test does not have anymore the object as controller
    void removeTest(SingleRTest test) {
        subTests.length=remove(subTests,test);
        if (find(test.testName,testName~"/")==0){
            test.testName=test.testName[(testName.length+1)..$];
        }
    }
    /// test is about to run its tests
    bool willRunTests(SingleRTest test){
        test.failureLog=this.failureLog;
        return testController.willRunTests(test);
    }
    /// test did run all its tests
    void didRunTests(SingleRTest test){
        synchronized(statLock){
            stat.nTests++;
            if (test.stat.failedTests>0){
                stat.failedTests++;
            } else if (test.stat.passedTests>0) {
                stat.passedTests++;
            } else {
                stat.skippedTests++;
            }
        }
        testController.didRunTests(test);
    }
    /// test will run a test
    bool willRunTest(SingleRTest test) {
        return testController.willRunTest(test);
    }
    /// test has skipped one test, should return werether the testing should continue
    bool testSkipped(SingleRTest test) {
        return testController.testSkipped(test);
    }
    /// test has passed one test, should return werether the testing should continue
    bool testPassed(SingleRTest test){
        return testController.testPassed(test);
    }
    /// test has failed one test, should return werether the testing should continue
    bool testFailed(SingleRTest test){
        synchronized(testController.writeLock()){
            test.failureLog(collectAppender(delegate void(CharSink s){
                dumperP(s)("test failed in collection`")(testName)("` created at `");
                dumperP(s)(sourceFile)(":")(sourceLine)("`\n");
            }));
        }
        return testController.testFailed(test);
    }
    bool isStopping(){
        return testController.isStopping;
    }
    Mutex writeLock(){ return testController.writeLock(); }
}

/// template that checks that the initialization arguments of testInit (checkInit and manualInit)
/// are compatible with the arguments of the test, and if not gives a nice error message
template checkTestInitArgs(S...){
    const validArgs=is(typeof(function(){S arg;mixin(completeInitStr!(S)(checkInit,manualInit));}));
    static if(!validArgs){
        pragma(msg,"invalid arguments to template testInit for the current context.");
        pragma(msg,"context (arguments to generate randomly for the test):"~S.stringof);
        pragma(msg,"checkInit=`"~checkInit~"`");
        pragma(msg,"manualInit=`"~manualInit~"`");
        pragma(msg,"and the resulting setup mixin is:`");
        pragma(msg,completeInitStr!(S)(checkInit,manualInit));
        pragma(msg,"`");
        pragma(msg,"actual error message should follow, but might be misleading, have wrong line number,...");
        pragma(msg,"-------------");
        // static assert(0,"stopping due to invalid arguments to testInit for current context");
    }
}

/// initializer for the tests.
/// This should be mixed in with a MixinIdentifier to have tests creating functions
/// in that context (often it should  be private) like this:
///     /// auto init using the generating functions available in this context
///     private mixin testInit!() autoInitT;
///     /// uses an int in [0;10) as first argument, automatic generation for the remaining
///     private mixin testInit!("","arg0=r.uniformR(10);") smallIntT;
/// then it gets used as follow:
///     autoInitT.testTrue("(2*x)%2==0",(int x){ return ((2*x)%2==0);},__LINE__,__FILE__).runTests();
///     smallIntT.testTrue("x*x<10",(int x){ return (x*x<100);},__LINE__,__FILE__).runTests();
/// checkInit can be used if the generation of the random configurations is mostly good,
///   but might contain some configurations that should be skipped. In check init one
///   should set the boolean variable "acceptable" to false if the configuration
///   should be skipped.
/// in manualInit you have the following variables:
///   arg0,arg1,... : variable of the first,second,... argument that you can initialize
///   arg0_i,arg0_i,... : index variable for combinatorial (extensive) coverage.
///     if you use it you probably want to initialize the next variable
///   arg0_nEl, arg1_nEl,...: variable that can be initialized to an int and defaults to -1 
///     abs(argI_nEl) gives the number of elements of argI_i, if argI_nEl>=0 then a purely
///     combinatorial generation is assumed, and does not set test.hasRandom to true for
///     this variable whereas if argI_nEl<0 a random component in the generation is assumed
///   acceptable: variable that can be set to false if the actual configuration should be skipped
///     (never set it unconditionally true)
template testInit(char[] checkInit="", char[] manualInit=""){
    
    /// creates a test that executes the given function and fails if it throws an exception
    SingleRTest testNoFail(S...)(char[] testName, void delegate(S) testF,long sourceLine=-1,
        char[] sourceFile="unknown",TestControllerI testController=null,
        TestSize testSize=TestSize(),CharSink failureLog=null,Rand r=null)
    {
        mixin checkTestInitArgs!(S);
        TestResult doTest(SingleRTest test){
            S arg;
            mixin(completeInitStr!(S)(checkInit,manualInit));
            if (!doSetup(test)){
                return TestResult.Skip;
            }
            try{
                test.baseDelegate.get!(void delegate(S))()(arg);
            } catch (SkipException s){
                return TestResult.Skip;
            } catch (Exception e){
                synchronized(test.testController.writeLock()){
                    test.failureLog(collectAppender(delegate void(void delegate(char[]) s){
                            dumperP(s)("test`")(test.testName)("` failed with exception\n"); }));
                    //test.failureLog.flush();
                    e.writeOut(test.failureLog);
                    //test.failureLog.flush();
                    mixin(printArgs(nArgs!(S),"test.failureLog"));
                }
                return TestResult.Fail;
            }
            return TestResult.Pass;
        }
        return new SingleRTest(testName,sourceLine,sourceFile,nArgs!(S),&doTest,
            testSize, testController, failureLog, r,Variant(testF));
    }
    /// ditto
    SingleRTest testNoFailF(S...)(char[] testName, void function(S) testF,long sourceLine=-1,
        char[] sourceFile="unknown",TestControllerI testController=null,
        TestSize testSize=TestSize(),CharSink failureLog=null,Rand r=null)
    {
        struct WrapF{
            void function(S) fun;
            void dlg(S arg){ this.fun(arg); }
        }
        auto dlg=new WrapF;
        dlg.fun=testF;
        return testNoFail(testName,&dlg.dlg,sourceLine,sourceFile,
            testController,testSize,failureLog,r);
    }
    
    /// creates a test that executes the given function and fails if no exception is raised
    SingleRTest testFail(S...)(char[] testName, void delegate(S) testF,long sourceLine=-1L,
        char[] sourceFile="unknown",TestControllerI testController=null,
        TestSize testSize=TestSize(),CharSink failureLog=null,Rand r=null)
    {
        mixin checkTestInitArgs!(S);
        TestResult doTest(SingleRTest test){
            S arg;
            mixin(completeInitStr!(S)(checkInit,manualInit));
            if (!doSetup(test)) return TestResult.Skip;
            try{
                test.baseDelegate.get!(void delegate(S))()(arg);
            } catch (SkipException s){
                return TestResult.Skip;
            } catch (Exception e){
                return TestResult.Pass;
            }
            synchronized(test.testController.writeLock){
                char[256] buf;
                auto arr=lGrowableArray!(char)(buf,0,GASharing.GlobalNoFree);
                dumperP(&arr)("test`")(test.testName)("` failed (no exception thrown and one expected)\n");
                test.failureLog(arr.takeData);
                //test.failureLog.flush();
                mixin(printArgs(nArgs!(S),"test.failureLog"));
            }
            return TestResult.Fail;
        }
        return new SingleRTest(testName,sourceLine,sourceFile,nArgs!(S),&doTest,
            testSize, testController, failureLog, r,Variant(testF));
    }
    /// ditto
    SingleRTest testFailF(S...)(char[] testName, void function(S) testF,long sourceLine=-1,
        char[] sourceFile="unknown",TestControllerI testController=null,
        TestSize testSize=TestSize(),CharSink failureLog=null,Rand r=null)
    {
        struct WrapF{
            void function(S) fun;
            void dlg(S arg){ this.fun(arg); }
        }
        auto dlg=new WrapF;
        dlg.fun=testF;
        return testFail(testName,&dlg.dlg,sourceLine,sourceFile,
            testController,testSize,failureLog,r);
    }
    
    /// creates a test that checks that the given function returns true
    SingleRTest testTrue(S...)(char[] testName, bool delegate(S) testF,long sourceLine=-1L,
        char[] sourceFile="unknown",TestControllerI testController=null,
        TestSize testSize=TestSize(),CharSink failureLog=null,Rand r=null)
    {
        mixin checkTestInitArgs!(S);
        TestResult doTest(SingleRTest test){
            S arg;
            mixin(completeInitStr!(S)(checkInit,manualInit));
            if (!doSetup(test)) return TestResult.Skip;
            try{
                bool callRes=test.baseDelegate.get!(bool delegate(S))()(arg);
                if (callRes){
                    return TestResult.Pass;
                } else {
                    synchronized(test.testController.writeLock){
                        char[256] buf;
                        auto arr=lGrowableArray!(char)(buf,0,GASharing.GlobalNoFree);
                        dumperP(&arr)("test`")(test.testName)("` failed (returned false instead of true)\n");
                        test.failureLog(arr.data);
                        mixin(printArgs(nArgs!(S),"test.failureLog"));
                    }
                    return TestResult.Fail;
                }
            } catch (SkipException s){
                return TestResult.Skip;
            } catch (Exception e){
                synchronized(test.testController.writeLock){
                    char[256] buf;
                    auto arr=lGrowableArray!(char)(buf,0,GASharing.GlobalNoFree);
                    test.failureLog(dumperP(&arr)("test`")(test.testName)("` failed with exception\n").call.data);
                    //test.failureLog.flush();
                    e.writeOut(test.failureLog);
                    //test.failureLog.flush();
                    mixin(printArgs(nArgs!(S),"test.failureLog"));
                }
                return TestResult.Fail;
            }
        }
        return new SingleRTest(testName,sourceLine,sourceFile,nArgs!(S),&doTest,
            testSize, testController, failureLog, r,Variant(testF));
    }
    /// ditto
    SingleRTest testTrueF(S...)(char[] testName, bool function(S) testF,long sourceLine=-1,
        char[] sourceFile="unknown",TestControllerI testController=null,
        TestSize testSize=TestSize(),CharSink failureLog=null,Rand r=null)
    {
        struct WrapF{
            bool function(S) fun;
            bool dlg(S arg){ return this.fun(arg); }
        }
        auto dlg=new WrapF;
        dlg.fun=testF;
        return testTrue(testName,&dlg.dlg,sourceLine,sourceFile,
            testController,testSize,failureLog,r);
    }

    /// creates a test that checks that the given function returns false
    SingleRTest testFalse(S...)(char[] testName, bool delegate(S) testF,long sourceLine=-1L,
        char[] sourceFile="unknown",TestControllerI testController=null,
        TestSize testSize=TestSize(),CharSink failureLog=null,Rand r=null)
    {
        mixin checkTestInitArgs!(S);
        int nargs=nArgs!(S);
        TestResult doTest(SingleRTest test){
            S arg;
            mixin(completeInitStr!(S)(checkInit,manualInit));
            if (!doSetup(test)) return TestResult.Skip;
            try{
                bool callRes=test.baseDelegate.get!(bool delegate(S))()(arg);
                if (callRes){
                    synchronized(test.testController.writeLock){
                        char[256] buf;
                        auto arr=lGrowableArray!(char)(buf,0,GASharing.GlobalNoFree);
                        dumperP(&arr)("test`")(test.testName)("` failed (returned true instead of false)\n");
                        test.failureLog(arr.data);
                        mixin(printArgs(nArgs!(S),"test.failureLog"));
                    }
                    return TestResult.Fail;
                } else {
                    return TestResult.Pass;
                }
            } catch (SkipException s){
                return TestResult.Skip;
            } catch (Exception e){
                synchronized(test.testController.writeLock){
                    //test.failureLog.flush();
                    char[256] buf;
                    auto arr=lGrowableArray!(char)(buf,0,GASharing.GlobalNoFree);
                    dumperP(&arr)("test`")(test.testName)("` unexpectedly failed with exception\n");
                    test.failureLog(arr.data);
                    //test.failureLog.flush();
                    e.writeOut(test.failureLog);
                    //test.failureLog.flush();
                    mixin(printArgs(nArgs!(S),"test.failureLog"));
                }
                return TestResult.Fail;
            }
        }
        return new SingleRTest(testName,sourceLine,sourceFile,nArgs!(S),&doTest,
            testSize, testController, failureLog, r,Variant(testF));
    }
    /// ditto
    SingleRTest testFalseF(S...)(char[] testName, bool function(S) testF,long sourceLine=-1,
        char[] sourceFile="unknown",TestControllerI testController=null,
        TestSize testSize=TestSize(),CharSink failureLog=null,Rand r=null)
    {
        struct WrapF{
            bool function(S) fun;
            bool dlg(S arg){ return this.fun(arg); }
        }
        auto dlg=new WrapF;
        dlg.fun=testF;
        return testFalse(testName,&dlg.dlg,sourceLine,sourceFile,
            testController,testSize,failureLog,r);
    }
}
