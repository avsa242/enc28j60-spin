{
    --------------------------------------------
    Filename: tcp-serv-1.spin
    Description: TCP testing: server
    Author: Jesse Burt
    Copyright (c) 2023
    Started Feb 21, 2023
    Updated Mar 10, 2023
    See end of file for terms of use.
    --------------------------------------------
}
#include "net-common.spinh"

CON

    _clkmode    = cfg._clkmode
    _xinfreq    = cfg._xinfreq

' -- User-defined constants
    SER_BAUD    = 115_200
    LED         = cfg.LED1

{ SPI configuration }
    CS_PIN      = 1
    SCK_PIN     = 2
    MOSI_PIN    = 3
    MISO_PIN    = 4
' --

OBJ

    cfg :   "boardcfg.ybox2"
    ser :   "com.serial.terminal.ansi"
    time:   "time"
    net :   "net.eth.enc28j60" | MTU_MAX = 1518
    fsyn:   "signal.synth"
    crc :   "math.crc"
    svc :   "services.spinh"
    socket: "sockets" | NR_SOCKETS = 5

VAR

    { receive status vector }
    word _nxtpkt, _rxlen, _rxstatus

    long _tcp_rts

    { TCP payload }
    word _tcp_recvq, _tcp_sendq
    byte _tcp_recv[net.MTU_MAX-net.TCP_HDR_SZ-net.IP_HDR_SZ-net.ETH_FRM_SZ]
    byte _tcp_send[net.MTU_MAX-net.TCP_HDR_SZ-net.IP_HDR_SZ-net.ETH_FRM_SZ]

