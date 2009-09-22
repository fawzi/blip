#!/bin/sh

if [ -z "$CC" ]; then
    CC=gcc
fi

$CC -g -c SimpleProtocol.c
ar -r libSimpleProtocol.a SimpleProtocol.o
$CC -g -o EchoServer EchoServer.c SimpleProtocol.c -lpthread
$CC -g -o SimpleClient SimpleClient.c SimpleProtocol.c
