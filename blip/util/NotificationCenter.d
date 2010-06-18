/// threadsafe Notification center
/// You might want to add the notify requests to a single thread, but it is not needed.
/// The callbacks that can be called when in process must be threadsafe.
/// The calling order of the callbacks is not defined (and changes from notification to notification)
///
/// author: Fawzi
/// license: Apache 2.0
module blip.util.NotificationCenter;
import blip.sync.Atomic;
import blip.t.core.Variant;
import blip.container.AtomicSLink;

struct Callback{
    enum Flags{
        None=0,
        Resubmit=1, /// resubmit
        ReceiveWhenInProcess=2, /// receive when a notification happens while processing the first one (callback has to be threadsafe)
        ReceiveAll=4, /// receive all notification (even if you are still waiting for the first to start executing, the callback should be threadsafe)
    }
    void delegate(char[],Callback*,Variant) callback;
    Callback *next;
    Flags flags;
    
    equals_t opEqual(ref Callback c){
        return callback==c.callback && flags==c.flags;
    }
    
    static Callback *freeList;
    static Callback *newCallback(void delegate(char[],Callback*,Variant) callback,
        Flags flags=Flags.None)
    {
        auto newC=popFrom(freeList);
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
    Callback *catchAll;
    Callback *dynCallbacks;
}

class NotificationCenter{
    CallbackList*[char[]] notificationLists;
    this(){}
    bool registerCallback(char[]name,void delegate(char[],Callback*,Variant) callback,
        Callback.Flags flags=Callback.Flags.None){
        return registerCallback(name,Callback.newCallback(callback,flags));
    }
    bool registerCallback(char[]name,Callback *callback){
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
        if ((callback.flags & Callback.Flags.ReceiveAll)!=0){
            insertAt(res.catchAll,callback);
            return true;
        } else {
            insertAt(res.dynCallbacks,callback);
            return true;
        }
    }
    void notify(char[]name,Variant args){
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
            auto pos=res.catchAll;
            while (pos !is null){
                pos.callback(name,pos,args);
                pos=pos.next;
            }
            pos=atomicSwap(res.dynCallbacks,cast(Callback *)null);
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
