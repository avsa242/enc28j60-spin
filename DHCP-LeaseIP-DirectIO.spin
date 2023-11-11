{
    --------------------------------------------
    Filename: DHCP-LeaseIP-DirectIO.spin
    Description: Demo using the ENC28J60 driver and preliminary network protocols
        * attempts to lease an IP address using DHCP from a remote server
        * requests 2 minute lease (what it gets may depend on your network)
        * renews the IP lease when it expires
        * responds to ICMP Echo requests (ping)
        * assembles frames directly on the chip
    Author: Jesse Burt
    Copyright (c) 2023
    Started Feb 21, 2022
    Updated Aug 2, 2023
    See end of file for terms of use.
    --------------------------------------------
}
#include "net-common.spinh"
#define ENC_EXT_CLK

CON

    _clkmode    = cfg#_clkmode
    _xinfreq    = cfg#_xinfreq

' -- User-defined constants
    SER_BAUD    = 115_200
    LED         = cfg#LED1

{ set ICMP echo data buffer size to accommodate a particular implementation }
{   of the 'ping' utility on the remote node }
{   can be WINDOWS_PING (32), LINUX_PING (48) or any arbitrary number }
    ICMP_DAT_LEN= LINUX_PING

' --

    { DHCP states }
    INIT        = 0
    SELECTING   = 1
    REQUESTING  = 2
    INIT_REBOOT = 3
    REBOOTING   = 4
    BOUND       = 5
    RENEWING    = 6
    REBINDING   = 7

    { _default_ data sizes for OS ping utilities }
    LINUX_PING  = 48
    WINDOWS_PING= 32

OBJ

    cfg:    "boardcfg.ybox2"
    ser:    "com.serial.terminal.ansi"
    time:   "time"
    net:    "net.eth.enc28j60" | CS=1, SCK=2, MOSI=3, MISO=4
#ifdef ENC_EXT_CLK
    fsyn:   "signal.synth"
#endif
    math:   "math.int"
    crc:    "math.crc"
    svc:    "services.spinh"
    ethii:  "protocol.net.eth-ii"
    ip:     "protocol.net.ip"
    arp:    "protocol.net.arp"
    udp:    "protocol.net.udp"
    bootp:  "protocol.net.bootp"
    icmp:   "protocol.net.icmp"

VAR

    long _tmr_stack[50], _timer_set, _dly
    long _dhcp_state

    { receive status vector }
    word _nxtpkt, _rxlen, _rxstatus

    byte _icmp_data[ICMP_DAT_LEN]

