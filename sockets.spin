{
    --------------------------------------------
    Filename: sockets.spin
    Description: TCP socket management
    Author: Jesse Burt
    Copyright (c) 2023
    Started Feb 21, 2023
    Updated Mar 10, 2023
    See end of file for terms of use.
    --------------------------------------------
}
CON

    NR_SOCKETS      = 5                         ' can be overridden in parent obj declaration

    { socket states }
    #0, CLOSED, LISTEN, SYN_SENT, SYN_RECEIVED, ESTABLISHED, FIN_WAIT_1, FIN_WAIT_2, ...
        CLOSE_WAIT, CLOSING, LAST_ACK

VAR

    long remote_ip[NR_SOCKETS]
    long handler[NR_SOCKETS]
    long remote_mss[NR_SOCKETS]
    long remote_seq_nr[NR_SOCKETS]
    long local_seq_nr[NR_SOCKETS]
    word remote_port[NR_SOCKETS]
    word state[NR_SOCKETS]
    word local_port[NR_SOCKETS]

PUB null()
' This is not a top-level object

PUB accept(lcl_port, rem_ip, rem_port, rem_isn, ptr_svr): s
' Accept a client connection to a local server process
'   lcl_port: local TCP port the server process is running on
'   rem_ip: remote IP address
'   rem_port: remote TCP port
'   rem_isn: remote's initial sequence number
    s := first_avail()
    if ( s == -1 )
        return                                  ' no socket available
    local_port[s] := lcl_port
    set_local_seq_nr_rand(s)
    remote_ip[s] := rem_ip
    remote_port[s] := rem_port
    remote_seq_nr[s] := rem_isn
    handler[s] := ptr_svr
    state[s] := LISTEN

PUB any_listening(lcl_port): l | s
' Check for any sockets listening on the given port number
    l := -1
    repeat s from 0 to NR_SOCKETS-1
        if is_listening(s, lcl_port) => 0
            return s

PUB any_match(lcl_port, rem_ip, rem_port): m | s
' Check for any sockets that match the given local port, remote IP address and port
'   Returns:
'       socket number if a match is found
'       -1 if no match found
    m := -1
    repeat s from 0 to NR_SOCKETS-1
        if matches(s, lcl_port, rem_ip, rem_port) => 0
            return s

PUB bind(sock_nr, port, ptr_handler): s | rnd_seed
' Bind a socket to a local port and server function
'   sock_nr: index of socket number in the range 0..NR_SOCKETS-1
'   port: TCP port number to listen on
'   ptr_handler: pointer to function to call when an incoming connection is made to this port
'   Returns: index of socket number allocated, or -1 if socket isn't available
    if ( state[sock_nr] == CLOSED )
        local_port[sock_nr] := port
        handler[sock_nr] := ptr_handler
        state[sock_nr] := LISTEN
        rnd_seed := cnt
        local_seq_nr[sock_nr] := ?rnd_seed
        return sock_nr
    else                                        ' socket not available
        return -1

PUB close(sock_nr)
' Close the given socket
    remote_ip[sock_nr] := 0
    handler[sock_nr] := 0
    remote_mss[sock_nr] := 0
    remote_seq_nr[sock_nr] := 0
    local_seq_nr[sock_nr] := 0
    remote_port[sock_nr] := 0
    state[sock_nr] := CLOSED
    local_port[sock_nr] := 0
    return sock_nr

PUB first_avail(): s
' Get the first available TCP socket number
'   Returns: socket number, or -1 if none available
    repeat s from 0 to NR_SOCKETS-1
        if ( state[s] == CLOSED )
            return s
    return -1

PUB inc_remote_seq_nr(sock_nr, val)
' Increment remote sequence number
'   sock_nr: socket number
'   val: value to increase sequence number by
    remote_seq_nr[sock_nr] += val

PUB is_listening(sock_nr, port): l
' Check to see if a socket is listening on the given port number
'   Returns: matching socket number, or -1 if no match
    l := -1
    if ( (local_port[sock_nr] == port) and (state[sock_nr] == LISTEN) )
        return sock_nr

PUB matches(sock_nr, lcl_port, rem_ip, rem_port): m
' Check to see if there is an existing socket matching the TCP port and IP pairs
'   Returns: matching socket number, or -1 if no match
    m := -1
    if (lcl_port == local_port[sock_nr] and ...
        rem_ip == remote_ip[sock_nr] and ...
        rem_port == remote_port[sock_nr])
            return sock_nr

PUB set_handler(sock_nr, ptr_func)
' Set handler function for connections to the given socket number
    handler[sock_nr] := ptr_func

PUB set_local_port(sock_nr, port): s
' Set local port number of socket
    local_port[sock_nr] := port
    return sock_nr

PUB set_local_seq_nr(sock_nr, seq):s
' Set local sequence number of socket
    local_seq_nr[sock_nr] := seq
    return sock_nr

PUB set_local_seq_nr_rand(sock_nr) | rnd
' Set the local sequence number to a random number (intended for ISN)
    rnd := cnt
    local_seq_nr[sock_nr] := ?rnd

PUB set_remote_ip(sock_nr, ip): s
' Set remote IP address of socket
    remote_ip[sock_nr] := ip
    return sock_nr

PUB set_remote_port(sock_nr, port): s
' Set remote port number of socket
    remote_port[sock_nr] := port
    return sock_nr

PUB set_remote_seq_nr(sock_nr, seq): s
' Set the remote sequence number of a socket
    remote_seq_nr[sock_nr] := seq
    return sock_nr

PUB set_state(sock_nr, st): s
' Set socket to specified state
    state[sock_nr] := st
    return sock_nr

PUB unbind(sock_nr)
' Un-bind a listening TCP socket
'   sock_nr: socket number of registered service
'   Returns: index of socket number deleted, or -1 if socket wasn't allocated
    if ( state[sock_nr] == LISTEN )
        local_port[sock_nr] := 0
        handler[sock_nr] := 0
        state[sock_nr] := CLOSED
        remote_seq_nr[sock_nr] := 0
        return sock_nr
    else
        return -1


DAT
{
Copyright 2023 Jesse Burt

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
}

