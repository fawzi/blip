module gobo.fft.fftw;

import tango.stdc.stdio;
import tango.stdc.stddef;


/*
 * Copyright (c) 2003, 2007-8 Matteo Frigo
 * Copyright (c) 2003, 2007-8 Massachusetts Institute of Technology
 *
 * The following statement of license applies *only* to this header file,
 * and *not* to the other files distributed with FFTW or derived therefrom:
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS
 * OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
 * GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
/***************************** NOTE TO USERS *********************************
 *
 *                 THIS IS A HEADER FILE, NOT A MANUAL
 *
 *    If you want to know how to use FFTW, please read the manual,
 *    online at http://www.fftw.org/doc/ and also included with FFTW.
 *    For a quick start, see the manual's tutorial section.
 *
 *   (Reading header files to learn how to use a library is a habit
 *    stemming from code lacking a proper manual.  Arguably, it's a
 *    *bad* habit in most cases, because header files can contain
 *    interfaces that are not part of the public, stable API.)
 *
 ****************************************************************************/

alias double fftw_double;
alias float fftw_float;
alias real fftwl_double;
alias cdouble fftw_complex;
alias cfloat fftwf_complex;
alias creal fftwl_complex;

enum fftw_r2r_kind_do_not_use_me {
     FFTW_R2HC=0, FFTW_HC2R=1, FFTW_DHT=2,
     FFTW_REDFT00=3, FFTW_REDFT01=4, FFTW_REDFT10=5, FFTW_REDFT11=6,
     FFTW_RODFT00=7, FFTW_RODFT01=8, FFTW_RODFT10=9, FFTW_RODFT11=10
}

// is is a keyword, so is and os have been renamed
struct fftw_iodim_do_not_use_me {
     int n; /* dimension size */
     int istride; /* input stride */
     int ostride; /* output stride */
}

struct fftw_iodim64_do_not_use_me {
     ptrdiff_t n; /* dimension size */
     ptrdiff_t istride; /* input stride */
     ptrdiff_t ostride; /* output stride */
};


typedef void *fftw_plan;
typedef fftw_iodim_do_not_use_me fftw_iodim;
typedef fftw_iodim64_do_not_use_me fftw_iodim64;
alias fftw_r2r_kind_do_not_use_me fftw_r2r_kind;

typedef void *fftwf_plan;
typedef fftw_iodim_do_not_use_me fftwf_iodim;
typedef fftw_iodim64_do_not_use_me fftwf_iodim64;
alias fftw_r2r_kind_do_not_use_me fftwf_r2r_kind;

typedef void *fftwl_plan;
typedef fftw_iodim_do_not_use_me fftwl_iodim;
typedef fftw_iodim64_do_not_use_me fftwl_iodim64;
alias fftw_r2r_kind_do_not_use_me fftwl_r2r_kind;

