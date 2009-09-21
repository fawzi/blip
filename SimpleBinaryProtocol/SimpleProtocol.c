/// a simple binary protocol
/// kind,size,msg in network order
/// useful to connect fortran programs
/// author: fawzi
/// license: apache 2.0, GPL
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <string.h>
#include <sys/time.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <errno.h>
#include "SimpleProtocol.h"

enum SBP_SIZES{
    max_listening_sockets=10,
    endian_buf_size=1024
};

struct sbp_listening_sockets{
    int externalId;
    int nSockets;
    int maxDesc;
    int lastISock;
    socket_t socktable[max_listening_sockets];
    int sockfamile[max_listening_sockets];
    fd_set selectSet;
    struct sbp_listening_sockets *next;
};

struct sbp_listening_sockets *sbpListeningSockets=NULL;
int swapBits=0;

void reduceLen64(char*name,uint64_t*len){
    uint64_t i,l= *len;
    for (i=0;i < l;++i){
        if (name[i]==0) {
            *len=i;
            break;
        }
    }
}

void reduceLen32(char*name,uint32_t*len){
    uint32_t i,l= *len;
    for (i=0;i < l;++i){
        if (name[i]==0) {
            *len=i;
            break;
        }
    }
}

int sbpInit(){
    int i=1;
    swapBits=(*(char *)&i)!=1; // small endian is the default
    fprintf(stderr,"SBP init, swapBits %d\n",swapBits);
    return 0;
}
/// f77 interface
void sbpinit(int*ierr){
    *ierr=sbpInit();
}
void sbpinit_(int*ierr){
    *ierr=sbpInit();
}
void sbpinit__(int*ierr){
    *ierr=sbpInit();
}

int sbpEnd(){
    return 0;
}
/// f77 interface
void sbpend(int*ierr){
    *ierr=sbpEnd();
}
void sbpend_(int*ierr){
    *ierr=sbpEnd();
}
void sbpend__(int*ierr){
    *ierr=sbpEnd();
}

int sbpSendHeader64(socket_t sock, int32_t kind, uint64_t len){
    uint64_t buf[2];
    char* bufPos=(char*)&buf;
    char* pos;
    if (swapBits){
        pos=(char*)&kind;
        bufPos[3]=pos[0];
        bufPos[2]=pos[1];
        bufPos[1]=pos[2];
        bufPos[0]=pos[3];
        bufPos+=4;
        pos=(char*)&len;
        bufPos[7]=pos[0];
        bufPos[6]=pos[1];
        bufPos[5]=pos[2];
        bufPos[4]=pos[3];
        bufPos[3]=pos[4];
        bufPos[2]=pos[5];
        bufPos[1]=pos[6];
        bufPos[0]=pos[7];
        bufPos+=8;
    } else {
        *((uint32_t*)bufPos)=kind;
        bufPos+=4;
        *((uint64_t*)bufPos)=len;
    }
    if (write(sock,&buf,12)!=12) {
        perror("SBP error sending header");
        return 1;
    }
    return 0;
}
// f77 bindings
void sbpsendh64(int *ierr,socket_t *sock, int32_t *kind, uint64_t *length){
    *ierr=sbpSendHeader64(*sock,*kind,*length);
}
void sbpsendh64_(int *ierr,socket_t *sock, int32_t *kind, uint64_t *length){
    *ierr=sbpSendHeader64(*sock,*kind,*length);
}
void sbpsendh64__(int *ierr,socket_t *sock, int32_t *kind, uint64_t *length){
    *ierr=sbpSendHeader64(*sock,*kind,*length);
}

int sbpSendHeader32(socket_t sock, int32_t kind, uint32_t length){
    return sbpSendHeader64(sock,kind,(uint64_t)length);
}
// f77 bindings
void sbpsendh32(int *ierr,socket_t *sock, int32_t *kind, uint32_t *length){
    *ierr=sbpSendHeader32(*sock,*kind,*length);
}
void sbpsendh32_(int *ierr,socket_t *sock, int32_t *kind, uint32_t *length){
    *ierr=sbpSendHeader32(*sock,*kind,*length);
}
void sbpsendh32__(int *ierr,socket_t *sock, int32_t *kind, uint32_t *length){
    *ierr=sbpSendHeader32(*sock,*kind,*length);
}

int sbpSend4_32(socket_t sock,void* start,uint32_t len){
    uint64_t bitLen=((uint64_t)len)*4UL;
    if (swapBits){
        sbpSendInvert4(sock,start,bitLen);
    } else {
        sbpSendDirect(sock,start,bitLen);
    }
}

int sbpSend8_32(socket_t sock,void* start,uint32_t len){
    uint64_t bitLen=((uint64_t)len)*8UL;
    if (swapBits){
        sbpSendInvert8(sock,start,bitLen);
    } else {
        sbpSendDirect(sock,start,bitLen);
    }
}

int sbpSend4_64(socket_t sock,void* start,uint64_t len){
    if (swapBits){
        sbpSendInvert4(sock,start,len);
    } else {
        sbpSendDirect(sock,start,len);
    }
}

int sbpSend8_64(socket_t sock,void* start,uint64_t len){
    if (swapBits){
        sbpSendInvert8(sock,start,len);
    } else {
        sbpSendDirect(sock,start,len);
    }
}

int sbpSendDirect(socket_t sock,void* start,uint64_t len){
    if (write(sock,start,(size_t)len)!=len) {
        perror("SBP error sending data");
        return 1;
    }
    return 0;
}

int sbpSendInvert4(socket_t sock,uint64_t len, void* start){
    const size_t bufSize=endian_buf_size+4;
    uint32_t _buf[endian_buf_size/4];
    char* buf=(char*)&_buf;
    char* bufPos=buf;
    char* bufEnd=bufPos+bufSize-4;
    char* pos=(char*)start;
    char* end=pos+len;
    while (pos<end){
        bufPos[3]=pos[0];
        bufPos[2]=pos[1];
        bufPos[1]=pos[2];
        bufPos[0]=pos[3];
        bufPos+=4;
        pos+=4;
        if (bufPos>=bufEnd){
            if (write(sock,buf,bufPos-buf)!=bufPos-buf) {
                perror("SBP error sending byte inverted 4 byte data");
                return 1;
            }
            bufPos=buf;
        }
    }
    if (write(sock,buf,bufPos-buf)!=bufPos-buf) {
        perror("SBP error sending last byte inverted 4 byte data");
        return 2;
    }
}

