/**
 * cpuset defs
 * now with the opaque function defs take them from hwloc/cpuset.h,
 * doesn't use BitVector anymore... but offers somethig similar
 * build on the exported functions
 */
module blip.parallel.hwloc.cpuset;
version(noHwloc){} else {
import blip.t.stdc.config;
import blip.t.stdc.stringz;
/** \defgroup hwlocality_cpuset The Cpuset API
 *
 * For use in hwloc itself, a hwloc_cpuset_t represents a set of logical
 * processors.
 *
 * \note cpusets are indexed by OS logical processor number.
 * @{
 */


/** \brief
 * Set of CPUs
 */
struct hwloc_cpuset_t{
    void *data;
    
    static hwloc_cpuset_t alloc(){
        return hwloc_cpuset_alloc();
    }

    void free(){
        hwloc_cpuset_free(*this);
    }

    /** \brief Duplicate CPU set \p set by allocating a new CPU set and copying its contents */
    hwloc_cpuset_t dup(){
        return hwloc_cpuset_dup(*this);
    }

    /** \brief Copy the contents of CPU set \p src into the already allocated CPU set \p dst */
    hwloc_cpuset_t opSliceAssign(hwloc_cpuset_t src){
        hwloc_cpuset_copy(*this,src);
        return *this;
    }


    /*
     * Cpuset/String Conversion
     */

    /** \brief Stringify a cpuset.
     *
     * Up to \p buflen characters may be written in buffer \p buf.
     *
     * \return the number of character that were actually written if not truncating,
     * or that would have been written  (not including the ending \\0).
     */
    int snprintf(char[]s){
        return hwloc_cpuset_snprintf(s.ptr,s.length, *this);
    }
    
    /** \brief Stringify a cpuset into a newly allocated string.
     *
     * \return the number of character that were actually written
     * (not including the ending \\0).
     */
    char[] toString(){
        char *res;
        auto len=hwloc_cpuset_asprintf(&res, *this);
        return res[0..len];
    }

    /** \brief Parse a cpuset string.
     *
     * Must start and end with a digit.
     */
    hwloc_cpuset_t fromString(char[] s){
       return hwloc_cpuset_from_string(toStringz(s));
    }


    /** \brief
     *  Primitives & macros for building, modifying and consulting "sets" of cpus.
     */

    /** \brief Empty CPU set \p set */
    hwloc_cpuset_t zero(){
        hwloc_cpuset_zero(*this);
        return *this;
    }

    /** \brief Fill CPU set \p set */
    hwloc_cpuset_t fill(){
        hwloc_cpuset_fill(*this);
        return *this;
    }

    /** \brief Setup CPU set \p set from c_ulong \p mask */
    void hwloc_cpuset_from_ulong(hwloc_cpuset_t set, c_ulong mask);

    /** \brief Setup CPU set \p set from c_ulong \p mask used as \p i -th subset */
    void set_ith_ulong(int i,c_ulong mask){
        hwloc_cpuset_from_ith_ulong(*this,i,mask);
    }

    /** \brief Convert the \p i -th subset of CPU set \p set into c_ulong mask */
    c_ulong get_ith_ulong(int i){
        return hwloc_cpuset_to_ith_ulong(*this,i);
    }

    /** \brief sets the cpu i */
    void opIndexAssign(bool value,uint i){
        if (value){
            hwloc_cpuset_set(*this, i);
        } else {
            hwloc_cpuset_clr(*this,i);
        }
    }
    
    /// sets all the bits in i..j to the given value
    /// warning unlike the hwloc_cpuset_set_range the range excludes j
    void opIndexAssign(bool value,uint i,uint j){
        if (value){
            hwloc_cpuset_set_range(*this,i,j-1);
        } else {
            if (i<j){
                auto newC=alloc();
                hwloc_cpuset_set_range(newC,i,j-1);
                hwloc_cpuset_andnot(*this,*this,newC);
                newC.free();
            }
        }
    }

    /** \brief Test whether CPU \p cpu is part of set \p set */
    bool opIndex(uint i){
        return hwloc_cpuset_isset(*this,i)!=0;
    }
    
    /** \brief Test whether set \p set1 is equal to set \p set2 */
    equals_t opEqual(hwloc_cpuset_t s2){
        return hwloc_cpuset_isequal(*this,s2);
    }

    /** \brief Test whether sets \p set1 and \p set2 intersects */
    bool intersect(hwloc_cpuset_t s2){
        return hwloc_cpuset_intersects(*this,s2)!=0;
    }

    /** \brief Test whether set \p sub_set is part of set \p super_set */
    bool isincluded(hwloc_cpuset_t s2){
        return hwloc_cpuset_isincluded(*this,s2)!=0;
    }

    /** \brief Or set \p modifier_set into set \p set */
    hwloc_cpuset_t opOrAssign(hwloc_cpuset_t s2){
        hwloc_cpuset_or(*this,*this,s2);
        return *this;
    }

    /** \brief And set \p modifier_set into set \p set */
    hwloc_cpuset_t opAndAssign(hwloc_cpuset_t s2){
        hwloc_cpuset_and(*this,*this,s2);
        return *this;
    }

    /** \brief Clear set \p modifier_set out of set \p set */
    hwloc_cpuset_t andNot(hwloc_cpuset_t s2){
        hwloc_cpuset_andnot(*this,*this,s2);
        return *this;
    }

    /** \brief Xor set \p set with set \p modifier_set */
    hwloc_cpuset_t opXorAssign(hwloc_cpuset_t s2){
        hwloc_cpuset_xor(*this,*this,s2);
        return *this;
    }

    /** \brief Compute the first CPU (least significant bit) in CPU set \p set */
    int first(){
        return hwloc_cpuset_first(*this);
    }

    /** \brief Compute the last CPU (most significant bit) in CPU set \p set */
    int last(){
        return hwloc_cpuset_last(*this);
    }

    /** \brief Keep a single CPU among those set in CPU set \p set
     *
     * Might be used before binding so that the process does not
     * have a chance of migrating between multiple logical CPUs
     * in the original mask.
     *
     * MODIFIES the current object!
     */
    hwloc_cpuset_t singlify(){
        hwloc_cpuset_singlify(*this);
        return *this;
    }

    /** \brief Compar CPU sets \p set1 and \p set2 using their first set bit.
     *
     * Smaller least significant bit is smaller.
     * The empty CPU set is considered higher than anything.
     */
    int compare_first(hwloc_cpuset_t s2){
        return hwloc_cpuset_compare_first(*this,s2);
    }

    /** \brief Compar CPU sets \p set1 and \p set2 using their last bits.
     *
     * Higher most significant bit is higher.
     * The empty CPU set is considered lower than anything.
     */
    int opCmp(hwloc_cpuset_t s2){
        return hwloc_cpuset_compare(*this,s2);
    }

    /** \brief Compute the weight of CPU set \p set */
    int weight(){
        return hwloc_cpuset_weight(*this);
    }
    
}

extern(C):

/*
 * CPU set allocation, freeing and copying.
 */

/** \brief Allocate a new empty CPU set */
hwloc_cpuset_t hwloc_cpuset_alloc();

/** \brief Free CPU set \p set */
void hwloc_cpuset_free(hwloc_cpuset_t set);

/** \brief Duplicate CPU set \p set by allocating a new CPU set and copying its contents */
hwloc_cpuset_t hwloc_cpuset_dup(hwloc_cpuset_t set);

/** \brief Copy the contents of CPU set \p src into the already allocated CPU set \p dst */
void hwloc_cpuset_copy(hwloc_cpuset_t dst, hwloc_cpuset_t src);


/*
 * Cpuset/String Conversion
 */

/** \brief Stringify a cpuset.
 *
 * Up to \p buflen characters may be written in buffer \p buf.
 *
 * \return the number of character that were actually written if not truncating,
 * or that would have been written  (not including the ending \\0).
 */
int hwloc_cpuset_snprintf(char * buf, size_t buflen, hwloc_cpuset_t set);

/** \brief Stringify a cpuset into a newly allocated string.
 *
 * \return the number of character that were actually written
 * (not including the ending \\0).
 */
int hwloc_cpuset_asprintf(char ** strp, hwloc_cpuset_t set);

/** \brief Parse a cpuset string.
 *
 * Must start and end with a digit.
 */
hwloc_cpuset_t hwloc_cpuset_from_string(char * string);


/** \brief
 *  Primitives & macros for building, modifying and consulting "sets" of cpus.
 */

/** \brief Empty CPU set \p set */
void hwloc_cpuset_zero(hwloc_cpuset_t set);

/** \brief Fill CPU set \p set */
void hwloc_cpuset_fill(hwloc_cpuset_t set);

/** \brief Setup CPU set \p set from c_ulong \p mask */
void hwloc_cpuset_from_ulong(hwloc_cpuset_t set, c_ulong mask);

/** \brief Setup CPU set \p set from c_ulong \p mask used as \p i -th subset */
void hwloc_cpuset_from_ith_ulong(hwloc_cpuset_t set, int i, c_ulong mask);

/** \brief Convert the beginning part of CPU set \p set into c_ulong \p mask */
c_ulong hwloc_cpuset_to_ulong(hwloc_cpuset_t set);

/** \brief Convert the \p i -th subset of CPU set \p set into c_ulong mask */
c_ulong hwloc_cpuset_to_ith_ulong(hwloc_cpuset_t set, int i);

/** \brief Clear CPU set \p set and set CPU \p cpu */
void hwloc_cpuset_cpu(hwloc_cpuset_t set, uint cpu);

/** \brief Clear CPU set \p set and set all but the CPU \p cpu */
void hwloc_cpuset_all_but_cpu(hwloc_cpuset_t set, uint cpu);

/** \brief Add CPU \p cpu in CPU set \p set */
void hwloc_cpuset_set(hwloc_cpuset_t set, uint cpu);

/** \brief Add CPUs from \p begincpu to \p endcpu in CPU set \p set */
void hwloc_cpuset_set_range(hwloc_cpuset_t set, uint begincpu, uint endcpu);

/** \brief Remove CPU \p cpu from CPU set \p set */
void hwloc_cpuset_clr(hwloc_cpuset_t set, uint cpu);

/** \brief Remove CPUs from \p begincpu to \p endcpu in CPU set \p set */
void hwloc_cpuset_clr_range(hwloc_cpuset_t set, uint begincpu, uint endcpu);

/** \brief Test whether CPU \p cpu is part of set \p set */
int hwloc_cpuset_isset(hwloc_cpuset_t set, uint cpu);

/** \brief Test whether set \p set is zero */
int hwloc_cpuset_iszero(hwloc_cpuset_t set);

/** \brief Test whether set \p set is full */
int hwloc_cpuset_isfull(hwloc_cpuset_t set);

/** \brief Test whether set \p set1 is equal to set \p set2 */
int hwloc_cpuset_isequal (hwloc_cpuset_t set1, hwloc_cpuset_t set2);

/** \brief Test whether sets \p set1 and \p set2 intersects */
int hwloc_cpuset_intersects (hwloc_cpuset_t set1, hwloc_cpuset_t set2);

/** \brief Test whether set \p sub_set is part of set \p super_set */
int hwloc_cpuset_isincluded (hwloc_cpuset_t sub_set, hwloc_cpuset_t super_set);

/** \brief Or sets \p set1 and \p set2 and store the result in set \p res */
void hwloc_cpuset_or (hwloc_cpuset_t res, hwloc_cpuset_t set1, hwloc_cpuset_t set2);

/** \brief And sets \p set1 and \p set2 and store the result in set \p res */
void hwloc_cpuset_and (hwloc_cpuset_t res, hwloc_cpuset_t set1, hwloc_cpuset_t set2);

/** \brief And set \p set1 and the negation of \p set2 and store the result in set \p res */
void hwloc_cpuset_andnot (hwloc_cpuset_t res, hwloc_cpuset_t set1, hwloc_cpuset_t set2);

/** \brief Xor sets \p set1 and \p set2 and store the result in set \p res */
void hwloc_cpuset_xor (hwloc_cpuset_t res, hwloc_cpuset_t set1, hwloc_cpuset_t set2);

/** \brief Negate set \p set and store the result in set \p res */
void hwloc_cpuset_not (hwloc_cpuset_t res, hwloc_cpuset_t set);

/** \brief Compute the first CPU (least significant bit) in CPU set \p set */
int hwloc_cpuset_first(hwloc_cpuset_t set);

/** \brief Compute the last CPU (most significant bit) in CPU set \p set */
int hwloc_cpuset_last(hwloc_cpuset_t set);

/** \brief Keep a single CPU among those set in CPU set \p set
 *
 * Might be used before binding so that the process does not
 * have a chance of migrating between multiple logical CPUs
 * in the original mask.
 */
void hwloc_cpuset_singlify(hwloc_cpuset_t set);

/** \brief Compar CPU sets \p set1 and \p set2 using their first set bit.
 *
 * Smaller least significant bit is smaller.
 * The empty CPU set is considered higher than anything.
 */
int hwloc_cpuset_compare_first(hwloc_cpuset_t set1, hwloc_cpuset_t set2);

/** \brief Compar CPU sets \p set1 and \p set2 using their last bits.
 *
 * Higher most significant bit is higher.
 * The empty CPU set is considered lower than anything.
 */
int hwloc_cpuset_compare(hwloc_cpuset_t set1, hwloc_cpuset_t set2);

/** \brief Compute the weight of CPU set \p set */
int hwloc_cpuset_weight(hwloc_cpuset_t set);
}
