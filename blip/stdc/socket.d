/// modern socket functions (for nice ip6)
///
/// mainly wrapping of a tango module
module blip.stdc.socket;
import tango.core.Version;
static if(Tango.Major>0||Tango.Minor>999){
    public import tango.sys.consts.socket;
} else {
    public import tango.stdc.constants.socket;
}

static if (!is(typeof(SOL_TCP))){
    alias IPPROTO_TCP SOL_TCP;
}

version (Win32) {
        pragma (lib, "ws2_32.lib");

        private import tango.sys.win32.WsaSock;
} else {
    
    // sys/socket.hostname
    public import tango.stdc.posix.sys.socket: sockaddr,sockaddr_storage,socklen_t;
    private typedef int socket_t = -1;
    extern(C){
        socket_t     accept(socket_t, sockaddr *restrict, socklen_t *restrict);
        int     bind(socket_t, sockaddr *, socklen_t);
        int     connect(socket_t, sockaddr *, socklen_t);
        int     listen(socket_t, int);
        int     shutdown(socket_t, int);
        socket_t     socket(int, int, int);
        ptrdiff_t recv(int, void *, size_t, int);
        // ssize_t recvfrom(int, void *restrict, size_t, int,
        //         struct sockaddr *restrict, socklen_t *restrict);
        // ssize_t recvmsg(int, struct msghdr *, int);
        ptrdiff_t send(int, void *, size_t, int);
        // ssize_t sendmsg(int, const struct msghdr *, int);
        // ssize_t sendto(int, const void *, size_t, int, const struct sockaddr *,
        //         socklen_t);
        int     setsockopt(int, int, int, void *, socklen_t);
        int     getsockopt(int, int, int, void *, socklen_t *);
    }
    
    // arpa/inet.h
    // print ip addresses
    extern(C){
        char *inet_ntop(int af, void * src, char * dst, socklen_t size);
        int inet_pton(int af, char * src, void * dst);
    }
    
    // select
    public import tango.stdc.posix.sys.select: fd_set,select,FD_ZERO,FD_SET,FD_ISSET;

    // netdb.h
    
    version(darwin){
        extern(C) {
            struct addrinfo {
                int ai_flags;   /* AI_PASSIVE, AI_CANONNAME, AI_NUMERICHOST */
                int ai_family;  /* PF_xxx */
                int ai_socktype;    /* SOCK_xxx */
                int ai_protocol;    /* 0 or IPPROTO_xxx for IPv4 and IPv6 */
                socklen_t   ai_addrlen; /* length of ai_addr */
                char    *ai_canonname;  /* canonical name for hostname */
                sockaddr *ai_addr;   /* binary address */
                addrinfo *ai_next;   /* next structure in linked list */
            }
        }
        enum {
            PF_UNSPEC    =0,
            SOCK_STREAM  =1,
            AI_PASSIVE   =0x00000001
        }
    } else version(linux){
        extern(C) {
            struct addrinfo {
                int ai_flags;   /* AI_PASSIVE, AI_CANONNAME, AI_NUMERICHOST */
                int ai_family;  /* PF_xxx */
                int ai_socktype;    /* SOCK_xxx */
                int ai_protocol;    /* 0 or IPPROTO_xxx for IPv4 and IPv6 */
                socklen_t   ai_addrlen; /* length of ai_addr */
                sockaddr *ai_addr;   /* binary address */
                char    *ai_canonname;  /* canonical name for hostname */
                addrinfo *ai_next;   /* next structure in linked list */
            }
        }
        enum {
            PF_UNSPEC    =0,
            SOCK_STREAM  =1,
            AI_PASSIVE   =0x00000001
        }
    } else {
        static assert(0,"define this from <netdb.h>");
    }
    
    extern(C){
        void              freeaddrinfo(addrinfo *);
        char       *gai_strerror(int);
        int               getaddrinfo(char *restrict, char *restrict,
                              addrinfo *restrict,
                              addrinfo **restrict);
        int               getnameinfo(sockaddr *restrict, socklen_t,
                              char *restrict, socklen_t, char *restrict,
                              socklen_t, int);
    }

    public import blip.stdc.unistd: read, write, close;

}

