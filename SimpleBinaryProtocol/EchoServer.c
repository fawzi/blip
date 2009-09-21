// Simple send test server that waits on a given port and echoes the incoming messages
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "SimpleProtocol.h"

void *handleConnection(void* sockT){
    socket_t sock=(socket_t)sockT;
    int err;
    while(1){
        uint32_t kind;
        uint64_t len;
        char *resA;
        int *resI;
        double *resD;
        if ((err=sbpReadHeader64(sock,&kind,&len))!=0){
            printf("error %d reading header on sock %d\n",err,sock);
            return NULL;
        }
        switch (kind){
        case kind_raw:
            resA=(char*)malloc((size_t)len);
            printf("received %ld raw bytes on socket %d\n",len,sock);
            if (sbpReadCharsPiece64(sock,resA,len)){
                printf("error receiving char piece\n");
                free(resA);
                return NULL;
            }
            printf("'%.*s'\n",(uint32_t)len,resA);
            free(resA);
            break;
        case kind_char:
            resA=(char*)malloc((size_t)len);
            printf("received %ld chars on socket %d\n",len,sock);
            if (sbpReadCharsPiece64(sock,resA,len)){
                printf("error receiving char piece\n");
                free(resA);
                return NULL;
            }
            printf("'%.*s'\n",(uint32_t)len,resA);
            if (strcmp(resA,"doTests")==0){
                int i;
                int iA[10];
                double dA[11];
                char cA[8];
                uint32_t l;
                l=8;
                if ((err=sbpReadChars32(sock,&cA[0],&l))!=0){
                    printf("socket %d error %d reading c8\n",sock,err);
                }
                printf("socket %d read ch8 %d '%.8s'\n",sock,l,&cA[0]);
                for (i=0;i<8;i++){
                    if (cA[i]!='a'+i)
                        printf("socket %d error unexpected char\n",sock);
                }
                
                if ((err=sbpReadInt4Array32(sock,&iA[0],10))!=0){
                    printf("socket %d error %d reading i10\n",sock,err);
                }
                printf("read i10 [\n");
                for (i=0;i<10;i++){
                    printf(" %d",iA[i]);
                }
                printf("]\n");
                for (i=0;i<10;i++){
                    if (iA[i]!=i)
                        printf("socket %d error unexpected int\n",sock);
                }
                
                if ((err=sbpReadDoubleArray32(sock,&dA[0],11))!=0){
                    printf("socket %d error %d reading d11\n",sock,err);
                }
                printf("socket %d read d11 [\n",sock);
                for (i=0;i<11;i++){
                    printf(" %g",dA[i]);
                }
                printf("]\n");
                for (i=0;i<11;i++){
                    if (dA[i]!=(double)i)
                        printf("socket %d error unexpected double\n",sock);
                }
                printf("socket %d passed tests\n",sock);
            }
            free(resA);
            break;
        case kind_int_small:
            resI=(int*)malloc((size_t)len);
            printf("received %ld raw bytes of int socket %d\n",len,sock);
            if (sbpReadInt4ArrayPiece64(sock,resI,len)){
                printf("error receiving int piece\n");
                free(resI);
                return NULL;
            }
            {
                int i;
                for (i=0;i<len/4;++i){
                    printf(" %d",resI[i]);
                    if (i%6==0) printf("\n");
                }
            }
            printf("\n");
            free(resI);
            break;
        case kind_double_small:
            resD=(double*)malloc((size_t)len);
            printf("received %ld raw bytes on socket %d\n",len,sock);
            if (sbpReadDoublePiece64(sock,resD,len)){
                printf("error receiving char piece\n");
                free(resD);
                return NULL;
            }
            {
                int i;
                for (i=0;i<len/8;++i){
                    printf(" %d",resD[i]);
                    if (i%6==0) printf("\n");
                }
            }
            printf("\n");
            free(resD);
            break;
        default:
            printf("unknown type %d\n",kind);
            return NULL;
        }
        
    }
}

int main(int argc,char*argv[]){
    char addrBuf[1024];
    socket_t listenSock;
    uint32_t addrL=(uint32_t)sizeof(addrBuf);
    if (argc!=2){
        printf("usage: %s port\n    Starts up the server and listens to the given port\n",argv[0]);
        return 1;
    }
    if (sbpInit()){ printf("initialization error\n"); return 2; }
    if (sbpListenForService32(&listenSock,argv[1],strlen(argv[1]))){
        printf("listen error\n");
        return 3;
    }
    if (sbpGethostname32(&addrBuf[0], &addrL)){
        printf("error could not get hostname\n");
        printf("listening on port '%s'\n",argv[1]);
    } else {
        printf("listening on port '%.*s %s'\n",addrL,&addrBuf[0],argv[1]);
    }
    
    while (1){
        pthread_t new_t;
        pthread_attr_t t_attr;
        socket_t newSock;
        uint32_t len=sizeof(addrBuf);
        if (sbpAccept32(listenSock,&newSock,addrBuf,&len)){
            printf("accept error\n");
            return 4;
        }
        printf("accepted connection %d from %.*s\n",newSock,len,addrBuf);
        if( pthread_attr_init( &t_attr ) ){
            printf("thread_attr init error\n");
            return 5;
        }
        if( pthread_attr_setstacksize( &t_attr, 1024*1024 ) ){
            printf("thread_attr stackSize error\n");
            return 6;
        }
        if( pthread_attr_setdetachstate( &t_attr, PTHREAD_CREATE_DETACHED ) ){
            printf("thread_attr detach error\n");
            return 7;
        }
        if (pthread_create(&new_t,&t_attr,&handleConnection,(void *)newSock)){
            printf("error creating thread\n");
            return 8;
        }
    }
}
