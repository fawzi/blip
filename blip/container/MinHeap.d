/// a minimum heap structure that can wait until a minimum is available
/// built on the top of tango Heap structure
//
// Copyright 2010 the blip developer group
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
module blip.container.MinHeap;
import tango.util.container.more.Heap;
import blip.parallel.smp.Wait;
import blip.serialization.Serialization;

/// multithread safe min heap
class MinHeapSync(T){
    MinHeap!(T) heap;
    WaitCondition nonEmpty;
    
    /// returns the internal data (heap)
    T[] data(){
        synchronized(this){
            return heap.data;
        }
    }
    /// sets the inernal data
    void data(T[] d){
        synchronized(this){
            heap.data(d);
        }
    }

    mixin(serializeSome("MinHeapSync!("~T.mangleof~")","data"));
    mixin printOut!();

    bool nonEmptyHeap(){
        return heap.length!=0;
    }
    
    this(){
        nonEmpty=new WaitCondition(&nonEmptyHeap);
    }
    void push(T[] t){
        synchronized(this){
            heap.push(t);
        }
        nonEmpty.checkCondition();
    }
    void push(T t){
        synchronized(this){
            heap.push(t);
        }
        nonEmpty.checkCondition();
    }
    T pop(){
        synchronized(this){
            return heap.pop();
        }
    }
    /// returns the minimal energy elements, waits if no elements is available until some becomese available
    T waitPop(){
        while (1){
            synchronized(this){
                if (heap.length>0)
                    return heap.pop();
            }
            nonEmpty.wait();
        }
    }
}