int sbpSendInvert8(int sock, uint64_t* start,uint64_t len){
    const int bufSize=endian_buf_size+8;
    uint64_t _buf[bufSize/8];
    char* buf=(char*)&_buf;
    char* bufPos=buf;
    char* bufEnd=bufPos+bufSize-8;
    char* pos=(char*)start,*end=pos+(size_t)len;
    while (pos<end){
        bufPos[7]=pos[0];
        bufPos[6]=pos[1];
        bufPos[5]=pos[2];
        bufPos[4]=pos[3];
        bufPos[3]=pos[4];
        bufPos[2]=pos[5];
        bufPos[1]=pos[6];
        bufPos[0]=pos[7];
        bufPos+=8;
        pos+=8;
        if (bufPos>=bufEnd){
            if (write(sock,buf,bufPos-buf)!=bufPos-buf) {
                perror("SBP error sending byte inverted 8 byte data");
                return 1;
            }
            bufPos=buf;
        }
    }
    if (write(sock,buf,bufPos-buf)!=bufPos-buf) {
        perror("SBP error sending last byte inverted 4 byte data");
        return 2;
    }
}

int sbpSendChars32(socket_t sock,char* p,uint32_t len){
    if (sbpSendHeader32(sock,kind_char,len)!=0) return 3;
    return sbpSendDirect(sock,p,len);
}
/// f77 interface
void sbpsendc32n(int *ierr,socket_t*sock,char*p,uint32_t len){
    *ierr=sbpSendChars32(*sock,p,len);
}
void sbpsendc32n_(int *ierr,socket_t*sock,char*p,uint32_t len){
    *ierr=sbpSendChars32(*sock,p,len);
}
void sbpsendc32n__(int *ierr,socket_t*sock,char*p,uint32_t len){
    *ierr=sbpSendChars32(*sock,p,len);
}

int sbpSendChars64(socket_t sock,char* p,uint64_t len){
    if (sbpSendHeader64(sock,kind_char,len)!=0) return 3;
    return sbpSendDirect(sock,p,len);
}
/// f77 interface
void sbpsendc64n(int *ierr,socket_t*sock,char*p,uint64_t len){
    *ierr=sbpSendChars64(*sock,p,len);
}
void sbpsendc64n_(int *ierr,socket_t*sock,char*p,uint64_t len){
    *ierr=sbpSendChars64(*sock,p,len);
}
void sbpsendc64n__(int *ierr,socket_t*sock,char*p,uint64_t len){
    *ierr=sbpSendChars64(*sock,p,len);
}

int sbpSendCharsPiece32(socket_t sock,char* p,uint32_t len){
    return sbpSendDirect(sock,p,len);
}
/// f77 interface
void sbpsendcp32n(int *ierr,socket_t*sock,char*p,uint32_t len){
    *ierr=sbpSendCharsPiece32(*sock,p,len);
}
void sbpsendcp32n_(int *ierr,socket_t*sock,char*p,uint32_t len){
    *ierr=sbpSendCharsPiece32(*sock,p,len);
}
void sbpsendcp32n__(int *ierr,socket_t*sock,char*p,uint32_t len){
    *ierr=sbpSendCharsPiece32(*sock,p,len);
}

int sbpSendCharsPiece64(socket_t sock,char* p,uint64_t len){
    return sbpSendDirect(sock,p,len);
}
/// f77 interface
void sbpsendcp64n(int *ierr,socket_t*sock,char*p,uint64_t len){
    *ierr=sbpSendCharsPiece64(*sock,p,len);
}
void sbpsendcp64n_(int *ierr,socket_t*sock,char*p,uint64_t len){
    *ierr=sbpSendCharsPiece64(*sock,p,len);
}
void sbpsendcp64n__(int *ierr,socket_t*sock,char*p,uint64_t len){
    *ierr=sbpSendCharsPiece64(*sock,p,len);
}

int sbpSendInt4Array64(socket_t sock, void*p, uint64_t len){
    uint64_t byteLen=4UL*len;
    if (sbpSendHeader64(sock,kind_int_small,byteLen)!=0) return 3;
    return sbpSend4_64(sock,p,byteLen);
}
/// f77 interface
void sbpsendi64(int*ierr,socket_t*sock,void*p,uint64_t*len){
    *ierr=sbpSendInt4Array64(*sock,p,*len);
}
void sbpsendi64_(int*ierr,socket_t*sock,void*p,uint64_t*len){
    *ierr=sbpSendInt4Array64(*sock,p,*len);
}
void sbpsendi64__(int*ierr,socket_t*sock,void*p,uint64_t*len){
    *ierr=sbpSendInt4Array64(*sock,p,*len);
}

int sbpSendInt4ArrayPiece64(socket_t sock, void*p, uint64_t len){
    uint64_t byteLen=4UL*len;
    return sbpSend4_64(sock,p,byteLen);
}
/// f77 interface
void sbpsendip64(int*ierr,socket_t*sock,void*p,uint64_t*len){
    *ierr=sbpSendInt4ArrayPiece64(*sock,p,*len);
}
void sbpsendip64_(int*ierr,socket_t*sock,void*p,uint64_t*len){
    *ierr=sbpSendInt4ArrayPiece64(*sock,p,*len);
}
void sbpsendip64__(int*ierr,socket_t*sock,void*p,uint64_t*len){
    *ierr=sbpSendInt4ArrayPiece64(*sock,p,*len);
}

int sbpSendInt4Array32(socket_t sock, void*p, uint32_t len){
    uint64_t byteLen=4UL*len;
    if (sbpSendHeader64(sock,kind_int_small,byteLen)!=0) return 3;
    return sbpSend4_64(sock,p,byteLen);
}
/// f77 interface
void sbpsendi32(int*ierr,socket_t*sock,void*p,uint32_t*len){
    *ierr=sbpSendInt4Array32(*sock,p,*len);
}
void sbpsendi32_(int*ierr,socket_t*sock,void*p,uint32_t*len){
    *ierr=sbpSendInt4Array32(*sock,p,*len);
}
void sbpsendi32__(int*ierr,socket_t*sock,void*p,uint32_t*len){
    *ierr=sbpSendInt4Array32(*sock,p,*len);
}

