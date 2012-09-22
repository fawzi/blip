/// threadsafe Notification center
/// You might want to add the notify requests to a single thread, but it is not needed.
/// The callbacks that can be called when in process must be threadsafe.
/// The calling order of the callbacks is not defined (and changes from notification to notification)
/// The interface might seem ugly (for example no simple way to remove a notification), but
/// it ensures thread safety, try to respect it.
///
/// author: Fawzi
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
module blip.util.NotificationCenter;
import blip.sync.Atomic;
import blip.core.Variant;
import blip.container.AtomicSLink;
import blip.Comp;

struct Callback{
    enum Flags{
        None=0,
        Resubmit=1, /// resubmit
        ReceiveWhenInProcess=2, /// receive when a notification happens while processing the first one (callback has to be threadsafe)
        ReceiveAll=7, /// receive all notification (even if you are still waiting for the first to start executing, the callback should be threadsafe)
    }
    void delegate(string,Callback*,Variant) callback;
    Callback *next;
    Flags flags;
    
    equals_t opEqual(ref Callback c){
        return callback==c.callback && flags==c.flags;
    }
    
    shared static Callback *freeList;
    static Callback *newCallback(void delegate(string,Callback*,Variant) callback,
        Flags flags=Flags.None)
    {
        auto newC=cast(Callback*)popFrom(freeList);
        if (newC is null) {
            newC=new Callback;
        }
        newC.callback=callback;
        newC.flags=flags;
        newC.next=null;
        return newC;
    }
    static void giveBack(Callback* cb){
        cb.callback=null;
        cb.flags=Flags.None;
        insertAt(freeList,cb);
    }
}
struct CallbackList{
    shared Callback *catchAll;
    shared Callback *dynCallbacks;
}

class NotificationCenter{
    CallbackList*[string ] notificationLists;
    this(){}
    /// unregisters a "ReceiveAll" callback (other callbacks can be removed by removing the resubmit flag, which will drop them at the next notification)
    /// use the Resubmit flag also for ReceiveAll callbacks?
    bool unregisterReceiveAllCallback(string name,Callback*cb){
        synchronized(this){
            auto res2=name in notificationLists;
            if (res2 is null) return false;
            auto lst=&((*res2).catchAll);
            while((*lst)!is null && (*cast(Callback**)lst)!is cb){
                lst= &((*lst).next);
            }
            if ((*cast(Callback**)lst)is cb){
                *lst=cast(shared Callback*)cb.next;
                return true;
            }
        }
        return false;
    }
    Callback * registerCallback(string name,void delegate(string,Callback*,Variant) callback,
        Callback.Flags flags=Callback.Flags.None){
        auto res=Callback.newCallback(callback,flags);
        if (registerCallback(name,res)){
            return res;
        } else {
            return null;
        }
    }
    bool registerCallback(string name,Callback *callback){
        CallbackList*res;
        synchronized(this){
            auto res2=name in notificationLists;
            if (res2 is null){
                res=new CallbackList;
                notificationLists[name]=res;
            } else {
                res=*res2;
            }
        }
        if ((callback.flags & Callback.Flags.ReceiveAll)==Callback.Flags.ReceiveAll){
            insertAt(res.catchAll,callback);
            return true;
        } else {
            insertAt(res.dynCallbacks,callback);
            return true;
        }
    }
    void notify(string name,Variant args){
        CallbackList*res;
        synchronized(this){
            auto res2=name in notificationLists;
            if (res2 is null){
                res=null;
            } else {
                res=*res2; // we synchronize it because if we are really unlucky reallocation might happen before dereferencing
            }
        }
        if (res !is null){
            auto pos=cast(Callback *)res.catchAll;
            while (pos !is null){
                pos.callback(name,pos,args);
                pos=pos.next;
            }
            pos=atomicSwap!(Callback*,Callback*)(res.dynCallbacks,cast(Callback *)null);
            while (pos !is null){
                auto pNext=pos.next;
                auto didResub=false;
                if ((pos.flags&Callback.Flags.Resubmit)!=0 &&
                    (pos.flags&Callback.Flags.ReceiveWhenInProcess)!=0){
                    didResub=true;
                    insertAt(res.dynCallbacks,pos);
                }
                pos.callback(name,pos,args);
                if ((pos.flags&Callback.Flags.Resubmit)!=0 && !didResub){
                    insertAt(res.dynCallbacks,pos);
                }
                pos=pNext;
            }
        }
    }
}
