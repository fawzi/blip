!! a simple binary protocol
!! kind,size,msg in network order
!! useful to connect fortran programs
!! author: fawzi
!! license: apache 2.0, GPL

! the methods named with the n at the end the 32 bit version (length of string passed
! by value as 32bit integer after the character ptr is probably probably the correct
! one on all compilers (I know no compiler that uses 64 bit int for string length)
! but the 64 bit version is given for completness

! for a slightly better description look at the C header descriptions

! one could overload 32 and 64 bit versions, to make the usage simpler

INTEGER, PARAMETER :: sbp_real_8 = SELECTED_REAL_KIND ( 14, 200 )
INTEGER, PARAMETER :: sbp_int_8 = SELECTED_INT_KIND(18)
INTEGER, PARAMETER :: sbp_int_4 = SELECTED_INT_KIND(6)

INTEGER(int_4), PARAMETER :: sbp_kind_raw=0, &
    sbp_kind_char=1, &
    sbp_kind_int_small=2, &
    sbp_kind_double_small=3

!!!!!!!!! init/stop lib !!!!!!!!!

INTERFACE
   SUBROUTINE sbpinit(ierr)
    INTEGER(sbp_int_4) :: ierr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpend(ierr)
    INTEGER(sbp_int_4) :: ierr
   END SUBROUTINE
END INTERFACE

!!!!!!!!! sending !!!!!!!!!

INTERFACE
   SUBROUTINE sbpsendh64(ierr,sock,kind,len)
    INTEGER(sbp_int_4) :: ierr,sock,kind
    INTEGER(sbp_int_8) :: len
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpsendh32(ierr,sock,kind,len)
    INTEGER(sbp_int_4) :: ierr,sock,kind,len
   END SUBROUTINE
END INTERFACE

INTERFACE
   SUBROUTINE sbpsendc32n(ierr,sock,str)
    INTEGER(sbp_int_4) :: ierr,sock
    CHARACTER(LEN=*) :: str
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpsendc64n(ierr,sock,str)
    INTEGER(sbp_int_4) :: ierr,sock
    CHARACTER(LEN=*) :: str
   END SUBROUTINE
END INTERFACE

INTERFACE
   SUBROUTINE sbpsendi64(ierr,sock,iarr,len)
    INTEGER(sbp_int_4) :: ierr,sock,len
    INTEGER(sbp_int_4), dimension(*) :: iarr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpsendi32(ierr,sock,str,len)
    INTEGER(sbp_int_4) :: ierr,sock,len
    INTEGER(LEN=*) :: str
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpsendip64(ierr,sock,iarr,len)
    INTEGER(sbp_int_4) :: ierr,sock
    INTEGER(sbp_int_8) :: len
    INTEGER(sbp_int_4), dimension(*) :: iarr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpsendip32(ierr,sock,str,len)
    INTEGER(sbp_int_4) :: ierr,sock,len
    INTEGER(sbp_int_4), dimension(*) :: iarr
   END SUBROUTINE
END INTERFACE

INTERFACE
   SUBROUTINE sbpsendd64(ierr,sock,arr,len)
    INTEGER(sbp_int_4) :: ierr,sock,len
    REAL(sbp_real_8), dimension(*) :: arr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpsendd32(ierr,sock,str,len)
    INTEGER(sbp_int_4) :: ierr,sock,len
    REAL(sbp_real_8), dimension(*) :: arr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpsenddp64(ierr,sock,arr,len)
    INTEGER(sbp_int_4) :: ierr,sock
    INTEGER(sbp_int_8) :: len
    REAL(sbp_real_8), dimension(*) :: arr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpsenddp32(ierr,sock,arr,len)
    INTEGER(sbp_int_4) :: ierr,sock,len
    REAL(sbp_real_8), dimension(*) :: arr
   END SUBROUTINE
END INTERFACE

!!!!!!!!!!! receiving !!!!!!!!!!!

INTERFACE
   SUBROUTINE sbpreadh64(ierr,sock,kind,len)
    INTEGER(sbp_int_4) :: ierr,sock,kind
    INTEGER(sbp_int_8) :: len
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpreadh32(ierr,sock,kind,len)
    INTEGER(sbp_int_4) :: ierr,sock,kind,len
   END SUBROUTINE
END INTERFACE

INTERFACE
   SUBROUTINE sbpreadc32n(ierr,sock,str)
    INTEGER(sbp_int_4) :: ierr,sock
    CHARACTER(LEN=*) :: str
   END SUBROUTINE
END INTERFACE
! probably wrong (I know no compiler that uses 64 bit int for string length)
INTERFACE
   SUBROUTINE sbpreadc64n(ierr,sock,str)
    INTEGER(sbp_int_4) :: ierr,sock
    CHARACTER(LEN=*) :: str
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpreadcp32n(ierr,sock,str)
    INTEGER(sbp_int_4) :: ierr,sock
    CHARACTER(LEN=*) :: str
   END SUBROUTINE
END INTERFACE
! probably wrong (I know no compiler that uses 64 bit int for string length)
INTERFACE
   SUBROUTINE sbpreadcp64n(ierr,sock,str)
    INTEGER(sbp_int_4) :: ierr,sock
    CHARACTER(LEN=*) :: str
   END SUBROUTINE
END INTERFACE

INTERFACE
   SUBROUTINE sbpreadi64(ierr,sock,iarr,len)
    INTEGER(sbp_int_4) :: ierr,sock,len
    INTEGER(sbp_int_4), dimension(*) :: iarr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpreadi32(ierr,sock,str,len)
    INTEGER(sbp_int_4) :: ierr,sock,len
    INTEGER(LEN=*) :: str
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpreadip64(ierr,sock,iarr,len)
    INTEGER(sbp_int_4) :: ierr,sock
    INTEGER(sbp_int_8) :: len
    INTEGER(sbp_int_4), dimension(*) :: iarr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpreadip32(ierr,sock,str,len)
    INTEGER(sbp_int_4) :: ierr,sock,len
    INTEGER(sbp_int_4), dimension(*) :: iarr
   END SUBROUTINE
END INTERFACE

INTERFACE
   SUBROUTINE sbpreadd64(ierr,sock,arr,len)
    INTEGER(sbp_int_4) :: ierr,sock,len
    REAL(sbp_real_8), dimension(*) :: arr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpreadd32(ierr,sock,str,len)
    INTEGER(sbp_int_4) :: ierr,sock,len
    REAL(sbp_real_8), dimension(*) :: arr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpreaddp64(ierr,sock,arr,len)
    INTEGER(sbp_int_4) :: ierr,sock
    INTEGER(sbp_int_8) :: len
    REAL(sbp_real_8), dimension(*) :: arr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpreaddp32(ierr,sock,arr,len)
    INTEGER(sbp_int_4) :: ierr,sock,len
    REAL(sbp_real_8), dimension(*) :: arr
   END SUBROUTINE
END INTERFACE

/// connection
INTERFACE
   SUBROUTINE sboconn32n(ierr,sock,str)
    INTEGER(sbp_int_4) :: ierr,sock
    CHARACTER(len=*) :: str
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sboconn64n(ierr,sock,str)
    INTEGER(sbp_int_4) :: ierr,sock
    CHARACTER(len=*) :: str
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbplisten32n(ierr,sock,portStr)
    INTEGER(sbp_int_4) :: ierr,sock
    CHARACTER(len=*) :: portStr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbplisten64n(ierr,sock,portStr)
    INTEGER(sbp_int_4) :: ierr,sock
    CHARACTER(len=*) :: portStr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpclose(ierr,sock)
    INTEGER(sbp_int_4) :: ierr,sock
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpaccept32n(ierr,sock, newSock,addr)
    INTEGER(sbp_int_4) :: ierr,sock, newSock
    CHARACTER(len=*) :: addr
   END SUBROUTINE
END INTERFACE
INTERFACE
   SUBROUTINE sbpaccept64n(ierr,sock, newSock,addr)
    INTEGER(sbp_int_4) :: ierr,sock, newSock
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
