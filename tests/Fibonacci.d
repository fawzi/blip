/// a test of the performace of the library using the fibonacci function
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
module Fibonacci;
import blip.parallel.smp.WorkManager;
import blip.time.RealtimeClock;
import blip.io.BasicIO;
import blip.io.Console;
import blip.container.GrowableArray;
import Integer=tango.text.convert.Integer;
import blip.Comp;

long fib(long n){
    auto tAtt=taskAtt;
    if (n<2) return 1;
    long f1;
    long f2;
    Task("f1",delegate void(){ f1=fib(n-1); }).autorelease.submitYield();
    Task("f2",delegate void(){ f2=fib(n-2); }).autorelease.submit();
    (cast(Task)cast(Object)tAtt).finishSubtasks();
    return f1+f2;
}

void testFib(long n){
    for (int ii=0;ii<2;++ii){
        auto t0=realtimeClock();
        auto res=fib(n);
        auto t1=realtimeClock();
        sout("fib(")(n)(")=")(res)(" time=")((t1-t0)*realtimeClockPeriod())("\n");
    }
}
int main(string [] args){
    long n=15;
    if (args.length>1){
        n=Integer.toInt(args[1]);
    }
    Task("testFib",delegate void(){ testFib(n); }).autorelease.executeNow();
    return 0;
}
