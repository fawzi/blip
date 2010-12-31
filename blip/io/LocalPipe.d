/// a local pipe object
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
module blip.io.LocalPipe;
import blip.io.BasicIO;
import blip.parallel.smp.Wait;

class LocalPipe{
    ubyte[] buf;
    size_t pos;
    size_t length;
    bool writeStopped;
    bool readStopped;
    WaitCondition waitMoreData;
    WaitCondition waitReadSome;
    
    enum{ minBlock=16 }
    
    bool hasSomeData(){
        return length>0 || writeStopped;
    }
    
    bool hasSomeSpace(){
        return length+minBlock<buf.length || readStopped;
    }
    
    this(ubyte[] buf){
        this.buf=buf;
        if (buf.length<2*minBlock) throw new Exception("buf is too small",__FILE__,__LINE__);
        waitMoreData=new WaitCondition(&this.hasSomeData);
        waitReadSome=new WaitCondition(&this.hasSomeSpace);
    }
    
    void rawWrite(void[] data){
        scope(exit) waitMoreData.checkCondition();
        while(data.length>0){
            assert(!writeStopped);
            bool shouldWait=false;
            synchronized(this){
                auto toWrite=buf.length-length;
                if (toWrite>0){
                    if (toWrite>data.length) toWrite=data.length;
                    auto pAtt=pos+length;
                    if (pAtt<buf.length){
                        if (buf.length-pAtt<toWrite) toWrite=buf.length-pAtt;
                        buf[pAtt..pAtt+toWrite]=cast(ubyte[])(data[0..toWrite]);
                    } else {
                        pAtt-=buf.length;
                        buf[pAtt..toWrite]=cast(ubyte[])(data[0..toWrite]);
                    }
                    length+=toWrite;
                    data=data[toWrite..$];
                } else {
                    shouldWait=true;
                    if (readStopped) throw new BIOException("write to pipe with closed read end",__FILE__,__LINE__);
                }
            }
            if (shouldWait) waitReadSome.wait();
        }
    }
    
    size_t readSome(void[] data){
        scope(exit) waitReadSome.checkCondition();
        while (true){
            assert(!readStopped);
            bool shouldWait=false;
            synchronized(this){
                if (length>0){
                    auto toRead=length;
                    if (data.length<toRead) toRead=data.length;
                    auto firstRead=buf.length-pos;
                    if (toRead<firstRead) firstRead=toRead;
                    data[0..firstRead]=buf[pos..pos+firstRead];
                    if (firstRead<toRead){
                        data[firstRead..toRead]=buf[0..toRead-firstRead];
                    }
                    return toRead;
                } else {
                    if (writeStopped) return Eof;
                    shouldWait=true;
                }
            }
            if (shouldWait) waitMoreData.wait();
        }
    }
    void rawReadExact(void[] data){
        readExact(&readSome,data);
    }
    void flush(){}
    /// closes the writing
    void close(){
        writeStopped=true;
    }
    /// shutdown the read
    void shutdownInput(){
        readStopped=true;
    }
}