int sbpSendInt4ArrayPiece32(socket_t sock, void*p, uint32_t len){
    uint64_t byteLen=4UL*len;
    return sbpSend4_64(sock,p,byteLen);
}
/// f77 interface
void sbpsendip32(int*ierr,socket_t*sock,void*p,uint32_t*len){
    *ierr=sbpSendInt4ArrayPiece32(*sock,p,*len);
}
void sbpsendip32_(int*ierr,socket_t*sock,void*p,uint32_t*len){
    *ierr=sbpSendInt4ArrayPiece32(*sock,p,*len);
}
void sbpsendip32__(int*ierr,socket_t*sock,void*p,uint32_t*len){
    *ierr=sbpSendInt4ArrayPiece32(*sock,p,*len);
}

int sbpSendDoubleArray64(socket_t sock, void*p, uint64_t len){
    uint64_t byteLen=8UL*len;
    if (sbpSendHeader64(sock,kind_double_small,byteLen)!=0) return 3;
    return sbpSend8_64(sock,p,byteLen);
}
/// f77 interface
void sbpsendd64(int*ierr,socket_t*sock,void*p,uint64_t* len){
    *ierr=sbpSendDoubleArray64(*sock,p,*len);
}
void sbpsendd64_(int*ierr,socket_t*sock,void*p,uint64_t* len){
    *ierr=sbpSendDoubleArray64(*sock,p,*len);
}
void sbpsendd64__(int*ierr,socket_t*sock,void*p,uint64_t* len){
    *ierr=sbpSendDoubleArray64(*sock,p,*len);
}

int sbpSendDoubleArray32(socket_t sock, void*p, uint32_t len){
    uint64_t byteLen=8UL*len;
    if (sbpSendHeader64(sock,kind_double_small,byteLen)!=0) return 3;
    return sbpSend8_64(sock,p,byteLen);
}
/// f77 interface
void sbpsendd32(int*ierr,socket_t*sock,void*p,uint32_t* len){
    *ierr=sbpSendDoubleArray32(*sock,p,*len);
}
void sbpsendd32_(int*ierr,socket_t*sock,void*p,uint32_t* len){
    *ierr=sbpSendDoubleArray32(*sock,p,*len);
}
void sbpsendd32__(int*ierr,socket_t*sock,void*p,uint32_t* len){
    *ierr=sbpSendDoubleArray32(*sock,p,*len);
}

int sbpSendDoublePiece32(socket_t sock, void*p, uint32_t len){
    uint64_t byteLen=8UL*len;
    return sbpSend8_64(sock,p,byteLen);
}
/// f77 interface
void sbpsenddp32(int*ierr,socket_t*sock,void*p,uint32_t* len){
    *ierr=sbpSendDoublePiece32(*sock,p,*len);
}
void sbpsenddp32_(int*ierr,socket_t*sock,void*p,uint32_t* len){
    *ierr=sbpSendDoublePiece32(*sock,p,*len);
}
void sbpsenddp32__(int*ierr,socket_t*sock,void*p,uint32_t* len){
    *ierr=sbpSendDoublePiece32(*sock,p,*len);
}


//////// receiving ///////

int sbpReadHeader64(socket_t sock, uint32_t *kind, uint64_t *len){
    uint64_t buf[2],nodata=0;
    char* bufPos=(char*)&buf,*endBuf=bufPos+12;
    char* pos;
    while (bufPos<endBuf){
        size_t toRead=(size_t)(endBuf-bufPos);
        size_t readB=recv(sock,bufPos,toRead,MSG_WAITALL);
        if (readB==0){
            if (++nodata>10000){
                fprintf(stderr,"partial read %d/%d:",bufPos-((char*)&buf),toRead);
                for (pos=(char*)&buf;pos<bufPos;++pos)
                    fprintf(stderr," %02x",*pos);
                fprintf(stderr,"\n");
                perror("SBP no data in receiving header");
                return 1;
            }
        } else {
            nodata=0;
        }
        if (readB==-(size_t)1){
            perror("SBP EOF in receiving header");
            return 2;
        }
        bufPos+=readB;
    }
    bufPos=(char*)&buf;
    if (swapBits){
        pos=(char*)kind;
        pos[0]=bufPos[3];
        pos[1]=bufPos[2];
        pos[2]=bufPos[1];
        pos[3]=bufPos[0];
        bufPos+=4;
        pos=(char*)len;
        pos[0]=bufPos[7];
        pos[1]=bufPos[6];
        pos[2]=bufPos[5];
        pos[3]=bufPos[4];
        pos[4]=bufPos[3];
        pos[5]=bufPos[2];
        pos[6]=bufPos[1];
        pos[7]=bufPos[0];
    } else {
        *kind=*((uint32_t*)bufPos);
        bufPos+=4;
        *len=*((uint64_t*)bufPos);
    }
    //printf("read header kind %d len %d\n",*kind,(int)*len);
    return 0;
}
// f77 bindings
void sbpreadh64(int *ierr,socket_t *sock, uint32_t *kind, uint64_t *length){
    *ierr=sbpReadHeader64(*sock,kind,length);
}
void sbpreadh64_(int *ierr,socket_t *sock, uint32_t *kind, uint64_t *length){
    *ierr=sbpReadHeader64(*sock,kind,length);
}
void sbpreadh64__(int *ierr,socket_t *sock, uint32_t *kind, uint64_t *length){
    *ierr=sbpReadHeader64(*sock,kind,length);
}

