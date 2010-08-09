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
import blip.parallel.smp.Wait;
import blip.serialization.Serialization;

/**
  *
  * Copyright:  Copyright (C) 2008 Chris Wright.  All rights reserved.
  * License:    BSD style: $(LICENSE)
  * Version:    Oct 2008: Initial release
  * Author:     Chris Wright, aka dhasenan
  *
  */
private import tango.core.Exception;

bool minHeapCompare(T)(T a, T b) {return a <= b;}
bool maxHeapCompare(T)(T a, T b) {return a >= b;}
void defaultHeapSwap(T)(T t, uint index) {}

/** A heap is a data structure where you can insert items in random order and extract them in sorted order. 
  * Pushing an element into the heap takes O(lg n) and popping the top of the heap takes O(lg n). Heaps are 
  * thus popular for sorting, among other things.
  * 
  * No opApply is provided, since most people would expect this to return the contents in sorted order,
  * not do significant heap allocation, not modify the collection, and complete in linear time. This
  * combination is not possible with a heap. 
  *
  * Note: always pass by reference when modifying a heap. 
  *
  * The template arguments to the heap are:
  *     T       = the element type
  *     Compare = a function called when ordering elements. Its signature should be bool(T, T).
  *               see minHeapCompare() and maxHeapCompare() for examples.
  *     Move    = a function called when swapping elements. Its signature should be void(T, uint).
  *               The default does nothing, and should suffice for most users. You 
  *               probably want to keep this function small; it's called O(log N) 
  *               times per insertion or removal.
*/

struct Heap (T, alias Compare = minHeapCompare!(T), alias Move = defaultHeapSwap!(T))
{
        alias pop       remove;
        alias push      opCatAssign;

        // The actual data.
        private T[]     heap;
        
        // The index of the cell into which the next element will go.
        private uint    next;
        
        /// returns the heaped data
        T[] data(){
            return heap[0..next];
        }
        /// sets the heap data (must be a valid heap)
        void data(T[] newData){
            heap[0..next]=T.init;
            if (heap.length<newData.length){
                heap.length=newData.length;
            }
            heap[0..newData.length]=newData;
        }
        size_t length(){
            return next;
        }

        /** Inserts the given element into the heap. */
        void push (T t)
        {
                auto index = next++;
                while (heap.length <= index)
                       heap.length = 2 * heap.length + 32;

                heap [index] = t;
                Move (t, index);
                fixup (index);
        }

        /** Inserts all elements in the given array into the heap. */
        void push (T[] array)
        {
                if (heap.length < next + array.length)
                        heap.length = next + array.length + 32;

                foreach (t; array) push (t);
        }

        /** Removes the top of this heap and returns it. */
        T pop ()
        {
                return removeAt (0);
        }

        /** Remove the every instance that matches the given item. */
        void removeAll (T t)
        {
                // TODO: this is slower than it could be.
                // I am reasonably certain we can do the O(n) scan, but I want to
                // look at it a bit more.
                while (remove (t)) {}
        }

        /** Remove the first instance that matches the given item. 
          * Returns: true iff the item was found, otherwise false. */
        bool remove (T t)
        {
                foreach (i, a; heap)
                {
                        if (a is t || a == t)
                        {
                                removeAt (i);
                                return true;
                        }
                }
                return false;
        }

        /** Remove the element at the given index from the heap.
          * The index is according to the heap's internal layout; you are 
          * responsible for making sure the index is correct.
          * The heap invariant is maintained. */
        T removeAt (uint index)
        {
                if (next <= index)
                {
                        throw new NoSuchElementException ("Heap :: tried to remove an"
                                ~ " element with index greater than the size of the heap "
                                ~ "(did you call pop() from an empty heap?)");
                }
                next--;
                auto t = heap[index];
                // if next == index, then we have nothing valid on the heap
                // so popping does nothing but change the length
                // the other calls are irrelevant, but we surely don't want to
                // call Move with invalid data
                if (next > index)
                {
                        heap[index] = heap[next];
                        Move(heap[index], index);
                        fixdown(index);

                        // added via ticket 1885 (kudos to wolfwood)
                        if (heap[index] is heap[next])
                            fixup(index);
                }
                return t;
        }

        /** Gets the value at the top of the heap without removing it. */
        T peek ()
        {
                assert (next > 0);
                return heap[0];
        }

        /** Returns the number of elements in this heap. */
        uint size ()
        {
                return next;
        }

        /** Reset this heap. */
        void clear ()
        {
                next = 0;
        }

        /** reset this heap, and use the provided host for value elements */
        void clear (T[] host)
        {
                this.heap = host;
                clear;
        }

        /** Get the reserved capacity of this heap. */
        uint capacity ()
        {
                return heap.length;
        }

        /** Reserve enough space in this heap for value elements. The reserved space is truncated or extended as necessary. If the value is less than the number of elements already in the heap, throw an exception. */
        uint capacity (uint value)
        {
                if (value < next)
                {
                        throw new IllegalArgumentException ("Heap :: illegal truncation");
                }
                heap.length = value;
                return value;
        }

        /** Return a shallow copy of this heap. */
        Heap clone ()
        {
                Heap other;
                other.heap = this.heap.dup;
                other.next = this.next;
                return other;
        }

        // Get the index of the parent for the element at the given index.
        private uint parent (uint index)
        {
                return (index - 1) / 2;
        }

        // Having just inserted, restore the heap invariant (that a node's value is greater than its children)
        private void fixup (uint index)
        {
                if (index == 0) return;
                uint par = parent (index);
                if (!Compare(heap[par], heap[index]))
                {
                        swap (par, index);
                        fixup (par);
                }
        }

        // Having just removed and replaced the top of the heap with the last inserted element,
        // restore the heap invariant.
        private void fixdown (uint index)
        {
                uint left = 2 * index + 1;
                uint down;
                if (left >= next)
                {
                        return;
                }

                if (left == next - 1)
                {
                        down = left;
                }
                else if (Compare (heap[left], heap[left + 1]))
                {
                        down = left;
                }
                else
                {
                        down = left + 1;
                }

                if (!Compare(heap[index], heap[down]))
                {
                        swap (index, down);
                        fixdown (down);
                }
        }

        // Swap two elements in the array.
        private void swap (uint a, uint b)
        {
                auto t1 = heap[a];
                auto t2 = heap[b];
                heap[a] = t2;
                Move(t2, a);
                heap[b] = t1;
                Move(t1, b);
        }
}


/** A minheap implementation. This will have the smallest item as the top of the heap. 
  *
  * Note: always pass by reference when modifying a heap. 
  *
*/

template MinHeap(T)
{
        alias Heap!(T, minHeapCompare) MinHeap;
}

/** A maxheap implementation. This will have the largest item as the top of the heap. 
  *
  * Note: always pass by reference when modifying a heap. 
  *
*/

template MaxHeap(T)
{
        alias Heap!(T, maxHeapCompare) MaxHeap;
}

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
    T popWait(){
        while (1){
            synchronized(this){
                if (heap.length>0)
                    return heap.pop();
            }
            nonEmpty.wait();
        }
    }
}
