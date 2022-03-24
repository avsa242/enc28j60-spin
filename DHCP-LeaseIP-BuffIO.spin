{
    --------------------------------------------
    Filename: DHCP-LeaseIP-BuffIO.spin
    Author: Jesse Burt
    Description: Demo using the ENC28J60 driver and preliminary network
        protocol objects to lease an IP address using DHCP from a remote server
        for 2 minutes, and renew when the lease expires
        (utilizes buffer IO object)
    Copyright (c) 2022
    Started Feb 21, 2022
    Updated Mar 20, 2022
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
    long _xid

    { receive status vector }
    word _nxtpkt, _rxlen, _rxstatus

    word _ethii_st, _ip_st, _udp_st, _dhcp_st
    byte _buff[TXBUFFSZ]

    byte _attempt

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
    eth.nodeaddress(@_mac_local) ' set and read back MAC address
    eth.getnodeaddress(@_mac_local)
    showmacaddr(@"MAC Addr: ", @_mac_local)
    ser.newline{}
    ser.printf1(@"Chip rev: %x\n", eth.revid{})

    ser.str(@"waiting for PHY link...")
    repeat until eth.phylinkstate{} == eth#UP
    ser.strln(@"link UP")

    bytefill(@_buff, 0, MTU_MAX)

    _dly := 4
    _xid := (math.rndi($7fff_ffff) & $7fff_fff0)

    _dhcp_state := 0

    repeat
        case _dhcp_state
            INIT:
                discover{}
                _dhcp_state++
            SELECTING:
                rn := (math.rndi(2)-1)          ' add random (-1..+1) sec delay
                _timer_set := (_dly + rn) <# 64 ' start counting down
                repeat
                    if (eth.pktcnt{})           ' pkt received?
                        getframe{}
                        if (processframe{} == net#DHCPOFFER)
                            { offer received from DHCP server; request it }
                            _dhcp_state := REQUESTING
                            quit                ' got an offer; next state
                while _timer_set
                if (_dhcp_state == SELECTING)
                    { timer expired without a response; double the delay time
                        +/- 1sec, up to 64secs, until the next attempt }
                    if (_dly < 64)
                        _dly *= 2
                    _xid++
                    _dhcp_state := INIT
                    ser.strln(@"No response - retrying")
                else
                    _dly := 4                   ' reset delay time
            REQUESTING:
                request{}
                _dhcp_state++
            3:
                rn := (math.rndi(2)-1)          ' add random (-1..+1) sec delay
                _timer_set := (_dly + rn) <# 64 ' start counting down
                repeat
                    if (eth.pktcnt{})
                        getframe{}
                        if (processframe{} == net#DHCPACK)
                            { server acknowledged request; we're now bound
                                to this IP }
                            _dhcp_state := BOUND
                            quit
                while _timer_set
                if (_dhcp_state == 3)
                    if (_dly < 64)
                        _dly *= 2
                    _dhcp_state := REQUESTING
            BOUND:
                _my_ip := net.bootp_yourip{}
                ser.strln(@"---")
                ser.fgcolor(ser#GREEN)
                showipaddr(@"My IP: ", _my_ip)
                ser.fgcolor(ser#WHITE)
                ser.newline{}
                ser.printf1(@"Lease time: %dsec\n", net.dhcp_ipleasetime{})
                ser.printf1(@"Rebind time: %dsec\n", net.dhcp_iprebindtime{})
                ser.printf1(@"Renewal time: %dsec\n", net.dhcp_iprenewtime{})
                ser.strln(@"---")
                { set a timer for the lease expiry }
                _timer_set := net.dhcp_ipleasetime{}
                _dhcp_state++
            6:
                ifnot (_timer_set)
                    { when the lease timer expires, reset everything back
                        to the initial state and try to get a new lease }
                    ser.strln(@"Lease expired. Renewing IP")
                    _xid := (math.rndi($7fff_ffff) & $7fff_fff0)
                    _dhcp_state := INIT
                if (eth.pktcnt{})
                    { if any frames are received, process them; they might be
                        the server sending ARP requests confirming we're
                        bound to the IP }
                    getframe{}
                    processframe{}
                if (ser.rxcheck{} == "l")
                    { press 'l' at any time to see how much time we have left
                        on our lease }
                    ser.printf1(@"Lease time remaining: %dsec\n", _timer_set)

PUB Discover{} | ipchk, frm_end
' Construct a DHCPDISCOVER message, and transmit it
    wordfill(@_ethii_st, 0, 4)
    startframe{}
    _ethii_st := net.currptr{}                         ' mark start of Eth-II data
    net.ethii_setdestaddr(@_mac_bcast)
    net.ethii_setsrcaddr(@_mac_local)
    net.ethii_setethertype(ETYP_IPV4)
    net.wr_ethii_frame{}

    _ip_st := net.currptr{}                    ' mark start of IPV4 data
    net.ip_setversion(4)
    net.ip_sethdrlen(5)
    net.ip_setdscp(0)
    net.ip_setecn(0)
    net.ip_setdgramlen(0)
    net.ip_setmsgident($0001)
    net.ip_setflags(%010)   'XXX why?
    net.ip_setfragoffset(0)
    net.ip_setttl(128)
    net.ip_setl4proto(net#UDP)
    net.ip_sethdrchk($0000)
    net.ip_setsrcaddr($00_00_00_00)
    net.ip_setdestaddr($ff_ff_ff_ff)
    net.wr_ip_header{}

    _udp_st := net.currptr{}                   ' mark start of UDP data
    net.udp_setsrcport(svc#BOOTP_C)
    net.udp_setdestport(svc#BOOTP_S)
    net.udp_setchksum(0)
    net.wr_udp_header{}

    _dhcp_st := net.currptr{}                  ' mark start of BOOTP data
    net.bootp_setopcode(net#BOOT_REQ)
    net.bootp_sethdwtype(net#ETHERNET)
    net.bootp_sethdwaddrlen(MACADDR_LEN)
    net.bootp_sethops(0)
    net.bootp_settransid(_xid)
    net.bootp_setleaseelapsed(1)
    net.bootp_setbcastflag(true)
    net.bootp_setclientip($00_00_00_00)
    net.bootp_setyourip($00_00_00_00)
    net.bootp_setsrvip($00_00_00_00)
    net.bootp_setgwyip($00_00_00_00)
    net.bootp_setclientmac(@_mac_local)
    net.dhcp_setparamsreqd(@_dhcp_params, 5)
    net.dhcp_setipleasetime(120)                      ' request 2min lease
    net.dhcp_setmaxmsglen(MTU_MAX)
    net.dhcp_setmsgtype(net#DHCPDISCOVER)
    net.wr_dhcp_msg{}
    frm_end := net.currptr{}

    { update UDP header with length: UDP header + DHCP message }
    net.setptr(_udp_st+net#UDP_DGRAM_LEN)
    net.wrword_msbf(net.udp_hdrlen{} + net.dhcp_msglen{})
    net.setptr(frm_end)

    { update IP header with length: IP header + UDP header + DHCP message }
    net.ip_setdgramlen((net.ip_hdrlen{}*4)+net.udp_hdrlen{}+net.dhcp_msglen{})
    net.setptr(_ip_st)
    net.wr_ip_header{}
    ipchk := crc.inetchksum(@_buff[_ip_st], net.ip_hdrlen{}*4)
    net.setptr(_ip_st+net#IP_CKSUM)
    net.wrword_msbf(ipchk)
    net.setptr(frm_end)

'    ser.hexdump(@_buff, 0, 4, frm_end, 16)
    ser.printf1(@"[TX: %d][IPv4][UDP][BOOTP][REQUEST][DHCPDISCOVER]\n", frm_end)
    eth.txpayload(@_buff, frm_end)
    sendframe{}

PUB Request{} | ipchk, frm_end
' Construct a DHCPREQUEST message, and transmit it
    wordfill(@_ethii_st, 0, 4)
    startframe{}
    _ethii_st := net.currptr{}
    net.ethii_setdestaddr(@_mac_bcast)
    net.ethii_setsrcaddr(@_mac_local)
    net.ethii_setethertype(ETYP_IPV4)
    net.wr_ethii_frame{}

    _ip_st := net.currptr{}
    net.ip_setversion(4)
    net.ip_sethdrlen(5)
    net.ip_setdscp(0)
    net.ip_setecn(0)
    net.ip_setdgramlen(0)
    net.ip_setmsgident($0001)
    net.ip_setflags(%010)   'XXX why?
    net.ip_setfragoffset(0)
    net.ip_setttl(128)
    net.ip_setl4proto(net#UDP)
    net.ip_sethdrchk($0000)
    net.ip_setsrcaddr($00_00_00_00)
    net.ip_setdestaddr($ff_ff_ff_ff)
    net.wr_ip_header{}

    _udp_st := net.currptr{}
    net.udp_setsrcport(svc#BOOTP_C)
    net.udp_setdestport(svc#BOOTP_S)
    net.udp_setdgramlen(0)   'xxx
    net.udp_setchksum($0000)'xxx
    net.wr_udp_header{}

    _dhcp_st := net.currptr{}
    net.bootp_setopcode(net#BOOT_REQ)
    net.bootp_sethdwtype(net#ETHERNET)
    net.bootp_sethdwaddrlen(MACADDR_LEN)
    net.bootp_settransid(_xid)
    net.bootp_setleaseelapsed(1)
    net.bootp_setbcastflag(true)
    net.bootp_setclientmac(@_mac_local)
    net.dhcp_setparamsreqd(@_dhcp_params, 5)
    net.dhcp_setmaxmsglen(MTU_MAX)
    net.dhcp_setipleasetime(120)  '2min
    net.dhcp_setmsgtype(net#DHCPREQUEST)
    net.wr_dhcp_msg{}
    frm_end := net.currptr{}

    { update UDP header with length: UDP header + DHCP message }
    net.setptr(_udp_st+net#UDP_DGRAM_LEN)
    net.wrword_msbf(net.udp_hdrlen{} + net.dhcp_msglen{})
    net.setptr(frm_end)

    { update IP header with length: IP header + UDP header + DHCP message }
    net.ip_setdgramlen((net.ip_hdrlen{}*4)+net.udp_hdrlen{}+net.dhcp_msglen{})
    net.setptr(_ip_st)
    net.wr_ip_header{}
    ipchk := crc.inetchksum(@_buff[_ip_st], net.ip_hdrlen{}*4)
    net.setptr(_ip_st+net#IP_CKSUM)
    net.wrword_msbf(ipchk)
    net.setptr(frm_end)

'    ser.hexdump(@_buff, 0, 4, frm_end, 16)
    ser.printf1(@"[TX: %d][IPv4][UDP][BOOTP][REQUEST][DHCPREQUEST]\n", net.currptr{})
    eth.txpayload(@_buff, net.currptr{})
    sendframe{}

PUB ARP_Reply{}
' Construct ARP reply message
    net.ethii_setsrcaddr(@_mac_local)
    net.ethii_setdestaddr(net.arp_senderhwaddr{})
    net.ethii_setethertype(ETYP_ARP)
    net.arp_sethwtype(net#HRD_ETH)
    net.arp_setprototype(ETYP_IPV4)
    net.arp_sethwaddrlen(MACADDR_LEN)
    net.arp_setprotoaddrlen(IPV4ADDR_LEN)
    net.bootp_setopcode(net#ARP_REPL)
    net.arp_settargethwaddr(net.arp_senderhwaddr{})
    net.arp_settargetprotoaddr(net.arp_senderprotoaddr{})
    net.arp_setsenderprotoaddr(_my_ip)
    { is at }
    net.arp_setsenderhwaddr(@_mac_local)

    net.init(@_buff)
    net.wr_ethii_frame{}
    net.wr_arp_msg{}

    eth.txpayload(@_buff, net.currptr{})

PUB GetFrame{} | rdptr
' Receive frame from ethernet device
    { get receive status vector }
    eth.fifordptr(_nxtpkt)
    eth.rxpayload(@_nxtpkt, 6)

    ser.printf1(@"[RX: %d]", _rxlen)
    { reject oversized packets }
    if (_rxlen =< MTU_MAX)
        eth.rxpayload(@_buff, _rxlen)
    else
        ser.strln(@"[OVERSIZED]")

    { ERRATA: read pointer start must be odd; subtract 1 }
    rdptr := _nxtpkt-1

    if ((rdptr < RXSTART) or (rdptr > RXSTOP))
        rdptr := RXSTOP

    eth.pktdec{}

    eth.fiforxrdptr(rdptr)

PRI ProcessARP{} | opcode
' Process ARP message
'    ser.hexdump(@_buff+net.currptr{}, 0, 4, _rxlen, 16)
    net.rd_arp_msg{}
    showarpmsg(opcode := net.arp_opcode{})
    case opcode
        net#ARP_REQ:
            { if we're currently bound to an IP, and the ARP request is for
                our IP, send a reply confirming we have it }
            if (_dhcp_state => BOUND)
                if (net.arp_targetprotoaddr{} == _my_ip)
                    startframe{}
                    arp_reply{}
                    ser.printf1(@"[TX: %d]", net.currptr{})
                    ser.str(@"[ARP]")
                    ser.str(@"[REPLY] ")
                    ser.fgcolor(ser#YELLOW)
                    showarpmsg(net#ARP_REPL)
                    ser.fgcolor(ser#WHITE)
                    sendframe{}
        net#ARP_REPL:

PRI ProcessFrame{} | ether_t
' Hand off the frame data to the appropriate handler
'    ser.hexdump(@_buff, 0, 4, _rxlen, 16)
    net.init(@_buff)
    net.rd_ethii_frame{}
    ether_t := net.ethii_ethertype{}

    { ARP? }
    if (ether_t == ETYP_ARP)
        ser.str(@"[ARP]")
'        ser.hexdump(@_buff, 0, 4, _rxlen, 16)
        processarp{}
    { IPv4? }
    elseif (ether_t == ETYP_IPV4)
        ser.str(@"[IPv4]")
        net.rd_ip_header{}
        { UDP? }
        if (net.ip_l4proto{} == net#UDP)
            ser.str(@"[UDP]")
            net.rd_udp_header{}
            { BOOTP? }
            if (net.udp_destport{} == svc#BOOTP_C)
                ser.str(@"[BOOTP]")
                net.rd_bootp_msg{}
                { BOOTP reply? }
                if (net.bootp_opcode{} == net#BOOT_REPL)
                    ser.str(@"[REPLY]")
                    if (net.dhcp_msgtype{} == net#DHCPOFFER)
                        ser.strln(@"[DHCPOFFER]")
                        return net#DHCPOFFER
                    if (net.dhcp_msgtype{} == net#DHCPACK)
                        ser.strln(@"[DHCPACK]")
                        return net#DHCPACK
        ser.newline{}
    else
        ser.str(@"[Unknown ethertype: ")
        ser.hex(ether_t, 4)
        ser.strln(@"]")

    bytefill(@_buff, 0, MTU_MAX)

PRI SendFrame{}
{ show raw packet }
'    ser.hexdump(@_buff, 0, 4, net.currptr{}, 16)
'    repeat
{ send packet }
    eth.fifotxstart(TXSTART)        'ETXSTL: TXSTART
    eth.fifotxend(TXSTART+net.currptr{})   'ETXNDL: TXSTART+currptr
    eth.txenabled(true)             'send

    bytefill(@_buff, 0, MTU_MAX)
'    bootp.resetptr{}

PRI ShowARPMsg(opcode)
' Show Wireshark-ish messages about the ARP message received
    case opcode
        net#ARP_REQ:
            showipaddr(@"Who has ", net.arp_targetprotoaddr{})
            showipaddr(@"? Tell ", net.arp_senderprotoaddr{})
            ser.newline{}
        net#ARP_REPL:
            showipaddr(0, net.arp_senderprotoaddr{})
            showmacaddr(@" is at ", net.arp_senderhwaddr{})
            ser.newline{}

PRI ShowIPAddr(ptr_msg, addr) | i
' Display IP address, with optional preceding string (pass 0 to ignore)
    if (ptr_msg)
        ser.str(ptr_msg)
    repeat i from 0 to 3
        ser.dec(addr.byte[i])
        if (i < 3)
            ser.char(".")

PRI ShowMACAddr(ptr_msg, ptr_addr) | i
' Display MAC address, with optional preceding string (pass 0 to ignore)
    if (ptr_msg)
        ser.str(ptr_msg)
    repeat i from 0 to 5
        ser.hex(byte[ptr_addr][i], 2)
        if (i < 5)
            ser.char(":")

PRI ShowMACOUI(ptr_msg, ptr_addr) | i
' Display OUI of MAC address, with optional preceding string (pass 0 to ignore)
    if (ptr_msg)
        ser.str(ptr_msg)
    repeat i from 0 to 2
        ser.hex(byte[ptr_addr][i], 2)
        if (i > 3)
            ser.char(":")

PRI StartFrame{}
' Reset pointers, and add control byte to frame
    eth.fifowrptr(TXSTART)
    net.setptr(0)
    net.wr_byte($00)                      ' per-frame control byte

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
