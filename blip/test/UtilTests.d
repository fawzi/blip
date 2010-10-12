/// a collection of the tests in blip.util
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
module blip.test.UtilTests;
import blip.util.BinSearch;
import blip.core.Array;
import blip.rtest.RTest;
import blip.io.BasicIO;
import blip.container.GrowableArray;
import blip.util.NotificationCenter;
import blip.sync.Atomic;
import blip.parallel.smp.WorkManager;

void checkLb(T)(T[]arr,T val,size_t lb,size_t ub){
    auto lb1=lBound(arr,val,lb,ub);
    try{
        if (arr.length>0){
            assert(lb1>=lb);
            assert(lb1<=ub||ub<lb);
            if (lb1<ub){
                assert(arr[lb1]>=val);
            }
            if (lb1>lb){
                assert(arr[lb1-1]<val);
            }
        } else {
            assert(lb1==lb);
        }
    } catch(Exception e){
        throw new Exception(collectAppender(delegate void(CharSink s){
            dumper(s)(lb1)("=lBound(")(arr)(",")(val)(",")(lb)(",")(ub)(")");
        }),__FILE__,__LINE__,e);
    }
}


void checkUb(T)(T[]arr,T val,size_t lb,size_t ub){
    auto ub1=uBound(arr,val,lb,ub);
    try{
        if (arr.length>0){
            assert(ub1>=lb);
            assert(ub1<=ub||ub<lb);
            if (ub1<ub){
                assert(arr[ub1]>val);
            }
            if (ub1>lb){
                assert(arr[ub1-1]<=val);
            }
        } else {
            assert(ub1==lb);
        }
    } catch(Exception e){
        throw new Exception(collectAppender(delegate void(CharSink s){
            dumper(s)(ub1)("=uBound(")(arr)(",")(val)(",")(lb)(",")(ub)(")");
        }),__FILE__,__LINE__,e);
    }
}

void checkLbUb(T)(T[]arr,T val,size_t lb,size_t ub){
    checkLb!(uint)(arr,val,lb,ub);
    checkUb!(uint)(arr,val,lb,ub);
    checkLb!(uint)(arr,val,ub,lb);
    checkUb!(uint)(arr,val,ub,lb);
}

void testLUBounds(uint[]arr,uint maxVal,uint bound1,uint bound2){
    foreach(ref el;arr){
        el=el%maxVal;
    }
    sort(arr);
    auto lb=bound1%arr.length;
    if (arr.length>0){
        auto ub=bound2%arr.length+1;
        checkLbUb!(uint)(arr,arr[lb],lb,ub);
        checkLbUb!(uint)(arr,arr[lb]-1,lb,ub);
        checkLbUb!(uint)(arr,arr[lb]+1,lb,ub);
        checkLbUb!(uint)(arr,arr[$-1],lb,ub);
        checkLbUb!(uint)(arr,arr[$-1]-1,lb,ub);
        checkLbUb!(uint)(arr,arr[$-1]+1,lb,ub);
        checkLbUb!(uint)(arr,(arr[lb]+arr[$-1])/2,lb,ub);
    } else {
        checkLbUb!(uint)(arr,0,lb,lb);
        checkLbUb!(uint)(arr,1,lb,lb);
        checkLbUb!(uint)(arr,2,lb,lb);
    }
}

class Summer{
    int sum;
    LocalGrowableArray!(int) log;
    char[] name;
    void callBack(char[] n,Callback* cl,Variant v){
        assert(n==name);
        atomicAdd(sum,v.get!(int)());
        synchronized(this){
            log(v.get!(int)());
        }
    }
    this(char[]n){
        name=n;
    }
}
class DoNotify{
    int msg;
    char[] name;
    NotificationCenter nc;
    void doNotify(){
        nc.notify(name,Variant(msg));
    }
    this(NotificationCenter nc,char[] n,int m){
        this.nc=nc;
        name=n;
        msg=m;
    }
}

void testNotificationCenter(char[] notName,int[] notf){
    auto nc=new NotificationCenter();
    auto summer1=new Summer(notName);
    auto summer2=new Summer(notName);
    auto summer3=new Summer(notName);
    auto summer4=new Summer(notName);
    nc.registerCallback(notName,&summer1.callBack,Callback.Flags.None);
    nc.registerCallback(notName,&summer2.callBack,Callback.Flags.Resubmit);
    nc.registerCallback(notName,&summer3.callBack,Callback.Flags.Resubmit|Callback.Flags.ReceiveWhenInProcess);
    nc.registerCallback(notName,&summer4.callBack,Callback.Flags.ReceiveAll);
    int mySum=0;
    Task("notifyAll",delegate void(){
        for (size_t i=0;i<notf.length;++i){
            auto notifier=new DoNotify(nc,notName,notf[i]);
            Task("notify",&notifier.doNotify).autorelease.submit();
            mySum+=notf[i];
        }
    }).autorelease.executeNow();
    assert(summer4.sum==mySum);
    assert(summer4.log.length==notf.length);
    assert(summer3.log.length<=notf.length);
    assert(summer2.log.length<=notf.length);
    assert(summer1.log.length==1);
    assert(summer1.log[0]==summer1.sum);
}

/// all tests for util, as template so that they are not instantiated if not used
TestCollection utilTests()(TestCollection superColl=null){
    TestCollection coll=new TestCollection("util",__LINE__,__FILE__,superColl);
    
    autoInitTst.testNoFailF("testLUBounds",&testLUBounds,__LINE__,__FILE__,coll);
    autoInitTst.testNoFailF("testNotificationCenter",&testNotificationCenter,__LINE__,__FILE__,coll);
    return coll;
}
