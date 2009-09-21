/// Simple client testing the protocol
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "SimpleProtocol.h"
#include <unistd.h>


int main(int argc,char*argv[]){
    int iA[10];
    double dA[11];
    char cA[8];
    int i;
    sbpInit();
    socket_t sock;
    
    if (argc!=2){
        printf("usage %s \"host port\"\n");
        return 0;
    }
    if (sbpConnectTo32(&sock, argv[1],(uint32_t)strlen(argv[1]))){
        printf("error connecting\n");
        return 1;
    }
    
    printf("connected\n");
    if (sbpSendChars32(sock,"doTests",7)){
        printf("error sending doTests string\n");
    }
    printf("sent doTests\n");
    for (i=0;i<8;i++)cA[i]='a'+i;
    for (i=0;i<10;i++)iA[i]=i;
    for (i=0;i<11;i++)dA[i]=(double)i;
    
    if (sbpSendChars32(sock,&cA[0],8)){
        printf("error sending c8\n");
    }
    printf("sent c8\n");
    if (sbpSendInt4Array32(sock,&iA[0],10)){
        printf("error sending i10\n");
    }
    printf("sent i10\n");
    if (sbpSendDoubleArray32(sock,&dA[0],11)){
        printf("error sending d11\n");
    }
    printf("sent d11\n");
    printf("did send test\n");
    sbpClose(sock,1);
    printf("closed Socket\n");
    sleep(10);
    printf("end\n");
}