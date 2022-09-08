{
    --------------------------------------------
    Filename: DHCP-LeaseIP-BuffIO.spin
    Author: Jesse Burt
    Description: Demo using the ENC28J60 driver and preliminary network
        protocols
        * attempts to lease an IP address using DHCP from a remote server
        * requests 2 minute lease (what it gets may depend on your network)
        * renews the IP lease when it expires
        * responds to ICMP Echo requests (ping)
        * uses buffered I/O (assembles frames on the Propeller, then sends to
            ethernet controller)
    Copyright (c) 2022
    Started Feb 21, 2022
    Updated Apr 19, 2022
    See end of file for terms of use.
    --------------------------------------------
}
#include "net-common.spinh"

CON

    _clkmode    = cfg#_clkmode
    _xinfreq    = cfg#_xinfreq

' -- User-defined constants
    SER_BAUD    = 115_200
    LED         = cfg#LED1

{ SPI configuration }
    CS_PIN      = 1
    SCK_PIN     = 2
    MOSI_PIN    = 3
    MISO_PIN    = 4

{ set ICMP echo data buffer size to accommodate a particular implementation }
{   of the 'ping' utility on the remote node }
{   can be WINDOWS_PING (32), LINUX_PING (48) or any arbitrary number }
    ICMP_DAT_LEN= LINUX_PING

' --

    { ENC28J60 FIFO }
    MTU_MAX     = 1518
    TXBUFFSZ    = MTU_MAX
    RXSTART     = 0
    RXSTOP      = (TXSTART - 2) | 1
    TXSTART     = 8192 - (TXBUFFSZ + 8)
    TXEND       = TXSTART + (TXBUFFSZ + 8)

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

    cfg : "core.con.boardcfg.ybox2"
    ser : "com.serial.terminal.ansi"
    time: "time"
    eth : "net.eth.enc28j60"
#ifdef YBOX2
    fsyn: "signal.synth"
#endif
    net : "net.buffer-io"
    math: "math.int"
    crc : "math.crc"
    svc : "services.spinh"

VAR

    long _tmr_stack[50], _timer_set, _dly
    long _dhcp_state
    long _my_ip

    { receive status vector }
    word _nxtpkt, _rxlen, _rxstatus

    word _ip_st, _udp_st

    byte _buff[TXBUFFSZ], _icmp_data[ICMP_DAT_LEN]

