/// aliases to easily cope with "strange" blas
module gobo.blas.Types;

alias float f_float;
alias double f_double;
alias cfloat f_cfloat;
alias cdouble f_cdouble;
alias int f_int;

template isBlasType(T){
   const bool isBlasType=is(T==f_float)|| is(T==f_double) ||
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