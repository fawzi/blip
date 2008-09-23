/*******************************************************************************
    module that creates a test executable.
    
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module test;
import blip.narray.BasicTypes;
import tango.io.Stdout;
import blip.rtest.RTest;
import blip.narray.NArray;
import blip.narray.Test;
import blip.random.Random: rand;
import blip.narray.Convolve;
import blip.TemplateFu;

private mixin testInit!() autoInitTst2;

void main(){
    debug(UnitTest){
        // change this to true to track bugs that crash or stop the program without throwing an exception
        alias int T;
        const int rank=3;
        bool trace=true;
        rand.fromString("SyncCMWC+KISS99000000003ade6df6_00000020_1e3fd537_3c2d7cb7_734a9009_c40d3cc2_ad9fb396_704f0bf2_65d20925_cb086536_d934cada_c267b569_de935bca_22437a44_1bcd0539_ed357c90_b1b5efea_c1a48458_4d9d2b70_16926e83_8236196c_1ff3477b_9fc05479_b272c573_0faac6da_9e79be1f_aba9c273_22570946_9bb952ed_9154b378_4b810aa4_70082cce_5f375044_cbe0bfc4_00000000_3aa3c60d_00000000_00000000_ed37286a_ff13d5bd_0062bbf9_07e63bec");
        Stdout(rand.toString()).newline;
        SingleRTest.defaultTestController=new TextController(//TextController.OnFailure.StopAllTests,
            TextController.OnFailure.StopTest,
            TextController.PrintLevel.AllShort,Stdout,Stdout,1,trace);
        doNArrayTests(10);
    } else {
        Stdout("You need -debug=UnitTest to perform the tests").newline;
    }
}