int sbpReadHeader32(socket_t sock, uint32_t* kind, uint32_t* length){
    uint64_t len;
    int res=sbpReadHeader64(sock,kind,&len);
    *length=(uint32_t)len;
    if (len>0xFFFFFFFFU) return 10;
    return res;
}
// f77 bindings
void sbpreadh32(int *ierr,socket_t *sock, uint32_t *kind, uint32_t *length){
    *ierr=sbpReadHeader32(*sock,kind,length);
}
void sbpreadh32_(int *ierr,socket_t *sock, uint32_t *kind, uint32_t *length){
    *ierr=sbpReadHeader32(*sock,kind,length);
}
void sbpreadh32__(int *ierr,socket_t *sock, uint32_t *kind, uint32_t *length){
    *ierr=sbpReadHeader32(*sock,kind,length);
}

int sbpRead4_32(socket_t sock,void* start,uint32_t len){
    uint64_t bitLen=((uint64_t)len)*4;
    if (swapBits){
        sbpReadInvert4(sock,start,bitLen);
    } else {
        sbpReadDirect(sock,start,bitLen);
    }
}

int sbpRead8_32(socket_t sock,void* start,uint32_t len){
    uint64_t bitLen=((uint64_t)len)*8;
    if (swapBits){
        sbpReadInvert8(sock,start,bitLen);
    } else {
        sbpReadDirect(sock,start,bitLen);
    }
}

int sbpRead4_64(socket_t sock,void* start,uint64_t len){
    if (swapBits){
        sbpReadInvert4(sock,start,len);
    } else {
        sbpReadDirect(sock,start,len);
    }
}

int sbpRead8_64(socket_t sock,void* start,uint64_t len){
    if (swapBits){
        sbpReadInvert8(sock,start,len);
    } else {
        sbpReadDirect(sock,start,len);
    }
}

int sbpReadDirect(socket_t sock,void* start,uint64_t len){
    char*pos=start;
    char*end=start+len;
    int nodata=0;
    while(pos!=end){
        size_t readB=recv(sock,pos,end-pos,MSG_WAITALL);
        if (readB==0){
            if (++nodata>10000){
                fprintf(stderr,"SBP partial read %d, no data\n",pos-((char*)start));
                return 6;
            }
        } else {
            nodata=0;
        }
        if (readB==-(size_t)1) {
            perror("SBP EOF error reading data");
            return 5;
        }
        pos+=readB;
    }
    /*{
        uint64_t i;
        printf("read:");
        for (i=0;i<len;++i){
            printf("%02x ",((char*)start)[i]);
        }
        printf("\n");
    }*/
    return 0;
}

int sbpSkip(socket_t sock,uint64_t len){
    // we don't use seek because it is not always supported
    const size_t bufSize=endian_buf_size;
    char buf[bufSize];
    uint64_t readBTot=0;
    while(readBTot!=len){
        uint64_t toRead=len-readBTot;
        if (toRead>bufSize) toRead=bufSize;
        size_t readB=read(sock,&buf,(size_t)toRead);
        if (readB==-(size_t)1) {
            perror("SBP EOF error reading data");
            return 5;
        }
        if (readB==0) {
            perror("SBP error no data read");
            return 6;
        }
        readBTot+=readB;
    }
    return 0;
}

int sbpReadInvert4(socket_t sock,uint64_t len, void* start){
    const size_t bufSize=endian_buf_size+4;
    uint32_t _buf[bufSize/4];
    char* bufPos=(char*)&_buf;
    char *pos=(char*)start;
    char* posEnd=pos+len;
    while (pos!=posEnd){
        char *bufPos2;
        size_t toRead=posEnd-pos;
        if (toRead>bufSize-4) toRead=bufSize-4;
        size_t readB=read(sock,bufPos,toRead);
        if (readB==-(size_t)1) {
            perror("SBP EOF error reading data");
            return 5;
        }
        if (readB==0) {
            perror("SBP error no data read");
            return 6;
        }
        char*end=bufPos+readB;
        if (end >= ((char*)&_buf)+4){
            end-=4;
            for (bufPos=(char*)&_buf;bufPos<end;bufPos+=4){
                pos[0]=bufPos[3];
                pos[1]=bufPos[2];
                pos[2]=bufPos[1];
                pos[3]=bufPos[0];
                pos+=4;
            }
            end+=4;
        }
        bufPos2=(char*)&_buf;
        while (bufPos<end){
            *bufPos2=*bufPos;
            ++bufPos;++bufPos2;
        }
        bufPos=bufPos2;
    }
    return 0;
}

int sbpReadInvert8(int sock, uint64_t* start,uint64_t len){
    const int bufSize=endian_buf_size+8;
    uint64_t _buf[bufSize/8];
    char* bufPos=(char*)&_buf;
    char* bufEnd=bufPos+bufSize-8;
    char *pos=(char*)start;
    char* posEnd=pos+len;
    
    while (pos!=posEnd){
        char *bufPos2;
        size_t toRead=posEnd-pos;
        if (toRead>bufSize-8) toRead=bufSize-8;
        size_t readB=read(sock,bufPos,toRead);
        if (readB==-(size_t)1) {
            perror("SBP EOF error reading data");
            return 5;
        }
        if (readB==0) {
            perror("SBP error no data read");
            return 6;
        }
        char*end=bufPos+readB;
        if (end>(char*)(&_buf[1])){
            end-=8;
            for (bufPos=(char*)&_buf;bufPos<end;bufPos+=8){
                pos[0]=bufPos[7];
                pos[1]=bufPos[6];
                pos[2]=bufPos[5];
                pos[3]=bufPos[4];
                pos[4]=bufPos[3];
                pos[5]=bufPos[2];
                pos[6]=bufPos[1];
                pos[7]=bufPos[0];
                pos+=8;
            }
            end+=8;
        }
        bufPos2=(char*)&_buf;
        while (bufPos<end){
            *bufPos2=*bufPos;
            ++bufPos;++bufPos2;
        }
        bufPos=bufPos2;
    }
    return 0;
}

///////

