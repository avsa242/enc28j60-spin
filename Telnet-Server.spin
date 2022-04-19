{
    --------------------------------------------
    Filename: Telnet-Server.spin
    Author: Jesse Burt
    Description: WIP Telnet server, for testing TCP
    Copyright (c) 2022
    Started Apr 16, 2022
    Updated Apr 19, 2022
    See end of file for terms of use.
   --------------------------------------------

    NOTE: Requires DHCP-LeaseIP-BuffIO.spin
}
#define TCP_TEL
#include "DHCP-LeaseIP-BuffIO.spin"

VAR

    long _seq_nr, _cli_seq_nr
    byte _tcp_state

CON

{ responder states }
'    CLOSED          = 0
    LISTEN          = 0
    SYN_RECEIVED    = 1
    ESTABLISHED     = 2
    CLOSE_WAIT      = 3
    LAST_ACK        = 4

PRI Process_TCP{} | isn, hdr_len, paylen_rx
' Process TCP datagrams
    ser.str(@"[TCP]")
    net.rd_tcp_header{}
    net.rd_tcp_opts{}
    showtcp_flags(net.tcp_flags)
    ser.newline

    { reset connection request received? Set everything back to its }
    { initial state }
    if (net.tcp_flags{} == net#RST_BIT)
        ser.strln(@"Connection reset")
        _seq_nr := _cli_seq_nr := 0
        net.tcp_reset{}                         ' clear ALL stored TCP header data
        _tcp_state := LISTEN
        return

    if (net.tcp_flags{} == (net#FIN_BIT | net#ACK_BIT)) and (_tcp_state < CLOSE_WAIT)
        _tcp_state := CLOSE_WAIT

    { if this node is bound to an IP, the TCP message was directed to it, }
    {   and we're listening on the port, set up a connection }
    if ( (_dhcp_state => BOUND) and (net.ip_destaddr{} == _my_ip) and {
}   lookdown(net.tcp_destport{}: svc#TELNET) )
        case _tcp_state
            LISTEN:
                isn := math.rndi(posx)
                _seq_nr := isn
                ser.strln(@"[LISTEN]")
                if (net.tcp_flags{} == net#SYN_BIT)
                    _cli_seq_nr := net.tcp_seqnr{} + 1
                    tcp_send(net#SYN_BIT | net#ACK_BIT, 0, 0)
                    _tcp_state := SYN_RECEIVED
            SYN_RECEIVED:
                ser.strln(@"[SYN_RECEIVED]")
                if (net.tcp_flags{} == net#ACK_BIT)
                    _tcp_state := ESTABLISHED
            ESTABLISHED:
                ser.strln(@"[ESTABLISHED]")
                if ((net.tcp_flags{} & net#PSH_BIT) or (net.tcp_flags{} & net#ACK_BIT))
                    hdr_len := net.ip_hdrlen{}+net.tcp_hdrlenbytes{}
                    paylen_rx := net.ip_dgramlen{}-hdr_len
                    { if there's a payload attached to this segment, }
                    {   show a hexdump of it; skip over the ethernet-II header, }
                    {   the IP header, and the TCP header + options }
                    if (paylen_rx > 0)
                        ser.hexdump(@_buff+net#ETH_FRM_SZ+hdr_len, 0, 4, paylen_rx, (16 <# paylen_rx) )
                    _cli_seq_nr += paylen_rx    ' inc their seq nr by sz of payld rx'd
                    _seq_nr := net.tcp_acknr{}  ' maintain our seq nr based on their ack
                    tcp_send(net#ACK_BIT, 0, 0)
            CLOSE_WAIT:
                ser.strln(@"[CLOSE_WAIT]")
                _cli_seq_nr++
                tcp_send(net#FIN_BIT | net#ACK_BIT, 0, 0)
                _tcp_state := LAST_ACK
            LAST_ACK:
                ser.strln(@"[LAST_ACK]")
                if (net.tcp_flags{} & net#ACK_BIT)
                    _tcp_state := LISTEN'CLOSED

PRI ShowTCP_Flags(flags) | i
' Display the TCP header's flag bits as symbols
    ser.str(@": [")
    repeat i from 8 to 0
        if (flags & (|< i))
            ser.fgcolor(ser#BRIGHT+ser#WHITE)
            ser.str(@_tcp_flagstr[i*6])
        else
            ser.fgcolor(ser#BRIGHT+ser#BLACK)
            ser.str(@_tcp_flagstr[i*6])
    ser.fgcolor(ser#WHITE)
    ser.char("]")

PRI TCP_Send(flags, data_len, ptr_data) | ip_st, ipchk, tcp_st, frm_end, pseudo_chk, tcpchk, tmp

    if ((data_len + net#IP_HDR_SZ + net#TCP_HDR_SZ) > MTU_MAX)         ' data len + IP hdr + TCP hdr
        return -1                               ' frame too big; ignore

    startframe{}
    ethii_reply
    ip_st := net.currptr{}
    ipv4_reply{}
    tcp_st := net.currptr{}

    { swap source/dest ports so as to "reply" }
    tmp := net.tcp_srcport{}
    net.tcp_setsrcport(net.tcp_destport{})
    net.tcp_setdestport(tmp)

    net.tcp_setacknr(_cli_seq_nr)               ' client's seq num
    net.tcp_setseqnr(_seq_nr)                   ' our seq num
    net.tcp_setflags(flags)

    net.tcp_setchksum(0)                        ' init chksum field to 0 for real chksum calc
    net.tcp_sethdrlen(0)                        ' same with header length (no TCP opts yet)
    net.tcp_seturgentptr(0)
    net.wr_tcp_header{}
    frm_end := net.currptr{}                    ' update frame end: add TCP header

    { write TCP options, as necessary }
    if (flags & net#SYN_BIT)
        net.writeklv(net#MSS, 4, true, net.tcp_mss{}, net#MSBF)
        net.writeklv(net#TMSTAMPS, 10, true, net.tcp_timest_ptr{}, net#MSBF)
        net.writeklv(net#WIN_SCALE, 3, true, 10, 0)
        net.writeklv(net#NOOP, 0, false, 0, 0)
        net.writeklv(net#NOOP, 0, false, 0, 0)
        net.writeklv(net#NOOP, 0, false, 0, 0)
        net.writeklv(net#NOOP, 0, false, 0, 0)
    elseif (flags & net#ACK_BIT)
        net.writeklv(net#NOOP, 0, false, 0, 0)
        net.writeklv(net#NOOP, 0, false, 0, 0)
        net.writeklv(net#TMSTAMPS, 10, true, net.tcp_timest_ptr{}, net#MSBF)
    net.tcp_sethdrlenbytes(20 + (net.currptr{} - frm_end))  ' hdr len = TCP hdr + opts len
    frm_end := net.currptr{}                    ' update frame end: add TCP options

    net.setptr(tcp_st + net#TCPH_HDRLEN)
    net.wr_byte(net.tcp_hdrlen{} | ((net.tcp_flags{} >> net#NONCE) & 1) )
    net.setptr(frm_end)

    ip_updchksum(net.ip_hdrlen{} + net.tcp_hdrlenbytes{} + data_len)

    { update TCP header with checksum }
    _tcp_ph_src := net.ip_srcaddr{}
    _tcp_ph_dest := net.ip_destaddr{}
    _tcp_ph_proto := net.ip_l4proto{}

    tmp := net.tcp_hdrlenbytes{}             'XXX got to be a better way...
    _tcp_ph_len.byte[1] := tmp.byte[0]  '
'    ser.hexdump(@_tcp_ph_src, 0, 4, 12, 12) ' inspect pseudo-header

    { calc checksum of TCP/IP pseudo header, then the TCP header }
    pseudo_chk := crc.inetchksum(@_tcp_ph_src, 12, $00)
    tcpchk := crc.inetchksum(@_buff[tcp_st], net.tcp_hdrlenbytes{}, pseudo_chk)
    net.setptr(tcp_st+net#TCPH_CKSUM)
    net.wrword_msbf(tcpchk)
    net.setptr(frm_end)

    { if there's a payload, tack it on the end }
    if (data_len > 0)
        net.wrblk_lsbf(ptr_data, data_len)

    eth.txpayload(@_buff, net.currptr{})
    sendframe{}
    ser.printf1(@"[TX: %d][IPv4][TCP]", frm_end)
    showtcp_flags(flags)
    ser.newline{}

DAT
    ' XXX var?
    { TCP pseudo-header }
    _tcp_ph_src    long $00_00_00_00
    _tcp_ph_dest   long $00_00_00_00
    _tcp_ph_zero   byte $00
    _tcp_ph_proto  byte net#TCP
    _tcp_ph_len    word $00_00

    { TCP flags: strings }
    _tcp_flagstr
        byte    " FIN ", 0
        byte    " SYN ", 0
        byte    " RST ", 0
        byte    " PSH ", 0
        byte    " ACK ", 0
        byte    " URG ", 0
        byte    " ECN ", 0
        byte    " CWR ", 0
        byte    " NON ", 0

DAT
{
    --------------------------------------------------------------------------------------------------------
    TERMS OF USE: MIT License

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
    associated documentation files (the "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
    following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial
    portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
    LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
    WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    --------------------------------------------------------------------------------------------------------
}