extern(C):

 extern void fftw_execute(fftw_plan p);
 extern fftw_plan fftw_plan_dft(int rank, int *n, fftw_complex *in_arr, fftw_complex *out_arr, int sign, uint flags);
 extern fftw_plan fftw_plan_dft_1d(int n, fftw_complex *in_arr, fftw_complex *out_arr, int sign, uint flags);
 extern fftw_plan fftw_plan_dft_2d(int n0, int n1, fftw_complex *in_arr, fftw_complex *out_arr, int sign, uint flags);
 extern fftw_plan fftw_plan_dft_3d(int n0, int n1, int n2, fftw_complex *in_arr, fftw_complex *out_arr, int sign, uint flags);
 extern fftw_plan fftw_plan_many_dft(int rank, int *n, int howmany, fftw_complex *in_arr, int *inembed, int istride, int idist, fftw_complex *out_arr, int *onembed, int ostride, int odist, int sign, uint flags);
 extern fftw_plan fftw_plan_guru_dft(int rank, fftw_iodim *dims, int howmany_rank, fftw_iodim *howmany_dims, fftw_complex *in_arr, fftw_complex *out_arr, int sign, uint flags);
 extern fftw_plan fftw_plan_guru_split_dft(int rank, fftw_iodim *dims, int howmany_rank, fftw_iodim *howmany_dims, double *ri, double *ii, double *ro, double *io, uint flags);
 extern fftw_plan fftw_plan_guru64_dft(int rank, fftw_iodim64 *dims, int howmany_rank, fftw_iodim64 *howmany_dims, fftw_complex *in_arr, fftw_complex *out_arr, int sign, uint flags);
 extern fftw_plan fftw_plan_guru64_split_dft(int rank, fftw_iodim64 *dims, int howmany_rank, fftw_iodim64 *howmany_dims, double *ri, double *ii, double *ro, double *io, uint flags);
 extern void fftw_execute_dft(fftw_plan p, fftw_complex *in_arr, fftw_complex *out_arr);
 extern void fftw_execute_split_dft(fftw_plan p, double *ri, double *ii, double *ro, double *io);
 extern fftw_plan fftw_plan_many_dft_r2c(int rank, int *n, int howmany, double *in_arr, int *inembed, int istride, int idist, fftw_complex *out_arr, int *onembed, int ostride, int odist, uint flags);
 extern fftw_plan fftw_plan_dft_r2c(int rank, int *n, double *in_arr, fftw_complex *out_arr, uint flags);
 extern fftw_plan fftw_plan_dft_r2c_1d(int n,double *in_arr,fftw_complex *out_arr,uint flags);
 extern fftw_plan fftw_plan_dft_r2c_2d(int n0, int n1, double *in_arr, fftw_complex *out_arr, uint flags);
 extern fftw_plan fftw_plan_dft_r2c_3d(int n0, int n1, int n2, double *in_arr, fftw_complex *out_arr, uint flags);
 extern fftw_plan fftw_plan_many_dft_c2r(int rank, int *n, int howmany, fftw_complex *in_arr, int *inembed, int istride, int idist, double *out_arr, int *onembed, int ostride, int odist, uint flags);
 extern fftw_plan fftw_plan_dft_c2r(int rank, int *n, fftw_complex *in_arr, double *out_arr, uint flags);
 extern fftw_plan fftw_plan_dft_c2r_1d(int n,fftw_complex *in_arr,double *out_arr,uint flags);
 extern fftw_plan fftw_plan_dft_c2r_2d(int n0, int n1, fftw_complex *in_arr, double *out_arr, uint flags);
 extern fftw_plan fftw_plan_dft_c2r_3d(int n0, int n1, int n2, fftw_complex *in_arr, double *out_arr, uint flags);
 extern fftw_plan fftw_plan_guru_dft_r2c(int rank, fftw_iodim *dims, int howmany_rank, fftw_iodim *howmany_dims, double *in_arr, fftw_complex *out_arr, uint flags);
 extern fftw_plan fftw_plan_guru_dft_c2r(int rank, fftw_iodim *dims, int howmany_rank, fftw_iodim *howmany_dims, fftw_complex *in_arr, double *out_arr, uint flags);
 extern fftw_plan fftw_plan_guru_split_dft_r2c( int rank, fftw_iodim *dims, int howmany_rank, fftw_iodim *howmany_dims, double *in_arr, double *ro, double *io, uint flags);
 extern fftw_plan fftw_plan_guru_split_dft_c2r( int rank, fftw_iodim *dims, int howmany_rank, fftw_iodim *howmany_dims, double *ri, double *ii, double *out_arr, uint flags);
 extern fftw_plan fftw_plan_guru64_dft_r2c(int rank, fftw_iodim64 *dims, int howmany_rank, fftw_iodim64 *howmany_dims, double *in_arr, fftw_complex *out_arr, uint flags);
 extern fftw_plan fftw_plan_guru64_dft_c2r(int rank, fftw_iodim64 *dims, int howmany_rank, fftw_iodim64 *howmany_dims, fftw_complex *in_arr, double *out_arr, uint flags);
 extern fftw_plan fftw_plan_guru64_split_dft_r2c( int rank, fftw_iodim64 *dims, int howmany_rank, fftw_iodim64 *howmany_dims, double *in_arr, double *ro, double *io, uint flags);
 extern fftw_plan fftw_plan_guru64_split_dft_c2r( int rank, fftw_iodim64 *dims, int howmany_rank, fftw_iodim64 *howmany_dims, double *ri, double *ii, double *out_arr, uint flags);
 extern void fftw_execute_dft_r2c(fftw_plan p, double *in_arr, fftw_complex *out_arr);
 extern void fftw_execute_dft_c2r(fftw_plan p, fftw_complex *in_arr, double *out_arr);
 extern void fftw_execute_split_dft_r2c(fftw_plan p, double *in_arr, double *ro, double *io);
 extern void fftw_execute_split_dft_c2r(fftw_plan p, double *ri, double *ii, double *out_arr);
 extern fftw_plan fftw_plan_many_r2r(int rank, int *n, int howmany, double *in_arr, int *inembed, int istride, int idist, double *out_arr, int *onembed, int ostride, int odist, fftw_r2r_kind *kind, uint flags);
 extern fftw_plan fftw_plan_r2r(int rank, int *n, double *in_arr, double *out_arr, fftw_r2r_kind *kind, uint flags);
 extern fftw_plan fftw_plan_r2r_1d(int n, double *in_arr, double *out_arr, fftw_r2r_kind kind, uint flags);
 extern fftw_plan fftw_plan_r2r_2d(int n0, int n1, double *in_arr, double *out_arr, fftw_r2r_kind kind0, fftw_r2r_kind kind1, uint flags);
 extern fftw_plan fftw_plan_r2r_3d(int n0, int n1, int n2, double *in_arr, double *out_arr, fftw_r2r_kind kind0, fftw_r2r_kind kind1, fftw_r2r_kind kind2, uint flags);
 extern fftw_plan fftw_plan_guru_r2r(int rank, fftw_iodim *dims, int howmany_rank, fftw_iodim *howmany_dims, double *in_arr, double *out_arr, fftw_r2r_kind *kind, uint flags);
 extern fftw_plan fftw_plan_guru64_r2r(int rank, fftw_iodim64 *dims, int howmany_rank, fftw_iodim64 *howmany_dims, double *in_arr, double *out_arr, fftw_r2r_kind *kind, uint flags);
 extern void fftw_execute_r2r(fftw_plan p, double *in_arr, double *out_arr);
 extern void fftw_destroy_plan(fftw_plan p);
 extern void fftw_forget_wisdom();
 extern void fftw_cleanup();
 extern void fftw_set_timelimit(double);
 extern void fftw_plan_with_nthreads(int nthreads);
 extern int fftw_init_threads();
 extern void fftw_cleanup_threads();
 extern void fftw_export_wisdom_to_file(FILE *output_file);
 extern char *fftw_export_wisdom_to_string();
 extern void fftw_export_wisdom(void (*write_char)(char c, void *), void *data);
 extern int fftw_import_system_wisdom();
 extern int fftw_import_wisdom_from_file(FILE *input_file);
 extern int fftw_import_wisdom_from_string(char *input_string);
 extern int fftw_import_wisdom(int (*read_char)(void *), void *data);
 extern void fftw_fprint_plan(fftw_plan p, FILE *output_file);
 extern void fftw_print_plan(fftw_plan p);
 extern void *fftw_malloc(size_t n);
 extern void fftw_free(void *p);
 extern void fftw_flops(fftw_plan p, double *add, double *mul, double *fmas);
 extern double fftw_estimate_cost(fftw_plan p);
 extern char[1] fftw_version;
 extern char[1] fftw_cc;
 extern char[1] fftw_codelet_optim;

 extern void fftwf_execute(fftwf_plan p);
 extern fftwf_plan fftwf_plan_dft(int rank, int *n, fftwf_complex *in_arr, fftwf_complex *out_arr, int sign, uint flags);
 extern fftwf_plan fftwf_plan_dft_1d(int n, fftwf_complex *in_arr, fftwf_complex *out_arr, int sign, uint flags);
 extern fftwf_plan fftwf_plan_dft_2d(int n0, int n1, fftwf_complex *in_arr, fftwf_complex *out_arr, int sign, uint flags);
 extern fftwf_plan fftwf_plan_dft_3d(int n0, int n1, int n2, fftwf_complex *in_arr, fftwf_complex *out_arr, int sign, uint flags);
 extern fftwf_plan fftwf_plan_many_dft(int rank, int *n, int howmany, fftwf_complex *in_arr, int *inembed, int istride, int idist, fftwf_complex *out_arr, int *onembed, int ostride, int odist, int sign, uint flags);
 extern fftwf_plan fftwf_plan_guru_dft(int rank, fftwf_iodim *dims, int howmany_rank, fftwf_iodim *howmany_dims, fftwf_complex *in_arr, fftwf_complex *out_arr, int sign, uint flags);
 extern fftwf_plan fftwf_plan_guru_split_dft(int rank, fftwf_iodim *dims, int howmany_rank, fftwf_iodim *howmany_dims, float *ri, float *ii, float *ro, float *io, uint flags);
 extern fftwf_plan fftwf_plan_guru64_dft(int rank, fftwf_iodim64 *dims, int howmany_rank, fftwf_iodim64 *howmany_dims, fftwf_complex *in_arr, fftwf_complex *out_arr, int sign, uint flags);
 extern fftwf_plan fftwf_plan_guru64_split_dft(int rank, fftwf_iodim64 *dims, int howmany_rank, fftwf_iodim64 *howmany_dims, float *ri, float *ii, float *ro, float *io, uint flags);
 extern void fftwf_execute_dft(fftwf_plan p, fftwf_complex *in_arr, fftwf_complex *out_arr);
 extern void fftwf_execute_split_dft(fftwf_plan p, float *ri, float *ii, float *ro, float *io);
 extern fftwf_plan fftwf_plan_many_dft_r2c(int rank, int *n, int howmany, float *in_arr, int *inembed, int istride, int idist, fftwf_complex *out_arr, int *onembed, int ostride, int odist, uint flags);
 extern fftwf_plan fftwf_plan_dft_r2c(int rank, int *n, float *in_arr, fftwf_complex *out_arr, uint flags);
 extern fftwf_plan fftwf_plan_dft_r2c_1d(int n,float *in_arr,fftwf_complex *out_arr,uint flags);
 extern fftwf_plan fftwf_plan_dft_r2c_2d(int n0, int n1, float *in_arr, fftwf_complex *out_arr, uint flags);
 extern fftwf_plan fftwf_plan_dft_r2c_3d(int n0, int n1, int n2, float *in_arr, fftwf_complex *out_arr, uint flags);
 extern fftwf_plan fftwf_plan_many_dft_c2r(int rank, int *n, int howmany, fftwf_complex *in_arr, int *inembed, int istride, int idist, float *out_arr, int *onembed, int ostride, int odist, uint flags);
 extern fftwf_plan fftwf_plan_dft_c2r(int rank, int *n, fftwf_complex *in_arr, float *out_arr, uint flags);
 extern fftwf_plan fftwf_plan_dft_c2r_1d(int n,fftwf_complex *in_arr,float *out_arr,uint flags);
 extern fftwf_plan fftwf_plan_dft_c2r_2d(int n0, int n1, fftwf_complex *in_arr, float *out_arr, uint flags);
 extern fftwf_plan fftwf_plan_dft_c2r_3d(int n0, int n1, int n2, fftwf_complex *in_arr, float *out_arr, uint flags);
 extern fftwf_plan fftwf_plan_guru_dft_r2c(int rank, fftwf_iodim *dims, int howmany_rank, fftwf_iodim *howmany_dims, float *in_arr, fftwf_complex *out_arr, uint flags);
 extern fftwf_plan fftwf_plan_guru_dft_c2r(int rank, fftwf_iodim *dims, int howmany_rank, fftwf_iodim *howmany_dims, fftwf_complex *in_arr, float *out_arr, uint flags);
 extern fftwf_plan fftwf_plan_guru_split_dft_r2c( int rank, fftwf_iodim *dims, int howmany_rank, fftwf_iodim *howmany_dims, float *in_arr, float *ro, float *io, uint flags);
 extern fftwf_plan fftwf_plan_guru_split_dft_c2r( int rank, fftwf_iodim *dims, int howmany_rank, fftwf_iodim *howmany_dims, float *ri, float *ii, float *out_arr, uint flags);
 extern fftwf_plan fftwf_plan_guru64_dft_r2c(int rank, fftwf_iodim64 *dims, int howmany_rank, fftwf_iodim64 *howmany_dims, float *in_arr, fftwf_complex *out_arr, uint flags);
 extern fftwf_plan fftwf_plan_guru64_dft_c2r(int rank, fftwf_iodim64 *dims, int howmany_rank, fftwf_iodim64 *howmany_dims, fftwf_complex *in_arr, float *out_arr, uint flags);
 extern fftwf_plan fftwf_plan_guru64_split_dft_r2c( int rank, fftwf_iodim64 *dims, int howmany_rank, fftwf_iodim64 *howmany_dims, float *in_arr, float *ro, float *io, uint flags);
 extern fftwf_plan fftwf_plan_guru64_split_dft_c2r( int rank, fftwf_iodim64 *dims, int howmany_rank, fftwf_iodim64 *howmany_dims, float *ri, float *ii, float *out_arr, uint flags);
 extern void fftwf_execute_dft_r2c(fftwf_plan p, float *in_arr, fftwf_complex *out_arr);
 extern void fftwf_execute_dft_c2r(fftwf_plan p, fftwf_complex *in_arr, float *out_arr);
 extern void fftwf_execute_split_dft_r2c(fftwf_plan p, float *in_arr, float *ro, float *io);
 extern void fftwf_execute_split_dft_c2r(fftwf_plan p, float *ri, float *ii, float *out_arr);
 extern fftwf_plan fftwf_plan_many_r2r(int rank, int *n, int howmany, float *in_arr, int *inembed, int istride, int idist, float *out_arr, int *onembed, int ostride, int odist, fftwf_r2r_kind *kind, uint flags);
 extern fftwf_plan fftwf_plan_r2r(int rank, int *n, float *in_arr, float *out_arr, fftwf_r2r_kind *kind, uint flags);
 extern fftwf_plan fftwf_plan_r2r_1d(int n, float *in_arr, float *out_arr, fftwf_r2r_kind kind, uint flags);
 extern fftwf_plan fftwf_plan_r2r_2d(int n0, int n1, float *in_arr, float *out_arr, fftwf_r2r_kind kind0, fftwf_r2r_kind kind1, uint flags);
 extern fftwf_plan fftwf_plan_r2r_3d(int n0, int n1, int n2, float *in_arr, float *out_arr, fftwf_r2r_kind kind0, fftwf_r2r_kind kind1, fftwf_r2r_kind kind2, uint flags);
 extern fftwf_plan fftwf_plan_guru_r2r(int rank, fftwf_iodim *dims, int howmany_rank, fftwf_iodim *howmany_dims, float *in_arr, float *out_arr, fftwf_r2r_kind *kind, uint flags);
 extern fftwf_plan fftwf_plan_guru64_r2r(int rank, fftwf_iodim64 *dims, int howmany_rank, fftwf_iodim64 *howmany_dims, float *in_arr, float *out_arr, fftwf_r2r_kind *kind, uint flags);
 extern void fftwf_execute_r2r(fftwf_plan p, float *in_arr, float *out_arr);
 extern void fftwf_destroy_plan(fftwf_plan p);
 extern void fftwf_forget_wisdom();
 extern void fftwf_cleanup();
 extern void fftwf_set_timelimit(double);
 extern void fftwf_plan_with_nthreads(int nthreads);
 extern int fftwf_init_threads();
 extern void fftwf_cleanup_threads();
 extern void fftwf_export_wisdom_to_file(FILE *output_file);
 extern char *fftwf_export_wisdom_to_string();
 extern void fftwf_export_wisdom(void (*write_char)(char c, void *), void *data);
 extern int fftwf_import_system_wisdom();
 extern int fftwf_import_wisdom_from_file(FILE *input_file);
 extern int fftwf_import_wisdom_from_string(char *input_string);
 extern int fftwf_import_wisdom(int (*read_char)(void *), void *data);
 extern void fftwf_fprint_plan(fftwf_plan p, FILE *output_file);
 extern void fftwf_print_plan(fftwf_plan p);
 extern void *fftwf_malloc(size_t n);
 extern void fftwf_free(void *p);
 extern void fftwf_flops(fftwf_plan p, double *add, double *mul, double *fmas);
 extern double fftwf_estimate_cost(fftwf_plan p);
 extern char[1] fftwf_version;
 extern char[1] fftwf_cc;
 extern char[1] fftwf_codelet_optim;

 extern void fftwl_execute(fftwl_plan p);
 extern fftwl_plan fftwl_plan_dft(int rank, int *n, fftwl_complex *in_arr, fftwl_complex *out_arr, int sign, uint flags);
 extern fftwl_plan fftwl_plan_dft_1d(int n, fftwl_complex *in_arr, fftwl_complex *out_arr, int sign, uint flags);
 extern fftwl_plan fftwl_plan_dft_2d(int n0, int n1, fftwl_complex *in_arr, fftwl_complex *out_arr, int sign, uint flags);
 extern fftwl_plan fftwl_plan_dft_3d(int n0, int n1, int n2, fftwl_complex *in_arr, fftwl_complex *out_arr, int sign, uint flags);
 extern fftwl_plan fftwl_plan_many_dft(int rank, int *n, int howmany, fftwl_complex *in_arr, int *inembed, int istride, int idist, fftwl_complex *out_arr, int *onembed, int ostride, int odist, int sign, uint flags);
 extern fftwl_plan fftwl_plan_guru_dft(int rank, fftwl_iodim *dims, int howmany_rank, fftwl_iodim *howmany_dims, fftwl_complex *in_arr, fftwl_complex *out_arr, int sign, uint flags);
 extern fftwl_plan fftwl_plan_guru_split_dft(int rank, fftwl_iodim *dims, int howmany_rank, fftwl_iodim *howmany_dims, fftwl_double *ri, fftwl_double *ii, fftwl_double *ro, fftwl_double *io, uint flags);
 extern fftwl_plan fftwl_plan_guru64_dft(int rank, fftwl_iodim64 *dims, int howmany_rank, fftwl_iodim64 *howmany_dims, fftwl_complex *in_arr, fftwl_complex *out_arr, int sign, uint flags);
 extern fftwl_plan fftwl_plan_guru64_split_dft(int rank, fftwl_iodim64 *dims, int howmany_rank, fftwl_iodim64 *howmany_dims, fftwl_double *ri, fftwl_double *ii, fftwl_double *ro, fftwl_double *io, uint flags);
 extern void fftwl_execute_dft(fftwl_plan p, fftwl_complex *in_arr, fftwl_complex *out_arr);
 extern void fftwl_execute_split_dft(fftwl_plan p, fftwl_double *ri, fftwl_double *ii, fftwl_double *ro, fftwl_double *io);
 extern fftwl_plan fftwl_plan_many_dft_r2c(int rank, int *n, int howmany, fftwl_double *in_arr, int *inembed, int istride, int idist, fftwl_complex *out_arr, int *onembed, int ostride, int odist, uint flags);
 extern fftwl_plan fftwl_plan_dft_r2c(int rank, int *n, fftwl_double *in_arr, fftwl_complex *out_arr, uint flags);
 extern fftwl_plan fftwl_plan_dft_r2c_1d(int n,fftwl_double *in_arr,fftwl_complex *out_arr,uint flags);
 extern fftwl_plan fftwl_plan_dft_r2c_2d(int n0, int n1, fftwl_double *in_arr, fftwl_complex *out_arr, uint flags);
 extern fftwl_plan fftwl_plan_dft_r2c_3d(int n0, int n1, int n2, fftwl_double *in_arr, fftwl_complex *out_arr, uint flags);
 extern fftwl_plan fftwl_plan_many_dft_c2r(int rank, int *n, int howmany, fftwl_complex *in_arr, int *inembed, int istride, int idist, fftwl_double *out_arr, int *onembed, int ostride, int odist, uint flags);
 extern fftwl_plan fftwl_plan_dft_c2r(int rank, int *n, fftwl_complex *in_arr, fftwl_double *out_arr, uint flags);
 extern fftwl_plan fftwl_plan_dft_c2r_1d(int n,fftwl_complex *in_arr,fftwl_double *out_arr,uint flags);
 extern fftwl_plan fftwl_plan_dft_c2r_2d(int n0, int n1, fftwl_complex *in_arr, fftwl_double *out_arr, uint flags);
 extern fftwl_plan fftwl_plan_dft_c2r_3d(int n0, int n1, int n2, fftwl_complex *in_arr, fftwl_double *out_arr, uint flags);
 extern fftwl_plan fftwl_plan_guru_dft_r2c(int rank, fftwl_iodim *dims, int howmany_rank, fftwl_iodim *howmany_dims, fftwl_double *in_arr, fftwl_complex *out_arr, uint flags);
 extern fftwl_plan fftwl_plan_guru_dft_c2r(int rank, fftwl_iodim *dims, int howmany_rank, fftwl_iodim *howmany_dims, fftwl_complex *in_arr, fftwl_double *out_arr, uint flags);
 extern fftwl_plan fftwl_plan_guru_split_dft_r2c( int rank, fftwl_iodim *dims, int howmany_rank, fftwl_iodim *howmany_dims, fftwl_double *in_arr, fftwl_double *ro, fftwl_double *io, uint flags);
 extern fftwl_plan fftwl_plan_guru_split_dft_c2r( int rank, fftwl_iodim *dims, int howmany_rank, fftwl_iodim *howmany_dims, fftwl_double *ri, fftwl_double *ii, fftwl_double *out_arr, uint flags);
 extern fftwl_plan fftwl_plan_guru64_dft_r2c(int rank, fftwl_iodim64 *dims, int howmany_rank, fftwl_iodim64 *howmany_dims, fftwl_double *in_arr, fftwl_complex *out_arr, uint flags);
 extern fftwl_plan fftwl_plan_guru64_dft_c2r(int rank, fftwl_iodim64 *dims, int howmany_rank, fftwl_iodim64 *howmany_dims, fftwl_complex *in_arr, fftwl_double *out_arr, uint flags);
 extern fftwl_plan fftwl_plan_guru64_split_dft_r2c( int rank, fftwl_iodim64 *dims, int howmany_rank, fftwl_iodim64 *howmany_dims, fftwl_double *in_arr, fftwl_double *ro, fftwl_double *io, uint flags);
 extern fftwl_plan fftwl_plan_guru64_split_dft_c2r( int rank, fftwl_iodim64 *dims, int howmany_rank, fftwl_iodim64 *howmany_dims, fftwl_double *ri, fftwl_double *ii, fftwl_double *out_arr, uint flags);
 extern void fftwl_execute_dft_r2c(fftwl_plan p, fftwl_double *in_arr, fftwl_complex *out_arr);
 extern void fftwl_execute_dft_c2r(fftwl_plan p, fftwl_complex *in_arr, fftwl_double *out_arr);
 extern void fftwl_execute_split_dft_r2c(fftwl_plan p, fftwl_double *in_arr, fftwl_double *ro, fftwl_double *io);
 extern void fftwl_execute_split_dft_c2r(fftwl_plan p, fftwl_double *ri, fftwl_double *ii, fftwl_double *out_arr);
 extern fftwl_plan fftwl_plan_many_r2r(int rank, int *n, int howmany, fftwl_double *in_arr, int *inembed, int istride, int idist, fftwl_double *out_arr, int *onembed, int ostride, int odist, fftwl_r2r_kind *kind, uint flags);
 extern fftwl_plan fftwl_plan_r2r(int rank, int *n, fftwl_double *in_arr, fftwl_double *out_arr, fftwl_r2r_kind *kind, uint flags);
 extern fftwl_plan fftwl_plan_r2r_1d(int n, fftwl_double *in_arr, fftwl_double *out_arr, fftwl_r2r_kind kind, uint flags);
 extern fftwl_plan fftwl_plan_r2r_2d(int n0, int n1, fftwl_double *in_arr, fftwl_double *out_arr, fftwl_r2r_kind kind0, fftwl_r2r_kind kind1, uint flags);
 extern fftwl_plan fftwl_plan_r2r_3d(int n0, int n1, int n2, fftwl_double *in_arr, fftwl_double *out_arr, fftwl_r2r_kind kind0, fftwl_r2r_kind kind1, fftwl_r2r_kind kind2, uint flags);
 extern fftwl_plan fftwl_plan_guru_r2r(int rank, fftwl_iodim *dims, int howmany_rank, fftwl_iodim *howmany_dims, fftwl_double *in_arr, fftwl_double *out_arr, fftwl_r2r_kind *kind, uint flags);
 extern fftwl_plan fftwl_plan_guru64_r2r(int rank, fftwl_iodim64 *dims, int howmany_rank, fftwl_iodim64 *howmany_dims, fftwl_double *in_arr, fftwl_double *out_arr, fftwl_r2r_kind *kind, uint flags);
 extern void fftwl_execute_r2r(fftwl_plan p, fftwl_double *in_arr, fftwl_double *out_arr);
 extern void fftwl_destroy_plan(fftwl_plan p);
 extern void fftwl_forget_wisdom();
 extern void fftwl_cleanup();
 extern void fftwl_set_timelimit(double);
 extern void fftwl_plan_with_nthreads(int nthreads);
 extern int fftwl_init_threads();
 extern void fftwl_cleanup_threads();
 extern void fftwl_export_wisdom_to_file(FILE *output_file);
 extern char *fftwl_export_wisdom_to_string();
 extern void fftwl_export_wisdom(void (*write_char)(char c, void *), void *data);
 extern int fftwl_import_system_wisdom();
 extern int fftwl_import_wisdom_from_file(FILE *input_file);
 extern int fftwl_import_wisdom_from_string(char *input_string);
 extern int fftwl_import_wisdom(int (*read_char)(void *), void *data);
 extern void fftwl_fprint_plan(fftwl_plan p, FILE *output_file);
 extern void fftwl_print_plan(fftwl_plan p);
 extern void *fftwl_malloc(size_t n);
 extern void fftwl_free(void *p);
 extern void fftwl_flops(fftwl_plan p, double *add, double *mul, double *fmas);
 extern double fftwl_estimate_cost(fftwl_plan p);
 extern char[1] fftwl_version;
 extern char[1] fftwl_cc;
 extern char[1] fftwl_codelet_optim;