int sbpReadChars64(socket_t sock,char* p,uint64_t *len){
    uint64_t rcvLen;
    uint32_t kind;
    if (sbpReadHeader64(sock,&kind,&rcvLen)!=0) return 13;
    if (kind!=kind_char) return 10;
    if (rcvLen<= *len){
        char *pos;
        if (sbpReadDirect(sock,p,rcvLen)!=0) return 12;
        if (rcvLen< *len) p[rcvLen]=0;
        *len=rcvLen;
        return 0;
    } else {
        if (sbpReadDirect(sock,p,*len)!=0) return 11;
        if (sbpSkip(sock,rcvLen-*len)!=0) return 10;
        return 1;
    }
}
/// f77 interface
void sbpreadc64n(int *ierr,socket_t*sock,char*p,uint64_t len){
    uint64_t newLen=len;
    char*pos;
    *ierr=sbpReadChars64(*sock,p,&newLen);
    for (pos=p+newLen;pos<p+len;++pos){
        *pos=' '; // use memset?
    }
}
void sbpreadc64n_(int *ierr,socket_t*sock,char*p,uint64_t len){
    sbpreadc64n(ierr,sock,p,len);
}
void sbpreadc64n__(int *ierr,socket_t*sock,char*p,uint64_t len){
    sbpreadc64n(ierr,sock,p,len);
}

int sbpReadChars32(socket_t sock,char* p,uint32_t *len){
    uint64_t newLen=(uint64_t)(*len);
    int res=sbpReadChars64(sock,p,&newLen);
    *len=(uint32_t)newLen;
    return res;
}
/// f77 interface
void sbpreadc32n(int *ierr,socket_t*sock,char*p,uint32_t len){
    uint64_t newLen=len;
    char*pos;
    *ierr=sbpReadChars64(*sock,p,&newLen);
    for (pos=p+(size_t)newLen;pos<p+(size_t)len;++pos){
        *pos=' '; // use memset?
    }
}
void sbpreadc32n_(int *ierr,socket_t*sock,char*p,uint32_t len){
    sbpreadc64n(ierr,sock,p,len);
}
void sbpreadc32n__(int *ierr,socket_t*sock,char*p,uint32_t len){
    sbpreadc64n(ierr,sock,p,len);
}

int sbpReadCharsPiece64(socket_t sock,char* p,uint64_t len){
    return sbpReadDirect(sock,p,len);
}
/// f77 interface
void sbpreadcp64n(int *ierr,socket_t*sock,char*p,uint64_t len){
    *ierr=sbpReadCharsPiece64(*sock,p,len);
}
void sbpreadcp64n_(int *ierr,socket_t*sock,char*p,uint64_t len){
    *ierr=sbpReadCharsPiece64(*sock,p,len);
}
void sbpreadcp64n__(int *ierr,socket_t*sock,char*p,uint64_t len){
    *ierr=sbpReadCharsPiece64(*sock,p,len);
}

int sbpReadCharsPiece32(socket_t sock,char* p,uint32_t len){
    sbpReadCharsPiece64(sock,p,(uint64_t)len);
}
/// f77 interface
void sbpreadcp32n(int *ierr,socket_t*sock,char*p,uint32_t len){
    *ierr=sbpReadCharsPiece32(*sock,p,len);
}
void sbpreadcp32n_(int *ierr,socket_t*sock,char*p,uint32_t len){
    *ierr=sbpReadCharsPiece32(*sock,p,len);
}
void sbpreadcp32n__(int *ierr,socket_t*sock,char*p,uint32_t len){
    *ierr=sbpReadCharsPiece32(*sock,p,len);
}

int sbpReadInt4Array64(socket_t sock, void*p, uint64_t len){
    uint64_t byteLen=4UL*len,rcvLen=byteLen;
    uint32_t kind;
    int err;
    if (sbpReadHeader64(sock,&kind,&rcvLen)!=0) return 13;
    if (rcvLen!=byteLen) {
        //sbpSkip(sock,rcvLen);
        return 15;
    }
    if (kind!=kind_int_small) {
        //sbpRead4_64(sock,p,rcvLen);
        return 14;
    }
    return sbpRead4_64(sock,p,rcvLen);
}
/// f77 interface
void sbpreadi64(int*ierr,socket_t*sock,void*p,uint64_t*len){
    *ierr=sbpReadInt4Array64(*sock,p,*len);
}
void sbpreadi64_(int*ierr,socket_t*sock,void*p,uint64_t*len){
    *ierr=sbpSendInt4Array64(*sock,p,*len);
}
void sbpreadi64__(int*ierr,socket_t*sock,void*p,uint64_t*len){
    *ierr=sbpSendInt4Array64(*sock,p,*len);
}

int sbpReadInt4Array32(socket_t sock, void*p, uint32_t len){
    return sbpReadInt4Array64(sock,p,(uint64_t)len);
}
/// f77 interface
void sbpreadi32(int*ierr,socket_t*sock,void*p,uint32_t*len){
    *ierr=sbpReadInt4Array32(*sock,p,*len);
}
void sbpreadi32_(int*ierr,socket_t*sock,void*p,uint32_t*len){
    *ierr=sbpReadInt4Array32(*sock,p,*len);
}
void sbpreadi32__(int*ierr,socket_t*sock,void*p,uint32_t*len){
    *ierr=sbpReadInt4Array32(*sock,p,*len);
}

int sbpReadInt4ArrayPiece64(socket_t sock, void*p, uint64_t len){
    uint64_t byteLen=4UL*len;
    return sbpRead4_64(sock,p,byteLen);
}
/// f77 interface
void sbpreadip64(int*ierr,socket_t*sock,void*p,uint64_t*len){
    *ierr=sbpReadInt4ArrayPiece64(*sock,p,*len);
}
void sbpreadip64_(int*ierr,socket_t*sock,void*p,uint64_t*len){
    *ierr=sbpReadInt4ArrayPiece64(*sock,p,*len);
}
void sbpreadip64__(int*ierr,socket_t*sock,void*p,uint64_t*len){
    *ierr=sbpReadInt4ArrayPiece64(*sock,p,*len);
}

int sbpReadInt4ArrayPiece32(socket_t sock, void*p, uint32_t len){
    uint64_t byteLen=4UL*len;
    return sbpRead4_64(sock,p,byteLen);
}
/// f77 interface
void sbpreadip32(int*ierr,socket_t*sock,void*p,uint32_t*len){
    *ierr=sbpReadInt4ArrayPiece32(*sock,p,*len);
}
void sbpreadip32_(int*ierr,socket_t*sock,void*p,uint32_t*len){
    *ierr=sbpReadInt4ArrayPiece32(*sock,p,*len);
}
void sbpreadip32__(int*ierr,socket_t*sock,void*p,uint32_t*len){
    *ierr=sbpReadInt4ArrayPiece32(*sock,p,*len);
}

