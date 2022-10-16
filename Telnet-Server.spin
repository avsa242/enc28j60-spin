{
    --------------------------------------------
    Filename: Telnet-Server.spin
    Author: Jesse Burt
    Description: WIP Telnet server, for testing TCP
    Copyright (c) 2022
    Started Apr 16, 2022
    Updated Oct 16, 2022
    See end of file for terms of use.
   --------------------------------------------

    NOTE: Requires DHCP-LeaseIP-BuffIO.spin
}
#define TCP_TEL
#include "DHCP-LeaseIP-BuffIO.spin"
VAR

    byte _tcp_state

CON

{ responder states }
'    CLOSED          = 0
    LISTEN          = 0
    SYN_RECEIVED    = 1
    ESTABLISHED     = 2
    CLOSE_WAIT      = 3
    LAST_ACK        = 4

PRI process_tcp{} | isn, hdr_len, paylen_rx
' Process TCP datagrams
    net.rd_tcp_header{}
    net.rd_tcp_opts{}

    { reset connection request received? Set everything back to its }
    { initial state }
    if (net.tcp_flags{} == net#RST_BIT)
        ser.strln(@"Connection reset")
        net.tcp_reset{}                         ' clear ALL stored TCP header data
        _tcp_state := LISTEN
        return

    { if this node is bound to an IP, and the TCP message was directed to it, }
    {   and we're listening on the port, then set up a connection }
    if ( (_dhcp_state => BOUND) and (net.ip_dest_addr{} == _my_ip) and {
}   lookdown(net.tcp_dest_port{}: svc#TELNET) )
        case _tcp_state
            LISTEN:
                ser.strln(@"[LISTEN]")
                if (net.tcp_flags{} == net#SYN_BIT)
                    net.tcp_swap_seq_nrs{}
                    net.tcp_set_seq_nr(math.rndi(posx))
                    net.tcp_inc_ack_nr(1)
                    tcp_send(net#SYN_BIT | net#ACK_BIT, 0, 0)
                    _tcp_state := SYN_RECEIVED
            SYN_RECEIVED:
                show_ip_addr(@"[SYN_RECEIVED] ", net.ip_src_addr{}, string(10, 13))
                if (net.tcp_flags{} == net#ACK_BIT)
                    _tcp_state := ESTABLISHED
            ESTABLISHED:
                show_ip_addr(@"[ESTABLISHED] ", net.ip_src_addr{}, string(10, 13))
                if ((net.tcp_flags{} & net#PSH_BIT) or (net.tcp_flags{} == net#ACK_BIT))
                    hdr_len := net.ip_hdr_len{}+net.tcp_hdr_len_bytes{}
                    paylen_rx := net.ip_dgram_len{}-hdr_len
                    { if there's a payload attached to this segment, }
                    {   show a hexdump of it; skip over the ethernet-II header, }
                    {   the IP header, and the TCP header + options }
                    if (paylen_rx > 0)
                        ser.hexdump(@_buff+net#ETH_FRM_SZ+hdr_len, 0, 4, paylen_rx, (16 <# paylen_rx) )
                    net.tcp_swap_seq_nrs{}
                    net.tcp_inc_ack_nr(paylen_rx)
                    tcp_send(net#ACK_BIT, 0, 0)
                if (net.tcp_flags{} == (net#FIN_BIT | net#ACK_BIT))
                    _tcp_state := CLOSE_WAIT
            CLOSE_WAIT:
                show_ip_addr(@"[CLOSE_WAIT] ", net.ip_src_addr{}, string(10, 13))
                net.tcp_swap_seq_nrs{}
                net.tcp_inc_ack_nr(1)
                tcp_send(net#FIN_BIT | net#ACK_BIT, 0, 0)
                _tcp_state := LAST_ACK
            LAST_ACK:
                show_ip_addr(@"[LAST_ACK] ", net.ip_src_addr{}, string(10, 13))
                if (net.tcp_flags{} & net#ACK_BIT)
                    _tcp_state := LISTEN'CLOSED

PRI show_tcp_flags(flags) | i
' Display the TCP header's flag bits as symbols
    ser.str(@": [")
    repeat i from 8 to 0
        if ( flags & |<(i) )
            ser.fgcolor(ser#WHITE)
            ser.str(@_tcp_flagstr[i*6])
        else
            ser.fgcolor(ser#DKGREY)
            ser.str(@_tcp_flagstr[i*6])
    ser.fgcolor(ser#GREY)
    ser.char("]")

PRI tcp_send(flags, data_len, ptr_data) | ipchk, tcp_st, frm_end, pseudo_chk, tcpchk, tmp

    { before doing anything, check that the segment fits within the max MTU }
    if ((data_len + net#ETH_FRM_SZ + net#IP_HDR_SZ + net#TCP_HDR_SZ) > MTU_MAX)
        return -1                               ' frame too big; ignore

    start_frame{}
    ethii_reply
    ipv4_reply{}
    tcp_st := net.fifo_wr_ptr{}

    { swap source/dest ports so as to "reply" }
    net.tcp_swap_ports{}

    net.tcp_set_flags(flags)

    net.tcp_set_chksum(0)                        ' init chksum field to 0 for real chksum calc
    net.tcp_set_hdr_len(0)                        ' same with header length (no TCP opts yet)
    net.tcp_set_urgent_ptr(0)
    net.wr_tcp_header{}
    frm_end := net.fifo_wr_ptr{}                    ' update frame end: add TCP header

    { write TCP options, as necessary }
    if (flags & net#SYN_BIT)
        net.write_klv(net#MSS, 4, true, net.tcp_mss{}, net#MSBF)
        net.write_klv(net#TMSTAMPS, 10, true, net.tcp_timest_ptr{}, net#MSBF)
        net.write_klv(net#WIN_SCALE, 3, true, 10, 0)
        net.write_klv(net#NOOP, 0, false, 0, 0)
        net.write_klv(net#NOOP, 0, false, 0, 0)
        net.write_klv(net#NOOP, 0, false, 0, 0)
        net.write_klv(net#NOOP, 0, false, 0, 0)
    elseif (flags & net#ACK_BIT)
        net.write_klv(net#NOOP, 0, false, 0, 0)
        net.write_klv(net#NOOP, 0, false, 0, 0)
        net.write_klv(net#TMSTAMPS, 10, true, net.tcp_timest_ptr{}, net#MSBF)
    net.tcp_set_hdr_len_bytes(net#TCP_HDR_SZ + (net.fifo_wr_ptr{} - frm_end))  ' hdr len = TCP hdr + opts len
    frm_end := net.fifo_wr_ptr{}                    ' update frame end: add TCP options

    net.fifo_set_wr_ptr(tcp_st + net#TCPH_HDRLEN)
    net.wr_byte(net.tcp_hdr_len{} | ((net.tcp_flags{} >> net#NONCE) & 1) )
    net.fifo_set_wr_ptr(frm_end)

    ipv4_updchksum(net.ip_hdr_len{} + net.tcp_hdr_len_bytes{} + data_len)

    { update TCP header with checksum }
    _tcp_ph_src := net.ip_src_addr{}
    _tcp_ph_dest := net.ip_dest_addr{}
    _tcp_ph_proto := net.ip_l4_proto{}

    tmp := net.tcp_hdr_len_bytes{}             'XXX got to be a better way...
    _tcp_ph_len.byte[1] := tmp.byte[0]  '
'    ser.hexdump(@_tcp_ph_src, 0, 4, 12, 12) ' inspect pseudo-header

    { calc checksum of TCP/IP pseudo header, then the TCP header }
    pseudo_chk := crc.inet_chksum(@_tcp_ph_src, 12, $00)
    tcpchk := crc.inet_chksum(@_buff[tcp_st], net.tcp_hdr_len_bytes{}, pseudo_chk)
    net.fifo_set_wr_ptr(tcp_st+net#TCPH_CKSUM)
    net.wrword_msbf(tcpchk)
    net.fifo_set_wr_ptr(frm_end)

    { if there's a payload, tack it on the end }
    if (data_len > 0)
        net.wrblk_lsbf(ptr_data, data_len)

    eth.tx_payload(@_buff, net.fifo_wr_ptr{})
    send_frame{}

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
Copyright 2022 Jesse Burt

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