enum{
 FFTW_FORWARD=-1,
 FFTW_BACKWARD=1,
}
const double FFTW_NO_TIMELIMIT=-1.0;
enum:uint{
/* documented flags */
 FFTW_MEASURE=0U,
 FFTW_DESTROY_INPUT=1U << 0,
 FFTW_UNALIGNED=1U << 1,
 FFTW_CONSERVE_MEMORY=1U << 2,
 FFTW_EXHAUSTIVE=1U << 3,
 FFTW_PRESERVE_INPUT=1U << 4,
 FFTW_PATIENT=1U << 5,
 FFTW_ESTIMATE=1U << 6,
/* undocumented beyond-guru flags */
 FFTW_ESTIMATE_PATIENT=1U << 7,
 FFTW_BELIEVE_PCOST=1U << 8,
 FFTW_NO_DFT_R2HC=1U << 9,
 FFTW_NO_NONTHREADED=1U << 10,
 FFTW_NO_BUFFERING=1U << 11,
 FFTW_NO_INDIRECT_OP=1U << 12,
 FFTW_ALLOW_LARGE_GENERIC=1U << 13,
 FFTW_NO_RANK_SPLITS=1U << 14,
 FFTW_NO_VRANK_SPLITS=1U << 15,
 FFTW_NO_VRECURSE=1U << 16,
 FFTW_NO_SIMD=1U << 17,
 FFTW_NO_SLOW=1U << 18,
 FFTW_NO_FIXED_RADIX_LARGE_N=1U << 19,
 FFTW_ALLOW_PRUNING=1U << 20,
 FFTW_WISDOM_ONLY=1U << 21,
}