int sbpReadDoubleArray64(socket_t sock, void*p, uint64_t len){
    uint64_t byteLen=8UL*len,rcvLen;
    uint32_t kind;
    if (sbpReadHeader64(sock,&kind,&rcvLen)!=0) return 13;
    if (rcvLen!=byteLen) {
        // sbpSkip(sock,rcvLen);
        return 15;
    }
    if (kind!=kind_double_small) {
        //sbpRead8_64(sock,p,byteLen);
        return 14;
    }
    return sbpRead8_64(sock,p,byteLen);
}
/// f77 interface
void sbpreadd64(int*ierr,socket_t*sock,void*p,uint64_t* len){
    *ierr=sbpReadDoubleArray64(*sock,p,*len);
}
void sbpreadd64_(int*ierr,socket_t*sock,void*p,uint64_t* len){
    *ierr=sbpReadDoubleArray64(*sock,p,*len);
}
void sbpreadd64__(int*ierr,socket_t*sock,void*p,uint64_t* len){
    *ierr=sbpReadDoubleArray64(*sock,p,*len);
}

int sbpReadDoublePiece64(socket_t sock, void*p, uint64_t len){
    uint64_t byteLen=8UL*len;
    return sbpRead8_64(sock,p,byteLen);
}
/// f77 interface
void sbpreaddp64(int*ierr,socket_t*sock,void*p,uint64_t* len){
    *ierr=sbpReadDoublePiece64(*sock,p,*len);
}
void sbpreaddp64_(int*ierr,socket_t*sock,void*p,uint64_t* len){
    *ierr=sbpReadDoublePiece64(*sock,p,*len);
}
void sbpreaddp64__(int*ierr,socket_t*sock,void*p,uint64_t* len){
    *ierr=sbpReadDoublePiece64(*sock,p,*len);
}

int sbpReadDoubleArray32(socket_t sock, void*p, uint32_t len){
    return sbpReadDoubleArray64(sock,p,(uint64_t)len);
}
/// f77 interface
void sbpreadd32(int*ierr,socket_t*sock,void*p,uint32_t* len){
    *ierr=sbpReadDoubleArray32(*sock,p,*len);
}
void sbpreadd32_(int*ierr,socket_t*sock,void*p,uint32_t* len){
    *ierr=sbpReadDoubleArray32(*sock,p,*len);
}
void sbpreadd32__(int*ierr,socket_t*sock,void*p,uint32_t* len){
    *ierr=sbpReadDoubleArray32(*sock,p,*len);
}

int sbpReadDoublePiece32(socket_t sock, void*p, uint32_t len){
    uint64_t byteLen=8UL*len;
    return sbpRead8_64(sock,p,byteLen);
}
/// f77 interface
void sbpreaddp32(int*ierr,socket_t*sock,void*p,uint32_t* len){
    *ierr=sbpReadDoublePiece32(*sock,p,*len);
}
void sbpreaddp32_(int*ierr,socket_t*sock,void*p,uint32_t* len){
    *ierr=sbpReadDoublePiece32(*sock,p,*len);
}
void sbpreaddp32__(int*ierr,socket_t*sock,void*p,uint32_t* len){
    *ierr=sbpReadDoublePiece32(*sock,p,*len);
}

int sbpConnectTo32(socket_t *sock, char*address,uint32_t len){
    int err;
    char nullTermAddress[1026];
    char *nodeName=NULL,*serviceName=NULL;
    struct sockaddr addrName;
    struct addrinfo hints,*addressInfo=NULL,*addrAtt=NULL;
    
    *sock=-1;
    if (len>1024) return 3; // address too long

    {
        size_t i=0,ii=0;
        while(i<len && address[i]==' '&& address[i]!=0) ++i;
        nodeName=&nullTermAddress[ii];
        while(i<len && address[i]!=' '&& address[i]!=0){
            nullTermAddress[ii]=address[i];
            ++i;++ii;
        }
        nullTermAddress[ii]=0;
        ++ii;
        serviceName=&nullTermAddress[ii];
        while(i<len && address[i]==' '&& address[i]!=0) ++i;
        while(i<len && address[i]!=' '&& address[i]!=0){
            nullTermAddress[ii]=address[i];
            ++i;++ii;
        }
        nullTermAddress[ii]=0;
        ++ii;
        while(i<len && address[i]==' '&& address[i]!=0) ++i;
        if (i<len && address[i]!=0){
            // error interpreting address
            return 21;
        }
    }
    fprintf(stderr,"will try connecting to '%s' on port '%s'\n",nodeName,serviceName);
    
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = PF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    
    err=getaddrinfo(nodeName,serviceName,&hints,&addressInfo);
    if (err){
        fprintf(stderr,"SBP %s\n", gai_strerror(err));
        return 22;
    }
    
    socket_t s=-1;
    for (addrAtt=addressInfo;addrAtt;addrAtt->ai_next){
        s = socket(addrAtt->ai_family, addrAtt->ai_socktype, addrAtt->ai_protocol);
        if (s<0) continue;
        if (connect(s, addrAtt->ai_addr, addrAtt->ai_addrlen) != 0) {
            close(s);
            s = -1;
            continue;
        }
        break;
    }
    freeaddrinfo(addressInfo);
    if (s<0){
        perror("SBP could not connect");
        return 23;
    }
    *sock=s;
    return 0;
}
/// f77 interface
void sbpconn32n(int *ierr,socket_t *sock, char*address,uint32_t len){
    *ierr=sbpConnectTo32(sock,address,len);
}
void sbpconn32n_(int *ierr,socket_t *sock, char*address,uint32_t len){
    *ierr=sbpConnectTo32(sock,address,len);
}
void sbpconn32n__(int *ierr,socket_t *sock, char*address,uint32_t len){
    *ierr=sbpConnectTo32(sock,address,len);
}

