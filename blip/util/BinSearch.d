/// module with binary search utilities. Works on any indexable ordered structure
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
module blip.util.BinSearch;


/// returns if t<u, using < or a comparing op x.opCmp and an element or a bool lessThan predicate
/// be careful that the predicate for the right side cannot be used on the left side and viceversa 
/// (!(a<b)) <==> a>=b <=/=> b<a
bool lessThan(T,U)(T t,U u){
    static if (is(typeof(t(u))==bool)){
        return t(u);
    } else static if (is(typeof(t(u)<0))){
        return t(u)<0;
    } else static if (is(typeof(u(t))==bool)){
        return u(t);
    } else static if (is(typeof(u(t)>0))){
        return u(t)>0;
    } else {
        return t<u;
    }
}

/// returns if t>u, using < or a comparing op x.opCmp and an element or a bool lessThan(x) predicate
/// be careful that the predicate for the right side cannot be used on the left side and viceversa 
/// (!(a>b)) <==> a<=b <=/=> b>a
bool moreThan(T,U)(T t,U u){
    static if (is(typeof(t(u))==bool)){
        t(u);
    } else static if (is(typeof(t(u)>0))){
        return t(u)>0;
    } else static if (is(typeof(u(t))==bool)){
        return u(t);
    } else static if (is(typeof(u(t)<0))){
        return u(t)<0;
    } else {
        return t>u;
    }
}

/// finds the lower bund to toFind in the ordered arraylike (i.e. indexable) structure arr
///     lowerbound means: lbound=max_i arr[i-1]<toFind
/// assuming arr[-1]=-inifinity, arr[arr.length]=inifinity.
///
/// As usual in D ub is exclusive.
/// If the value toFind is repeated it finds the first occurence
/// The result is always within the array bounds if arr.length>0, lb otherwise.
/// To keep the array ordered you want to insert before it (this is the first possible insertion point)
/// toFind should be either the element to find or a comparison operator or a lessThan predicate
/// this works correctly for unsigned IdxTypes.
/// Using a predicate note that the predicate for lbound (lessThan) is not simply the opposite of 
/// the one for ubound (moreThan)
typeof(IdxType1.init+IdxType2.init) uBound(ArrType,ToFind,IdxType1=size_t,IdxType2=size_t)(ArrType arr,ToFind toFind,IdxType1 lb_,IdxType2 ub_){
    alias typeof(IdxType1.init+IdxType2.init) IdxType;
    if (ub_<=lb_) return cast(IdxType)lb_;
    IdxType lb=cast(IdxType)lb_;
    IdxType ub=cast(IdxType)ub_;
    while(lb<ub){
        IdxType mid=lb+(ub-lb)/2;
        assert(lb<=mid && lb<ub);
        if (lessThan(toFind,arr[mid])){
            ub=mid;
        } else {
            lb=mid+1;
        }
    }
    return lb;
}
/// ditto
typeof(ArrType.init.length) lBound(ArrType,ToFind)(ArrType arr,ToFind toFind){
    return lBound!(ArrType,ToFind,typeof(ArrType.init.length),typeof(ArrType.init.length))
        (arr,toFind,0,arr.length);
}

/// finds the upper bund to toFind in the ordered arraylike (i.e. indexable) structure arr
///     upperbound means: min_i arr[i]>toFind
/// assuming arr[-1]=-inifinity, arr[arr.length]=inifinity.
///
/// As usual in D ub is exclusive.
/// If the value toFind is repeated it finds the last occurence
/// the result is always within the array bounds if arr.length>0, lb otherwise.
/// to keep the array ordered you want to insert at its position (this is the last possible insertion point).
/// toFind should be either the element to find or a comparison operator or a moreThan predicate
/// Using a predicate note that the predicate for lbound (lessThan) is not simply the opposite of 
/// the one for ubound (moreThan)
typeof(IdxType1.init+IdxType2.init) lBound(ArrType,ToFind,IdxType1=size_t,IdxType2=size_t)(ArrType arr,ToFind toFind,IdxType1 lb_,IdxType2 ub_){
    alias typeof(IdxType1.init+IdxType2.init) IdxType;
    if (ub_<=lb_) return cast(IdxType)lb_;
    IdxType lb=cast(IdxType)lb_;
    IdxType ub=cast(IdxType)ub_;
    while(lb<ub){
        IdxType mid=lb+(ub-lb)/2;
        assert(lb<=mid && lb<ub);
        if (moreThan(toFind,arr[mid])){
            lb=mid+1;
        } else {
            ub=mid;
        }
    }
    return lb;
}
/// ditto
typeof(ArrType.init.length) uBound(ArrType,ToFind)(ArrType arr,ToFind toFind){
    return uBound!(ArrType,ToFind,typeof(ArrType.init.length),typeof(ArrType.init.length))
        (arr,toFind,0,arr.length);
}
