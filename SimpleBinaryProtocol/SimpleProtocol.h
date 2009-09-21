/// a simple binary protocol
/// kind,size,msg in network order
/// useful to connect fortran or C programs, it is relatively fast, but keeping still
/// keeps the programs quite decoupled (as separate processes, that can even be
/// distribued on different computers, and parallelized with different libraries)
///
/// the 32/64 suffix refers to the width of the length argument
/// at the moment utility methods for sending and receiving of 4 bytes integers
/// and 64 bytes doubles are available
/// socket and kind of message are always 4 bytes integers
/// all routines return an integer that is 0 if there were no errors, and non zero if there
/// were errors
///
/// The Send/Read of Chars/Int4/Double methods noramlly send header+data,
/// but to send or receive large amounts of data for which you do not want to
/// allocate space (for example if they are distribued), you might use the
/// SendHeader/ReadHeader and the *Piece methods separately (you have to
/// ensure that the data of all pieces correctly sums up to the length given
/// in the header
///
/// author: fawzi
/// license: apache 2.0, GPLv2
#ifndef _SIMPLE_PROTOCOL_H
#define _SIMPLE_PROTOCOL_H 1
#include <stdint.h>

enum SBP_KIND{
    kind_raw=0,         // binary blob
    kind_char=1,        // characters
    kind_int_small=2,   // small endian 4 bytes integers
    kind_double_small=3 // small endian doubles
};
typedef int socket_t;

/// initializes the library (checks if endianness swap is needed)
int sbpInit();
/// stops the library
int sbpEnd();

/////////// sending ////////

int sbpSendHeader64(socket_t sock, int32_t kind, uint64_t len);
int sbpSendHeader32(socket_t sock, int32_t kind, uint32_t length);
int sbpSend4_32(socket_t sock,void* start,uint32_t len);
int sbpSend8_32(socket_t sock,void* start,uint32_t len);
int sbpSend4_64(socket_t sock,void* start,uint64_t len);
int sbpSend8_64(socket_t sock,void* start,uint64_t len);
int sbpSendChars32(socket_t sock,char* p,uint32_t len);
int sbpSendChars64(socket_t sock,char* p,uint64_t len);
int sbpSendCharsPiece32(socket_t sock,char* p,uint32_t len);
int sbpSendCharsPiece64(socket_t sock,char* p,uint64_t len);
int sbpSendInt4Array64(socket_t sock, void *p, uint64_t len);
int sbpSendInt4ArrayPiece64(socket_t sock, void *p, uint64_t len);
int sbpSendInt4Array32(socket_t sock, void *p, uint32_t len);
int sbpSendInt4ArrayPiece32(socket_t sock, void *p, uint32_t len);
int sbpSendDoubleArray64(socket_t sock, void *p, uint64_t len);
int sbpSendDoubleArray32(socket_t sock, void *p, uint32_t len);
int sbpSendDoublePiece32(socket_t sock, void *p, uint32_t len);

//////// receiving ///////

int sbpReadHeader64(socket_t sock, uint32_t *kind, uint64_t *len);
int sbpReadHeader32(socket_t sock, uint32_t* kind, uint32_t* length);
int sbpRead4_32(socket_t sock,void* start,uint32_t len);
int sbpRead8_32(socket_t sock,void* start,uint32_t len);
int sbpRead4_64(socket_t sock,void* start,uint64_t len);
int sbpRead8_64(socket_t sock,void* start,uint64_t len);
int sbpSkip(socket_t sock,uint64_t len);
int sbpReadChars64(socket_t sock,char* p,uint64_t*len);
int sbpReadChars32(socket_t sock,char* p,uint32_t*len);
int sbpReadCharsPiece64(socket_t sock,char* p,uint64_t len);
int sbpReadCharsPiece32(socket_t sock,char* p,uint32_t len);
int sbpReadInt4Array64(socket_t sock, void *p, uint64_t len);
int sbpReadInt4Array32(socket_t sock, void *p, uint32_t len);
int sbpReadInt4ArrayPiece64(socket_t sock, void *p, uint64_t len);
int sbpReadInt4ArrayPiece32(socket_t sock, void *p, uint32_t len);
int sbpReadDoubleArray64(socket_t sock, void *p, uint64_t len);
int sbpReadDoublePiece64(socket_t sock, void *p, uint64_t len);
int sbpReadDoubleArray32(socket_t sock, void *p, uint32_t len);
int sbpReadDoublePiece32(socket_t sock, void *p, uint32_t len);

//////// connection ////////

/// client connect to the given address (which should have the from "host port")
int sbpConnectTo32(socket_t *sock, char*address,uint32_t len);
/// ditto
int sbpConnectTo64(socket_t *sock, char*address,uint64_t len);
/// start server listen on a socket, service is tipically just a string with the port number
int sbpListenForService32(socket_t *sock,char *service,uint32_t len);
/// ditto
int sbpListenForService64(socket_t *sock,char *service,uint64_t len);
/// closes the given socket (0 read side, 1 write side, 2 both)
int sbpClose(socket_t sock,int what);
/// sever command to accept an incoming connection (blocking, add timeout?)
int sbpAccept32(socket_t sock,socket_t *newSock,char*addrStr,uint32_t*addrLen);
/// ditto
int sbpAccept64(socket_t sock,socket_t *newSock,char*addrStr,uint64_t*addrLen);
/// returns the hostname of the current computer
int sbpGethostname32(char*,uint32_t*);
/// ditto
int sbpGethostname64(char*,uint64_t*);

#endif

