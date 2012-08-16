/// basic models defining some useful interfaces
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
module blip.BasicModels;
import blip.Comp;

/// type of a loop
// these values cannot be changed easily, as they have many hidden dependencies as:
// - dchem.sys.PIndexes.KindRange
// - dchem.sys.SegmentedArray
// - dchem.neigh.HierarchicalSort
enum LoopType{
    Sequential=0,
    Parallel=1,
}

/// interface of an object that can describe itself
interface BasicObjectI{
    void desc(void delegate(cstring) s);
}

/// basic interface for objects that can be copied (shallowly)
interface DuplicableI{
    DuplicableI dup();
}

/// basic interface for objects that can be copied (deeply)
interface DeepDuplicableI{
    DeepDuplicableI deepdup();
}

/// basic copiable objects
interface CopiableObjectI : BasicObjectI,DuplicableI,DeepDuplicableI { }

/// object that can do a foreach loop
interface ForeachableI(T){
    static if (is(T U:U*)){
        /// loop without index, has to be implemented
        int opApply(int delegate(ref U x) dlg);
        /// loop with index, migh not be implemented (and throw)
        int opApply(int delegate(ref size_t i,ref U x) dlg);
    } else {
        /// loop without index, has to be implemented
        int opApply(int delegate(ref T x) dlg);
        /// loop with index, migh not be implemented (and throw)
        int opApply(int delegate(ref size_t i,ref T x) dlg);
    }
}

/// simple iterator
interface SimpleIteratorI(T): ForeachableI!(T){
    /// goes to the next element
    bool next(ref T);
}

/// forward iterator interface, and (parallel)foreach support.
/// the two things cannot be mixed (begin to iterate,
/// then continue with opApply/foreach is not allowed 
/// unless specifically noted)
interface FIteratorI(T): SimpleIteratorI!(T){
    /// might make opApply parallel (if the work amount is larger than
    /// optimalChunkSize, tries to subdivide it in chunks of that size)
    ForeachableI!(T) parallelLoop(size_t optimalChunkSize);
    /// might make opApply parallel.
    ForeachableI!(T) parallelLoop();
}

/// implements an empty iterator
class EmptyFIterator(T):FIteratorI!(T){
    bool next(ref T){ return false; }
    static if (is(T U:U*)){
        int opApply(int delegate(ref U x) dlg) { return 0; }
        int opApply(int delegate(ref size_t i,ref U x) dlg) { return 0; }
    } else {
        int opApply(int delegate(ref T x) dlg) { return 0; }
        int opApply(int delegate(ref size_t i,ref T x) dlg) { return 0; }
    }
    ForeachableI!(T) parallelLoop(size_t optimalChunkSize){ return this; }
    ForeachableI!(T) parallelLoop() { return this; }
    __gshared static EmptyFIterator instance;
    shared static this(){ instance=new EmptyFIterator; }
}

/// template to mixin opApply based on a next operation
template opApplyFromNext(T){
    static if(is(T U:U*)){
        /// loop without index
        int opApply(int delegate(ref U x) loopBody){
            T el;
            while(next(el)){
                if (auto res=loopBody(*el)) return res;
            }
            return 0;
        }
        /// loop with index
        int opApply(int delegate(ref size_t i,ref U x) dlg){
            T el;
            size_t counter=0;
            while(next(el)){
                if (auto res=loopBody(counter,*el)) return res;
                ++counter;
            }
            return 0;
        }
    } else {
        /// loop without index
        int opApply(int delegate(ref T x) loopBody){
            T el;
            while(next(el)){
                if (auto res=loopBody(el)) return res;
            }
            return 0;
        }
        /// loop with index
        int opApply(int delegate(ref size_t i,ref T x) loopBody){
            T el;
            size_t counter=0;
            while(next(el)){
                if (auto res=loopBody(counter,el)) return res;
                ++counter;
            }
            return 0;
        }
    }
}

/+ 
// overloading not working with all compilers yet

/// template to mixin opApply based on a next operation
template opApplyCounterFromNext(T){
    static if(is(T U:U*)){
        /// loop with index
        int opApply(int delegate(ref size_t i,ref U x) dlg){
            T el;
            size_t counter=0;
            while(next(el)){
                if (auto res=loopBody(counter,*el)) return res;
                ++counter;
            }
            return 0;
        }
    } else {
        /// loop with index
        int opApply(int delegate(ref size_t i,ref T x) dlg){
            T el;
            size_t counter=0;
            while(next(el)){
                if (auto res=loopBody(counter,el)) return res;
                ++counter;
            }
            return 0;
        }
    }
}

/// template to mixin opApply based on a next operation
template opApplyCounterFromOpApply(T){
    static if(is(T U:U*)){
        /// loop with index
        int opApply(int delegate(ref size_t i,ref U x) dlg){
            size_t counter=0;
            auto inBody=delegate int(ref U x){
                if (auto res=loopBody(counter,*x)) return res;
                ++counter;
                return 0;
            }
            return opApply(inBody);
        }
    } else {
        /// loop with index
        int opApply(int delegate(ref size_t i,ref T x) dlg){
            size_t counter=0;
            auto inBody=delegate int(ref T x){
                if (auto res=loopBody(counter,x)) return res;
                ++counter;
                return 0;
            }
            return opApply(inBody);
        }
    }
}
+/
