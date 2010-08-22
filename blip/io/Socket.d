/// socket implementation, non buffered, probably you want to wrap them
/// into a buffered stream
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
module blip.io.Socket;
import blip.io.BasicIO;
import blip.io.BasicStreams;
import blip.io.BasicStreams;
import blip.container.GrowableArray;
import blip.stdc.socket;
import blip.stdc.string: memset,strlen,memcpy;
import blip.stdc.errno;
import blip.util.TangoLog;

class BasicSocket{
    socket_t sock;
    
    this(socket_t s){
        sock=s;
    }
    
    this(char[]address,char[]service){
        int err;
        char buf[256];
        char * nodeName,serviceName;
        sockaddr addrName;
        addrinfo hints;
        addrinfo* addressInfo,addrAtt;

        sock=-1;
        auto a1=lGrowableArray(buf,0);
        dumper(&a1)(address)("\0")(service)("\0");
        auto addr0=a1.data();
        nodeName=a1.ptr;
        serviceName=a1.ptr+address.length+1;

        memset(&hints, 0, hints.sizeof);
        hints.ai_family = PF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;

        err=getaddrinfo(nodeName,serviceName,&hints,&addressInfo);
        if (err!=0){
            char *errStr= gai_strerror(err);
            throw new BIOException("getaddrinfo error:"~errStr[0..strlen(errStr)],__FILE__,__LINE__);
        }

        socket_t s=-1;
        for (addrAtt=addressInfo;addrAtt;addrAtt.ai_next){
            s = socket(addrAtt.ai_family, addrAtt.ai_socktype, addrAtt.ai_protocol);
            if (s<0) continue;
            if (connect(s, addrAtt.ai_addr, addrAtt.ai_addrlen) != 0) {
                shutdown(s,SHUT_RDWR);
                s = -1;
                continue;
            }
            break;
        }
        freeaddrinfo(addressInfo);
        if (s<0){
            throw new BIOException("could not connect to "~address~" "~service,__FILE__,__LINE__);
        }
        sock=s;
    }
    
    final void writeExact(void[] src){
        size_t written=0;
        while(written<src.length){
            auto wNow=write(sock,src.ptr+written,src.length-written);
            if (wNow==-1){
                char[] buf=new char[](256);
                auto msg=strerror_d(errno(), buf);
                if (msg.length==0){
                    auto a=lGrowableArray(buf,0);
                    a("IO error:");
                    writeOut(&a.appendArr,errno());
                    throw new BIOException(a.takeData(),__FILE__,__LINE__);
                }
                throw new BIOException(buf[0..strlen(buf.ptr)],__FILE__,__LINE__);
            }
            written+=wNow;
        }
    }
    
    final size_t rawReadInto(void[] dst){
        size_t res=read(sock,dst.ptr,dst.length);
        if (res==0) return Eof;
        if (res==-cast(size_t)1){
            char[] buf=new char[](256);
            auto errMsg=strerror_d(errno,buf);
            if (errMsg.length==0){
                auto a=lGrowableArray(buf,0);
                a("IO error:");
                writeOut(&a.appendArr,errno());
                throw new BIOException(a.takeData(),__FILE__,__LINE__);
            }
            throw new BIOException(errMsg,__FILE__,__LINE__);
        }
    }
    
    final void flush(){
    }
    
    void shutdownInput(){
        shutdown(sock,SHUT_RD);
    }

    void close(){
        shutdown(sock,SHUT_WR);
    }
    
}

/// a server that listens on one port
class SocketServer{
    char[]serviceName;
    size_t pos;
    socket_t[] socks;
    int[] sockfamile;
    fd_set selectSet;
    socket_t maxDesc;
    
    static class StopException:Exception{
        this(char[]msg,char[]file,long line){
            super(msg,file,line);
        }
    }
    
    this(char[]serviceName){
        this.serviceName=serviceName;
        addrinfo hints;
        addrinfo *res, res0;
        int isock, err;
        char nullTermAddress[80];
        memset(&hints,0,hints.sizeof);
        hints.ai_family = PF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;
        hints.ai_flags = AI_PASSIVE;
        char[128] buf;
        auto arr=lGrowableArray(buf,0);
        arr(serviceName);
        arr('\0');
        auto serviceZ=arr.data();
        err=getaddrinfo(null,serviceZ.ptr,&hints,&res0);
        if (err){
            char *str=gai_strerror(err);
            if (str is null || strlen(str)==0){
                arr.clearData();
                arr("getaddrinfo error:");
                writeOut(&arr.appendArr,err);
                throw new BIOException(arr.takeData(),__FILE__,__LINE__);
            } else {
                throw new BIOException(str[0..strlen(str)],__FILE__,__LINE__);
            } 
        }
        for (res=res0;res;res=res.ai_next){
            //printf("will create socket(%d,%d,%d)\n",res.ai_family,res.ai_socktype,res.ai_protocol);
            socket_t s=socket(res.ai_family,res.ai_socktype,res.ai_protocol);
            if (s<0) continue;
            if (bind(s,res.ai_addr,res.ai_addrlen)!=0){
                close(s);
                s=-1;
                continue;
            }
            listen(s,5);
            socks~=s;
            sockfamile~= res . ai_family;
        }
        freeaddrinfo(res0);
        if (socks.length==0){
            throw new BIOException("no bind sucessful",__FILE__,__LINE__);
        }
        FD_ZERO(&selectSet);
        maxDesc=0;
        foreach (sock;socks){
            FD_SET(sock,&selectSet);
            if (maxDesc<sock) maxDesc=sock;
        }
    }
    