DAT

    { this node's MAC address - OUI first }
    _mac_local   byte $02, $98, $0c, $06, $01, $c9

    { DHCP parameters to request }
    _dhcp_params
        byte bootp#IP_LEASE_TM
        byte bootp#DEF_IP_TTL
        byte bootp#DNS
        byte bootp#ROUTER
        byte bootp#SUBNET_MASK

PUB main{}

    setup{}

    math.rndseed(cnt)
    net.set_pkt_filter(0)
    net.preset_fdx{}

    net.node_address(@_mac_local)

    ser.str(@"waiting for PHY link...")
    repeat until ( net.phy_link_state{} == net#UP )
    ser.strln(@"link UP")

    _dly := 4
    _dhcp_state := INIT
    bootp.reset_bootp{}
    repeat
        case _dhcp_state
            INIT:
                bootp.bootp_set_xid(math.rndi(posx) & $7fff_fff0)
                _dhcp_state++
            SELECTING:
                dhcp_msg(bootp#DHCPDISCOVER)
                repeat
                    if ( net.pkt_cnt{} )          ' pkt received?
                        get_frame{}
                        if ( process_ethii{} == bootp#DHCPOFFER )
                            { offer received from DHCP server; request it }
                            _dhcp_state := REQUESTING
                            quit                ' got an offer; next state
                while _timer_set
                if ( _dhcp_state == SELECTING )
                    { timer expired without a response; double the delay time
                        +/- 1sec, up to 64secs, until the next attempt }
                    if ( _dly < 64 )
                        _dly *= 2
                    bootp.bootp_inc_xid{}
                    ser.strln(@"No response - retrying")
                else
                    _dly := 4                   ' reset delay time
            REQUESTING:
                dhcp_msg(bootp#DHCPREQUEST)
                repeat
                    if ( net.pkt_cnt{} )
                        get_frame{}
                        if ( process_ethii{} == bootp#DHCPACK )
                            { server acknowledged request; we're now bound
                                to this IP }
                            _dhcp_state := BOUND
                            quit
                while _timer_set
                if ( _dhcp_state == REQUESTING )
                    if ( _dly < 64 )
                        _dly *= 2
            BOUND:
                if ( ip.my_ip() == 0 )
                    ip.set_my_ip32(bootp.bootp_your_ip())
                    ser.fgcolor(ser#LTGREEN)
                    show_ip_addr(@"IP: ", ip.my_ip(), 0)
                    ser.fgcolor(ser#GREY)
                    ser.newline{}
                    { set a timer for the lease expiry }
                    _timer_set := bootp.dhcp_ip_lease_time{}
                ifnot ( _timer_set )
                    { when the lease timer expires, reset everything back
                        to the initial state and try to get a new lease }
                    ip.set_my_ip32(0)
                    _dhcp_state := INIT
                if ( net.pkt_cnt{} )
                    { if any frames are received, process them; they might be
                        the server sending ARP requests confirming we're
                        bound to the IP }
                    get_frame{}
                    process_ethii{}

PUB dhcp_msg(msg_t) | tmp
' Construct a DHCP message, and transmit it
    tmp := 0

    ethii.new(@net._mac_local, @_mac_bcast, ETYP_IPV4)
    ip.new(ip#UDP, $00_00_00_00, BCAST_IP)
    udp.new(svc#BOOTP_C, svc#BOOTP_S)

    bootp.bootp_set_opcode(bootp#BOOT_REQ)
    bootp.bootp_set_bcast_flag(true)
    bootp.bootp_set_client_mac(@net._mac_local)
    bootp.dhcp_set_params_reqd(@_dhcp_params, 5)
    bootp.dhcp_set_max_msg_len(net.MTU_MAX)
    bootp.dhcp_set_ip_lease_time(120)                ' 2min
    bootp.dhcp_set_msg_type(msg_t)
    bootp.wr_dhcp_msg{}

    { update UDP header with length: UDP header + DHCP message }
    tmp := net.fifo_wr_ptr{}
    net.fifo_set_wr_ptr(udp.start_pos{}+udp#UDP_DGRAMLEN)
    net.wrword_msbf(udp.hdr_len{} + bootp.dhcp_msg_len{})
    net.fifo_set_wr_ptr(tmp)

    { update IP header with length and checksum }
    ip.update_chksum(ip.hdr_len{} + udp.hdr_len{} + bootp.dhcp_msg_len{})
    net.send_frame{}

    _timer_set := (_dly + (math.rndi(2)-1)) <# 64 ' start counting down

PUB get_frame{} | rdptr
' Receive frame from ethernet device
    { get receive status vector }
    net.fifo_set_rd_ptr(_nxtpkt)
    net.rx_payload(@_nxtpkt, 6)

    { reject oversized packets }
    ifnot (_rxlen =< net.MTU_MAX)
        ser.strln(@"[OVERSIZED]")

    { ERRATA: read pointer start must be odd; subtract 1 }
    rdptr := _nxtpkt-1

    if ((rdptr < net.RXSTART) or (rdptr > net.RXSTOP))
        rdptr := net.RXSTOP

    net.pkt_dec{}

    net.fifo_set_rx_rd_ptr(rdptr)

PUB process_arp{} | opcode
' Process ARP message
    arp.rd_arp_msg{}
    show_arp_msg(arp.opcode{})
    if (arp.opcode{} == arp#ARP_REQ)
        { if we're currently bound to an IP, and the ARP request is for
            our IP, send a reply confirming we have it }
        if ( (_dhcp_state => BOUND) and (arp.target_proto_addr{} == ip.my_ip()) )
            arp.reply{}
            show_arp_msg(arp.opcode{})

PUB process_bootp{}
' Process BOOTP/DHCP message
    bootp.rd_bootp_msg{}
    { BOOTP reply? }
    if (bootp.bootp_opcode{} == bootp#BOOT_REPL)
        if (bootp.dhcp_msg_type{} == bootp#DHCPOFFER)
            return bootp#DHCPOFFER
        if (bootp.dhcp_msg_type{} == bootp#DHCPACK)
            return bootp#DHCPACK

PUB process_ethii{}: msg_t | ether_t
' Process Ethernet-II frame
    ethii.rd_ethii_frame{}
    ether_t := ethii.ethertype{}
    { route to the processor appropriate to the ethertype }
    if (ether_t == ETYP_ARP)
    { ARP }
        process_arp{}
    elseif (ether_t == ETYP_IPV4)
    { IPv4 }
        msg_t := process_ipv4{}

PUB process_icmp{} | icmp_st, frm_end, icmp_end
' Process ICMP messages
    { if this node is bound to an IP and the echo request was directed to it, }
    {   send a reply }
    icmp.rd_icmp_msg{}
    case icmp.msg_type{}
        icmp#ECHO_REQ:
        { ECHO request (ping) }
            net.rdblk_lsbf(@_icmp_data, ICMP_DAT_LEN)     ' read in the echo data
            if ( (_dhcp_state => BOUND) and (ip.dest_addr{} == ip.my_ip()) )
                ethii.reply{}
                icmp_st := ip.reply{}-net.TXSTART-1

                icmp.set_chksum(0)
                icmp.set_msg_type(icmp#ECHO_REPL)
                icmp.set_seq_nr(icmp.seq_nr{})
                icmp.wr_icmp_msg{}

                { echo the data that was received in the ping/echo request }
                net.wrblk_lsbf(@_icmp_data, ICMP_DAT_LEN)
                frm_end := net.fifo_wr_ptr{}

                ip.update_chksum(ip.hdr_len{} + icmp.msg_len{} + ICMP_DAT_LEN)

                icmp_end := net.fifo_wr_ptr{}-net.TXSTART
                { update ICMP checksum }
                net.inet_chksum(icmp_st, icmp_end, icmp_st+icmp#ICMP_CKSUM)
                net.fifo_set_wr_ptr(frm_end)

                net.send_frame{}
                ser.fgcolor(ser#GREEN)
                ser.strln(@"PING!")
                ser.fgcolor(ser#GREY)

PUB process_ipv4{}: msg
' Process IPv4 datagrams
    ip.rd_ip_header{}
    case ip.l4_proto{}
        { UDP? }
        ip#UDP:
            udp.rd_udp_header{}
            { BOOTP? }
            if (udp.dest_port{} == svc#BOOTP_C)
                msg := process_bootp{}
        ip#TCP:
#ifdef TCP_TEL
            process_tcp{}
#endif
        ip#ICMP:
            process_icmp{}

PUB show_arp_msg(opcode)
' Show Wireshark-ish messages about the ARP message received
    case opcode
        arp#ARP_REQ:
            show_ip_addr(@"[Who has ", arp.target_proto_addr{}, @"? Tell ")
            show_ip_addr(0, arp.sender_proto_addr{}, string("]", 10, 13))
        arp#ARP_REPL:
            show_ip_addr(@"[", arp.sender_proto_addr{}, @" is at ")
            show_mac_addr(0, arp.sender_hw_addr{}, string("]", 10, 13))

PUB show_ip_addr(ptr_premsg, addr, ptr_postmsg) | i
' Display IP address, with optional prefixed/postfixed strings (pass 0 to ignore)
    if (ptr_premsg)
        ser.str(ptr_premsg)
    repeat i from 0 to 3
        ser.dec(addr.byte[i])
        if (i < 3)
            ser.char(".")
    if (ptr_postmsg)
        ser.str(ptr_postmsg)

PUB show_mac_addr(ptr_premsg, ptr_addr, ptr_postmsg) | i
' Display MAC address, with optional prefixed/postfixed strings (pass 0 to ignore)
    if (ptr_premsg)
        ser.str(ptr_premsg)
    repeat i from 0 to 5
        ser.hexs(byte[ptr_addr][i], 2)
        if (i < 5)
            ser.char(":")
    if (ptr_postmsg)
        ser.str(ptr_postmsg)

PUB show_mac_oui(ptr_premsg, ptr_addr, ptr_postmsg) | i
' Display OUI of MAC address, with optional prefixed/postfixed strings (pass 0 to ignore)
    if (ptr_premsg)
        ser.str(ptr_premsg)
    repeat i from 0 to 2
        ser.hexs(byte[ptr_addr][i], 2)
        if (i < 2)
            ser.char(":")
    if (ptr_postmsg)
        ser.str(ptr_postmsg)

PRI cog_timer{}

    repeat
        repeat until _timer_set                 ' wait for a timer to be set
        repeat                                  ' wait 1s each loop
            time.sleep(1)
        while --_timer_set                      ' until timer expired

PUB setup{}

    ser.start(SER_BAUD)
    time.msleep(30)
    ser.clear{}
    ser.strln(@"Serial terminal started")

    cognew(cog_timer{}, @_tmr_stack)
#ifdef ENC_EXT_CLK
    { for boards that don't supply an external clock for the ENC28J60:
        feed the ENC28J60 a 25MHz clock, and give it time to lock onto it }
    fsyn.synth("A", cfg#ENC_OSCPIN, 25_000_000)
    time.msleep(50)
#endif
    if (net.start())
        ser.strln(string("ENC28J60 driver started"))
    else
        ser.strln(string("ENC28J60 driver failed to start - halting"))
        repeat

    { set up protocols - point them to the network device object }
    ethii.init(@net)
    ip.init(@net)
    arp.init(@net, @ethii)
    udp.init(@net)
    bootp.init(@net)
    icmp.init(@net)

 
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

