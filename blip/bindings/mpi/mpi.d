/// mpi bindings
///
/// at the moment this wraps openmpi, the constants and some things are specific
/// maybe we should wrap only the basic calls that are easier to make cross library...
///
/// derived from openmpi 1.3.3 mpi.h which is
///
/// Copyright (c) 2004-2005 The Trustees of Indiana University and Indiana
///                         University Research and Technology
///                         Corporation.  All rights reserved.
/// Copyright (c) 2004-2006 The University of Tennessee and The University
///                         of Tennessee Research Foundation.  All rights
///                         reserved.
/// Copyright (c) 2004-2007 High Performance Computing Center Stuttgart, 
///                         University of Stuttgart.  All rights reserved.
/// Copyright (c) 2004-2005 The Regents of the University of California.
///                         All rights reserved.
/// Copyright (c) 2007-2009 Cisco Systems, Inc.  All rights reserved.
/// Copyright (c) 2008-2009 Sun Microsystems, Inc.  All rights reserved.
///
///
/// author: fawzi
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
module blip.bindings.mpi.mpi;
version(mpi)
{
import tango.stdc.stddef;
/*
 * MPI version
 */
enum{ MPI_VERSION=2,MPI_SUBVERSION=1 }
/*
 * Typedefs
 */
typedef ptrdiff_t MPI_Aint;
typedef long MPI_Offset;
typedef void *MPI_Comm;
typedef void *MPI_Datatype;
typedef void *MPI_Errhandler;
typedef void *MPI_File;
typedef void *MPI_Group;
typedef void *MPI_Info;
typedef void *MPI_Op;
typedef void *MPI_Request;
alias ompi_status_public_t MPI_Status;
typedef void *MPI_Win;
/*
 * MPI_Status
 */
struct ompi_status_public_t {
  int MPI_SOURCE;
  int MPI_TAG;
  int MPI_ERROR;
  int _count;
  int _cancelled;
}

/*
 * User typedefs
 */
alias extern(C) int function(MPI_Comm, int, void *,
                                void *, void *, int *) MPI_Copy_function;
alias extern(C) int function(MPI_Comm, int, void *, void *) MPI_Delete_function;
alias extern(C) int function(MPI_Datatype, MPI_Aint *, void *) MPI_Datarep_extent_function;
alias extern(C) int function(void *, MPI_Datatype,
                int, void *, MPI_Offset, void *)MPI_Datarep_conversion_function;
alias extern(C) void function(MPI_Comm *, int *, ...) MPI_Comm_errhandler_fn;
    /* This is a little hackish, but errhandler.h needs space for a
       MPI_File_errhandler_fn.  While it could just be removed, this
       allows us to maintain a stable ABI within OMPI, at least for
       apps that don't use MPI I/O. */
alias extern(C) void function(MPI_File *, int *, ...)ompi_file_errhandler_fn;
alias ompi_file_errhandler_fn MPI_File_errhandler_fn;
alias extern(C) void function(MPI_Win *, int *, ...) MPI_Win_errhandler_fn;
alias extern(C) void function(MPI_Comm *, int *, ...) MPI_Handler_function;
alias extern(C) void function(void *, void *, int *, MPI_Datatype *) MPI_User_function;
alias extern(C) int function(MPI_Comm, int, void *,
                   void *, void *, int *)MPI_Comm_copy_attr_function;
alias extern(C) int function(MPI_Comm, int, void *, void *)MPI_Comm_delete_attr_function;
alias extern(C) int function(MPI_Datatype, int, void *,
            void *, void *, int *) MPI_Type_copy_attr_function;
alias extern(C) int function(MPI_Datatype, int,void *,
            void *)MPI_Type_delete_attr_function;
alias extern(C) int function(MPI_Win, int, void *,
            void *, void *, int *)MPI_Win_copy_attr_function;
alias extern(C) int function(MPI_Win, int, void *, void *)MPI_Win_delete_attr_function;
alias extern(C) int function(void *, MPI_Status *)MPI_Grequest_query_function;
alias extern(C) int function(void *)MPI_Grequest_free_function;
alias extern(C) int function(void *, int)MPI_Grequest_cancel_function;
/*
 * Miscellaneous constants
 */
enum{
 MPI_ANY_SOURCE=-1,
 MPI_PROC_NULL=-2,
 MPI_ROOT=-4,
 MPI_ANY_TAG=-1,
 MPI_MAX_PROCESSOR_NAME=256,
 MPI_MAX_ERROR_STRING=256,
 MPI_MAX_OBJECT_NAME=64,
 MPI_UNDEFINED=-32766,
 MPI_CART=1,
 MPI_GRAPH=2,
 MPI_KEYVAL_INVALID=-1,
}
/*
 * More constants
 */
const void *MPI_BOTTOM=null;
const void *MPI_IN_PLACE=cast(void *) 1;

enum{
 MPI_BSEND_OVERHEAD=128,
 MPI_MAX_INFO_KEY=36,
 MPI_MAX_INFO_VAL=256,
}
const char**  MPI_ARGV_NULL      =null;
const char*** MPI_ARGVS_NULL     =null;
const int*    MPI_ERRCODES_IGNORE=null;
enum {
 MPI_MAX_PORT_NAME=1024,
 MPI_MAX_NAME_LEN=MPI_MAX_PORT_NAME,
}

enum MPI_ORDER{
 C=0,
 FORTRAN=1,
}

enum MPI_DISTRIBUTE{
    BLOCK=0,
    CYCLIC=1,
    NONE=2,
    DFLT_DARG=-1,
}
/*
 * Since these values are arbitrary to Open MPI, we might as well make
 * them the same as ROMIO for ease of mapping.  These values taken
 * from ROMIO's mpio.h file.
 */
enum MPI_MODE{
 CREATE=1,
 RDONLY=2,
 WRONLY=4,
 RDWR=8,
 DELETE_ON_CLOSE=16,
 UNIQUE_OPEN=32,
 EXCL=64,
 APPEND=128,
 SEQUENTIAL=256,
 // mpi-2 One-Sided Communications asserts
 NOCHECK=1,
 NOPRECEDE=2,
 NOPUT=4,
 NOSTORE=8,
 NOSUCCEED=16,
}

enum{ MPI_DISPLACEMENT_CURRENT=-54278278 }

enum MPI_SEEK{
 SET=600,
 CUR=602,
 END=604,
}

enum{
 MPI_MAX_DATAREP_STRING=128,
}
/*
 * MPI-2 One-Sided Communications asserts
 */
enum{
 MPI_LOCK_EXCLUSIVE=1,
 MPI_LOCK_SHARED=2,
}
/*
 * Predefined attribute keyvals
 *
 * DO NOT CHANGE THE ORDER WITHOUT ALSO CHANGING THE ORDER IN
 * src/attribute/attribute_predefined.c and mpif.h.in.
 */
enum {
    /* MPI-1 */
    MPI_TAG_UB,
    MPI_HOST,
    MPI_IO,
    MPI_WTIME_IS_GLOBAL,
    /* MPI-2 */
    MPI_APPNUM,
    MPI_LASTUSEDCODE,
    MPI_UNIVERSE_SIZE,
    MPI_WIN_BASE,
    MPI_WIN_SIZE,
    MPI_WIN_DISP_UNIT,
    /* Even though these four are IMPI attributes, they need to be there
       for all MPI jobs */
    IMPI_CLIENT_SIZE,
    IMPI_CLIENT_COLOR,
    IMPI_HOST_SIZE,
    IMPI_HOST_COLOR
}
/*
 * Error classes and codes
 * Do not change the values of these without also modifying mpif.h.in.
 */
enum {MPI_SUCCESS=0}
enum MPI_ERR{
 SUCCESS=0,
 BUFFER=1,
 COUNT=2,
 TYPE=3,
 TAG=4,
 COMM=5,
 RANK=6,
 REQUEST=7,
 ROOT=8,
 GROUP=9,
 OP=10,
 TOPOLOGY=11,
 DIMS=12,
 ARG=13,
 UNKNOWN=14,
 TRUNCATE=15,
 OTHER=16,
 INTERN=17,
 IN_STATUS=18,
 PENDING=19,
 ACCESS=20,
 AMODE=21,
 ASSERT=22,
 BAD_FILE=23,
 BASE=24,
 CONVERSION=25,
 DISP=26,
 DUP_DATAREP=27,
 FILE_EXISTS=28,
 FILE_IN_USE=29,
 FILE=30,
 INFO_KEY=31,
 INFO_NOKEY=32,
 INFO_VALUE=33,
 INFO=34,
 IO=35,
 KEYVAL=36,
 LOCKTYPE=37,
 NAME=38,
 NO_MEM=39,
 NOT_SAME=40,
 NO_SPACE=41,
 NO_SUCH_FILE=42,
 PORT=43,
 QUOTA=44,
 READ_ONLY=45,
 RMA_CONFLICT=46,
 RMA_SYNC=47,
 SERVICE=48,
 SIZE=49,
 SPAWN=50,
 UNSUPPORTED_DATAREP=51,
 UNSUPPORTED_OPERATION=52,
 WIN=53,
 LASTCODE=54,
 SYSRESOURCE=-2,
}
/*
 * Comparison results.  Don't change the order of these, the group
 * comparison functions rely on it.
 * Do not change the order of these without also modifying mpif.h.in.
 */
enum {
  MPI_IDENT,
  MPI_CONGRUENT,
  MPI_SIMILAR,
  MPI_UNEQUAL
}
/*
 * MPI_Init_thread constants
 * Do not change the order of these without also modifying mpif.h.in.
 */
enum {
  MPI_THREAD_SINGLE,
  MPI_THREAD_FUNNELED,
  MPI_THREAD_SERIALIZED,
  MPI_THREAD_MULTIPLE
}
/*
 * Datatype combiners.
 * Do not change the order of these without also modifying mpif.h.in.
 */
enum {
  MPI_COMBINER_NAMED,
  MPI_COMBINER_DUP,
  MPI_COMBINER_CONTIGUOUS,
  MPI_COMBINER_VECTOR,
  MPI_COMBINER_HVECTOR_INTEGER,
  MPI_COMBINER_HVECTOR,
  MPI_COMBINER_INDEXED,
  MPI_COMBINER_HINDEXED_INTEGER,
  MPI_COMBINER_HINDEXED,
  MPI_COMBINER_INDEXED_BLOCK,
  MPI_COMBINER_STRUCT_INTEGER,
  MPI_COMBINER_STRUCT,
  MPI_COMBINER_SUBARRAY,
  MPI_COMBINER_DARRAY,
  MPI_COMBINER_F90_REAL,
  MPI_COMBINER_F90_COMPLEX,
  MPI_COMBINER_F90_INTEGER,
  MPI_COMBINER_RESIZED
}
/*
 * NULL handles
 */
const MPI_Group MPI_GROUP_NULL;
const MPI_Comm MPI_COMM_NULL;
const MPI_Request MPI_REQUEST_NULL;
const MPI_Op MPI_OP_NULL;
const MPI_Errhandler MPI_ERRHANDLER_NULL;
const MPI_Info MPI_INFO_NULL;
const MPI_Win MPI_WIN_NULL;
const MPI_File MPI_FILE_NULL;
static this(){
    MPI_GROUP_NULL = cast(MPI_Group)&ompi_mpi_group_null;
    MPI_COMM_NULL = cast(MPI_Comm)&ompi_mpi_comm_null;
    MPI_REQUEST_NULL = cast(MPI_Request)&ompi_request_null;
    MPI_OP_NULL = cast(MPI_Op)&ompi_mpi_op_null;
    MPI_ERRHANDLER_NULL = cast(MPI_Errhandler)&ompi_mpi_errhandler_null;
    MPI_INFO_NULL = cast(MPI_Info)&ompi_mpi_info_null;
    MPI_WIN_NULL = cast(MPI_Win)&ompi_mpi_win_null;
    MPI_FILE_NULL = cast(MPI_File)&ompi_mpi_file_null;
}

const MPI_Status* MPI_STATUS_IGNORE=cast(MPI_Status *)null;
const MPI_Status* MPI_STATUSES_IGNORE=cast(MPI_Status *)null;

/* MPI-2 specifies that the name "MPI_TYPE_NULL_DELETE_FN" (and all
   related friends) must be accessible in C, C++, and Fortran. This is
   unworkable if the back-end Fortran compiler uses all caps for its
   linker symbol convention -- it results in two functions with
   different signatures that have the same name (i.e., both C and
   Fortran use the symbol MPI_TYPE_NULL_DELETE_FN).  So we have to
   #define the C names to be something else, so that they names are
   *accessed* through MPI_TYPE_NULL_DELETE_FN, but their actual symbol
   name is different.

   However, this file is included when the fortran wrapper functions
   are compiled in Open MPI, so we do *not* want these #defines in
   this case (i.e., we need the Fortran wrapper function to be
   compiled as MPI_TYPE_NULL_DELETE_FN).  So add some #if kinds of
   protection for this case. */
   extern(C) extern int OMPI_C_MPI_TYPE_NULL_DELETE_FN( MPI_Datatype datatype, 
                                                     int type_keyval,
                                                     void* attribute_val_out, 
                                                     void* extra_state );
   extern(C) extern int OMPI_C_MPI_TYPE_NULL_COPY_FN( MPI_Datatype datatype, 
                                                   int type_keyval, 
                                                   void* extra_state,
                                                   void* attribute_val_in, 
                                                   void* attribute_val_out, 
                                                   int* flag );
   extern(C) extern int OMPI_C_MPI_TYPE_DUP_FN( MPI_Datatype datatype, 
                                             int type_keyval, 
                                             void* extra_state, 
                                             void* attribute_val_in, 
                                             void* attribute_val_out, 
                                             int* flag );
   extern(C) extern int OMPI_C_MPI_COMM_NULL_DELETE_FN( MPI_Comm comm, 
                                                     int comm_keyval,
                                                     void* attribute_val_out, 
                                                     void* extra_state );
   extern(C) extern int OMPI_C_MPI_COMM_NULL_COPY_FN( MPI_Comm comm, 
                                                   int comm_keyval, 
                                                   void* extra_state, 
                                                   void* attribute_val_in,
                                                   void* attribute_val_out, 
                                                   int* flag );
   extern(C) extern int OMPI_C_MPI_COMM_DUP_FN( MPI_Comm comm, int comm_keyval, 
                                             void* extra_state,
                                             void* attribute_val_in, 
                                             void* attribute_val_out,
                                             int* flag );
   extern(C) extern int OMPI_C_MPI_NULL_DELETE_FN( MPI_Comm comm, int comm_keyval,
                                                void* attribute_val_out, 
                                                void* extra_state );
   extern(C) extern int OMPI_C_MPI_NULL_COPY_FN( MPI_Comm comm, int comm_keyval, 
                                              void* extra_state,
                                              void* attribute_val_in, 
                                              void* attribute_val_out,
                                              int* flag );
   extern(C) extern int OMPI_C_MPI_DUP_FN( MPI_Comm comm, int comm_keyval, 
                                        void* extra_state,
                                        void* attribute_val_in, 
                                        void* attribute_val_out,
                                        int* flag );
   extern(C) extern int OMPI_C_MPI_WIN_NULL_DELETE_FN( MPI_Win window, 
                                                    int win_keyval,
                                                    void* attribute_val_out, 
                                                    void* extra_state );
   extern(C) extern int OMPI_C_MPI_WIN_NULL_COPY_FN( MPI_Win window, int win_keyval, 
                                                  void* extra_state, 
                                                  void* attribute_val_in,
                                                  void* attribute_val_out, 
                                                  int* flag );
   extern(C) extern int OMPI_C_MPI_WIN_DUP_FN( MPI_Win window, int win_keyval, 
                                            void* extra_state,
                                            void* attribute_val_in, 
                                            void* attribute_val_out,
                                            int* flag );

alias OMPI_C_MPI_NULL_DELETE_FN MPI_NULL_DELETE_FN;
alias OMPI_C_MPI_NULL_COPY_FN MPI_NULL_COPY_FN;
alias OMPI_C_MPI_DUP_FN MPI_DUP_FN;
alias OMPI_C_MPI_TYPE_NULL_DELETE_FN MPI_TYPE_NULL_DELETE_FN;
alias OMPI_C_MPI_TYPE_NULL_COPY_FN MPI_TYPE_NULL_COPY_FN;
alias OMPI_C_MPI_TYPE_DUP_FN MPI_TYPE_DUP_FN;
alias OMPI_C_MPI_COMM_NULL_DELETE_FN MPI_COMM_NULL_DELETE_FN;
alias OMPI_C_MPI_COMM_NULL_COPY_FN MPI_COMM_NULL_COPY_FN;
alias OMPI_C_MPI_COMM_DUP_FN MPI_COMM_DUP_FN;
alias OMPI_C_MPI_WIN_NULL_DELETE_FN MPI_WIN_NULL_DELETE_FN;
alias OMPI_C_MPI_WIN_NULL_COPY_FN MPI_WIN_NULL_COPY_FN;
alias OMPI_C_MPI_WIN_DUP_FN MPI_WIN_DUP_FN;

/* MPI_CONVERSION_FN_NULL is a sentinel value, but it has to be large
   enough to be the same size as a valid function pointer.  It
   therefore shares many characteristics between Fortran constants and
   Fortran sentinel functions.  For example, it shares the problem of
   having Fortran compilers have all-caps versions of the symbols that
   must be able to be present, and therefore has to be in this
   conditional block in mpi.h. */
// MPI_CONVERSION_FN_NULL // not defined

/*
 * External variables
 *
 * The below externs use the ompi_predefined_xxx_t structures to maintain
 * back compatibility between MPI library versions.
 * See ompi/communicator/communicator.h comments with struct ompi_communicator_t
 * for full explanation why we chose to use the ompi_predefined_xxx_t structure.
 */
enum{ PREDEFINED_COMMUNICATOR_PAD=(void*).sizeof * 128 }

struct ompi_predefined_communicator_t {
     char padding[PREDEFINED_COMMUNICATOR_PAD];
}

 extern extern(C) ompi_predefined_communicator_t ompi_mpi_comm_world;
 extern extern(C) ompi_predefined_communicator_t ompi_mpi_comm_self;
 extern extern(C) ompi_predefined_communicator_t ompi_mpi_comm_null;
 
 enum{ PREDEFINED_GROUP_PAD=((void*).sizeof * 32) }

 struct ompi_predefined_group_t {
     char padding[PREDEFINED_GROUP_PAD];
 }
 
 extern extern(C) ompi_predefined_group_t ompi_mpi_group_empty;
 extern extern(C) ompi_predefined_group_t ompi_mpi_group_null;
 
 enum{ PREDEFINED_REQUEST_PAD=(void*).sizeof * 32 }

 struct ompi_predefined_request_t {
     char padding[PREDEFINED_REQUEST_PAD];
 }
 
 extern extern(C) ompi_predefined_request_t ompi_request_null;
 
 enum{ PREDEFINED_OP_PAD=(void*).sizeof * 256 }

 struct ompi_predefined_op_t {
     char padding[PREDEFINED_OP_PAD ];
 }
 
 extern extern(C) ompi_predefined_op_t ompi_mpi_op_null;
 extern extern(C) ompi_predefined_op_t ompi_mpi_op_max, ompi_mpi_op_min;
 extern extern(C) ompi_predefined_op_t ompi_mpi_op_sum;
 extern extern(C) ompi_predefined_op_t ompi_mpi_op_prod;
 extern extern(C) ompi_predefined_op_t ompi_mpi_op_land;
 extern extern(C) ompi_predefined_op_t ompi_mpi_op_band;
 extern extern(C) ompi_predefined_op_t ompi_mpi_op_lor, ompi_mpi_op_bor;
 extern extern(C) ompi_predefined_op_t ompi_mpi_op_lxor;
 extern extern(C) ompi_predefined_op_t ompi_mpi_op_bxor;
 extern extern(C) ompi_predefined_op_t ompi_mpi_op_maxloc;
 extern extern(C) ompi_predefined_op_t ompi_mpi_op_minloc;
 extern extern(C) ompi_predefined_op_t ompi_mpi_op_replace;
 
 enum{ PREDEFINED_DATATYPE_PAD=512 }

  struct ompi_predefined_datatype_t {
      char padding[PREDEFINED_DATATYPE_PAD];
  }
 
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_char, ompi_mpi_byte;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_int, ompi_mpi_logic;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_short, ompi_mpi_long;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_float, ompi_mpi_double;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_long_double;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_cplex, ompi_mpi_packed;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_signed_char;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_unsigned_char;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_unsigned_short;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_unsigned, ompi_mpi_datatype_null;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_unsigned_long, ompi_mpi_ldblcplex;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_ub, ompi_mpi_lb;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_float_int, ompi_mpi_double_int;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_long_int, ompi_mpi_2int;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_short_int, ompi_mpi_dblcplex;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_integer, ompi_mpi_real;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_dblprec, ompi_mpi_character;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_2real, ompi_mpi_2dblprec;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_2integer, ompi_mpi_longdbl_int;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_wchar, ompi_mpi_long_long_int;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_unsigned_long_long;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_cxx_cplex, ompi_mpi_cxx_dblcplex;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_cxx_ldblcplex;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_cxx_bool;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_2cplex, ompi_mpi_2dblcplex;
/* other MPI2 datatypes */
/+ extern extern(C) ompi_predefined_datatype_t ompi_mpi_logical1;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_logical2;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_logical4;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_logical8;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_integer1;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_integer2;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_integer4;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_integer8;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_real4;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_real8;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_real16;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_complex8;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_complex16;
 extern extern(C) ompi_predefined_datatype_t ompi_mpi_complex32;+/
 enum{ PREDEFINED_ERRHANDLER_PAD=1024 }

 struct ompi_predefined_errhandler_t {
     char padding[PREDEFINED_ERRHANDLER_PAD];
 }
 
 extern extern(C) ompi_predefined_errhandler_t ompi_mpi_errhandler_null;
 extern extern(C) ompi_predefined_errhandler_t ompi_mpi_errors_are_fatal;
 extern extern(C) ompi_predefined_errhandler_t ompi_mpi_errors_return;
 
 enum{ PREDEFINED_WIN_PAD=(void*).sizeof * 64 }

 struct ompi_predefined_win_t {
     char padding[PREDEFINED_WIN_PAD];
 }
 
 extern extern(C) ompi_predefined_win_t ompi_mpi_win_null;
 
 enum{ PREDEFINED_FILE_PAD=(void*).sizeof * 192 }

 struct ompi_predefined_file_t {
     char padding[PREDEFINED_FILE_PAD];
 }
 
 extern extern(C) ompi_predefined_file_t ompi_mpi_file_null;
 
 enum{ PREDEFINED_INFO_PAD=(void*).sizeof * 32 }

 struct ompi_predefined_info_t {
     char padding[PREDEFINED_INFO_PAD];
 };
 
 extern extern(C) ompi_predefined_info_t ompi_mpi_info_null;
 extern extern(C) int *MPI_F_STATUS_IGNORE;
 extern extern(C) int *MPI_F_STATUSES_IGNORE;

/*
 * MPI predefined handles
 */
MPI_Comm MPI_COMM_WORLD;
MPI_Comm MPI_COMM_SELF;
MPI_Group MPI_GROUP_EMPTY;
MPI_Op MPI_MAX;
MPI_Op MPI_MIN;
MPI_Op MPI_SUM;
MPI_Op MPI_PROD;
MPI_Op MPI_LAND;
MPI_Op MPI_BAND;
MPI_Op MPI_LOR;
MPI_Op MPI_BOR;
MPI_Op MPI_LXOR;
MPI_Op MPI_BXOR;
MPI_Op MPI_MAXLOC;
MPI_Op MPI_MINLOC;
MPI_Op MPI_REPLACE;

static this(){
    MPI_COMM_WORLD = cast(MPI_Comm)&ompi_mpi_comm_world;
    MPI_COMM_SELF= cast(MPI_Comm)&ompi_mpi_comm_self;
    MPI_GROUP_EMPTY = cast(MPI_Group)&ompi_mpi_group_empty;
    MPI_MAX = cast(MPI_Op)&ompi_mpi_op_max;
    MPI_MIN = cast(MPI_Op)&ompi_mpi_op_min;
    MPI_SUM = cast(MPI_Op)&ompi_mpi_op_sum;
    MPI_PROD = cast(MPI_Op)&ompi_mpi_op_prod;
    MPI_LAND = cast(MPI_Op)&ompi_mpi_op_land;
    MPI_BAND = cast(MPI_Op)&ompi_mpi_op_band;
    MPI_LOR = cast(MPI_Op)&ompi_mpi_op_lor;
    MPI_BOR = cast(MPI_Op)&ompi_mpi_op_bor;
    MPI_LXOR = cast(MPI_Op)&ompi_mpi_op_lxor;
    MPI_BXOR = cast(MPI_Op)&ompi_mpi_op_bxor;
    MPI_MAXLOC = cast(MPI_Op)&ompi_mpi_op_maxloc;
    MPI_MINLOC = cast(MPI_Op)&ompi_mpi_op_minloc;
    MPI_REPLACE = cast(MPI_Op)&ompi_mpi_op_replace;
}
/* C datatypes */
MPI_Datatype MPI_DATATYPE_NULL;
MPI_Datatype MPI_BYTE;
MPI_Datatype MPI_PACKED;
MPI_Datatype MPI_CHAR;
MPI_Datatype MPI_SHORT;
MPI_Datatype MPI_INT;
MPI_Datatype MPI_LONG;
MPI_Datatype MPI_FLOAT;
MPI_Datatype MPI_DOUBLE;
MPI_Datatype MPI_LONG_DOUBLE;
MPI_Datatype MPI_UNSIGNED_CHAR;
MPI_Datatype MPI_SIGNED_CHAR;
MPI_Datatype MPI_UNSIGNED_SHORT;
MPI_Datatype MPI_UNSIGNED_LONG;
MPI_Datatype MPI_UNSIGNED;
MPI_Datatype MPI_FLOAT_INT;
MPI_Datatype MPI_DOUBLE_INT;
MPI_Datatype MPI_LONG_DOUBLE_INT;
MPI_Datatype MPI_LONG_INT;
MPI_Datatype MPI_SHORT_INT;
MPI_Datatype MPI_2INT;
MPI_Datatype MPI_UB;
MPI_Datatype MPI_LB;
MPI_Datatype MPI_WCHAR;
MPI_Datatype MPI_LONG_LONG_INT;
MPI_Datatype MPI_LONG_LONG;
MPI_Datatype MPI_UNSIGNED_LONG_LONG;
MPI_Datatype MPI_2COMPLEX;
MPI_Datatype MPI_2DOUBLE_COMPLEX;

static this(){
    MPI_DATATYPE_NULL = cast(MPI_Datatype)&ompi_mpi_datatype_null;
    MPI_BYTE = cast(MPI_Datatype)&ompi_mpi_byte;
    MPI_PACKED = cast(MPI_Datatype)&ompi_mpi_packed;
    MPI_CHAR = cast(MPI_Datatype)&ompi_mpi_char;
    MPI_SHORT = cast(MPI_Datatype)&ompi_mpi_short;
    MPI_INT = cast(MPI_Datatype)&ompi_mpi_int;
    MPI_LONG = cast(MPI_Datatype)&ompi_mpi_long;
    MPI_FLOAT = cast(MPI_Datatype)&ompi_mpi_float;
    MPI_DOUBLE = cast(MPI_Datatype)&ompi_mpi_double;
    MPI_LONG_DOUBLE = cast(MPI_Datatype)&ompi_mpi_long_double;
    MPI_UNSIGNED_CHAR = cast(MPI_Datatype)&ompi_mpi_unsigned_char;
    MPI_SIGNED_CHAR = cast(MPI_Datatype)&ompi_mpi_signed_char;
    MPI_UNSIGNED_SHORT = cast(MPI_Datatype)&ompi_mpi_unsigned_short;
    MPI_UNSIGNED_LONG = cast(MPI_Datatype)&ompi_mpi_unsigned_long;
    MPI_UNSIGNED = cast(MPI_Datatype)&ompi_mpi_unsigned;
    MPI_FLOAT_INT = cast(MPI_Datatype)&ompi_mpi_float_int;
    MPI_DOUBLE_INT = cast(MPI_Datatype)&ompi_mpi_double_int;
    MPI_LONG_DOUBLE_INT = cast(MPI_Datatype)&ompi_mpi_longdbl_int;
    MPI_LONG_INT = cast(MPI_Datatype)&ompi_mpi_long_int;
    MPI_SHORT_INT = cast(MPI_Datatype)&ompi_mpi_short_int;
    MPI_2INT = cast(MPI_Datatype)&ompi_mpi_2int;
    MPI_UB = cast(MPI_Datatype)&ompi_mpi_ub;
    MPI_LB = cast(MPI_Datatype)&ompi_mpi_lb;
    MPI_WCHAR = cast(MPI_Datatype)&ompi_mpi_wchar;
    MPI_LONG_LONG_INT = cast(MPI_Datatype)&ompi_mpi_long_long_int;
    MPI_LONG_LONG = cast(MPI_Datatype)&ompi_mpi_long_long_int;
    MPI_UNSIGNED_LONG_LONG = cast(MPI_Datatype)&ompi_mpi_unsigned_long_long;
    MPI_2COMPLEX = cast(MPI_Datatype)&ompi_mpi_2cplex;
    MPI_2DOUBLE_COMPLEX = cast(MPI_Datatype)&ompi_mpi_2dblcplex;
}
/* Fortran datatype bindings */
MPI_Datatype MPI_CHARACTER;
MPI_Datatype MPI_LOGICAL;
MPI_Datatype MPI_LOGICAL1;
MPI_Datatype MPI_LOGICAL2;
MPI_Datatype MPI_LOGICAL4;
MPI_Datatype MPI_LOGICAL8;
MPI_Datatype MPI_INTEGER;
MPI_Datatype MPI_INTEGER1;
MPI_Datatype MPI_INTEGER2;
MPI_Datatype MPI_INTEGER4;
MPI_Datatype MPI_INTEGER8;
MPI_Datatype MPI_REAL;
MPI_Datatype MPI_REAL4;
MPI_Datatype MPI_REAL8;
MPI_Datatype MPI_REAL16;
MPI_Datatype MPI_DOUBLE_PRECISION;
MPI_Datatype MPI_COMPLEX;
MPI_Datatype MPI_COMPLEX8;
MPI_Datatype MPI_COMPLEX16;
MPI_Datatype MPI_COMPLEX32;
MPI_Datatype MPI_DOUBLE_COMPLEX;
MPI_Datatype MPI_2REAL;
MPI_Datatype MPI_2DOUBLE_PRECISION;
MPI_Datatype MPI_2INTEGER;
MPI_Errhandler MPI_ERRORS_ARE_FATAL;
MPI_Errhandler MPI_ERRORS_RETURN;

static this(){
 MPI_CHARACTER = cast(MPI_Datatype)&ompi_mpi_character;
 MPI_LOGICAL = cast(MPI_Datatype)&ompi_mpi_logic;
/+ MPI_LOGICAL1 = cast(MPI_Datatype)&ompi_mpi_logical1;
 MPI_LOGICAL2 = cast(MPI_Datatype)&ompi_mpi_logical2;
 MPI_LOGICAL4 = cast(MPI_Datatype)&ompi_mpi_logical4;
 MPI_LOGICAL8 = cast(MPI_Datatype)&ompi_mpi_logical8;+/
 MPI_INTEGER = cast(MPI_Datatype)&ompi_mpi_integer;
/+ MPI_INTEGER1 = cast(MPI_Datatype)&ompi_mpi_integer1;
 MPI_INTEGER2 = cast(MPI_Datatype)&ompi_mpi_integer2;
 MPI_INTEGER4 = cast(MPI_Datatype)&ompi_mpi_integer4;
 MPI_INTEGER8 = cast(MPI_Datatype)&ompi_mpi_integer8;+/
 MPI_REAL = cast(MPI_Datatype)&ompi_mpi_real;
/+ MPI_REAL4 = cast(MPI_Datatype)&ompi_mpi_real4;
 MPI_REAL8 = cast(MPI_Datatype)&ompi_mpi_real8;
 MPI_REAL16 = cast(MPI_Datatype)&ompi_mpi_real16;+/
 MPI_DOUBLE_PRECISION = cast(MPI_Datatype)&ompi_mpi_dblprec;
 MPI_COMPLEX = cast(MPI_Datatype)&ompi_mpi_cplex;
/+ MPI_COMPLEX8 = cast(MPI_Datatype)&ompi_mpi_complex8;
 MPI_COMPLEX16 = cast(MPI_Datatype)&ompi_mpi_complex16;
 MPI_COMPLEX32 = cast(MPI_Datatype)&ompi_mpi_complex32;+/
 MPI_DOUBLE_COMPLEX = cast(MPI_Datatype)&ompi_mpi_dblcplex;
 MPI_2REAL = cast(MPI_Datatype)&ompi_mpi_2real;
 MPI_2DOUBLE_PRECISION = cast(MPI_Datatype)&ompi_mpi_2dblprec;
 MPI_2INTEGER = cast(MPI_Datatype)&ompi_mpi_2integer;
 MPI_ERRORS_ARE_FATAL = cast(MPI_Errhandler)&ompi_mpi_errors_are_fatal;
 MPI_ERRORS_RETURN = cast(MPI_Errhandler)&ompi_mpi_errors_return;
}

/* Typeclass definition for MPI_Type_match_size */
enum MPI_TYPECLASS{
    INTEGER=1,
    REAL=2,
    COMPLEX=3,
}

/*
 * MPI API
 */
extern(C):
int MPI_Abort(MPI_Comm comm, int errorcode);
int MPI_Accumulate(void *origin_addr, int origin_count, MPI_Datatype origin_datatype,
                                  int target_rank, MPI_Aint target_disp, int target_count,
                                  MPI_Datatype target_datatype, MPI_Op op, MPI_Win win);
int MPI_Add_error_class(int *errorclass);
int MPI_Add_error_code(int errorclass, int *errorcode);
int MPI_Add_error_string(int errorcode, char *string);
int MPI_Address(void *location, MPI_Aint *address);
int MPI_Allgather(void *sendbuf, int sendcount, MPI_Datatype sendtype,
                                 void *recvbuf, int recvcount,
                                 MPI_Datatype recvtype, MPI_Comm comm);
int MPI_Allgatherv(void *sendbuf, int sendcount, MPI_Datatype sendtype,
                                  void *recvbuf, int *recvcounts,
                                  int *displs, MPI_Datatype recvtype, MPI_Comm comm);
int MPI_Alloc_mem(MPI_Aint size, MPI_Info info,
                                 void *baseptr);
int MPI_Allreduce(void *sendbuf, void *recvbuf, int count,
                                 MPI_Datatype datatype, MPI_Op op, MPI_Comm comm);
int MPI_Alltoall(void *sendbuf, int sendcount, MPI_Datatype sendtype,
                                void *recvbuf, int recvcount,
                                MPI_Datatype recvtype, MPI_Comm comm);
int MPI_Alltoallv(void *sendbuf, int *sendcounts, int *sdispls,
                                 MPI_Datatype sendtype, void *recvbuf, int *recvcounts,
                                 int *rdispls, MPI_Datatype recvtype, MPI_Comm comm);
int MPI_Alltoallw(void *sendbuf, int *sendcounts, int *sdispls, MPI_Datatype *sendtypes,
                                 void *recvbuf, int *recvcounts, int *rdispls, MPI_Datatype *recvtypes,
                                 MPI_Comm comm);
int MPI_Attr_delete(MPI_Comm comm, int keyval);
int MPI_Attr_get(MPI_Comm comm, int keyval, void *attribute_val, int *flag);
int MPI_Attr_put(MPI_Comm comm, int keyval, void *attribute_val);
int MPI_Barrier(MPI_Comm comm);
int MPI_Bcast(void *buffer, int count, MPI_Datatype datatype,
                             int root, MPI_Comm comm);
int MPI_Bsend(void *buf, int count, MPI_Datatype datatype,
                             int dest, int tag, MPI_Comm comm);
int MPI_Bsend_init(void *buf, int count, MPI_Datatype datatype,
                                  int dest, int tag, MPI_Comm comm, MPI_Request *request);
int MPI_Buffer_attach(void *buffer, int size);
int MPI_Buffer_detach(void *buffer, int *size);
int MPI_Cancel(MPI_Request *request);
int MPI_Cart_coords(MPI_Comm comm, int rank, int maxdims, int *coords);
int MPI_Cart_create(MPI_Comm old_comm, int ndims, int *dims,
                                   int *periods, int reorder, MPI_Comm *comm_cart);
int MPI_Cart_get(MPI_Comm comm, int maxdims, int *dims,
                                int *periods, int *coords);
int MPI_Cart_map(MPI_Comm comm, int ndims, int *dims,
                                int *periods, int *newrank);
int MPI_Cart_rank(MPI_Comm comm, int *coords, int *rank);
int MPI_Cart_shift(MPI_Comm comm, int direction, int disp,
                                  int *rank_source, int *rank_dest);
int MPI_Cart_sub(MPI_Comm comm, int *remain_dims, MPI_Comm *new_comm);
int MPI_Cartdim_get(MPI_Comm comm, int *ndims);
int MPI_Close_port(char *port_name);
int MPI_Comm_accept(char *port_name, MPI_Info info, int root,
                                   MPI_Comm comm, MPI_Comm *newcomm);
int MPI_Comm_c2f(MPI_Comm comm);
int MPI_Comm_call_errhandler(MPI_Comm comm, int errorcode);
int MPI_Comm_compare(MPI_Comm comm1, MPI_Comm comm2, int *result);
int MPI_Comm_connect(char *port_name, MPI_Info info, int root,
                                    MPI_Comm comm, MPI_Comm *newcomm);
int MPI_Comm_create_errhandler(MPI_Comm_errhandler_fn *f,
                                MPI_Errhandler *errhandler);
int MPI_Comm_create_keyval(MPI_Comm_copy_attr_function *comm_copy_attr_fn,
                                          MPI_Comm_delete_attr_function *comm_delete_attr_fn,
                                          int *comm_keyval, void *extra_state);
int MPI_Comm_create(MPI_Comm comm, MPI_Group group, MPI_Comm *newcomm);
int MPI_Comm_delete_attr(MPI_Comm comm, int comm_keyval);
int MPI_Comm_disconnect(MPI_Comm *comm);
int MPI_Comm_dup(MPI_Comm comm, MPI_Comm *newcomm);
MPI_Comm MPI_Comm_f2c(int comm);
int MPI_Comm_free_keyval(int *comm_keyval);
int MPI_Comm_free(MPI_Comm *comm);
int MPI_Comm_get_attr(MPI_Comm comm, int comm_keyval,
                                     void *attribute_val, int *flag);
int MPI_Comm_get_errhandler(MPI_Comm comm, MPI_Errhandler *erhandler);
int MPI_Comm_get_name(MPI_Comm comm, char *comm_name, int *resultlen);
int MPI_Comm_get_parent(MPI_Comm *parent);
int MPI_Comm_group(MPI_Comm comm, MPI_Group *group);
int MPI_Comm_join(int fd, MPI_Comm *intercomm);
int MPI_Comm_rank(MPI_Comm comm, int *rank);
int MPI_Comm_remote_group(MPI_Comm comm, MPI_Group *group);
int MPI_Comm_remote_size(MPI_Comm comm, int *size);
int MPI_Comm_set_attr(MPI_Comm comm, int comm_keyval, void *attribute_val);
int MPI_Comm_set_errhandler(MPI_Comm comm, MPI_Errhandler errhandler);
int MPI_Comm_set_name(MPI_Comm comm, char *comm_name);
int MPI_Comm_size(MPI_Comm comm, int *size);
int MPI_Comm_spawn(char *command, char **argv, int maxprocs, MPI_Info info,
                                  int root, MPI_Comm comm, MPI_Comm *intercomm,
                                  int *array_of_errcodes);
int MPI_Comm_spawn_multiple(int count, char **array_of_commands, char ***array_of_argv,
                                           int *array_of_maxprocs, MPI_Info *array_of_info,
                                           int root, MPI_Comm comm, MPI_Comm *intercomm,
                                           int *array_of_errcodes);
int MPI_Comm_split(MPI_Comm comm, int color, int key, MPI_Comm *newcomm);
int MPI_Comm_test_inter(MPI_Comm comm, int *flag);
int MPI_Dims_create(int nnodes, int ndims, int *dims);
int MPI_Errhandler_c2f(MPI_Errhandler errhandler);
int MPI_Errhandler_create(MPI_Handler_function *f,
                                         MPI_Errhandler *errhandler);
MPI_Errhandler MPI_Errhandler_f2c(int errhandler);
int MPI_Errhandler_free(MPI_Errhandler *errhandler);
int MPI_Errhandler_get(MPI_Comm comm, MPI_Errhandler *errhandler);
int MPI_Errhandler_set(MPI_Comm comm, MPI_Errhandler errhandler);
int MPI_Error_class(int errorcode, int *errorclass);
int MPI_Error_string(int errorcode, char *string, int *resultlen);
int MPI_Exscan(void *sendbuf, void *recvbuf, int count,
                              MPI_Datatype datatype, MPI_Op op, MPI_Comm comm);
int MPI_File_c2f(MPI_File file);
MPI_File MPI_File_f2c(int file);
int MPI_File_call_errhandler(MPI_File fh, int errorcode);
int MPI_File_create_errhandler(MPI_File_errhandler_fn *f,
                                              MPI_Errhandler *errhandler);
int MPI_File_set_errhandler( MPI_File file, MPI_Errhandler errhandler);
int MPI_File_get_errhandler( MPI_File file, MPI_Errhandler *errhandler);
int MPI_File_open(MPI_Comm comm, char *filename, int amode,
                                 MPI_Info info, MPI_File *fh);
int MPI_File_close(MPI_File *fh);
int MPI_File_delete(char *filename, MPI_Info info);
int MPI_File_set_size(MPI_File fh, MPI_Offset size);
int MPI_File_preallocate(MPI_File fh, MPI_Offset size);
int MPI_File_get_size(MPI_File fh, MPI_Offset *size);
int MPI_File_get_group(MPI_File fh, MPI_Group *group);
int MPI_File_get_amode(MPI_File fh, int *amode);
int MPI_File_set_info(MPI_File fh, MPI_Info info);
int MPI_File_get_info(MPI_File fh, MPI_Info *info_used);
int MPI_File_set_view(MPI_File fh, MPI_Offset disp, MPI_Datatype etype,
                                     MPI_Datatype filetype, char *datarep, MPI_Info info);
int MPI_File_get_view(MPI_File fh, MPI_Offset *disp,
                                     MPI_Datatype *etype,
                                     MPI_Datatype *filetype, char *datarep);
int MPI_File_read_at(MPI_File fh, MPI_Offset offset, void *buf,
                                    int count, MPI_Datatype datatype, MPI_Status *status);
int MPI_File_read_at_all(MPI_File fh, MPI_Offset offset, void *buf,
                                        int count, MPI_Datatype datatype, MPI_Status *status);
int MPI_File_write_at(MPI_File fh, MPI_Offset offset, void *buf,
                                     int count, MPI_Datatype datatype, MPI_Status *status);
int MPI_File_write_at_all(MPI_File fh, MPI_Offset offset, void *buf,
                                         int count, MPI_Datatype datatype, MPI_Status *status);
int MPI_File_iread_at(MPI_File fh, MPI_Offset offset, void *buf,
                                     int count, MPI_Datatype datatype, MPI_Request *request);
int MPI_File_iwrite_at(MPI_File fh, MPI_Offset offset, void *buf,
                                      int count, MPI_Datatype datatype, MPI_Request *request);
int MPI_File_read(MPI_File fh, void *buf, int count,
                                 MPI_Datatype datatype, MPI_Status *status);
int MPI_File_read_all(MPI_File fh, void *buf, int count,
                                     MPI_Datatype datatype, MPI_Status *status);
int MPI_File_write(MPI_File fh, void *buf, int count,
                                  MPI_Datatype datatype, MPI_Status *status);
int MPI_File_write_all(MPI_File fh, void *buf, int count,
                                      MPI_Datatype datatype, MPI_Status *status);
int MPI_File_iread(MPI_File fh, void *buf, int count,
                                  MPI_Datatype datatype, MPI_Request *request);
int MPI_File_iwrite(MPI_File fh, void *buf, int count,
                                   MPI_Datatype datatype, MPI_Request *request);
int MPI_File_seek(MPI_File fh, MPI_Offset offset, int whence);
int MPI_File_get_position(MPI_File fh, MPI_Offset *offset);
int MPI_File_get_byte_offset(MPI_File fh, MPI_Offset offset,
                                            MPI_Offset *disp);
int MPI_File_read_shared(MPI_File fh, void *buf, int count,
                                        MPI_Datatype datatype, MPI_Status *status);
int MPI_File_write_shared(MPI_File fh, void *buf, int count,
      MPI_Datatype datatype, MPI_Status *status);
int MPI_File_iread_shared(MPI_File fh, void *buf, int count,
                                         MPI_Datatype datatype, MPI_Request *request);
int MPI_File_iwrite_shared(MPI_File fh, void *buf, int count,
                                          MPI_Datatype datatype, MPI_Request *request);
int MPI_File_read_ordered(MPI_File fh, void *buf, int count,
                                         MPI_Datatype datatype, MPI_Status *status);
int MPI_File_write_ordered(MPI_File fh, void *buf, int count,
                                          MPI_Datatype datatype, MPI_Status *status);
int MPI_File_seek_shared(MPI_File fh, MPI_Offset offset, int whence);
int MPI_File_get_position_shared(MPI_File fh, MPI_Offset *offset);
int MPI_File_read_at_all_begin(MPI_File fh, MPI_Offset offset, void *buf,
                                              int count, MPI_Datatype datatype);
int MPI_File_read_at_all_end(MPI_File fh, void *buf, MPI_Status *status);
int MPI_File_write_at_all_begin(MPI_File fh, MPI_Offset offset, void *buf,
                                               int count, MPI_Datatype datatype);
int MPI_File_write_at_all_end(MPI_File fh, void *buf, MPI_Status *status);
int MPI_File_read_all_begin(MPI_File fh, void *buf, int count,
                                           MPI_Datatype datatype);
int MPI_File_read_all_end(MPI_File fh, void *buf, MPI_Status *status);
int MPI_File_write_all_begin(MPI_File fh, void *buf, int count,
                                            MPI_Datatype datatype);
int MPI_File_write_all_end(MPI_File fh, void *buf, MPI_Status *status);
int MPI_File_read_ordered_begin(MPI_File fh, void *buf, int count,
                                               MPI_Datatype datatype);
int MPI_File_read_ordered_end(MPI_File fh, void *buf, MPI_Status *status);
int MPI_File_write_ordered_begin(MPI_File fh, void *buf, int count,
                                                MPI_Datatype datatype);
int MPI_File_write_ordered_end(MPI_File fh, void *buf, MPI_Status *status);
int MPI_File_get_type_extent(MPI_File fh, MPI_Datatype datatype,
                                            MPI_Aint *extent);
int MPI_File_set_atomicity(MPI_File fh, int flag);
int MPI_File_get_atomicity(MPI_File fh, int *flag);
int MPI_File_sync(MPI_File fh);
int MPI_Finalize();
int MPI_Finalized(int *flag);
int MPI_Free_mem(void *base);
int MPI_Gather(void *sendbuf, int sendcount, MPI_Datatype sendtype,
                              void *recvbuf, int recvcount, MPI_Datatype recvtype,
                              int root, MPI_Comm comm);
int MPI_Gatherv(void *sendbuf, int sendcount, MPI_Datatype sendtype,
                               void *recvbuf, int *recvcounts, int *displs,
                               MPI_Datatype recvtype, int root, MPI_Comm comm);
int MPI_Get_address(void *location, MPI_Aint *address);
int MPI_Get_count(MPI_Status *status, MPI_Datatype datatype, int *count);
int MPI_Get_elements(MPI_Status *status, MPI_Datatype datatype, int *count);
int MPI_Get(void *origin_addr, int origin_count,
                           MPI_Datatype origin_datatype, int target_rank,
                           MPI_Aint target_disp, int target_count,
                           MPI_Datatype target_datatype, MPI_Win win);
int MPI_Get_processor_name(char *name, int *resultlen);
int MPI_Get_version(int *vers, int *subversion);
int MPI_Graph_create(MPI_Comm comm_old, int nnodes, int *index,
                                    int *edges, int reorder, MPI_Comm *comm_graph);
int MPI_Graph_get(MPI_Comm comm, int maxindex, int maxedges,
                                 int *index, int *edges);
int MPI_Graph_map(MPI_Comm comm, int nnodes, int *index, int *edges,
                                 int *newrank);
int MPI_Graph_neighbors_count(MPI_Comm comm, int rank, int *nneighbors);
int MPI_Graph_neighbors(MPI_Comm comm, int rank, int maxneighbors,
                                       int *neighbors);
int MPI_Graphdims_get(MPI_Comm comm, int *nnodes, int *nedges);
int MPI_Grequest_complete(MPI_Request request);
int MPI_Grequest_start(MPI_Grequest_query_function *query_fn,
                                      MPI_Grequest_free_function *free_fn,
                                      MPI_Grequest_cancel_function *cancel_fn,
                                      void *extra_state, MPI_Request *request);
int MPI_Group_c2f(MPI_Group group);
int MPI_Group_compare(MPI_Group group1, MPI_Group group2, int *result);
int MPI_Group_difference(MPI_Group group1, MPI_Group group2,
                                        MPI_Group *newgroup);
int MPI_Group_excl(MPI_Group group, int n, int *ranks,
                                  MPI_Group *newgroup);
MPI_Group MPI_Group_f2c(int group);
int MPI_Group_free(MPI_Group *group);
int MPI_Group_incl(MPI_Group group, int n, int *ranks,
                                  MPI_Group *newgroup);
int MPI_Group_intersection(MPI_Group group1, MPI_Group group2,
                                          MPI_Group *newgroup);
int MPI_Group_range_excl(MPI_Group group, int n, int ranges[][3],
                                        MPI_Group *newgroup);
int MPI_Group_range_incl(MPI_Group group, int n, int ranges[][3],
                                        MPI_Group *newgroup);
int MPI_Group_rank(MPI_Group group, int *rank);
int MPI_Group_size(MPI_Group group, int *size);
int MPI_Group_translate_ranks(MPI_Group group1, int n, int *ranks1,
                                             MPI_Group group2, int *ranks2);
int MPI_Group_union(MPI_Group group1, MPI_Group group2,
                                   MPI_Group *newgroup);
int MPI_Ibsend(void *buf, int count, MPI_Datatype datatype, int dest,
                              int tag, MPI_Comm comm, MPI_Request *request);
int MPI_Info_c2f(MPI_Info info);
int MPI_Info_create(MPI_Info *info);
int MPI_Info_delete(MPI_Info info, char *key);
int MPI_Info_dup(MPI_Info info, MPI_Info *newinfo);
MPI_Info MPI_Info_f2c(int info);
int MPI_Info_free(MPI_Info *info);
int MPI_Info_get(MPI_Info info, char *key, int valuelen,
                                char *value, int *flag);
int MPI_Info_get_nkeys(MPI_Info info, int *nkeys);
int MPI_Info_get_nthkey(MPI_Info info, int n, char *key);
int MPI_Info_get_valuelen(MPI_Info info, char *key, int *valuelen,
                                         int *flag);
int MPI_Info_set(MPI_Info info, char *key, char *value);
int MPI_Init(int *argc, char ***argv);
int MPI_Initialized(int *flag);
int MPI_Init_thread(int *argc, char ***argv, int required,
                                   int *provided);
int MPI_Intercomm_create(MPI_Comm local_comm, int local_leader,
                                        MPI_Comm bridge_comm, int remote_leader,
                                        int tag, MPI_Comm *newintercomm);
int MPI_Intercomm_merge(MPI_Comm intercomm, int high,
                                       MPI_Comm *newintercomm);
int MPI_Iprobe(int source, int tag, MPI_Comm comm, int *flag,
                              MPI_Status *status);
int MPI_Irecv(void *buf, int count, MPI_Datatype datatype, int source,
                             int tag, MPI_Comm comm, MPI_Request *request);
int MPI_Irsend(void *buf, int count, MPI_Datatype datatype, int dest,
                              int tag, MPI_Comm comm, MPI_Request *request);
int MPI_Isend(void *buf, int count, MPI_Datatype datatype, int dest,
                             int tag, MPI_Comm comm, MPI_Request *request);
int MPI_Issend(void *buf, int count, MPI_Datatype datatype, int dest,
                              int tag, MPI_Comm comm, MPI_Request *request);
int MPI_Is_thread_main(int *flag);
int MPI_Keyval_create(MPI_Copy_function *copy_fn,
                                     MPI_Delete_function *delete_fn,
                                     int *keyval, void *extra_state);
int MPI_Keyval_free(int *keyval);
int MPI_Lookup_name(char *service_name, MPI_Info info, char *port_name);
int MPI_Op_c2f(MPI_Op op);
int MPI_Op_create(MPI_User_function *fn, int commute, MPI_Op *op);
int MPI_Open_port(MPI_Info info, char *port_name);
MPI_Op MPI_Op_f2c(int op);
int MPI_Op_free(MPI_Op *op);
int MPI_Pack_external(char *datarep, void *inbuf, int incount,
                                     MPI_Datatype datatype, void *outbuf,
                                     MPI_Aint outsize, MPI_Aint *position);
int MPI_Pack_external_size(char *datarep, int incount,
                                          MPI_Datatype datatype, MPI_Aint *size);
int MPI_Pack(void *inbuf, int incount, MPI_Datatype datatype,
                            void *outbuf, int outsize, int *position, MPI_Comm comm);
int MPI_Pack_size(int incount, MPI_Datatype datatype, MPI_Comm comm,
                                 int *size);
int MPI_Pcontrol(int level, ...);
int MPI_Probe(int source, int tag, MPI_Comm comm, MPI_Status *status);
int MPI_Publish_name(char *service_name, MPI_Info info,
                                    char *port_name);
int MPI_Put(void *origin_addr, int origin_count, MPI_Datatype origin_datatype,
                           int target_rank, MPI_Aint target_disp, int target_count,
                           MPI_Datatype target_datatype, MPI_Win win);
int MPI_Query_thread(int *provided);
int MPI_Recv_init(void *buf, int count, MPI_Datatype datatype, int source,
                                 int tag, MPI_Comm comm, MPI_Request *request);
int MPI_Recv(void *buf, int count, MPI_Datatype datatype, int source,
                            int tag, MPI_Comm comm, MPI_Status *status);
int MPI_Reduce(void *sendbuf, void *recvbuf, int count,
                              MPI_Datatype datatype, MPI_Op op, int root, MPI_Comm comm);
int MPI_Reduce_scatter(void *sendbuf, void *recvbuf, int *recvcounts,
                                      MPI_Datatype datatype, MPI_Op op, MPI_Comm comm);
int MPI_Register_datarep(char *datarep,
                                        MPI_Datarep_conversion_function *read_conversion_fn,
                                        MPI_Datarep_conversion_function *write_conversion_fn,
                                        MPI_Datarep_extent_function *dtype_file_extent_fn,
                                        void *extra_state);
int MPI_Request_c2f(MPI_Request request);
MPI_Request MPI_Request_f2c(int request);
int MPI_Request_free(MPI_Request *request);
int MPI_Request_get_status(MPI_Request request, int *flag,
                                          MPI_Status *status);
int MPI_Rsend(void *ibuf, int count, MPI_Datatype datatype, int dest,
                             int tag, MPI_Comm comm);
int MPI_Rsend_init(void *buf, int count, MPI_Datatype datatype,
                                  int dest, int tag, MPI_Comm comm,
                                  MPI_Request *request);
int MPI_Scan(void *sendbuf, void *recvbuf, int count,
                            MPI_Datatype datatype, MPI_Op op, MPI_Comm comm);
int MPI_Scatter(void *sendbuf, int sendcount, MPI_Datatype sendtype,
                               void *recvbuf, int recvcount, MPI_Datatype recvtype,
                               int root, MPI_Comm comm);
int MPI_Scatterv(void *sendbuf, int *sendcounts, int *displs,
                                MPI_Datatype sendtype, void *recvbuf, int recvcount,
                                MPI_Datatype recvtype, int root, MPI_Comm comm);
int MPI_Send_init(void *buf, int count, MPI_Datatype datatype,
                                 int dest, int tag, MPI_Comm comm,
                                 MPI_Request *request);
int MPI_Send(void *buf, int count, MPI_Datatype datatype, int dest,
                            int tag, MPI_Comm comm);
int MPI_Sendrecv(void *sendbuf, int sendcount, MPI_Datatype sendtype,
                                int dest, int sendtag, void *recvbuf, int recvcount,
                                MPI_Datatype recvtype, int source, int recvtag,
                                MPI_Comm comm, MPI_Status *status);
int MPI_Sendrecv_replace(void * buf, int count, MPI_Datatype datatype,
                                        int dest, int sendtag, int source, int recvtag,
                                        MPI_Comm comm, MPI_Status *status);
int MPI_Ssend_init(void *buf, int count, MPI_Datatype datatype,
                                  int dest, int tag, MPI_Comm comm,
                                  MPI_Request *request);
int MPI_Ssend(void *buf, int count, MPI_Datatype datatype, int dest,
                             int tag, MPI_Comm comm);
int MPI_Start(MPI_Request *request);
int MPI_Startall(int count, MPI_Request *array_of_requests);
int MPI_Status_c2f(MPI_Status *c_status, int *f_status);
int MPI_Status_f2c(int *f_status, MPI_Status *c_status);
int MPI_Status_set_cancelled(MPI_Status *status, int flag);
int MPI_Status_set_elements(MPI_Status *status, MPI_Datatype datatype,
                                           int count);
int MPI_Testall(int count, MPI_Request array_of_requests[], int *flag,
                               MPI_Status array_of_statuses[]);
int MPI_Testany(int count, MPI_Request array_of_requests[], int *index,
                               int *flag, MPI_Status *status);
int MPI_Test(MPI_Request *request, int *flag, MPI_Status *status);
int MPI_Test_cancelled(MPI_Status *status, int *flag);
int MPI_Testsome(int incount, MPI_Request array_of_requests[],
                                int *outcount, int array_of_indices[],
                                MPI_Status array_of_statuses[]);
int MPI_Topo_test(MPI_Comm comm, int *status);
int MPI_Type_c2f(MPI_Datatype datatype);
int MPI_Type_commit(MPI_Datatype *type);
int MPI_Type_contiguous(int count, MPI_Datatype oldtype,
                                       MPI_Datatype *newtype);
int MPI_Type_create_darray(int size, int rank, int ndims,
                                          int gsize_array[], int distrib_array[],
                                          int darg_array[], int psize_array[],
                                          int order, MPI_Datatype oldtype,
                                          MPI_Datatype *newtype);
int MPI_Type_create_f90_complex(int p, int r, MPI_Datatype *newtype);
int MPI_Type_create_f90_integer(int r, MPI_Datatype *newtype);
int MPI_Type_create_f90_real(int p, int r, MPI_Datatype *newtype);
int MPI_Type_create_hindexed(int count, int array_of_blocklengths[],
                                            MPI_Aint array_of_displacements[],
                                            MPI_Datatype oldtype,
                                            MPI_Datatype *newtype);
int MPI_Type_create_hvector(int count, int blocklength, MPI_Aint stride,
                                           MPI_Datatype oldtype,
                                           MPI_Datatype *newtype);
int MPI_Type_create_keyval(MPI_Type_copy_attr_function *type_copy_attr_fn,
                                          MPI_Type_delete_attr_function *type_delete_attr_fn,
                                          int *type_keyval, void *extra_state);
int MPI_Type_create_indexed_block(int count, int blocklength,
                                                 int array_of_displacements[],
                                                 MPI_Datatype oldtype,
                                                 MPI_Datatype *newtype);
int MPI_Type_create_struct(int count, int array_of_block_lengths[],
                                          MPI_Aint array_of_displacements[],
                                          MPI_Datatype array_of_types[],
                                          MPI_Datatype *newtype);
int MPI_Type_create_subarray(int ndims, int size_array[], int subsize_array[],
                                            int start_array[], int order,
                                            MPI_Datatype oldtype, MPI_Datatype *newtype);
int MPI_Type_create_resized(MPI_Datatype oldtype, MPI_Aint lb,
                                           MPI_Aint extent, MPI_Datatype *newtype);
int MPI_Type_delete_attr(MPI_Datatype type, int type_keyval);
int MPI_Type_dup(MPI_Datatype type, MPI_Datatype *newtype);
int MPI_Type_extent(MPI_Datatype type, MPI_Aint *extent);
int MPI_Type_free(MPI_Datatype *type);
int MPI_Type_free_keyval(int *type_keyval);
MPI_Datatype MPI_Type_f2c(int datatype);
int MPI_Type_get_attr(MPI_Datatype type, int type_keyval,
                                     void *attribute_val, int *flag);
int MPI_Type_get_contents(MPI_Datatype mtype, int max_integers,
                                         int max_addresses, int max_datatypes,
                                         int array_of_integers[],
                                         MPI_Aint array_of_addresses[],
                                         MPI_Datatype array_of_datatypes[]);
int MPI_Type_get_envelope(MPI_Datatype type, int *num_integers,
                                         int *num_addresses, int *num_datatypes,
                                         int *combiner);
int MPI_Type_get_extent(MPI_Datatype type, MPI_Aint *lb,
                                       MPI_Aint *extent);
int MPI_Type_get_name(MPI_Datatype type, char *type_name,
                                     int *resultlen);
int MPI_Type_get_true_extent(MPI_Datatype datatype, MPI_Aint *true_lb,
                                            MPI_Aint *true_extent);
int MPI_Type_hindexed(int count, int array_of_blocklengths[],
                                     MPI_Aint array_of_displacements[],
                                     MPI_Datatype oldtype, MPI_Datatype *newtype);
int MPI_Type_hvector(int count, int blocklength, MPI_Aint stride,
                                    MPI_Datatype oldtype, MPI_Datatype *newtype);
int MPI_Type_indexed(int count, int array_of_blocklengths[],
                                    int array_of_displacements[],
                                    MPI_Datatype oldtype, MPI_Datatype *newtype);
int MPI_Type_lb(MPI_Datatype type, MPI_Aint *lb);
int MPI_Type_match_size(int typeclass, int size, MPI_Datatype *type);
int MPI_Type_set_attr(MPI_Datatype type, int type_keyval,
                                     void *attr_val);
int MPI_Type_set_name(MPI_Datatype type, char *type_name);
int MPI_Type_size(MPI_Datatype type, int *size);
int MPI_Type_struct(int count, int array_of_blocklengths[],
                                   MPI_Aint array_of_displacements[],
                                   MPI_Datatype array_of_types[],
                                   MPI_Datatype *newtype);
int MPI_Type_ub(MPI_Datatype mtype, MPI_Aint *ub);
int MPI_Type_vector(int count, int blocklength, int stride,
                                   MPI_Datatype oldtype, MPI_Datatype *newtype);
int MPI_Unpack(void *inbuf, int insize, int *position,
                              void *outbuf, int outcount, MPI_Datatype datatype,
                              MPI_Comm comm);
int MPI_Unpublish_name(char *service_name, MPI_Info info, char *port_name);
int MPI_Unpack_external (char *datarep, void *inbuf, MPI_Aint insize,
                                        MPI_Aint *position, void *outbuf, int outcount,
                                        MPI_Datatype datatype);
int MPI_Waitall(int count, MPI_Request *array_of_requests,
                               MPI_Status *array_of_statuses);
int MPI_Waitany(int count, MPI_Request *array_of_requests,
                               int *index, MPI_Status *status);
int MPI_Wait(MPI_Request *request, MPI_Status *status);
int MPI_Waitsome(int incount, MPI_Request *array_of_requests,
                                int *outcount, int *array_of_indices,
                                MPI_Status *array_of_statuses);
int MPI_Win_c2f(MPI_Win win);
int MPI_Win_call_errhandler(MPI_Win win, int errorcode);
int MPI_Win_complete(MPI_Win win);
int MPI_Win_create(void *base, MPI_Aint size, int disp_unit,
                                  MPI_Info info, MPI_Comm comm, MPI_Win *win);
int MPI_Win_create_errhandler(MPI_Win_errhandler_fn *fn,
                                             MPI_Errhandler *errhandler);
int MPI_Win_create_keyval(MPI_Win_copy_attr_function *win_copy_attr_fn,
                                         MPI_Win_delete_attr_function *win_delete_attr_fn,
                                         int *win_keyval, void *extra_state);
int MPI_Win_delete_attr(MPI_Win win, int win_keyval);
MPI_Win MPI_Win_f2c(int win);
int MPI_Win_fence(int assertV, MPI_Win win);
int MPI_Win_free(MPI_Win *win);
int MPI_Win_free_keyval(int *win_keyval);
int MPI_Win_get_attr(MPI_Win win, int win_keyval,
                                    void *attribute_val, int *flag);
int MPI_Win_get_errhandler(MPI_Win win, MPI_Errhandler *errhandler);
int MPI_Win_get_group(MPI_Win win, MPI_Group *group);
int MPI_Win_get_name(MPI_Win win, char *win_name, int *resultlen);
int MPI_Win_lock(int lock_type, int rank, int assertV, MPI_Win win);
int MPI_Win_post(MPI_Group group, int assertV, MPI_Win win);
int MPI_Win_set_attr(MPI_Win win, int win_keyval, void *attribute_val);
int MPI_Win_set_errhandler(MPI_Win win, MPI_Errhandler errhandler);
int MPI_Win_set_name(MPI_Win win, char *win_name);
int MPI_Win_start(MPI_Group group, int assertV, MPI_Win win);
int MPI_Win_test(MPI_Win win, int *flag);
int MPI_Win_unlock(int rank, MPI_Win win);
int MPI_Win_wait(MPI_Win win);
double MPI_Wtick();
double MPI_Wtime();
  /*
   * Profiling MPI API
   */
int PMPI_Abort(MPI_Comm comm, int errorcode);
int PMPI_Accumulate(void *origin_addr, int origin_count, MPI_Datatype origin_datatype,
                                   int target_rank, MPI_Aint target_disp, int target_count,
                                   MPI_Datatype target_datatype, MPI_Op op, MPI_Win win);
int PMPI_Add_error_class(int *errorclass);
int PMPI_Add_error_code(int errorclass, int *errorcode);
int PMPI_Add_error_string(int errorcode, char *string);
int PMPI_Address(void *location, MPI_Aint *address);
int PMPI_Allgather(void *sendbuf, int sendcount, MPI_Datatype sendtype,
                                  void *recvbuf, int recvcount,
                                  MPI_Datatype recvtype, MPI_Comm comm);
int PMPI_Allgatherv(void *sendbuf, int sendcount, MPI_Datatype sendtype,
                                   void *recvbuf, int *recvcounts,
                                   int *displs, MPI_Datatype recvtype, MPI_Comm comm);
int PMPI_Alloc_mem(MPI_Aint size, MPI_Info info,
                                  void *baseptr);
int PMPI_Allreduce(void *sendbuf, void *recvbuf, int count,
                                  MPI_Datatype datatype, MPI_Op op, MPI_Comm comm);
int PMPI_Alltoall(void *sendbuf, int sendcount, MPI_Datatype sendtype,
                                 void *recvbuf, int recvcount,
                                 MPI_Datatype recvtype, MPI_Comm comm);
int PMPI_Alltoallv(void *sendbuf, int *sendcounts, int *sdispls,
                                  MPI_Datatype sendtype, void *recvbuf, int *recvcounts,
                                  int *rdispls, MPI_Datatype recvtype, MPI_Comm comm);
int PMPI_Alltoallw(void *sendbuf, int *sendcounts, int *sdispls, MPI_Datatype *sendtypes,
                    void *recvbuf, int *recvcounts, int *rdispls, MPI_Datatype *recvtypes,
                    MPI_Comm comm);
int PMPI_Attr_delete(MPI_Comm comm, int keyval);
int PMPI_Attr_get(MPI_Comm comm, int keyval, void *attribute_val, int *flag);
int PMPI_Attr_put(MPI_Comm comm, int keyval, void *attribute_val);
int PMPI_Barrier(MPI_Comm comm);
int PMPI_Bcast(void *buffer, int count, MPI_Datatype datatype,
                              int root, MPI_Comm comm);
int PMPI_Bsend(void *buf, int count, MPI_Datatype datatype,
                              int dest, int tag, MPI_Comm comm);
int PMPI_Bsend_init(void *buf, int count, MPI_Datatype datatype,
                                   int dest, int tag, MPI_Comm comm, MPI_Request *request);
int PMPI_Buffer_attach(void *buffer, int size);
int PMPI_Buffer_detach(void *buffer, int *size);
int PMPI_Cancel(MPI_Request *request);
int PMPI_Cart_coords(MPI_Comm comm, int rank, int maxdims, int *coords);
int PMPI_Cart_create(MPI_Comm old_comm, int ndims, int *dims,
                                    int *periods, int reorder, MPI_Comm *comm_cart);
int PMPI_Cart_get(MPI_Comm comm, int maxdims, int *dims,
                                 int *periods, int *coords);
int PMPI_Cart_map(MPI_Comm comm, int ndims, int *dims,
                                 int *periods, int *newrank);
int PMPI_Cart_rank(MPI_Comm comm, int *coords, int *rank);
int PMPI_Cart_shift(MPI_Comm comm, int direction, int disp,
                                   int *rank_source, int *rank_dest);
int PMPI_Cart_sub(MPI_Comm comm, int *remain_dims, MPI_Comm *new_comm);
int PMPI_Cartdim_get(MPI_Comm comm, int *ndims);
int PMPI_Close_port(char *port_name);
int PMPI_Comm_accept(char *port_name, MPI_Info info, int root,
                                    MPI_Comm comm, MPI_Comm *newcomm);
int PMPI_Comm_c2f(MPI_Comm comm);
int PMPI_Comm_call_errhandler(MPI_Comm comm, int errorcode);
int PMPI_Comm_compare(MPI_Comm comm1, MPI_Comm comm2, int *result);
int PMPI_Comm_connect(char *port_name, MPI_Info info, int root,
                                     MPI_Comm comm, MPI_Comm *newcomm);
int PMPI_Comm_create_errhandler(MPI_Comm_errhandler_fn *fn,
                                               MPI_Errhandler *errhandler);
int PMPI_Comm_create_keyval(MPI_Comm_copy_attr_function *comm_copy_attr_fn,
                                           MPI_Comm_delete_attr_function *comm_delete_attr_fn,
                                           int *comm_keyval, void *extra_state);
int PMPI_Comm_create(MPI_Comm comm, MPI_Group group, MPI_Comm *newcomm);
int PMPI_Comm_delete_attr(MPI_Comm comm, int comm_keyval);
int PMPI_Comm_disconnect(MPI_Comm *comm);
int PMPI_Comm_dup(MPI_Comm comm, MPI_Comm *newcomm);
MPI_Comm PMPI_Comm_f2c(int comm);
int PMPI_Comm_free_keyval(int *comm_keyval);
int PMPI_Comm_free(MPI_Comm *comm);
int PMPI_Comm_get_attr(MPI_Comm comm, int comm_keyval,
                                      void *attribute_val, int *flag);
int PMPI_Comm_get_errhandler(MPI_Comm comm, MPI_Errhandler *erhandler);
int PMPI_Comm_get_name(MPI_Comm comm, char *comm_name, int *resultlen);
int PMPI_Comm_get_parent(MPI_Comm *parent);
int PMPI_Comm_group(MPI_Comm comm, MPI_Group *group);
int PMPI_Comm_join(int fd, MPI_Comm *intercomm);
int PMPI_Comm_rank(MPI_Comm comm, int *rank);
int PMPI_Comm_remote_group(MPI_Comm comm, MPI_Group *group);
int PMPI_Comm_remote_size(MPI_Comm comm, int *size);
int PMPI_Comm_set_attr(MPI_Comm comm, int comm_keyval, void *attribute_val);
int PMPI_Comm_set_errhandler(MPI_Comm comm, MPI_Errhandler errhandler);
int PMPI_Comm_set_name(MPI_Comm comm, char *comm_name);
int PMPI_Comm_size(MPI_Comm comm, int *size);
int PMPI_Comm_spawn(char *command, char **argv, int maxprocs, MPI_Info info,
                                   int root, MPI_Comm comm, MPI_Comm *intercomm,
                                   int *array_of_errcodes);
int PMPI_Comm_spawn_multiple(int count, char **array_of_commands, char ***array_of_argv,
                                            int *array_of_maxprocs, MPI_Info *array_of_info,
                                            int root, MPI_Comm comm, MPI_Comm *intercomm,
                                            int *array_of_errcodes);
int PMPI_Comm_split(MPI_Comm comm, int color, int key, MPI_Comm *newcomm);
int PMPI_Comm_test_inter(MPI_Comm comm, int *flag);
int PMPI_Dims_create(int nnodes, int ndims, int *dims);
int PMPI_Errhandler_c2f(MPI_Errhandler errhandler);
int PMPI_Errhandler_create(MPI_Handler_function *fn,
                                          MPI_Errhandler *errhandler);
MPI_Errhandler PMPI_Errhandler_f2c(int errhandler);
int PMPI_Errhandler_free(MPI_Errhandler *errhandler);
int PMPI_Errhandler_get(MPI_Comm comm, MPI_Errhandler *errhandler);
int PMPI_Errhandler_set(MPI_Comm comm, MPI_Errhandler errhandler);
int PMPI_Error_class(int errorcode, int *errorclass);
int PMPI_Error_string(int errorcode, char *string, int *resultlen);
int PMPI_Exscan(void *sendbuf, void *recvbuf, int count,
                               MPI_Datatype datatype, MPI_Op op, MPI_Comm comm);
int PMPI_File_c2f(MPI_File file);
MPI_File PMPI_File_f2c(int file);
int PMPI_File_call_errhandler(MPI_File fh, int errorcode);
int PMPI_File_create_errhandler(MPI_File_errhandler_fn *fn,
                                               MPI_Errhandler *errhandler);
int PMPI_File_set_errhandler( MPI_File file, MPI_Errhandler errhandler);
int PMPI_File_get_errhandler( MPI_File file, MPI_Errhandler *errhandler);
int PMPI_File_open(MPI_Comm comm, char *filename, int amode,
                                  MPI_Info info, MPI_File *fh);
int PMPI_File_close(MPI_File *fh);
int PMPI_File_delete(char *filename, MPI_Info info);
int PMPI_File_set_size(MPI_File fh, MPI_Offset size);
int PMPI_File_preallocate(MPI_File fh, MPI_Offset size);
int PMPI_File_get_size(MPI_File fh, MPI_Offset *size);
int PMPI_File_get_group(MPI_File fh, MPI_Group *group);
int PMPI_File_get_amode(MPI_File fh, int *amode);
int PMPI_File_set_info(MPI_File fh, MPI_Info info);
int PMPI_File_get_info(MPI_File fh, MPI_Info *info_used);
int PMPI_File_set_view(MPI_File fh, MPI_Offset disp, MPI_Datatype etype,
                                      MPI_Datatype filetype, char *datarep, MPI_Info info);
int PMPI_File_get_view(MPI_File fh, MPI_Offset *disp,
                                      MPI_Datatype *etype,
                                      MPI_Datatype *filetype, char *datarep);
int PMPI_File_read_at(MPI_File fh, MPI_Offset offset, void *buf,
                                     int count, MPI_Datatype datatype, MPI_Status *status);
int PMPI_File_read_at_all(MPI_File fh, MPI_Offset offset, void *buf,
                                         int count, MPI_Datatype datatype, MPI_Status *status);
int PMPI_File_write_at(MPI_File fh, MPI_Offset offset, void *buf,
                                      int count, MPI_Datatype datatype, MPI_Status *status);
int PMPI_File_write_at_all(MPI_File fh, MPI_Offset offset, void *buf,
                                          int count, MPI_Datatype datatype, MPI_Status *status);
int PMPI_File_iread_at(MPI_File fh, MPI_Offset offset, void *buf,
                                      int count, MPI_Datatype datatype, MPI_Request *request);
int PMPI_File_iwrite_at(MPI_File fh, MPI_Offset offset, void *buf,
                                       int count, MPI_Datatype datatype, MPI_Request *request);
int PMPI_File_read(MPI_File fh, void *buf, int count,
                                  MPI_Datatype datatype, MPI_Status *status);
int PMPI_File_read_all(MPI_File fh, void *buf, int count,
                                      MPI_Datatype datatype, MPI_Status *status);
int PMPI_File_write(MPI_File fh, void *buf, int count,
                                   MPI_Datatype datatype, MPI_Status *status);
int PMPI_File_write_all(MPI_File fh, void *buf, int count,
                                       MPI_Datatype datatype, MPI_Status *status);
int PMPI_File_iread(MPI_File fh, void *buf, int count,
                                   MPI_Datatype datatype, MPI_Request *request);
int PMPI_File_iwrite(MPI_File fh, void *buf, int count,
                                    MPI_Datatype datatype, MPI_Request *request);
int PMPI_File_seek(MPI_File fh, MPI_Offset offset, int whence);
int PMPI_File_get_position(MPI_File fh, MPI_Offset *offset);
int PMPI_File_get_byte_offset(MPI_File fh, MPI_Offset offset,
                                             MPI_Offset *disp);
int PMPI_File_read_shared(MPI_File fh, void *buf, int count,
                                         MPI_Datatype datatype, MPI_Status *status);
int PMPI_File_write_shared(MPI_File fh, void *buf, int count,
                                          MPI_Datatype datatype, MPI_Status *status);
int PMPI_File_iread_shared(MPI_File fh, void *buf, int count,
                                          MPI_Datatype datatype, MPI_Request *request);
int PMPI_File_iwrite_shared(MPI_File fh, void *buf, int count,
                                           MPI_Datatype datatype, MPI_Request *request);
int PMPI_File_read_ordered(MPI_File fh, void *buf, int count,
                                          MPI_Datatype datatype, MPI_Status *status);
int PMPI_File_write_ordered(MPI_File fh, void *buf, int count,
                                           MPI_Datatype datatype, MPI_Status *status);
int PMPI_File_seek_shared(MPI_File fh, MPI_Offset offset, int whence);
int PMPI_File_get_position_shared(MPI_File fh, MPI_Offset *offset);
int PMPI_File_read_at_all_begin(MPI_File fh, MPI_Offset offset, void *buf,
                                               int count, MPI_Datatype datatype);
int PMPI_File_read_at_all_end(MPI_File fh, void *buf, MPI_Status *status);
int PMPI_File_write_at_all_begin(MPI_File fh, MPI_Offset offset, void *buf,
                                                int count, MPI_Datatype datatype);
int PMPI_File_write_at_all_end(MPI_File fh, void *buf, MPI_Status *status);
int PMPI_File_read_all_begin(MPI_File fh, void *buf, int count,
                                            MPI_Datatype datatype);
int PMPI_File_read_all_end(MPI_File fh, void *buf, MPI_Status *status);
int PMPI_File_write_all_begin(MPI_File fh, void *buf, int count,
                                             MPI_Datatype datatype);
int PMPI_File_write_all_end(MPI_File fh, void *buf, MPI_Status *status);
int PMPI_File_read_ordered_begin(MPI_File fh, void *buf, int count,
                                                MPI_Datatype datatype);
int PMPI_File_read_ordered_end(MPI_File fh, void *buf, MPI_Status *status);
int PMPI_File_write_ordered_begin(MPI_File fh, void *buf, int count,
                                                 MPI_Datatype datatype);
int PMPI_File_write_ordered_end(MPI_File fh, void *buf, MPI_Status *status);
int PMPI_File_get_type_extent(MPI_File fh, MPI_Datatype datatype,
                                             MPI_Aint *extent);
int PMPI_File_set_atomicity(MPI_File fh, int flag);
int PMPI_File_get_atomicity(MPI_File fh, int *flag);
int PMPI_File_sync(MPI_File fh);
int PMPI_Finalize();
int PMPI_Finalized(int *flag);
int PMPI_Free_mem(void *base);
int PMPI_Gather(void *sendbuf, int sendcount, MPI_Datatype sendtype,
                               void *recvbuf, int recvcount, MPI_Datatype recvtype,
                               int root, MPI_Comm comm);
int PMPI_Gatherv(void *sendbuf, int sendcount, MPI_Datatype sendtype,
                                void *recvbuf, int *recvcounts, int *displs,
                                MPI_Datatype recvtype, int root, MPI_Comm comm);
int PMPI_Get_address(void *location, MPI_Aint *address);
int PMPI_Get_count(MPI_Status *status, MPI_Datatype datatype, int *count);
int PMPI_Get_elements(MPI_Status *status, MPI_Datatype datatype,
                                     int *count);
int PMPI_Get(void *origin_addr, int origin_count,
                            MPI_Datatype origin_datatype, int target_rank,
                            MPI_Aint target_disp, int target_count,
                            MPI_Datatype target_datatype, MPI_Win win);
int PMPI_Get_processor_name(char *name, int *resultlen);
int PMPI_Get_version(int *vers, int *subversion);
int PMPI_Graph_create(MPI_Comm comm_old, int nnodes, int *index,
                                     int *edges, int reorder, MPI_Comm *comm_graph);
int PMPI_Graph_get(MPI_Comm comm, int maxindex, int maxedges,
                                  int *index, int *edges);
int PMPI_Graph_map(MPI_Comm comm, int nnodes, int *index, int *edges,
                                  int *newrank);
int PMPI_Graph_neighbors_count(MPI_Comm comm, int rank, int *nneighbors);
int PMPI_Graph_neighbors(MPI_Comm comm, int rank, int maxneighbors,
                                        int *neighbors);
int PMPI_Graphdims_get(MPI_Comm comm, int *nnodes, int *nedges);
int PMPI_Grequest_complete(MPI_Request request);
int PMPI_Grequest_start(MPI_Grequest_query_function *query_fn,
                                       MPI_Grequest_free_function *free_fn,
                                       MPI_Grequest_cancel_function *cancel_fn,
                                       void *extra_state, MPI_Request *request);
int PMPI_Group_c2f(MPI_Group group);
int PMPI_Group_compare(MPI_Group group1, MPI_Group group2, int *result);
int PMPI_Group_difference(MPI_Group group1, MPI_Group group2,
                                         MPI_Group *newgroup);
int PMPI_Group_excl(MPI_Group group, int n, int *ranks,
                                   MPI_Group *newgroup);
MPI_Group PMPI_Group_f2c(int group);
int PMPI_Group_free(MPI_Group *group);
int PMPI_Group_incl(MPI_Group group, int n, int *ranks,
                                   MPI_Group *newgroup);
int PMPI_Group_intersection(MPI_Group group1, MPI_Group group2,
                                           MPI_Group *newgroup);
int PMPI_Group_range_excl(MPI_Group group, int n, int ranges[][3],
                                         MPI_Group *newgroup);
int PMPI_Group_range_incl(MPI_Group group, int n, int ranges[][3],
                                         MPI_Group *newgroup);
int PMPI_Group_rank(MPI_Group group, int *rank);
int PMPI_Group_size(MPI_Group group, int *size);
int PMPI_Group_translate_ranks(MPI_Group group1, int n, int *ranks1,
                                              MPI_Group group2, int *ranks2);
int PMPI_Group_union(MPI_Group group1, MPI_Group group2,
                                    MPI_Group *newgroup);
int PMPI_Ibsend(void *buf, int count, MPI_Datatype datatype, int dest,
                               int tag, MPI_Comm comm, MPI_Request *request);
int PMPI_Info_c2f(MPI_Info info);
int PMPI_Info_create(MPI_Info *info);
int PMPI_Info_delete(MPI_Info info, char *key);
int PMPI_Info_dup(MPI_Info info, MPI_Info *newinfo);
MPI_Info PMPI_Info_f2c(int info);
int PMPI_Info_free(MPI_Info *info);
int PMPI_Info_get(MPI_Info info, char *key, int valuelen,
                                 char *value, int *flag);
int PMPI_Info_get_nkeys(MPI_Info info, int *nkeys);
int PMPI_Info_get_nthkey(MPI_Info info, int n, char *key);
int PMPI_Info_get_valuelen(MPI_Info info, char *key, int *valuelen,
                                          int *flag);
int PMPI_Info_set(MPI_Info info, char *key, char *value);
int PMPI_Init(int *argc, char ***argv);
int PMPI_Initialized(int *flag);
int PMPI_Init_thread(int *argc, char ***argv, int required,
                                    int *provided);
int PMPI_Intercomm_create(MPI_Comm local_comm, int local_leader,
                                         MPI_Comm bridge_comm, int remote_leader,
                                         int tag, MPI_Comm *newintercomm);
int PMPI_Intercomm_merge(MPI_Comm intercomm, int high,
                                        MPI_Comm *newintercomm);
int PMPI_Iprobe(int source, int tag, MPI_Comm comm, int *flag,
                               MPI_Status *status);
int PMPI_Irecv(void *buf, int count, MPI_Datatype datatype, int source,
                              int tag, MPI_Comm comm, MPI_Request *request);
int PMPI_Irsend(void *buf, int count, MPI_Datatype datatype, int dest,
                               int tag, MPI_Comm comm, MPI_Request *request);
int PMPI_Isend(void *buf, int count, MPI_Datatype datatype, int dest,
                              int tag, MPI_Comm comm, MPI_Request *request);
int PMPI_Issend(void *buf, int count, MPI_Datatype datatype, int dest,
                               int tag, MPI_Comm comm, MPI_Request *request);
int PMPI_Is_thread_main(int *flag);
int PMPI_Keyval_create(MPI_Copy_function *copy_fn,
                                      MPI_Delete_function *delete_fn,
                                      int *keyval, void *extra_state);
int PMPI_Keyval_free(int *keyval);
int PMPI_Lookup_name(char *service_name, MPI_Info info, char *port_name);
int PMPI_Op_c2f(MPI_Op op);
int PMPI_Op_create(MPI_User_function *fn, int commute,
                                  MPI_Op *op);
int PMPI_Open_port(MPI_Info info, char *port_name);
MPI_Op PMPI_Op_f2c(int op);
int PMPI_Op_free(MPI_Op *op);
int PMPI_Pack_external(char *datarep, void *inbuf, int incount,
                                      MPI_Datatype datatype, void *outbuf,
                                      MPI_Aint outsize, MPI_Aint *position);
int PMPI_Pack_external_size(char *datarep, int incount,
                                           MPI_Datatype datatype, MPI_Aint *size);
int PMPI_Pack(void *inbuf, int incount, MPI_Datatype datatype,
                             void *outbuf, int outsize, int *position, MPI_Comm comm);
int PMPI_Pack_size(int incount, MPI_Datatype datatype, MPI_Comm comm,
                                  int *size);
int PMPI_Pcontrol(int level, ...);
int PMPI_Probe(int source, int tag, MPI_Comm comm, MPI_Status *status);
int PMPI_Publish_name(char *service_name, MPI_Info info,
                                     char *port_name);
int PMPI_Put(void *origin_addr, int origin_count, MPI_Datatype origin_datatype,
                            int target_rank, MPI_Aint target_disp, int target_count,
                            MPI_Datatype target_datatype, MPI_Win win);
int PMPI_Query_thread(int *provided);
int PMPI_Recv_init(void *buf, int count, MPI_Datatype datatype, int source,
                                  int tag, MPI_Comm comm, MPI_Request *request);
int PMPI_Recv(void *buf, int count, MPI_Datatype datatype, int source,
                             int tag, MPI_Comm comm, MPI_Status *status);
int PMPI_Reduce(void *sendbuf, void *recvbuf, int count,
                               MPI_Datatype datatype, MPI_Op op, int root, MPI_Comm comm);
int PMPI_Reduce_scatter(void *sendbuf, void *recvbuf, int *recvcounts,
                                       MPI_Datatype datatype, MPI_Op op, MPI_Comm comm);
int PMPI_Register_datarep(char *datarep,
                                         MPI_Datarep_conversion_function *read_conversion_fn,
                                         MPI_Datarep_conversion_function *write_conversion_fn,
                                         MPI_Datarep_extent_function *dtype_file_extent_fn,
                                         void *extra_state);
int PMPI_Request_c2f(MPI_Request request);
MPI_Request PMPI_Request_f2c(int request);
int PMPI_Request_free(MPI_Request *request);
int PMPI_Request_get_status(MPI_Request request, int *flag,
                                           MPI_Status *status);
int PMPI_Rsend(void *ibuf, int count, MPI_Datatype datatype, int dest,
                              int tag, MPI_Comm comm);
int PMPI_Rsend_init(void *buf, int count, MPI_Datatype datatype,
                                   int dest, int tag, MPI_Comm comm,
                                   MPI_Request *request);
int PMPI_Scan(void *sendbuf, void *recvbuf, int count,
                             MPI_Datatype datatype, MPI_Op op, MPI_Comm comm);
int PMPI_Scatter(void *sendbuf, int sendcount, MPI_Datatype sendtype,
                                void *recvbuf, int recvcount, MPI_Datatype recvtype,
                                int root, MPI_Comm comm);
int PMPI_Scatterv(void *sendbuf, int *sendcounts, int *displs,
                                 MPI_Datatype sendtype, void *recvbuf, int recvcount,
                                 MPI_Datatype recvtype, int root, MPI_Comm comm);
int PMPI_Send_init(void *buf, int count, MPI_Datatype datatype,
                                  int dest, int tag, MPI_Comm comm,
                                  MPI_Request *request);
int PMPI_Send(void *buf, int count, MPI_Datatype datatype, int dest,
                             int tag, MPI_Comm comm);
int PMPI_Sendrecv(void *sendbuf, int sendcount, MPI_Datatype sendtype,
                                 int dest, int sendtag, void *recvbuf, int recvcount,
                                 MPI_Datatype recvtype, int source, int recvtag,
                                 MPI_Comm comm, MPI_Status *status);
int PMPI_Sendrecv_replace(void * buf, int count, MPI_Datatype datatype,
                                         int dest, int sendtag, int source, int recvtag,
                                         MPI_Comm comm, MPI_Status *status);
int PMPI_Ssend_init(void *buf, int count, MPI_Datatype datatype,
                                   int dest, int tag, MPI_Comm comm,
                                   MPI_Request *request);
int PMPI_Ssend(void *buf, int count, MPI_Datatype datatype, int dest,
                              int tag, MPI_Comm comm);
int PMPI_Start(MPI_Request *request);
int PMPI_Startall(int count, MPI_Request *array_of_requests);
int PMPI_Status_c2f(MPI_Status *c_status, int *f_status);
int PMPI_Status_f2c(int *f_status, MPI_Status *c_status);
int PMPI_Status_set_cancelled(MPI_Status *status, int flag);
int PMPI_Status_set_elements(MPI_Status *status, MPI_Datatype datatype,
                                            int count);
int PMPI_Testall(int count, MPI_Request array_of_requests[], int *flag,
                                MPI_Status array_of_statuses[]);
int PMPI_Testany(int count, MPI_Request array_of_requests[], int *index, int *flag, MPI_Status *status);
int PMPI_Test(MPI_Request *request, int *flag, MPI_Status *status);
int PMPI_Test_cancelled(MPI_Status *status, int *flag);
int PMPI_Testsome(int incount, MPI_Request array_of_requests[],
                                 int *outcount, int array_of_indices[],
                                 MPI_Status array_of_statuses[]);
int PMPI_Topo_test(MPI_Comm comm, int *status);
int PMPI_Type_c2f(MPI_Datatype datatype);
int PMPI_Type_commit(MPI_Datatype *type);
int PMPI_Type_contiguous(int count, MPI_Datatype oldtype,
                                        MPI_Datatype *newtype);
int PMPI_Type_create_darray(int size, int rank, int ndims,
                                           int gsize_array[], int distrib_array[],
                                           int darg_array[], int psize_array[],
                                           int order, MPI_Datatype oldtype,
                                           MPI_Datatype *newtype);
int PMPI_Type_create_f90_complex(int p, int r, MPI_Datatype *newtype);
int PMPI_Type_create_f90_integer(int r, MPI_Datatype *newtype);
int PMPI_Type_create_f90_real(int p, int r, MPI_Datatype *newtype);
int PMPI_Type_create_hindexed(int count, int array_of_blocklengths[],
                                             MPI_Aint array_of_displacements[],
                                             MPI_Datatype oldtype,
                                             MPI_Datatype *newtype);
int PMPI_Type_create_hvector(int count, int blocklength, MPI_Aint stride,
                                            MPI_Datatype oldtype,
                                            MPI_Datatype *newtype);
int PMPI_Type_create_keyval(MPI_Type_copy_attr_function *type_copy_attr_fn,
                                           MPI_Type_delete_attr_function *type_delete_attr_fn,
                                           int *type_keyval, void *extra_state);
int PMPI_Type_create_indexed_block(int count, int blocklength,
                                                  int array_of_displacements[],
                                                  MPI_Datatype oldtype,
                                                  MPI_Datatype *newtype);
int PMPI_Type_create_struct(int count, int array_of_block_lengths[],
                                           MPI_Aint array_of_displacements[],
                                           MPI_Datatype array_of_types[],
                                           MPI_Datatype *newtype);
int PMPI_Type_create_subarray(int ndims, int size_array[], int subsize_array[],
                                             int start_array[], int order,
                                             MPI_Datatype oldtype, MPI_Datatype *newtype);
int PMPI_Type_create_resized(MPI_Datatype oldtype, MPI_Aint lb,
                                            MPI_Aint extent, MPI_Datatype *newtype);
int PMPI_Type_delete_attr(MPI_Datatype type, int type_keyval);
int PMPI_Type_dup(MPI_Datatype type, MPI_Datatype *newtype);
int PMPI_Type_extent(MPI_Datatype type, MPI_Aint *extent);
int PMPI_Type_free(MPI_Datatype *type);
int PMPI_Type_free_keyval(int *type_keyval);
MPI_Datatype PMPI_Type_f2c(int datatype);
int PMPI_Type_get_attr(MPI_Datatype type, int type_keyval,
                                      void *attribute_val, int *flag);
int PMPI_Type_get_contents(MPI_Datatype mtype, int max_integers,
                                          int max_addresses, int max_datatypes,
                                          int array_of_integers[],
                                          MPI_Aint array_of_addresses[],
                                          MPI_Datatype array_of_datatypes[]);
int PMPI_Type_get_envelope(MPI_Datatype type, int *num_integers,
                                          int *num_addresses, int *num_datatypes,
                                          int *combiner);
int PMPI_Type_get_extent(MPI_Datatype type, MPI_Aint *lb,
                                        MPI_Aint *extent);
int PMPI_Type_get_name(MPI_Datatype type, char *type_name,
                                      int *resultlen);
int PMPI_Type_get_true_extent(MPI_Datatype datatype, MPI_Aint *true_lb,
                                             MPI_Aint *true_extent);
int PMPI_Type_hindexed(int count, int array_of_blocklengths[],
                                      MPI_Aint array_of_displacements[],
                                      MPI_Datatype oldtype, MPI_Datatype *newtype);
int PMPI_Type_hvector(int count, int blocklength, MPI_Aint stride,
                                     MPI_Datatype oldtype, MPI_Datatype *newtype);
int PMPI_Type_indexed(int count, int array_of_blocklengths[],
                                     int array_of_displacements[],
                                     MPI_Datatype oldtype, MPI_Datatype *newtype);
int PMPI_Type_lb(MPI_Datatype type, MPI_Aint *lb);
int PMPI_Type_match_size(int typeclass, int size, MPI_Datatype *type);
int PMPI_Type_set_attr(MPI_Datatype type, int type_keyval,
                                      void *attr_val);
int PMPI_Type_set_name(MPI_Datatype type, char *type_name);
int PMPI_Type_size(MPI_Datatype type, int *size);
int PMPI_Type_struct(int count, int array_of_blocklengths[],
                                    MPI_Aint array_of_displacements[],
                                    MPI_Datatype array_of_types[],
                                    MPI_Datatype *newtype);
int PMPI_Type_ub(MPI_Datatype mtype, MPI_Aint *ub);
int PMPI_Type_vector(int count, int blocklength, int stride,
                                    MPI_Datatype oldtype, MPI_Datatype *newtype);
int PMPI_Unpack(void *inbuf, int insize, int *position,
                               void *outbuf, int outcount, MPI_Datatype datatype,
                               MPI_Comm comm);
int PMPI_Unpublish_name(char *service_name, MPI_Info info,
                                       char *port_name);
int PMPI_Unpack_external (char *datarep, void *inbuf, MPI_Aint insize,
                                         MPI_Aint *position, void *outbuf, int outcount,
                                         MPI_Datatype datatype);
int PMPI_Waitall(int count, MPI_Request *array_of_requests,
                                MPI_Status *array_of_statuses);
int PMPI_Waitany(int count, MPI_Request *array_of_requests,
                                int *index, MPI_Status *status);
int PMPI_Wait(MPI_Request *request, MPI_Status *status);
int PMPI_Waitsome(int incount, MPI_Request *array_of_requests,
                                 int *outcount, int *array_of_indices,
                                 MPI_Status *array_of_statuses);
int PMPI_Win_c2f(MPI_Win win);
int PMPI_Win_call_errhandler(MPI_Win win, int errorcode);
int PMPI_Win_complete(MPI_Win win);
int PMPI_Win_create(void *base, MPI_Aint size, int disp_unit,
                                   MPI_Info info, MPI_Comm comm, MPI_Win *win);
int PMPI_Win_create_errhandler(MPI_Win_errhandler_fn *fn,
                                              MPI_Errhandler *errhandler);
int PMPI_Win_create_keyval(MPI_Win_copy_attr_function *win_copy_attr_fn,
                                          MPI_Win_delete_attr_function *win_delete_attr_fn,
                                          int *win_keyval, void *extra_state);
int PMPI_Win_delete_attr(MPI_Win win, int win_keyval);
MPI_Win PMPI_Win_f2c(int win);
int PMPI_Win_fence(int assertV, MPI_Win win);
int PMPI_Win_free(MPI_Win *win);
int PMPI_Win_free_keyval(int *win_keyval);
int PMPI_Win_get_attr(MPI_Win win, int win_keyval,
                                     void *attribute_val, int *flag);
int PMPI_Win_get_errhandler(MPI_Win win, MPI_Errhandler *errhandler);
int PMPI_Win_get_group(MPI_Win win, MPI_Group *group);
int PMPI_Win_get_name(MPI_Win win, char *win_name, int *resultlen);
int PMPI_Win_lock(int lock_type, int rank, int assertV, MPI_Win win);
int PMPI_Win_post(MPI_Group group, int assertV, MPI_Win win);
int PMPI_Win_set_attr(MPI_Win win, int win_keyval, void *attribute_val);
int PMPI_Win_set_errhandler(MPI_Win win, MPI_Errhandler errhandler);
int PMPI_Win_set_name(MPI_Win win, char *win_name);
int PMPI_Win_start(MPI_Group group, int assertV, MPI_Win win);
int PMPI_Win_test(MPI_Win win, int *flag);
int PMPI_Win_unlock(int rank, MPI_Win win);
int PMPI_Win_wait(MPI_Win win);
double PMPI_Wtick();
double PMPI_Wtime();
} else {
    
    typedef uint MPI_Op;
    
    enum :MPI_Op{
        MPI_MAX    ,
        MPI_MIN    ,
        MPI_SUM    ,
        MPI_PROD   ,
        MPI_LAND   ,
        MPI_BAND   ,
        MPI_LOR    ,
        MPI_BOR    ,
        MPI_LXOR   ,
        MPI_BXOR   ,
        MPI_MAXLOC ,
        MPI_MINLOC ,
        MPI_REPLACE,
    }
}