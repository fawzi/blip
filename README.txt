// this readme is taken from the comments in the source frm.rtest.RTest
= RTest
== RTest a random testing framework

A framework to quickly write tests that check property/functions using randomly
generated data or all combinations of some values.

I wrote this framework inspired by Haskell's Quickcheck, but the result is quite different.

At the moment it is only tango based.

The idea is to be able to write tests as quickly and as painlessly as possible.
Typical use would be for example:
You have a function that solves linear systems of equations, and you want to test it.
The matrix should be square, and the b vector should have the same size as the matrix dimension.
So either you define  an ad-hoc structure, or you write a custom generator for it
(it is quite unlikely that the constraint are satisfied just by chance and you would
spend all your time waiting for a valid test case).
Then (if detA>0) you can check that the solution really solves the system of equations 
with a small residual error.
Your test can fail in many ways also due to the internal checks of the equation solver,
and you want to  always have a nice report that lets you reproduce the problem.
Another typical use case is when you have a slow reference implementation for something
and a fast one, and you want to be sure they are the same.

For simplicity here we use really simple tests, in this case a possible use is:
{{{
    import frm.rtest.RTest;

    private mixin testInit!() autoInitTst; 

    void myTests(){
        // define a collection for my tests
        TestCollection myTests=new TestCollection("myTests",__LINE__,__FILE__);

        // define a test
        autoInitTst.testTrue("testName",functionToTest,__LINE__,__FILE__);
        // for example
        autoInitTst.testTrue("(2*x)%2==0",(int x){ return ((2*x)%2==0);},__LINE__,__FILE__);

        // run the tests
        myTests.runTests();
    }
}}}
If everything goes well not much should happen, because by default the printer does
not write successes.
You can change the default controller as follows:
{{{
    SingleRTest.defaultTestController=new TextController(
        TextController.OnFailure.StopTest,
        TextController.PrintLevel.AllShort,Stdout);
}}}
and it should write out something like
{{{
    test`testName`          failures-passes/totalTests(totalCombinatorialRuns)
}}}
i.e.:
{{{
    test`assert(x*x<100)`                 0-100/100(100)
    test`assert(x*x<100)`                 0- 56/100(100)
}}}
If one wants to run three times as many tests:
{{{
    myTests.runTests(3);
}}}
If a test fails then it will print out something like this
{{{
    test`(2*x)%4==0 || (2*x)%4==2` failed (returned false instead of true)
    arg0: -802454419

    To reproduce:
     intial rng state: CMWC000000003ade6df6_00000020_595a6207_2a7a7b53_e59a5471_492be655_75b9b464_f45bb6b8_c5af6b1d_1eb47eb9_ff49627d_fe4cecb1_fa196181_ab208cf5_cc398818_d75acbbc_92212c68_ceaff756_c47bf07b_c11af291_c1b66dc4_ac48aabe_462ec397_21bf4b7a_803338ab_c214db41_dc162ebe_41a762a8_7b914689_ba74dba0_d0e7fa35_7fb2df5a_3beb71fb_6dcee941_0000001f_2a9f30df_00000000_00000000
     counter: [0]
    ERROR test `(2*x)%4==0 || (2*x)%4==2` from `test.d:35` FAILED!!
    -----------------------------------------------------------
    test`(2*x)%4==0 || (2*x)%4==2`   1-  0/  1(  1)
}}}
from it you should see the arguments that made the test fail.
If you want to re-run it you can add .runTests(1,seed,counter) to it, i.e.:
{{{
autoInitTst.testTrue("(2*x)%4==0 || (2*x)%4==2 (should fail)",(int x){ return ((2*x)%4==0 || (2*x)%4==2);},
    __LINE__,__FILE__).runTests(1,"CMWC000000003ade6df6_00000020_595a6207_2a7a7b53_e59a5471_492be655_75b9b464_f45bb6b8_c5af6b1d_1eb47eb9_ff49627d_fe4cecb1_fa196181_ab208cf5_cc398818_d75acbbc_92212c68_ceaff756_c47bf07b_c11af291_c1b66dc4_ac48aabe_462ec397_21bf4b7a_803338ab_c214db41_dc162ebe_41a762a8_7b914689_ba74dba0_d0e7fa35_7fb2df5a_3beb71fb_6dcee941_0000001f_2a9f30df_00000000_00000000",[0])
}}}

If the default generator is not good enough you can create tests that use a custom generator like this:
{{{
    private mixin testInit!(checkInit,manualInit) customTst;
}}}
in manualInit you have the following variables:
  arg0,arg1,... : variable of the first,second,... argument that you can initialize
    (if you use it you are supposed to initialize it)
  arg0_i,arg1_i,... : index variable for combinatorial (extensive) coverage.
    if you use it you probably want to initialize the next variable
  arg0_nEl, arg1_nEl,...: variable that can be initialized to an int and defaults to -1 
    abs(argI_nEl) gives the number of elements of argI_i, if argI_nEl>=0 then a purely
    combinatorial generation is assumed, and does not set test.hasRandom to true for
    this variable whereas if argI_nEl<0 a random component in the generation is assumed
If the argument argI is not used in manualInit the default generation procedure
{{{
    Rand r=...;
    argI=generateRandom!(typeof(argI))(r,argI_i,argI_nEl,acceptable);
}}}
is used.
checkInit can be used if the generation of the random configurations is mostly good,
  but might contain some configurations that should be skipped. In checkInit one
  should set the boolean variable "acceptable" to false if the configuration
  should be skipped.

For example:
{{{
    private mixin testInit!("acceptable=(arg0%3!=0);","arg0=r.uniformR(10);") smallIntTst;
}}}
then gets used as follow:
{{{
    smallIntTst.testTrue("x*x<100",(int x){ return (x*x<100);},__LINE__,__FILE__).runTests();
}}}
by the way this is also a faster way to perform a test, as you can see you don't
need to define a collection (but probably it is a good idea to define one)

If you end up using custom generators much probably you should define a 
struct/class/typedef, and use that as input to your testing function and define
T generateRandom(T:YourType)(Rand r,int idx,ref int nEl, ref bool acceptable)
or implement the RandGen interface so that you can use the default automatic generation.
For a description of generateRandom and RandGen see the module frm.rtest.BasicGenerators.

enjoy

Fawzi Mohamed