DAT

    { this node's MAC address - OUI first }
    _mac_local   byte $02, $98, $0c, $06, $01, $c9

    { DHCP parameters to request }
    _dhcp_params
        byte net#IP_LEASE_TM
        byte net#DEF_IP_TTL
        byte net#DNS
        byte net#ROUTER
        byte net#SUBNET_MASK

PUB Main{} | rn

    setup{}
    net.init(@_buff)

    math.rndseed(cnt)
    eth.pktfilter(0)
    eth.preset_fdx{}

    eth.nodeaddress(@_mac_local)
    ser.printf1(@"Chip rev: %x\n", eth.revid{})

    ser.str(@"waiting for PHY link...")
    repeat until eth.phylinkstate{} == eth#UP
    ser.strln(@"link UP")

    bytefill(@_buff, 0, MTU_MAX)

    _dly := 4
    _dhcp_state := INIT
    net.reset_bootp{}
    net.bootp_setxid(math.rndi(posx) & $7fff_fff0)
    repeat
        case _dhcp_state
            INIT:
                net.bootp_setxid(math.rndi(posx) & $7fff_fff0)
                _dhcp_state++
            SELECTING:
                dhcp_msg(net#DHCPDISCOVER)
                rn := (math.rndi(2)-1)          ' add random (-1..+1) sec delay
                _timer_set := (_dly + rn) <# 64 ' start counting down
                repeat
                    if (eth.pktcnt{})           ' pkt received?
                        getframe{}
                        if (process_ethii{} == net#DHCPOFFER)
                            { offer received from DHCP server; request it }
                            _dhcp_state := REQUESTING
                            quit                ' got an offer; next state
                while _timer_set
                if (_dhcp_state == SELECTING)
                    { timer expired without a response; double the delay time
                        +/- 1sec, up to 64secs, until the next attempt }
                    if (_dly < 64)
                        _dly *= 2
                    net.bootp_inc_xid{}
                else
                    _dly := 4                   ' reset delay time
            REQUESTING:
                dhcp_msg(net#DHCPREQUEST)
                rn := (math.rndi(2)-1)          ' add random (-1..+1) sec delay
                _timer_set := (_dly + rn) <# 64 ' start counting down
                repeat
                    if (eth.pktcnt{})
                        getframe{}
                        if (process_ethii{} == net#DHCPACK)
                            { server acknowledged request; we're now bound
                                to this IP }
                            _dhcp_state := BOUND
                            quit
                while _timer_set
                if (_dhcp_state == REQUESTING)
                    if (_dly < 64)
                        _dly *= 2
            BOUND:
                if (_my_ip == 0)
                    _my_ip := net.bootp_yourip{}
                    ser.fgcolor(ser#LTGREEN)
                    showipaddr(@"IP: ", _my_ip, 0)
                    ser.fgcolor(ser#GREY)
                    ser.newline{}
                    { set a timer for the lease expiry }
                    _timer_set := net.dhcp_ipleasetime{}
                ifnot (_timer_set)
                    { when the lease timer expires, reset everything back
                        to the initial state and try to get a new lease }
                    _my_ip := 0
                    _dhcp_state := INIT
                if (eth.pktcnt{})
                    { if any frames are received, process them; they might be
                        the server sending ARP requests confirming we're
                        bound to the IP }
                    getframe{}
                    process_ethii{}

PUB ARP_Reply{}
' Construct ARP reply message
    startframe{}
    ethii_reply{}
    { change only the settings that differ from the request }
    net.arp_setopcode(net#ARP_REPL)
    net.arp_settargethwaddr(net.arp_senderhwaddr{})
    net.arp_settargetprotoaddr(net.arp_senderprotoaddr{})
    net.arp_setsenderprotoaddr(_my_ip)
    { /\- is at -\/ }
    net.arp_setsenderhwaddr(@_mac_local)

    net.wr_arp_msg{}
    eth.txpayload(@_buff, net.fifowrptr(-2))
    sendframe{}

PUB DHCP_Msg(msg_t) | tmp
' Construct a DHCP message, and transmit it
    tmp := 0
    net.reset_ipv4{}

    startframe{}
    ethii_new(@_mac_local, @_mac_bcast, ETYP_IPV4)
    ipv4_new(net#UDP, $00_00_00_00, BCAST_IP)
    udp_new(svc#BOOTP_C, svc#BOOTP_S)

    net.bootp_setopcode(net#BOOT_REQ)
    net.bootp_setbcastflag(true)
    net.bootp_setclientmac(@_mac_local)
    net.dhcp_setparamsreqd(@_dhcp_params, 5)
    net.dhcp_setmaxmsglen(MTU_MAX)
    net.dhcp_setipleasetime(120)  '2min
    net.dhcp_setmsgtype(msg_t)
    net.wr_dhcp_msg{}

    { update UDP header with length: UDP header + DHCP message }
    tmp := net.fifowrptr(-2)
    net.setptr(_udp_st+net#UDP_DGRAM_LEN)
    net.wrword_msbf(net.udp_hdrlen{} + net.dhcp_msglen{})
    net.setptr(tmp)

    ipv4_updchksum(net.ip_hdrlen{} + net.udp_hdrlen{} + net.dhcp_msglen{})

    eth.txpayload(@_buff, net.fifowrptr(-2))
    sendframe{}

PUB EthII_New(mac_src, mac_dest, ether_t)
' Start new ethernet-II frame
    net.ethii_setdestaddr(mac_dest)
    net.ethii_setsrcaddr(mac_src)
    net.ethii_setethertype(ether_t)
    net.wr_ethii_frame{}

PUB EthII_Reply{}: pos
' Set up/write Ethernet II frame as a reply to last received frame
    net.ethii_setdestaddr(net.ethii_srcaddr{})
    net.ethii_setsrcaddr(@_mac_local)
    net.wr_ethii_frame{}
    return net.fifowrptr(-2)

PUB GetFrame{} | rdptr
' Receive frame from ethernet device
    { get receive status vector }
    eth.fifordptr(_nxtpkt)
    eth.rxpayload(@_nxtpkt, 6)

    { reject oversized packets }
    if (_rxlen =< MTU_MAX)
        eth.rxpayload(@_buff, _rxlen)

    { ERRATA: read pointer start must be odd; subtract 1 }
    rdptr := _nxtpkt-1

    if ((rdptr < RXSTART) or (rdptr > RXSTOP))
        rdptr := RXSTOP

    eth.pktdec{}

    eth.fiforxrdptr(rdptr)

PUB IPV4_New(l4_proto, src_ip, dest_ip)
' Construct an IPV4 header
'   l4_proto: OSI Layer-4 protocol (TCP, UDP, *ICMP)
    _ip_st := net.fifowrptr(-2)                     ' mark start of IPV4 data
    net.ip_setl4proto(l4_proto)
    net.ip_setsrcaddr(src_ip)
    net.ip_setdestaddr(dest_ip)
    net.wr_ip_header{}

PUB IPV4_Reply{}: pos
' Set up/write IPv4 header as a reply to last received header
    net.ip_sethdrchk(0)                         ' init header checksum to 0
    ipv4_new(net.ip_l4proto{}, _my_ip, net.ip_srcaddr{})
    return net.fifowrptr(-2)

PUB ipv4_updchksum(length) | ipchk, ptr_tmp
' Update IP header with checksum
    ptr_tmp := net.fifowrptr(-2)                    ' cache current pointer

    { update IP header with specified length and calculate checksum }
    net.ip_setdgramlen(length)
    net.setptr(_ip_st)
    net.wr_ip_header{}
    ipchk := crc.inetchksum(@_buff[_ip_st], net.ip_hdrlen{}, $00)
    net.setptr(_ip_st+net#IP_CKSUM)
    net.wrword_msbf(ipchk)

    net.setptr(ptr_tmp)                         ' restore pointer pos

PUB Process_ARP{} | opcode
' Process ARP message
    net.rd_arp_msg{}
    if (net.arp_opcode{} == net#ARP_REQ)
        { if we're currently bound to an IP, and the ARP request is for
            our IP, send a reply confirming we have it }
        if ( (_dhcp_state => BOUND) and (net.arp_targetprotoaddr{} == _my_ip) )
            arp_reply{}

PUB Process_BOOTP{}
' Process BOOTP/DHCP message
    net.rd_bootp_msg{}
    { BOOTP reply? }
    if (net.bootp_opcode{} == net#BOOT_REPL)
        if (net.dhcp_msgtype{} == net#DHCPOFFER)
            return net#DHCPOFFER
        if (net.dhcp_msgtype{} == net#DHCPACK)
            return net#DHCPACK

PUB Process_EthII{}: msg_t | ether_t
' Process Ethernet-II frame
    net.init(@_buff)
    net.rd_ethii_frame{}
    ether_t := net.ethii_ethertype{}
    { route to the processor appropriate to the ethertype }
    if (ether_t == ETYP_ARP)
    { ARP }
        process_arp{}
    elseif (ether_t == ETYP_IPV4)
    { IPv4 }
        msg_t := process_ipv4{}

PUB Process_ICMP{} | icmp_st, frm_end, ipchk, icmpchk
' Process ICMP messages
    { if this node is bound to an IP and the echo request was directed to it, }
    {   send a reply }
    net.rd_icmp_msg{}
    case net.icmp_msgtype{}
        net#ECHO_REQ:
        { ECHO request (ping) }
            net.rdblk_lsbf(@_icmp_data, ICMP_DAT_LEN)     ' read in the echo data
            if ( (_dhcp_state => BOUND) and (net.ip_destaddr{} == _my_ip) )
                startframe{}
                ethii_reply{}
                icmp_st := ipv4_reply{}

                net.icmp_setchksum(0)
                net.icmp_setmsgtype(net#ECHO_REPL)
                net.icmp_setseqnr(net.icmp_seqnr{})
                net.wr_icmp_msg{}

                { write the echo data that was received in the request }
                net.wrblk_lsbf(@_icmp_data, ICMP_DAT_LEN)
                frm_end := net.fifowrptr(-2)

                ipv4_updchksum(net.ip_hdrlen{} + net.icmp_msglen{} + ICMP_DAT_LEN)

                icmpchk := crc.inetchksum(@_buff[icmp_st], net.icmp_msglen{} + ICMP_DAT_LEN, $00)
                net.setptr(icmp_st+net#ICMP_CKSUM)
                net.wrword_msbf(icmpchk)
                net.setptr(frm_end)

                eth.txpayload(@_buff, net.fifowrptr(-2))
                sendframe{}

PUB Process_IPV4{}: msg
' Process IPv4 datagrams
    net.rd_ip_header{}
    case net.ip_l4proto{}
        { UDP? }
        net#UDP:
            net.rd_udp_header{}
            { BOOTP? }
            if (net.udp_destport{} == svc#BOOTP_C)
                msg := process_bootp{}
        net#TCP:
#ifdef TCP_TEL
            process_tcp{}
#endif
        net#ICMP:
            process_icmp{}

PUB SendFrame{}
' Send queued ethernet frame
    { set TX FIFO parameters to point to assembled ethernet frame }
    eth.fifotxstart(TXSTART)                    ' ETXSTL: TXSTART
    eth.fifotxend(TXSTART+net.fifowrptr(-2))        ' ETXNDL: TXSTART+currptr
    eth.txenabled(true)                         ' send

PUB ShowARPMsg(opcode)
' Show Wireshark-ish messages about the ARP message received
    case opcode
        net#ARP_REQ:
            showipaddr(@"[Who has ", net.arp_targetprotoaddr{}, @"? Tell ")
            showipaddr(0, net.arp_senderprotoaddr{}, string("]", 10, 13))
        net#ARP_REPL:
            showipaddr(@"[", net.arp_senderprotoaddr{}, @" is at ")
            showmacaddr(0, net.arp_senderhwaddr{}, string("]", 10, 13))

PUB ShowIPAddr(ptr_premsg, addr, ptr_postmsg) | i
' Display IP address, with optional prefixed/postfixed strings (pass 0 to ignore)
    if (ptr_premsg)
        ser.str(ptr_premsg)
    repeat i from 0 to 3
        ser.dec(addr.byte[i])
        if (i < 3)
            ser.char(".")
    if (ptr_postmsg)
        ser.str(ptr_postmsg)

PUB ShowMACAddr(ptr_premsg, ptr_addr, ptr_postmsg) | i
' Display MAC address, with optional preceding string (pass 0 to ignore)
    if (ptr_premsg)
        ser.str(ptr_premsg)
    repeat i from 0 to 5
        ser.hex(byte[ptr_addr][i], 2)
        if (i < 5)
            ser.char(":")
    if (ptr_postmsg)
        ser.str(ptr_postmsg)

PUB ShowMACOUI(ptr_premsg, ptr_addr, ptr_postmsg) | i
' Display OUI of MAC address, with optional preceding string (pass 0 to ignore)
    if (ptr_premsg)
        ser.str(ptr_premsg)
    repeat i from 0 to 2
        ser.hex(byte[ptr_addr][i], 2)
        if (i < 2)
            ser.char(":")
    if (ptr_postmsg)
        ser.str(ptr_postmsg)

PUB StartFrame{}: pos
' Reset pointers, and add control byte to frame
    bytefill(@_buff, 0, MTU_MAX)                ' clear frame buffer
    eth.fifowrptr(TXSTART)
    net.setptr(0)
    net.wr_byte($00)                            ' per-frame control byte
    return net.fifowrptr(-2)

PUB UDP_New(src_p, dest_p)
' Construct a UDP header
    _udp_st := net.fifowrptr(-2)
    net.reset_udp{}
    net.udp_setsrcport(src_p)
    net.udp_setdestport(dest_p)
    net.wr_udp_header{}

PRI cog_Timer{}

    repeat
        repeat until _timer_set                 ' wait for a timer to be set
        repeat                                  ' wait 1s each loop
            time.sleep(1)
        while --_timer_set                      ' until timer expired

PUB Setup{}

    ser.start(SER_BAUD)
    time.msleep(30)
    ser.clear{}
    ser.strln(@"Serial terminal started")

    cognew(cog_timer{}, @_tmr_stack)
#ifdef YBOX2
    { YBOX2: feed the ENC28J60 a 25MHz clock, and give it time to lock onto it }
    fsyn.synth("A", cfg#ENC_OSCPIN, 25_000_000)
    time.msleep(50)
#endif
    if (eth.startx(CS_PIN, SCK_PIN, MOSI_PIN, MISO_PIN))
        ser.strln(string("ENC28J60 driver started"))
    else
        ser.strln(string("ENC28J60 driver failed to start - halting"))

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

