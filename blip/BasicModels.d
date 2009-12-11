/*******************************************************************************
        copyright:      Copyright (c) 2009. Fawzi Mohamed
        license:        Apache 2.0
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.BasicModels;

/// interface of an object that can describe itself
interface BasicObjectI{
    void desc(void delegate(char[]) s);
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

/// forward iterator interface, and foreach support.
/// the two things cannot be mixed (begin to iterate,
/// then continue with foreach is not allowed)
interface FIteratorI(T): ForeachableI!(T){
    /// goes to the next element
    T next();
    /// true if the iterator is at the end
    bool atEnd();
    /// might make opApply parallel (if the work amount is larger than
    /// optimalChunkSize, tries to subdivide it in chunks of that size)
    ForeachableI!(T) parallelLoop(size_t optimalChunkSize);
    /// might make opApply parallel.
    ForeachableI!(T) parallelLoop();
}

