/*******************************************************************************
    A module to perform random tests
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module frm.rtest.RTestFramework;
import frm.random.Random: RandomG;
import frm.random.engines.CMWC: CMWC_32_1;
public import frm.TemplateFu: nArgs,ctfe_i2a,ctfe_hasToken, ctfe_replaceToken;
public import tango.io.Print:Print;
import tango.io.Stdout: Stdout;
public import tango.core.Variant: Variant;
import tango.core.Array: find,remove;

// a reasonably collision free, fast and small (seedwise) rng
alias RandomG!(CMWC_32_1) Rand;

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
            res~=indent1~"static assert(is(typeof(generateRandom!(S["~ctfe_i2a(i)~"])(new Rand(),arg0_i,arg0_nEl,acceptable))),\n";
            res~=indent1~"    \""~T.stringof~" cannot be automatically generated, missing T generateRandom(T:"~T.stringof~")(Rand r,int idx,ref int nEl, ref bool acceptable) or RandGen interface.\");\n";
            res~=indent1~"arg["~ctfe_i2a(i)~"]"~"=generateRandom!(S["~ctfe_i2a(i)~"])(r,arg"~
                ctfe_i2a(i)~"_i,arg"~ctfe_i2a(i)~"_nEl,acceptable);\n";
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
char[] printArgs(int nargs,char[] printC="Stdout",char[] indent="    "){
    char[] res="".dup;
    res~=indent~"try{\n";
    for (int i=0;i<nargs;++i){
        res~=indent~"    "~printC~"(\"arg"~ctfe_i2a(i)~": \")(arg["~ctfe_i2a(i)~"]).newline;\n";
    }
    res~=indent~"}catch (Exception e) {\n";
    res~=indent~"    test.failureLog(\"could not print arguments due to exception\")(e).newline;\n";
    res~=indent~"};\n";
    return res;
}

enum TestResult : int{
    Pass=1,
    Skip=0,
    Fail=-1,
}

/// a test controller that writes out text to the given Print!(char) stream
class TextController: TestControllerI{
    Print!(char) log;
    bool isStopping;
    enum PrintLevel:int{ Error, Skip, AllShort, AllVerbose}
    PrintLevel printLevel;
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
        Print!(char) log=Stdout,int testFactor=1){
        this.log=log;
        this.onFailure=onFailure;
        this.isStopping=false;
        this.printLevel=printLevel;
        assert(testFactor>0,"testFactor must be positive");
        this.testFactor=testFactor;
    }
    /// test has the object as controller
    void willControlTest(SingleRTest test) { }
    /// test does not have anymore the object as controller
    void removeTest(SingleRTest test) { }
    /// test is about to run its tests
    bool willRunTests(SingleRTest test) {
        test.failureLog=log;
        test.testSize.nCombTestMax=test.testSize.nCombTestMax*testFactor;
        test.testSize.nSetupMax=test.testSize.nSetupMax*testFactor;
        test.testSize.budgetMax=test.testSize.budgetMax*testFactor;
        if (printLevel==PrintLevel.AllVerbose) log.format("{,-20} ",test.testName)();
        return !isStopping;
    }
    /// test did run all its tests
    void didRunTests(SingleRTest test) {
        bool shouldPrint=printLevel==PrintLevel.AllShort || printLevel==PrintLevel.AllVerbose ||
            test.stat.failedTests>0 || test.stat.passedTests==0 ||
            (printLevel==PrintLevel.Skip && test.stat.skippedTests>0);
        if (shouldPrint) {
            if (printLevel!=PrintLevel.AllVerbose || test.stat.failedTests>0)
                log.format("test`{,-50}",test.testName~"`");
            log.format(" {,3}-{,3}/{,3}({,3})",test.stat.failedTests,
                test.stat.passedTests,test.stat.nTests,test.stat.nCombTest).newline;
        }
        test.testSize.nCombTestMax=test.testSize.nCombTestMax/testFactor;
        test.testSize.nSetupMax=test.testSize.nSetupMax/testFactor;
        test.testSize.budgetMax=test.testSize.budgetMax/testFactor;
    }
    /// test will run a test
    bool willRunTest(SingleRTest test) {
        if (printLevel==PrintLevel.AllVerbose) log(".")();
        return !isStopping;
    }
    /// test has skipped one test, should return wether the testing should continue
    bool testSkipped(SingleRTest test) {
        if (printLevel==PrintLevel.AllVerbose) log("-")();
        return !isStopping;
    }
    /// test has passed one test, should return wether the testing should continue
    bool testPassed(SingleRTest test) {
        if (printLevel==PrintLevel.AllVerbose) log("+")();
        return !isStopping;
    }
    /// test has failed one test, should return wether the testing should continue
    bool testFailed(SingleRTest test){
        log.newline;
        log("To reproduce:\n intial rng state: ")(test.initialState).newline;
        log(" counter: [");
        foreach (i,c;test.counter){
            if (i!=0) log(", ");
            log(c);
        }
        log("]").newline;
        log("ERROR test `")(test.testName)("` from `")(test.sourceFile)(":")(test.sourceLine)("` FAILED!!").newline;
        log("-----------------------------------------------------------").newline;
        log.flush; // guaratee flush on file log
        switch (onFailure){
        case OnFailure.StopTest:
            return false;
        case OnFailure.Throw:
            throw new Exception("test failure");
        case OnFailure.StopAllTests:
            this.isStopping=true;
            break;
        case OnFailure.Continue:
            break;
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
            _testController.willControlTest(this);
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
    Print!(char) failureLog; /// place to log failure description (if available)
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
        assert(testFactor>0,"testFactor should be positive");
        scope(exit) testController.didRunTests(this);
        if (!testController.willRunTests(this)) return this;
        budgetLeft=testSize.budgetMax*testFactor;
        if (r is null) r=new Rand();
        if (failureLog is null) failureLog=Stdout; // use Stderr ?
        if (rngState !is null){
            r.fromString(rngState);
        }
        if (counterVal !is null){
            counter[]=counterVal;
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
        
    /// constructor
    this(char[]testName,long sourceLine,char[]sourceFile,
        int nargs,TestResult delegate(SingleRTest) testDlg,
        TestSize testSize=TestSize(),TestControllerI testController=null,
        Print!(char)failureLog=null, Rand r=null, Variant baseDelegate=Variant(null)){
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
        reset;
        this.baseDelegate=baseDelegate;
        this.testController=testController;
    }
}

class TestCollection: SingleRTest, TestControllerI {
    /// the tests in this collection
    SingleRTest[] subTests;
    /// constructor
    this(char[]testName,long sourceLine,char[]sourceFile,TestControllerI testController=null,
        SingleRTest[] subTests=[],Print!(char)failureLog=null, Rand r=null)
    {
        super(testName,sourceLine,sourceFile,1,null,TestSize(1,1,1.5), testController,
            failureLog, r, Variant(null));
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
    // runs the tests possibly restarting them with the given rngState/counterVal
    SingleRTest runTests(int testFactor=1,char[] rngState=null,int[] counterVal=null){
        assert(testFactor>0,"testFactor should be positive");
        scope(exit) testController.didRunTests(this);
        if (!testController.willRunTests(this)) return this;
        budgetLeft=testSize.budgetMax;
        if (r is null) r=new Rand();
        if (failureLog is null) failureLog=Stdout; // use Stderr ?
        if (rngState !is null){
            r.fromString(rngState);
        }
        if (counterVal !is null){
            counter[]=counterVal;
        }
        foreach (t;subTests){
            t.runTests(testFactor);
        }
        stat.nCombTest++;
        return this;
    }
    /// test has the object as controller
    void willControlTest(SingleRTest test){
        if (subTests.find(test)==subTests.length){
            subTests~=test;
            test.testName=testName~"/"~test.testName;
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
        test.r=this.r;
        test.failureLog=this.failureLog;
        return testController.willRunTests(test);
    }
    /// test did run all its tests
    void didRunTests(SingleRTest test){
        stat.nTests++;
        if (test.stat.failedTests>0){
            stat.failedTests++;
        } else if (test.stat.passedTests>0) {
            stat.passedTests++;
        } else {
            stat.skippedTests++;
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
        test.failureLog.format("test failed in collection`{}` created at `{}:{}`",testName,sourceFile,sourceLine).newline;
        return testController.testFailed(test);
    }
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
        char[] sourceFile="unknown",TestSize testSize=TestSize(),
        TestControllerI testController=null,Print!(char)failureLog=null,Rand r=null)
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
            }catch (Exception e){
                test.failureLog("test`")(test.testName)("` failed with exception").newline;
                test.failureLog(e).newline;
                mixin(printArgs(nArgs!(S),"test.failureLog"));
                return TestResult.Fail;
            }
            return TestResult.Pass;
        }
        return new SingleRTest(testName,sourceLine,sourceFile,nArgs!(S),&doTest,
            testSize, testController, failureLog, r,Variant(testF));
    }
    
    /// creates a test that executes the given function and fails if no exception is raised
    SingleRTest testFail(S...)(char[] testName, void delegate(S) testF,long sourceLine=-1L,
        char[] sourceFile="unknown",TestSize testSize=TestSize(),
        TestControllerI testController=null,Print!(char)failureLog=null,Rand r=null)
    {
        mixin checkTestInitArgs!(S);
        TestResult doTest(SingleRTest test){
            S arg;
            mixin(completeInitStr!(S)(checkInit,manualInit));
            if (!doSetup(test)) return TestResult.Skip;
            try{
                test.baseDelegate.get!(void delegate(S))()(arg);
            }catch (Exception e){
                return TestResult.Pass;
            }
            test.failureLog("test`")(test.testName)("` failed (no exception thrown and one expected)").newline;
            mixin(printArgs(nArgs!(S),"test.failureLog"));
            return TestResult.Fail;
        }
        return new SingleRTest(testName,sourceLine,sourceFile,nArgs!(S),&doTest,
            testSize, testController, failureLog, r,Variant(testF));
    }
    
    /// creates a test that checks that the given function returns true
    SingleRTest testTrue(S...)(char[] testName, bool delegate(S) testF,long sourceLine=-1L,
        char[] sourceFile="unknown",TestSize testSize=TestSize(),
        TestControllerI testController=null,Print!(char)failureLog=null,Rand r=null)
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
                    test.failureLog("test`")(test.testName)("` failed (returned false instead of true)").newline;
                    mixin(printArgs(nArgs!(S),"test.failureLog"));
                    return TestResult.Fail;
                }
            }catch (Exception e){
                test.failureLog("test`")(test.testName)("` failed with exception").newline;
                test.failureLog(e).newline;
                mixin(printArgs(nArgs!(S),"test.failureLog"));
                return TestResult.Fail;
            }
        }
        return new SingleRTest(testName,sourceLine,sourceFile,nArgs!(S),&doTest,
            testSize, testController, failureLog, r,Variant(testF));
    }

    /// creates a test that checks that the given function returns false
    SingleRTest testFalse(S...)(char[] testName, bool delegate(S) testF,long sourceLine=-1L,
        char[] sourceFile="unknown",TestSize testSize=TestSize(),
        TestControllerI testController=null,Print!(char)failureLog=null,Rand r=null)
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
                    test.failureLog("test`")(test.testName)("` failed (returned true instead of false)").newline;
                    mixin(printArgs(nArgs!(S),"test.failureLog"));
                    return TestResult.Fail;
                } else {
                    return TestResult.Pass;
                }
            }catch (Exception e){
                test.failureLog("test`")(test.testName)("` unexpectedly failed with exception").newline;
                test.failureLog(e).newline;
                mixin(printArgs(nArgs!(S),"test.failureLog"));
                return TestResult.Fail;
            }
        }
        return new SingleRTest(testName,sourceLine,sourceFile,nArgs!(S),&doTest,
            testSize, testController, failureLog, r,Variant(testF));
    }
}