DAT

    { this node's MAC address - OUI first }
    _mac_local  byte $02, $98, $0c, $06, $01, $c9

PUB main() | tmp

    setup()
    socket.bind(0, svc.TELNET, @service_telnetd)

    net.set_pkt_filter(0)
    net.preset_fdx()

    net.node_address(@_mac_local)
    net.ip_set_my_ip(10,42,0,216)               ' static IP
    ser.str(@"waiting for PHY link...")
    repeat until net.phy_link_state() == net.UP
    ser.strln(@"link UP")

    netstat()

    repeat
        if ( net.pkt_cnt() )
            get_frame()
            parse_ethii()
        if ( _tcp_rts > -1 )
            tcp_send()
        if ( ser.rx_check() == "n" )
            netstat()

PUB tcp_send() | tcp_st_abs, tcp_st_rel, pseudo_hdr_ck, tcp_seg_ck, final_chk

    if ( (_tcp_rts + net.ETH_FRM_SZ + net.IP_HDR_SZ + net.TCP_HDR_SZ) > net.MTU_MAX )
        return -1                               ' frame too big; ignore

    net.start_frame()
    net.wr_ethii_frame()
    net.ip_set_dgram_len(net.ip_hdr_len()+net.tcp_hdr_len_bytes()) 'XXX + tcp data length
    net.wr_ip_header()

    tcp_st_abs := net.fifo_wr_ptr()
    tcp_st_rel := (tcp_st_abs - net.TXSTART)-1
    net.wr_tcp_header()

    net.ipv4_update_chksum(net.ip_hdr_len() + net.tcp_hdr_len_bytes() + _tcp_sendq)

    { update TCP header with checksum }
    pseudo_hdr_ck := net.tcp_calc_pseudo_header_cksum(net.ip_src_addr(), net.ip_dest_addr(), ...
                                                      net.TCP, net.tcp_hdr_len_bytes())
    tcp_seg_ck := net.inet_chksum(tcp_st_rel, tcp_st_rel+net.tcp_hdr_len_bytes(), ...
                                  tcp_st_rel+net.TCPH_CKSUM)
    final_chk := ((tcp_seg_ck+pseudo_hdr_ck) & $ffff) + ((tcp_seg_ck+pseudo_hdr_ck) >> 16)

    net.fifo_set_wr_ptr(tcp_st_abs+net.TCPH_CKSUM)
    net.wrword_msbf(final_chk)

    { if there's a payload, tack it on the end }
    if (_tcp_rts > 0)
        net.wrblk_lsbf(@_tcp_send, _tcp_rts)

    'dump_frame(net.TXSTART+1, 14+20+20)

    net.send_frame()
    _tcp_rts := -1

VAR long _rdptr
PUB get_frame() | rdptr
' Receive frame from ethernet device
    { get receive status vector }
    net.fifo_set_rd_ptr(_nxtpkt)
    net.rx_payload(@_nxtpkt, 6)

    { reject oversized packets }
    ifnot ( _rxlen =< net.MTU_MAX )
        ser.strln(@"[OVERSIZED]")
    else
    { ERRATA: read pointer start must be odd; subtract 1 }
        _rdptr := _nxtpkt-1

        if ( (_rdptr < net.RXSTART) or (_rdptr > net.RXSTOP) )
            _rdptr := net.RXSTOP

    net.pkt_dec()

    net.fifo_set_rx_rd_ptr(_rdptr)

PUB parse_arp() | opcode
' Parse ARP message
'    ser.str(@"[ARP]")
    net.rd_arp_msg()

    show_arp_msg(net.arp_opcode())
    if ( net.arp_opcode() == net.ARP_REQ )
        { if we're currently bound to an IP, and the ARP request is for
            our IP, send a reply confirming we have it }
        if ( (net.arp_target_proto_addr() == net.my_ip()) )
            { reply }
            net.start_frame()
            net.ethii_reply()
            net.wr_ethii_frame()
            net.arp_reply()
            net.send_frame()
            show_arp_msg(net.arp_opcode())

PUB parse_ethii(): msg_t
' Parse Ethernet-II frame
'    ser.str(@"[ETHII]")
    net.rd_ethii_frame()
    if ( net.ethii_ethertype() == ETYP_IPV4 )
        parse_ipv4()
    elseif ( net.ethii_ethertype() == ETYP_ARP )
        parse_arp()

PUB parse_ipv4(): msg | tcp_payld_len
' Parse IPv4 header and pass to layer 4 protocol handler
    net.rd_ip_header()
    if ( (net.ip_dest_addr() == net.my_ip()) ) 
        if ( net.ip_l4_proto() == net.TCP )
            net.rd_tcp_header()
            { get length of the payload itself (minus the IP and TCP headers) }
            tcp_payld_len := net.ip_dgram_len() - ( net.ip_hdr_len() + net.tcp_hdr_len_bytes() )
            if ( tcp_payld_len )
                net.rdblk_lsbf(@_tcp_recv, tcp_payld_len)
            _tcp_recvq := 1
            parse_tcp()

PUB parse_tcp() | sock_nr
' Parse TCP header and pass to socket management
    repeat while _tcp_recvq
        if ( _tcp_recvq )
            if ( net.tcp_flags() == net.SYN_BIT )
                { is this segment trying to establish a new connection? }
                sock_nr := socket.any_listening(net.tcp_dest_port())
                if ( sock_nr > -1 )
                    { if it is, check for a service listening on that port }
                    manage_socket(sock_nr)
                    _tcp_recvq := 0
                    next
                else
                    { not listening - refuse the connection }
                    reset_conn()
                    _tcp_recvq := 0
                    next
            else
                { look for an existing socket that matches the connection }
                sock_nr := socket.any_match(net.tcp_dest_port(), net.ip_src_addr(), net.tcp_src_port())
                if ( sock_nr => 0 )
                    manage_socket(sock_nr)
                    _tcp_recvq := 0              ' mark segment read
                else
                    { half-open or other invalid connection - reset }
                    reset_conn()
                    _tcp_recvq := 0
                    next

PUB manage_socket(sock_nr) | hdr_len, paylen_rx, new_s
' Manage the state of a socket, based on the last segment stored
'   sock_nr: socket number/index of the connection
    netstat()
    case socket.state[sock_nr]
        socket.LISTEN:
            new_s := socket.accept( net.tcp_dest_port(), net.ip_src_addr(), net.tcp_src_port(), ...
                                    net.tcp_seq_nr() + 1, socket.handler[sock_nr])
            if ( new_s > 0 )
                { bind a new socket }
                net.ethii_reply()
                net.ipv4_reply()
                net.tcp_set_dest_port(socket.remote_port[new_s])
                net.tcp_set_src_port(socket.local_port[new_s])
                net.tcp_set_chksum(0)
                net.tcp_set_seq_nr(socket.local_seq_nr[new_s])
                net.tcp_set_ack_nr(socket.remote_seq_nr[new_s])
                net.tcp_set_flags(net.SYN_BIT | net.ACK_BIT)
                net.tcp_set_hdr_len_bytes(net.TCP_HDR_SZ)
                socket.set_state(new_s, socket.SYN_RECEIVED)
                tcp_send()
                _tcp_recvq := 0
            else
                { no more sockets available - refuse connection }
                reset_conn()
                return
        socket.SYN_SENT:
        socket.SYN_RECEIVED:
            if ( net.tcp_flags() == net.ACK_BIT )
                socket.set_local_seq_nr(sock_nr, net.tcp_ack_nr())
                socket.set_state(sock_nr, socket.ESTABLISHED)
        socket.ESTABLISHED:
            if ( net.tcp_flags() & net.PSH_BIT )
                socket.set_remote_seq_nr(sock_nr, net.tcp_seq_nr())
                hdr_len := net.ip_hdr_len()+net.tcp_hdr_len_bytes()
                paylen_rx := net.ip_dgram_len()-hdr_len
                if ( paylen_rx )
                    { pass the data to the server process }
                    socket.handler[sock_nr](@_tcp_recv, paylen_rx)
                    socket.inc_remote_seq_nr(sock_nr, paylen_rx)
                net.ethii_reply()
                net.ipv4_reply()
                net.tcp_set_dest_port(socket.remote_port[sock_nr])
                net.tcp_set_src_port(socket.local_port[sock_nr])
                net.tcp_set_chksum(0)
                net.tcp_set_seq_nr(socket.local_seq_nr[sock_nr])
                net.tcp_set_ack_nr(socket.remote_seq_nr[sock_nr])
                net.tcp_set_flags(net.ACK_BIT)
                tcp_send()
            if ( net.tcp_flags() & net.FIN_BIT )
                socket.state[sock_nr] := socket.CLOSE_WAIT
        socket.FIN_WAIT_1:
        socket.FIN_WAIT_2:
        socket.CLOSE_WAIT:
            socket.inc_remote_seq_nr(sock_nr, 1)
            net.ethii_reply()
            net.ipv4_reply()
            net.tcp_set_dest_port(socket.remote_port[sock_nr])
            net.tcp_set_src_port(socket.local_port[sock_nr])
            net.tcp_set_chksum(0)
            net.tcp_set_seq_nr(socket.local_seq_nr[sock_nr])
            net.tcp_set_ack_nr(socket.remote_seq_nr[sock_nr])
            net.tcp_set_flags(net.FIN_BIT | net.ACK_BIT)
            tcp_send()
            socket.state[sock_nr] := socket.LAST_ACK
        socket.CLOSING:
        socket.LAST_ACK:
            if ( net.tcp_flags() == net.ACK_BIT )
                socket.close(sock_nr)

PUB reset_conn()
' Reset a TCP connection
    net.tcp_set_flags(net.RST_BIT | net.ACK_BIT)
    net.ethii_reply()
    net.ipv4_reply()
    net.tcp_reply(1)
    net.tcp_set_hdr_len_bytes(net.TCP_HDR_SZ)
    _tcp_recv := 0
    tcp_send()

PUB setup()

    ser.start(SER_BAUD)
    time.msleep(30)
    ser.clear()
    ser.strln(@"Serial terminal started")

    fsyn.synth("A", cfg.ENC_OSCPIN, 25_000_000)
    time.msleep(50)

    if (net.startx(CS_PIN, SCK_PIN, MOSI_PIN, MISO_PIN))
        ser.strln(string("ENC28J60 driver started"))
    else
        ser.strln(string("ENC28J60 driver failed to start - halting"))
        repeat

    _tcp_rts := -1

#include "net-util.spin"
#include "telnet_app.spin"

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