    BasicSocket accept(char[]*addrStrPtr=null,char[]*serviceStrPtr=null){
        fd_set readSock;
        socket_t newSock=-1;
        while (1){
            int nSock,ndesc,ierr=0;
            memcpy(&readSock,&selectSet,fd_set.sizeof); // linux does not define FD_COPY
            ndesc=select(maxDesc+1, &readSock, null, null, null);
            if (ndesc<0){
                if (errno!=EINTR){
                    char[128] buf;
                    throw new BIOException(strerror_d(errno,buf),__FILE__,__LINE__);
                }
            }
            if (ndesc>0){
                int iSock;
                nSock=socks.length;
                int firstSock=pos+1;
                for (iSock=0;iSock<nSock;++iSock){
                    int iSockAtt=(iSock+firstSock)%nSock;
                    pos=iSockAtt;
                    if (FD_ISSET(socks[iSockAtt],&readSock)){
                        sockaddr address;
                        socklen_t addrLen=cast(socklen_t)address.sizeof;
                        newSock=blip.stdc.socket.accept(socks[iSockAtt],&address,&addrLen);
                        if (newSock<=0){ // ignore lost connections???
                            char[128] buf;
                            auto errMsg=strerror_d(errno,buf);
                            if (errMsg.length==0){
                                auto a=lGrowableArray(buf,0,GASharing.Local);
                                a("error accepting socket ");
                                writeOut(&a.appendArr,errno);
                                throw new BIOException(a.takeData,__FILE__,__LINE__);
                            }
                            throw new BIOException("error accepting socket "~errMsg,
                                __FILE__,__LINE__);
                        }
                        if (addrStrPtr !is null || serviceStrPtr !is null){
                            char[]addrStr,serviceStr;
                            if (addrStrPtr!is null) {
                                addrStr=*addrStrPtr;
                            }
                            if (serviceStrPtr!is null) {
                                serviceStr=*serviceStrPtr;
                            }
                            if (getnameinfo(&address,addrLen, addrStr.ptr, addrStr.length, serviceStr.ptr,serviceStr.length, 0))
                            {
                                if (addrStrPtr!is null) {
                                    *addrStrPtr=null;
                                }
                                if (serviceStrPtr!is null) {
                                    *serviceStrPtr=null;
                                }
                            } else {
                                if (addrStrPtr!is null) {
                                    *addrStrPtr=addrStr[0..strlen(addrStr.ptr)];
                                }
                                if (serviceStrPtr!is null) {
                                    *serviceStrPtr=serviceStr[0..strlen(serviceStr.ptr)];
                                }
                            }
                        }
                        return new BasicSocket(newSock);
                    }
                }
                Log.lookup("blip.io.Socket").warn("could not find the descriptor that was ready in SocketServer.accept for service "~serviceName~"\n");
            }
        }
    }
    
    void runWithHandler(void delegate(BasicSocket,char[] source) h){
        Log.lookup("blip.io.Socket").warn("starting server for "~serviceName);
        while(1){
            char[256] buf;
            char[] addr=buf;
            BasicSocket s;
            try{
                s=accept(&addr);
            } catch(BIOException e){
                char[256]buf2;
                auto a=lGrowableArray(buf2,0);
                dumper(&a)("error accepting ")(serviceName)(":");
                e.writeOut(&a.appendArr);
                Log.lookup("blip.io.Socket").warn(a.data);
            }
            addr=addr.dup;
            try{
                h(s,addr);
            } catch (StopException s){
                Log.lookup("blip.io.Socket").warn("stopping server for "~serviceName);
                break;
            } catch(Exception e){
                char[256]buf2;
                auto a=lGrowableArray(buf2,0);
                dumper(&a)("error handling accepted socket ")(serviceName)(" from ")(addr)(":");
                e.writeOut(&a.appendArr);
                Log.lookup("blip.io.Socket").warn(a.data);
            }
        }
    }
}
