/// a test of the performace of the library with a data parallel load
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
module Gauss;
import blip.parallel.smp.WorkManager;
import blip.time.RealtimeClock;
import blip.io.BasicIO;
import blip.io.Console;
import blip.container.GrowableArray;
import Integer=tango.text.convert.Integer;
import blip.math.random.Random;
import blip.parallel.smp.PLoopHelpers;
import blip.math.Math;
import blip.Comp;

class Gauss{
    double[] alpha,r,res;
    size_t blockSize;
    this(size_t n,size_t blockSize=100){
        alpha=new double[](n);
        r=new double[](3*n);
        res=new double[](n);
        this.blockSize=blockSize;
    }
    
    void randomize(Random rand){
        auto d=rand.uniformRD(2.0);
        foreach(ref a;alpha){
            d(a);
        }
        auto d2=rand.uniformR2D(-2.0,2.0);
        foreach(ref rr;r){
            d2(rr);
        }
    }
    
    void calc(){
        foreach(i,ref resAtt;pLoopArray(res,blockSize)){
            auto ii=3*i;
            resAtt=exp(-alpha[i]*(r[ii]*r[ii]+r[ii+1]*r[ii+1]+r[ii+2]*r[ii+2]));
        }
    }
}

int main(string [] args){
    size_t n=10000;
    if (args.length>1){
        n=Integer.toInt(args[1]);
    }
    size_t bSize=100;
    if (args.length>2){
        bSize=Integer.toInt(args[2]);
    }
    auto r=new Random();
    auto g=new Gauss(n,bSize);
    g.randomize(r);
    for (int ii=0;ii<2;++ii){
        auto t0=realtimeClock();
        g.calc();
        auto t1=realtimeClock();
        sout("gauss(")(n)(",")(bSize)("), time=")((t1-t0)*realtimeClockPeriod())("\n");
    }
    return 0;
}