int sbpConnectTo64(socket_t *sock, char*address,uint64_t len){
    if (len>1024) return 3; // address too long
    return sbpConnectTo32(sock,address,(int)len);
}
/// f77 interface
void sbpconn64n(int *ierr,socket_t *sock, char*address,uint64_t len){
    *ierr=sbpConnectTo64(sock,address,len);
}
void sbpconn64n_(int *ierr,socket_t *sock, char*address,uint64_t len){
    *ierr=sbpConnectTo64(sock,address,len);
}
void sbpconn64n__(int *ierr,socket_t *sock, char*address,uint64_t len){
    *ierr=sbpConnectTo64(sock,address,len);
}

int sbpListenForService32(socket_t *sock,char *service,uint32_t len){
    struct addrinfo hints, *res, *res0;
    struct sbp_listening_sockets lSock,*lSock2;
    int s=-1, isock, err;
    char nullTermAddress[80];
    char *serviceName=NULL;
    *sock=-1;
    memset(&hints,0,sizeof(hints));
    memset(&lSock,0,sizeof(lSock));
    hints.ai_family = PF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = AI_PASSIVE;
    
    {
        size_t i=0,ii=0;
        while(i<len && service[i]==' '&& service[i]!=0) ++i;
        serviceName=&nullTermAddress[ii];
        while(i<len && service[i]!=' '&& service[i]!=0){
            nullTermAddress[ii]=service[i];
            ++i;++ii;
        }
        nullTermAddress[ii]=0;
        ++ii;
        while(i<len && service[i]==' '&& service[i]!=0) ++i;
        if (i<len && service[i]!=0){
            // error interpreting service
            return 21;
        }
    }
    //printf("will start listening on port '%s'\n",serviceName);
    err=getaddrinfo(NULL,serviceName,&hints,&res0);
    if (err){
        fprintf(stderr,"SBP %s\n", gai_strerror(err));
        return 22;
    }
    lSock.nSockets=0;
    for (res=res0;res;res=res->ai_next){
        //printf("will create socket(%d,%d,%d)\n",res->ai_family,res->ai_socktype,res->ai_protocol);
        s=socket(res->ai_family,res->ai_socktype,res->ai_protocol);
        if (s<0) continue;
        if (bind(s,res->ai_addr,res->ai_addrlen)!=0){
            close(s);
            s=-1;
            continue;
        }
        listen(s,5);
        if (lSock.nSockets>max_listening_sockets){
            fprintf(stderr,"SBP sbpListenForService32 hit max listening sockets\n");
            break;
        }
        lSock.socktable[lSock.nSockets]=s;
        lSock.sockfamile[lSock.nSockets] = res -> ai_family;
        ++lSock.nSockets;
    }
    freeaddrinfo(res0);
    if (lSock.nSockets==0){
        return 1; // no bind successful
    }
    lSock.externalId=lSock.socktable[0];
    FD_ZERO(&lSock.selectSet);
    for (isock=0;isock<lSock.nSockets;++isock){
        FD_SET(lSock.socktable[isock],&lSock.selectSet);
        if (lSock.maxDesc<lSock.socktable[isock]) lSock.maxDesc=lSock.socktable[isock];
    }
    lSock2=(struct sbp_listening_sockets*)malloc(sizeof(lSock));
    memcpy(lSock2,&lSock,sizeof(lSock));
    lSock2->next=sbpListeningSockets;
    sbpListeningSockets=lSock2;
    *sock=lSock.externalId;
    return 0;
}
/// f77 interface
void sbplisten32n(int *ierr,socket_t *sock,char *service,uint32_t len){
    *ierr=sbpListenForService32(sock,service,len);
}
void sbplisten32n_(int *ierr,socket_t *sock,char *service,uint32_t len){
    *ierr=sbpListenForService32(sock,service,len);
}
void sbplisten32n__(int *ierr,socket_t *sock,char *service,uint32_t len){
    *ierr=sbpListenForService32(sock,service,len);
}

int sbpListenForService64(socket_t *sock,char *service,uint64_t len){
    if (len>1024){
        return 3;
    }
    return sbpListenForService32(sock,service,(uint32_t)len);
}
/// f77 interface
void sbplisten64n(int *ierr,socket_t *sock,char *service,uint64_t len){
    *ierr=sbpListenForService64(sock,service,len);
}
void sbplisten64n_(int *ierr,socket_t *sock,char *service,uint64_t len){
    *ierr=sbpListenForService64(sock,service,len);
}
void sbplisten64n__(int *ierr,socket_t *sock,char *service,uint64_t len){
    *ierr=sbpListenForService64(sock,service,len);
}

int sbpClose(socket_t sock,int what){
    // check in the listening sockets
    struct sbp_listening_sockets *lS,*lSOld;
    int how;
    if (what==0){
        how=SHUT_RD;
    }else if (what==1){
        how=SHUT_WR;
    }else {
        how=SHUT_RDWR;
    }
    for (lSOld=lS=sbpListeningSockets;lS;lS->next){
        if (lS->externalId==sock){
            int i;
            if (lSOld==lS){
                sbpListeningSockets=lS->next;
            } else {
                lSOld->next=lS->next;
            }
            
            for (i=0;i<lS->nSockets;++i){
                socket_t sock2=lS->socktable[i];
                if (shutdown(lS->socktable[i],how)){
                    perror("SBP sbpClose error shutting down socket");
                    return 3;
                }
                if (how==SHUT_RDWR && close(sock2)!=0) {
                    perror("SBP sbpClose error closing the socket");
                    return 3;
                }
            }
            free(lS);
            return 0;
        }
        lSOld=lS; 
    }
    if (shutdown(sock,how)!=0) {
        perror("SBP error shutting down the socket");
        return 3;
    }
    if (how==SHUT_RDWR && close(sock)!=0) {
        perror("SBP error closing the socket");
        return 3;
    }
    return 0;
}
/// f77 interface
void sbpclose(int *ierr,socket_t *sock,int *what){
    *ierr=sbpClose(*sock,*what);
}
void sbpclose_(int *ierr,socket_t *sock,int *what){
    *ierr=sbpClose(*sock,*what);
}
void sbpclose__(int *ierr,socket_t *sock,int *what){
    *ierr=sbpClose(*sock,*what);
}

