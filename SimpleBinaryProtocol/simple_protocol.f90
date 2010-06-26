module simple_protocol
public
!! a simple binary protocol
!! kind,size,msg in network order
!! useful to connect fortran programs
!! author: fawzi
!
! Copyright 2008-2010 the blip developer group
! 
! Licensed under the Apache License, Version 2.0 (the "License");
! you may not use this file except in compliance with the License.
! You may obtain a copy of the License at
! 
!     http://www.apache.org/licenses/LICENSE-2.0
! 
! Unless required by applicable law or agreed to in writing, software
! distributed under the License is distributed on an "AS IS" BASIS,
! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
! See the License for the specific language governing permissions and
! limitations under the License.
!
! this file is explicitly released also with GPLv2 for the projects that might need it

! the methods named with the n at the end the 32 bit version (length of string passed
! by value as 32bit integer after the character ptr is probably probably the correct
! one on all compilers (I know no compiler that uses 64 bit int for string length)
! but the 64 bit version is given for completness

! for a slightly better description look at the C header descriptions

INTEGER, PARAMETER :: sbp_real_8 = SELECTED_REAL_KIND ( 14, 200 )
INTEGER, PARAMETER :: sbp_int_8 = SELECTED_INT_KIND(18)
INTEGER, PARAMETER :: sbp_int_4 = SELECTED_INT_KIND(6)

INTEGER(SELECTED_INT_KIND(6)), PARAMETER :: sbp_kind_raw=0, &
    sbp_kind_char=1, &
    sbp_kind_int_small=2, &
    sbp_kind_double_small=3

!!!!!!!!! init/stop lib !!!!!!!!!

INTERFACE
   SUBROUTINE sbpinit(ierr)
    INTEGER(selected_int_kind(6)) :: ierr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpend(ierr)
    INTEGER(selected_int_kind(6)) :: ierr
   END SUBROUTINE
END INTERFACE

!!!!!!!!! sending !!!!!!!!!

INTERFACE
   SUBROUTINE sbpsendh64(ierr,sock,kind,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock,kind
    INTEGER(selected_int_kind(18)) :: len
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpsendh32(ierr,sock,kind,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock,kind,len
   END SUBROUTINE
END INTERFACE

INTERFACE sbpsendh
   MODULE PROCEDURE sbpsendh64, sbpsendh32
END INTERFACE

INTERFACE
   SUBROUTINE sbpsendc32n(ierr,sock,str)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    CHARACTER(LEN=*) :: str
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpsendc64n(ierr,sock,str)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    CHARACTER(LEN=*) :: str
   END SUBROUTINE
END INTERFACE

INTERFACE
   SUBROUTINE sbpsendi64(ierr,sock,iarr,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    INTEGER(selected_int_kind(18)) :: len
    INTEGER(selected_int_kind(6)), dimension(*) :: iarr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpsendi32(ierr,sock,iarr,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock,len
    INTEGER(selected_int_kind(6)), dimension(:) :: iarr
   END SUBROUTINE
END INTERFACE
INTERFACE sbpsendi
    MODULE PROCEDURE sbpsendi64,sbpsendi32
END INTERFACE

INTERFACE
   SUBROUTINE sbpsendip64(ierr,sock,iarr,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    INTEGER(selected_int_kind(18)) :: len
    INTEGER(selected_int_kind(6)), dimension(*) :: iarr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpsendip32(ierr,sock,iarr,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock,len
    INTEGER(selected_int_kind(6)), dimension(*) :: iarr
   END SUBROUTINE
END INTERFACE
INTERFACE sbpsendip
    MODULE PROCEDURE sbpsendip64,sbpsendip32
END INTERFACE

INTERFACE
   SUBROUTINE sbpsendd64(ierr,sock,arr,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    INTEGER(selected_int_kind(18)) :: len
    REAL(selected_real_kind(14,200)), dimension(*) :: arr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpsendd32(ierr,sock,arr,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock,len
    REAL(selected_real_kind(14,200)), dimension(*) :: arr
   END SUBROUTINE
END INTERFACE
INTERFACE sbpsendd
    MODULE PROCEDURE sbpsendd64,sbpsendd32
END INTERFACE

INTERFACE
   SUBROUTINE sbpsenddp64(ierr,sock,arr,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    INTEGER(selected_int_kind(18)) :: len
    REAL(selected_real_kind(14,200)), dimension(*) :: arr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpsenddp32(ierr,sock,arr,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock,len
    REAL(selected_real_kind(14,200)), dimension(*) :: arr
   END SUBROUTINE
END INTERFACE
INTERFACE sbpsenddp
    MODULE PROCEDURE sbpsenddp64,sbpsenddp32
END INTERFACE

!!!!!!!!!!! receiving !!!!!!!!!!!

INTERFACE
   SUBROUTINE sbpreadh64(ierr,sock,kind,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock,kind
    INTEGER(selected_int_kind(18)) :: len
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpreadh32(ierr,sock,kind,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock,kind,len
   END SUBROUTINE
END INTERFACE
INTERFACE sbpreadh
    MODULE PROCEDURE sbpreadh64,sbpreadh32
END INTERFACE

INTERFACE
   SUBROUTINE sbpreadc32n(ierr,sock,str)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    CHARACTER(LEN=*) :: str
   END SUBROUTINE
END INTERFACE
! probably wrong (I know no compiler that uses 64 bit int for string length)
INTERFACE
   SUBROUTINE sbpreadc64n(ierr,sock,str)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    CHARACTER(LEN=*) :: str
   END SUBROUTINE
END INTERFACE

INTERFACE
   SUBROUTINE sbpreadcp32n(ierr,sock,str)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    CHARACTER(LEN=*) :: str
   END SUBROUTINE
END INTERFACE
! probably wrong (I know no compiler that uses 64 bit int for string length)
INTERFACE
   SUBROUTINE sbpreadcp64n(ierr,sock,str)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    CHARACTER(LEN=*) :: str
   END SUBROUTINE
END INTERFACE

INTERFACE
   SUBROUTINE sbpreadi64(ierr,sock,iarr,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    INTEGER(selected_int_kind(6)), dimension(*) :: iarr
    INTEGER(selected_int_kind(18)) :: len
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpreadi32(ierr,sock,iarr,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock,len
    INTEGER(selected_int_kind(6)),dimension(:) :: iarr
   END SUBROUTINE
END INTERFACE
INTERFACE sbpreadi
    MODULE PROCEDURE sbpreadi64, sbpreadi32
END INTERFACE

INTERFACE
   SUBROUTINE sbpreadip64(ierr,sock,iarr,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    INTEGER(selected_int_kind(18)) :: len
    INTEGER(selected_int_kind(6)), dimension(*) :: iarr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpreadip32(ierr,sock,iarr,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock,len
    INTEGER(selected_int_kind(6)), dimension(*) :: iarr
   END SUBROUTINE
END INTERFACE
INTERFACE sbpreadip
    MODULE PROCEDURE sbpreadip64, sbpreadip32
END INTERFACE

INTERFACE
   SUBROUTINE sbpreadd64(ierr,sock,arr,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    INTEGER(selected_int_kind(18)) :: len
    REAL(selected_real_kind(14,200)), dimension(*) :: arr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpreadd32(ierr,sock,arr,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock,len
    REAL(selected_real_kind(14,200)), dimension(*) :: arr
   END SUBROUTINE
END INTERFACE
INTERFACE sbpreadd
    MODULE PROCEDURE sbpreadd64, sbpreadd32
END INTERFACE

INTERFACE
   SUBROUTINE sbpreaddp64(ierr,sock,arr,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    INTEGER(selected_int_kind(18)) :: len
    REAL(selected_real_kind(14,200)), dimension(*) :: arr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpreaddp32(ierr,sock,arr,len)
    INTEGER(selected_int_kind(6)) :: ierr,sock,len
    REAL(selected_real_kind(14,200)), dimension(*) :: arr
   END SUBROUTINE
END INTERFACE
INTERFACE sbpreaddp
    MODULE PROCEDURE sbpreaddp64, sbpreaddp32
END INTERFACE

!!! connection
INTERFACE
   SUBROUTINE sboconn32n(ierr,sock,str)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    CHARACTER(len=*) :: str
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sboconn64n(ierr,sock,str)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    CHARACTER(len=*) :: str
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbplisten32n(ierr,sock,portStr)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    CHARACTER(len=*) :: portStr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbplisten64n(ierr,sock,portStr)
    INTEGER(selected_int_kind(6)) :: ierr,sock
    CHARACTER(len=*) :: portStr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpclose(ierr,sock)
    INTEGER(selected_int_kind(6)) :: ierr,sock
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpaccept32n(ierr,sock, newSock,addr)
    INTEGER(selected_int_kind(6)) :: ierr,sock, newSock
    CHARACTER(len=*) :: addr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpaccept64n(ierr,sock, newSock,addr)
    INTEGER(selected_int_kind(6)) :: ierr,sock, newSock
    CHARACTER(len=*) :: addr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbphostn32n(addr)
    CHARACTER(len=*) :: addr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbphostn64n(addr)
    CHARACTER(len=*) :: addr
   END SUBROUTINE
END INTERFACE

end module
