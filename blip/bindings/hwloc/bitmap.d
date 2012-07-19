/// cpuset defs
/// now with the opaque function defs take them from hwloc/cpuset.h,
/// doesn't use BitVector anymore... but offers somethig similar
/// built on the exported functions
/// as it is quite close to the header probably counts a derived work from code
/// released under the BSD license by INRIA.
/// author: fawzi
// Copyright © 2009 CNRS, INRIA, Université Bordeaux 1, 2009-2010 the blip developer group
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
module blip.bindings.hwloc.bitmap;
version(noHwloc){} else {
import blip.stdc.config;
import blip.stdc.stringz;
import stdlib=blip.stdc.stdlib;
import blip.Comp;
/** \defgroup hwlocality_bitmap The Bitmap API
 *
 * For use in hwloc itself, a hwloc_bitmap_t represents a set of logical
 * processors.
 *
 * \note bitmaps are indexed by OS logical processor number.
 * @{
 */


/** \brief
 * Set of CPUs
 */
struct hwloc_bitmap_t{
    void *data;
    
    static hwloc_bitmap_t alloc(){
        return hwloc_bitmap_alloc();
    }

    void free(){
        hwloc_bitmap_free(*this);
    }

    /** \brief Duplicate CPU set \p set by allocating a new CPU set and copying its contents */
    hwloc_bitmap_t dup(){
        return hwloc_bitmap_dup(*this);
    }

    /** \brief Copy the contents of CPU set \p src into the already allocated CPU set \p dst */
    hwloc_bitmap_t opSliceAssign(hwloc_bitmap_t src){
        hwloc_bitmap_copy(*this,src);
        return *this;
    }


    /*
     * Bitmap/String Conversion
     */

    /** \brief Stringify a bitmap.
     *
     * Up to \p buflen characters may be written in buffer \p buf.
     *
     * \return the number of character that were actually written if not truncating,
     * or that would have been written  (not including the ending \\0).
     */
    int snprintf(char[] s){
        return hwloc_bitmap_snprintf(cast(char*)s.ptr,cast(size_t)s.length, *this);
    }
    
    string toString(){
        char *res;
        auto len=hwloc_bitmap_asprintf(&res, *this);
        auto s=res[0..len].dup;
	stdlib.free(res);
	return s;
    }

    /** \brief Parse a bitmap string.
     *
     * Must start and end with a digit.
     */
    int fromString(cstring s){
      int nRead=hwloc_bitmap_sscanf(*this,toStringz(s));
      return nRead;
    }

    /** \brief Stringify a bitmap in the list format.
    *
    * Lists are comma-separated indexes or ranges.
    * Ranges are dash separated indexes.
    * The last range may not have a ending indexes if the bitmap is infinite.
    *
    * Up to \p buflen characters may be written in buffer \p buf.
    *
    * If \p buflen is 0, \p buf may safely be \c NULL.
    *
    * \return the number of character that were actually written if not truncating,
    * or that would have been written (not including the ending \\0).
    */
    int listSprintf(char[] s){
    	return hwloc_bitmap_list_snprintf(s.ptr, s.length, *this);
    }

    /** \brief Stringify a bitmap into a newly allocated list string.
     */
    cstring listString(){
        char *res;
        auto len = hwloc_bitmap_list_asprintf(&res, *this);
	auto s=res[0..len].dup;
	stdlib.free(res);
	return s;
    }

    /** \brief Parse a list string and stores it in bitmap \p bitmap.
     */
    int fromListString(cstring s){
	return hwloc_bitmap_list_sscanf(*this, toStringz(s));
    }

    /** \brief
     *  Primitives & macros for building, modifying and consulting "sets" of cpus.
     */

    /** \brief Empty CPU set \p set */
    hwloc_bitmap_t zero(){
        hwloc_bitmap_zero(*this);
        return *this;
    }

    /** \brief Fill CPU set \p set */
    hwloc_bitmap_t fill(){
        hwloc_bitmap_fill(*this);
        return *this;
    }

    /** \brief Setup CPU set \p set from c_ulong \p mask */
    void bitmap_from_ulong(c_ulong mask){
        hwloc_bitmap_from_ulong(*this,mask);
    }

    /** \brief Setup CPU set \p set from c_ulong \p mask used as \p i -th subset */
    void set_ith_ulong(int i,c_ulong mask){
        hwloc_bitmap_from_ith_ulong(*this,i,mask);
    }

    /** \brief Convert the \p i -th subset of CPU set \p set into c_ulong mask */
    c_ulong get_ith_ulong(int i){
        return hwloc_bitmap_to_ith_ulong(*this,i);
    }

    /** \brief sets the cpu i */
    void opIndexAssign(bool value,uint i){
        if (value){
            hwloc_bitmap_set(*this, i);
        } else {
            hwloc_bitmap_clr(*this,i);
        }
    }
    
    /// sets all the bits in i..j to the given value
    /// warning unlike the hwloc_bitmap_set_range the range excludes j
    void opIndexAssign(bool value,uint i,uint j){
        if (value){
            hwloc_bitmap_set_range(*this,i,j-1);
        } else {
            if (i<j){
                auto newC=alloc();
                hwloc_bitmap_set_range(newC,i,j-1);
                hwloc_bitmap_andnot(*this,*this,newC);
                newC.free();
            }
        }
    }

    /** \brief Test whether CPU \p cpu is part of set \p set */
    bool opIndex(uint i){
        return hwloc_bitmap_isset(*this,i)!=0;
    }
    
    /** \brief Test whether set \p set1 is equal to set \p set2 */
    equals_t opEqual(hwloc_bitmap_t s2){
        return hwloc_bitmap_isequal(*this,s2);
    }

    /** \brief Test whether sets \p set1 and \p set2 intersects */
    bool intersect(hwloc_bitmap_t s2){
        return hwloc_bitmap_intersects(*this,s2)!=0;
    }

    /** \brief Test whether set \p sub_set is part of set \p super_set */
    bool isincluded(hwloc_bitmap_t s2){
        return hwloc_bitmap_isincluded(*this,s2)!=0;
    }

    /** \brief Or set \p modifier_set into set \p set */
    hwloc_bitmap_t opOrAssign(hwloc_bitmap_t s2){
        hwloc_bitmap_or(*this,*this,s2);
        return *this;
    }

    /** \brief And set \p modifier_set into set \p set */
    hwloc_bitmap_t opAndAssign(hwloc_bitmap_t s2){
        hwloc_bitmap_and(*this,*this,s2);
        return *this;
    }

    /** \brief Clear set \p modifier_set out of set \p set */
    hwloc_bitmap_t andNot(hwloc_bitmap_t s2){
        hwloc_bitmap_andnot(*this,*this,s2);
        return *this;
    }

    /** \brief Xor set \p set with set \p modifier_set */
    hwloc_bitmap_t opXorAssign(hwloc_bitmap_t s2){
        hwloc_bitmap_xor(*this,*this,s2);
        return *this;
    }

    /** \brief Compute the first CPU (least significant bit) in CPU set \p set */
    int first(){
        return hwloc_bitmap_first(*this);
    }

    /** \brief Compute the last CPU (most significant bit) in CPU set \p set */
    int last(){
        return hwloc_bitmap_last(*this);
    }

    /** \brief Keep a single CPU among those set in CPU set \p set
     *
     * Might be used before binding so that the process does not
     * have a chance of migrating between multiple logical CPUs
     * in the original mask.
     *
     * MODIFIES the current object!
     */
    hwloc_bitmap_t singlify(){
        hwloc_bitmap_singlify(*this);
        return *this;
    }

    /** \brief Compar CPU sets \p set1 and \p set2 using their first set bit.
     *
     * Smaller least significant bit is smaller.
     * The empty CPU set is considered higher than anything.
     */
    int compare_first(hwloc_bitmap_t s2){
        return hwloc_bitmap_compare_first(*this,s2);
    }

    /** \brief Compar CPU sets \p set1 and \p set2 using their last bits.
     *
     * Higher most significant bit is higher.
     * The empty CPU set is considered lower than anything.
     */
    int opCmp(hwloc_bitmap_t s2){
        return hwloc_bitmap_compare(*this,s2);
    }

    /** \brief Compute the weight of CPU set \p set */
    int weight(){
        return hwloc_bitmap_weight(*this);
    }
    
}

alias hwloc_bitmap_t hwloc_const_bitmap_t;

extern(C):

/*
 * CPU set allocation, freeing and copying.
 */

/** \brief Allocate a new empty CPU set */
hwloc_bitmap_t hwloc_bitmap_alloc();

/** \brief Free CPU set \p set */
void hwloc_bitmap_free(hwloc_bitmap_t set);

/** \brief Duplicate CPU set \p set by allocating a new CPU set and copying its contents */
hwloc_bitmap_t hwloc_bitmap_dup(hwloc_bitmap_t set);

/** \brief Copy the contents of CPU set \p src into the already allocated CPU set \p dst */
void hwloc_bitmap_copy(hwloc_bitmap_t dst, hwloc_bitmap_t src);


/*
 * Bitmap/String Conversion
 */

/** \brief Stringify a bitmap.
 *
 * Up to \p buflen characters may be written in buffer \p buf.
 *
 * \return the number of character that were actually written if not truncating,
 * or that would have been written  (not including the ending \\0).
 */
int hwloc_bitmap_snprintf(char * buf, size_t buflen, hwloc_bitmap_t set);

/** \brief Stringify a bitmap into a newly allocated string.
 *
 * \return the number of character that were actually written
 * (not including the ending \\0).
 */
int hwloc_bitmap_asprintf(char ** strp, hwloc_bitmap_t set);

/** \brief Parse a bitmap string.
 *
 * Must start and end with a digit.
 */
int hwloc_bitmap_sscanf(hwloc_bitmap_t,char * string);

/** \brief Stringify a bitmap in the list format.
 *
 * Lists are comma-separated indexes or ranges.
 * Ranges are dash separated indexes.
 * The last range may not have a ending indexes if the bitmap is infinite.
 *
 * Up to \p buflen characters may be written in buffer \p buf.
 *
 * If \p buflen is 0, \p buf may safely be \c NULL.
 *
 * \return the number of character that were actually written if not truncating,
 * or that would have been written (not including the ending \\0).
 */
int hwloc_bitmap_list_snprintf(char *buf, size_t buflen, hwloc_const_bitmap_t bitmap);

/** \brief Stringify a bitmap into a newly allocated list string.
 */
int hwloc_bitmap_list_asprintf(char ** strp, hwloc_const_bitmap_t bitmap);

/** \brief Parse a list string and stores it in bitmap \p bitmap.
 */
int hwloc_bitmap_list_sscanf(hwloc_bitmap_t bitmap, char *string);


/** \brief
 *  Primitives & macros for building, modifying and consulting "sets" of cpus.
 */

/** \brief Empty CPU set \p set */
void hwloc_bitmap_zero(hwloc_bitmap_t set);

/** \brief Fill CPU set \p set */
void hwloc_bitmap_fill(hwloc_bitmap_t set);

/** \brief Setup CPU set \p set from c_ulong \p mask */
void hwloc_bitmap_from_ulong(hwloc_bitmap_t set, c_ulong mask);

/** \brief Setup CPU set \p set from c_ulong \p mask used as \p i -th subset */
void hwloc_bitmap_from_ith_ulong(hwloc_bitmap_t set, int i, c_ulong mask);

/** \brief Convert the beginning part of CPU set \p set into c_ulong \p mask */
c_ulong hwloc_bitmap_to_ulong(hwloc_bitmap_t set);

/** \brief Convert the \p i -th subset of CPU set \p set into c_ulong mask */
c_ulong hwloc_bitmap_to_ith_ulong(hwloc_bitmap_t set, int i);

/** \brief Clear CPU set \p set and set CPU \p cpu */
void hwloc_bitmap_only(hwloc_bitmap_t set, uint cpu);

/** \brief Clear CPU set \p set and set all but the CPU \p cpu */
void hwloc_bitmap_allbut(hwloc_bitmap_t set, uint cpu);

/** \brief Add CPU \p cpu in CPU set \p set */
void hwloc_bitmap_set(hwloc_bitmap_t set, uint cpu);

/** \brief Add CPUs from \p begincpu to \p endcpu in CPU set \p set */
void hwloc_bitmap_set_range(hwloc_bitmap_t set, uint begincpu, uint endcpu);

/** \brief Remove CPU \p cpu from CPU set \p set */
void hwloc_bitmap_clr(hwloc_bitmap_t set, uint cpu);

/** \brief Remove CPUs from \p begincpu to \p endcpu in CPU set \p set */
void hwloc_bitmap_clr_range(hwloc_bitmap_t set, uint begincpu, uint endcpu);

/** \brief Test whether CPU \p cpu is part of set \p set */
int hwloc_bitmap_isset(hwloc_bitmap_t set, uint cpu);

/** \brief Test whether set \p set is zero */
int hwloc_bitmap_iszero(hwloc_bitmap_t set);

/** \brief Test whether set \p set is full */
int hwloc_bitmap_isfull(hwloc_bitmap_t set);

/** \brief Test whether set \p set1 is equal to set \p set2 */
int hwloc_bitmap_isequal (hwloc_bitmap_t set1, hwloc_bitmap_t set2);

/** \brief Test whether sets \p set1 and \p set2 intersects */
int hwloc_bitmap_intersects (hwloc_bitmap_t set1, hwloc_bitmap_t set2);

/** \brief Test whether set \p sub_set is part of set \p super_set */
int hwloc_bitmap_isincluded (hwloc_bitmap_t sub_set, hwloc_bitmap_t super_set);

/** \brief Or sets \p set1 and \p set2 and store the result in set \p res */
void hwloc_bitmap_or (hwloc_bitmap_t res, hwloc_bitmap_t set1, hwloc_bitmap_t set2);

/** \brief And sets \p set1 and \p set2 and store the result in set \p res */
void hwloc_bitmap_and (hwloc_bitmap_t res, hwloc_bitmap_t set1, hwloc_bitmap_t set2);

/** \brief And set \p set1 and the negation of \p set2 and store the result in set \p res */
void hwloc_bitmap_andnot (hwloc_bitmap_t res, hwloc_bitmap_t set1, hwloc_bitmap_t set2);

/** \brief Xor sets \p set1 and \p set2 and store the result in set \p res */
void hwloc_bitmap_xor (hwloc_bitmap_t res, hwloc_bitmap_t set1, hwloc_bitmap_t set2);

/** \brief Negate set \p set and store the result in set \p res */
void hwloc_bitmap_not (hwloc_bitmap_t res, hwloc_bitmap_t set);

/** \brief Compute the first CPU (least significant bit) in CPU set \p set */
int hwloc_bitmap_first(hwloc_bitmap_t set);

/** \brief Compute the last CPU (most significant bit) in CPU set \p set */
int hwloc_bitmap_last(hwloc_bitmap_t set);

/** \brief Keep a single CPU among those set in CPU set \p set
 *
 * Might be used before binding so that the process does not
 * have a chance of migrating between multiple logical CPUs
 * in the original mask.
 */
void hwloc_bitmap_singlify(hwloc_bitmap_t set);

/** \brief Compar CPU sets \p set1 and \p set2 using their first set bit.
 *
 * Smaller least significant bit is smaller.
 * The empty CPU set is considered higher than anything.
 */
int hwloc_bitmap_compare_first(hwloc_bitmap_t set1, hwloc_bitmap_t set2);

/** \brief Compar CPU sets \p set1 and \p set2 using their last bits.
 *
 * Higher most significant bit is higher.
 * The empty CPU set is considered lower than anything.
 */
int hwloc_bitmap_compare(hwloc_bitmap_t set1, hwloc_bitmap_t set2);

/** \brief Compute the weight of CPU set \p set */
int hwloc_bitmap_weight(hwloc_bitmap_t set);
}
