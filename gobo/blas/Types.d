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
