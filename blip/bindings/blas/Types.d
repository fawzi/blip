/// aliases to easily cope with "strange" blas
///
/// Version with minor modification of the blip.bindings wrappers from
/// http://www.dsource.org/projects/multiarray/browser/trunk/Gobo
///
///  Copyright (C) 2006-2008 William V. Baxter III, OLM Digital, Inc.
///
///  This software is provided 'as-is', without any express or implied
///  warranty.  In no event will the authors be held liable for any
///  damages arising from the use of this software.
///
///  Permission is granted to anyone to use this software for any
///  purpose, including commercial applications, and to alter it and
///  redistribute it freely, subject to the following restrictions:
///
///  1. The origin of this software must not be misrepresented; you must
///     not claim that you wrote the original software. If you use this
///     software in a product, an acknowledgment in the product
///     documentation would be appreciated but is not required.
///
///  2. Altered source versions must be plainly marked as such, and must
///     not be misrepresented as being the original software.
///  3. This notice may not be removed or altered from any source distribution.
///
///  William Baxter wbaxter@gmail.com
module blip.bindings.blas.Types;
import blip.Comp;

alias float f_float;
alias double f_double;
alias cfloat f_cfloat;
alias cdouble f_cdouble;
alias int f_int;

template isBlasType(T){
   immutable bool isBlasType=is(T==f_float)|| is(T==f_double) ||
       is(T==f_cfloat) || is(T==f_cdouble);
}

template BlasTypeForType(T){
    static if (isBlasType!(T)){
        alias T BlasTypeForType;
    } else static if (is(T==real)||is(T==double)){
        alias f_double BlasTypeForType;
    } else static if (is(T==float)){
        alias f_float BlasTypeForType;
    } else static if (is(T==cdouble)||is(T==creal)){
        alias f_cdouble BlasTypeForType;
    } else static if (is(T==cfloat)){
        alias f_cfloat BlasTypeForType;
    } else {
        static assert(0,"could not match type "~T.stringof~" to a blas type");
    }
}
