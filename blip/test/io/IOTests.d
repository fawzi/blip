/// tests of the i/o package
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
module blip.test.io.IOTests;
import blip.io.LocalPipe;
import blip.math.random.Random;
import blip.parallel.smp.Smp;
import blip.io.BasicIO;
import blip.io.EventWatcher;
import blip.rtest.RTest;

class LocalPipeTester{
    ubyte[] data;
    uint[] slicesIn;
    uint[] slicesOut;
    LocalPipe pipe;
    RandomSync rand;
    Exception exception;
    
    this(ubyte[] data,uint[] slicesIn,uint[] slicesOut,ubyte[] buf,RandomSync rand=null){
        this.data=data;
        this.slicesIn=slicesIn;
        this.slicesOut=slicesOut;
        this.rand=rand;
        this.pipe=new LocalPipe(buf);
        if (this.rand is null) this.rand=new RandomSync();
    }
    
    void adder(){
        try{
            uint pos=0;
            foreach(s;slicesOut){
                uint posNext=pos+cast(uint)(s%data.length);
                if (posNext>data.length) posNext=cast(uint)data.length;
                pipe.rawWrite(data[pos..posNext]);
                noToutWatcher.sleepTask(rand.uniformR2(0.0,1.0)*0.001);
                pos=posNext;
            }
            if (pos<data.length){
                pipe.rawWrite(data[pos..$]);
            }
            pipe.close();
        } catch(Exception e){
            exception=new Exception("adder failed",__FILE__,__LINE__,e);
        }
    }
    void reader(){
        try{
            ubyte[] readData=new ubyte[](data.length);
            uint pos=0;
            foreach(s;slicesIn){
                uint posNext=pos+cast(uint)(s%data.length);
                if (posNext>data.length) posNext=cast(uint)data.length;
                pipe.rawReadExact(readData[pos..posNext]);
                noToutWatcher.sleepTask(rand.uniformR2(0.0,1.0)*0.001);
                pos=posNext;
            }
            if (pos<data.length){
                pipe.rawReadExact(readData[pos..$]);
            }
            pipe.shutdownInput();
            if (readData!=data){
                throw new Exception("read data is unexpected",__FILE__,__LINE__);
            }
        } catch(Exception e){
            if (exception is null)
                exception=new Exception("reader failed",__FILE__,__LINE__,e);
        }
    }
    void doTests(){
        Task("testLocalPipe.adder",&this.adder).autorelease.submit();
        Task("testLocalPipe.reader",&this.reader).autorelease.submit();
    }
}
void testLocalPipe(ubyte[]data,uint[]slicesIn,uint[]slicesOut){
    ubyte[32] buf;
    auto tester=new LocalPipeTester(data,slicesIn,slicesOut,buf);
    Task("testLocalPipe",&tester.doTests).autorelease.executeNow();
}

/// all tests for io, as template so that they are not instantiated if not used
TestCollection ioTests()(TestCollection superColl=null){
    TestCollection coll=new TestCollection("io",__LINE__,__FILE__,superColl);
    
    autoInitTst.testNoFailF("testLocalPipe",&testLocalPipe,__LINE__,__FILE__,coll);
    return coll;
}
