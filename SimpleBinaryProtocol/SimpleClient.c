/// Simple client testing the protocol
/// author: fawzi
//
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
//
// this file is explicitly released also with GPLv2 for the projects that might need it
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