/// returns 1 if addrStr could not be fully initialized (either due to a lookup error 
/// or because it was too small)
int sbpAccept32(socket_t sock,socket_t *newSock,char*addrStr,uint32_t *addrStrLen){
    struct fd_set readSock;
    struct sbp_listening_sockets *lS;
    *newSock=-1;
    for (lS=sbpListeningSockets;lS;lS->next){
        if (lS->externalId==sock){
            break;
        }
    }
    if (! lS || lS->externalId!=sock){
        fprintf(stderr,"SBP requested socket is not have listening type\n");
    }
    while (1){
        int nSock,ndesc,ierr=0;
        FD_COPY(&(lS->selectSet),&readSock);
        ndesc=select(lS->maxDesc+1, &readSock, NULL, NULL, NULL);
        if (ndesc<0){
            if (errno!=EINTR){
                perror("SBP error while waiting in select");
            }
        }
        if (ndesc>0){
            int iSock;
            nSock=lS->nSockets;
            int firstSock=lS->lastISock+1;
            for (iSock=0;iSock<nSock;++iSock){
                int iSockAtt=(iSock+firstSock)%nSock;
                lS->lastISock=iSockAtt;
                if (FD_ISSET(lS->socktable[iSockAtt],&readSock)){
                    char serviceBuf[80];
                    struct sockaddr address;
                    socklen_t addrLen=(socklen_t)sizeof(address);
                    socklen_t addrStrLen2=(socklen_t)(*addrStrLen);
                    *newSock=accept(lS->socktable[iSockAtt],&address,&addrLen);
                    if (*newSock<=0){
                        perror("SBP accepting socket");
                        return 33;
                    }
                    if (getnameinfo(&address, address.sa_len, addrStr, addrStrLen2, &serviceBuf[0],
                        (socklen_t)sizeof(serviceBuf), 0))
                    {
                        addrStr[0]=0;
                        // failed to resolve hostanme
                        ierr=1;
                    } else {
                        size_t i,ii;
                        int addrL=strlen(addrStr);
                        int portL=strlen(&serviceBuf[0]);
                        ii=addrL;
                        addrStr[ii]=' ';
                        ++ii;
                        for (i=0;i<addrL;++i){
                            if (ii== *addrStrLen){
                                // not enough space
                                ierr=1;
                                break;
                            }
                            addrStr[ii]=serviceBuf[i];
                            ++ii;
                        }
                        if (ii<*addrStrLen)
                            addrStr[ii]=0;
                        *addrStrLen=ii;
                    }
                    return ierr;
                }
            }
            fprintf(stderr,"SBP could not find the descriptor that was ready\n");
            return 19;
        }
    }
}
/// f77 interface
void sbpaccept32n(int *ierr,socket_t*sock,socket_t*newSock,char*addrStr,uint32_t addrLen){
    uint32_t newLen=addrLen,ii;
    *ierr=sbpAccept32(*sock,newSock,addrStr,&newLen);
    for(ii=newLen;ii<addrLen;++ii){
        addrStr[ii]=' ';
    }
}
void sbpaccept32n_(int *ierr,socket_t*sock,socket_t*newSock,char*addrStr,uint32_t addrLen){
    sbpaccept32n(ierr,sock,newSock,addrStr,addrLen);
}
void sbpaccept32n__(int *ierr,socket_t*sock,socket_t*newSock,char*addrStr,uint32_t addrLen){
    sbpaccept32n(ierr,sock,newSock,addrStr,addrLen);
}

int sbpAccept64(socket_t sock,socket_t *newSock,char*addrStr,uint64_t *addrLen){
    uint32_t newLen=(uint32_t)(*addrLen);
    int err;
    if (*addrLen > 0xFFFFFFFFU){
        newLen=0xFFFFFFFFU; // probably something is wrong... give an error?
    }
    err=sbpAccept32(sock,newSock,addrStr,&newLen);
    *addrLen=(uint64_t)newLen;
    return err;
}
/// f77 interface
void sbpaccept64n(int *ierr,socket_t*sock,socket_t*newSock,char*addrStr,uint64_t addrLen){
    uint64_t newLen=addrLen,ii;
    *ierr=sbpAccept64(*sock,newSock,addrStr,&newLen);
    for(ii=newLen;ii<addrLen;++ii){
        addrStr[ii]=' ';
    }
}
void sbpaccept64n_(int *ierr,socket_t*sock,socket_t*newSock,char*addrStr,uint64_t addrLen){
    sbpaccept64n(ierr,sock,newSock,addrStr,addrLen);
}
void sbpaccept64n__(int *ierr,socket_t*sock,socket_t*newSock,char*addrStr,uint64_t addrLen){
    sbpaccept64n(ierr,sock,newSock,addrStr,addrLen);
}

int sbpGethostname64(char *name, uint64_t *namelen){
    size_t i,len=(size_t)(*namelen);
    int res=gethostname(name,len);
    reduceLen64(name,namelen);
    return res;
}

int sbpGethostname32(char *name, uint32_t* namelen){
    size_t i,len=(size_t)(*namelen);
    int res=gethostname(name,len);
    reduceLen32(name,namelen);
    return res;
}

/// f77 interface
void sbphostn32n(int*ierr,char*name,uint32_t namelen){
    uint32_t i,newLen=namelen;
    *ierr=sbpGethostname32(name,&newLen);
    for (i=newLen;i<namelen;++i){
        name[i]=' ';
    }
}
void sbphostn32n_(int*ierr,char*name,uint32_t namelen){
    sbphostn32n(ierr,name,namelen);
}
void sbphostn32n__(int*ierr,char*name,uint32_t namelen){
    sbphostn32n(ierr,name,namelen);
}

/// f77 interface
void sbphostn64n(int*ierr,char*name,uint64_t namelen){
    uint64_t i,newLen=namelen;
    *ierr=sbpGethostname64(name,&newLen);
    for (i=newLen;i<namelen;++i){
        name[i]=' ';
    }
}
void sbphostn64n_(int*ierr,char*name,uint64_t namelen){
    sbphostn64n(ierr,name,namelen);
}
void sbphostn64n__(int*ierr,char*name,uint64_t namelen){
    sbphostn64n(ierr,name,namelen);
}


