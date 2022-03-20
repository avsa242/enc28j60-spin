{
    --------------------------------------------
    Filename: DHCP-LeaseIP-Demo.spin
    Author: Jesse Burt
    Description: Demo using the ENC28J60 driver and preliminary network
        protocol objects to lease an IP address using DHCP from a remote server
        for 2 minutes, and renew when the lease expires
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

    cfg     : "core.con.boardcfg.ybox2"
    ser     : "com.serial.terminal.ansi"
    time    : "time"
    eth     : "net.eth.enc28j60"
#ifdef YBOX2
    fsyn    : "signal.synth"
#endif
    ethii   : "protocol.net.eth-ii"
    ip      : "protocol.net.ip"
    arp     : "protocol.net.arp"
    udp     : "protocol.net.udp"
    bootp   : "protocol.net.bootp"
    math    : "math.int"
    crc     : "math.crc"

VAR

    long _tmr_stack[100], _timer_set, _dly
    long _dhcp_state
    long _my_ip
    long _xid

    { receive status vector }
    word _nxtpkt, _rxlen, _rxstatus

    word _ethii_st, _ip_st, _udp_st, _dhcp_st
    word _rxptr, _txptr, _ptr_buff, _ptr
    byte _rxbuff[RXSTOP-RXSTART], _txbuff[TXBUFFSZ]

    byte _attempt

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

PUB Main{} | rn

    setup{}
    _rxptr := _txptr := 0

    math.rndseed(cnt)
    eth.pktfilter(0)
    eth.preset_fdx{}
    eth.nodeaddress(@_mac_local) ' set and read back MAC address
    eth.getnodeaddress(@_mac_local)
    showmacaddr(@"MAC Addr: ", @_mac_local)
    ser.newline
    ser.printf1(@"Chip rev: %x\n", eth.revid{})

    ser.str(@"waiting for PHY link...")
    repeat until eth.phylinkstate{} == eth#UP
    ser.strln(@"link UP")

    bytefill(@_rxbuff, 0, RXSTOP-RXSTART)

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
                        if (processframe{} == bootp#DHCPOFFER)
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
                        if (processframe{} == bootp#DHCPACK)
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
                _my_ip := bootp.yourip{}
                ser.strln(@"---")
                ser.fgcolor(ser#GREEN)
                showipaddr(@"My IP: ", _my_ip)
                ser.fgcolor(ser#WHITE)
                ser.newline{}
                ser.printf1(@"Lease time: %dsec\n", bootp.ipleasetime{})
                ser.printf1(@"Rebind time: %dsec\n", bootp.iprebindtime{})
                ser.printf1(@"Renewal time: %dsec\n", bootp.iprenewaltime{})
                ser.strln(@"---")
                { set a timer for the lease expiry }
                _timer_set := bootp.ipleasetime{}
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

PUB Discover{} | ipchk
' Construct a DHCPDISCOVER message, and transmit it
    wordfill(@_ethii_st, 0, 4)
    setptr(@_txbuff)
    startframe{}
    _ethii_st := _txptr                         ' mark start of Eth-II data
    ethii.setdestaddr(@_mac_bcast)
    ethii.setsrcaddr(@_mac_local)
    ethii.setethertype(ETYP_IPV4)
    _txptr += ethii.wr_ethii_frame(@_txbuff[_txptr])

    _ip_st := _txptr                            ' mark start of IPV4 data
    ip.setversion(4)
    ip.setheaderlen(5)
    ip.setdscp(0)
    ip.setecn(0)
    ip.settotallen(0)
    ip.setmsgident($0001)
    ip.setflags(%010)   'XXX why?
    ip.setfragoffset(0)
    ip.settimetolive(128)
    ip.setlayer4proto(ip#UDP)
    ip.sethdrchksum($0000)
    ip.setsourceaddr($00_00_00_00)
    ip.setdestaddr($ff_ff_ff_ff)
    _txptr += ip.wr_ip_header(@_txbuff[_txptr])

    _udp_st := _txptr                           ' mark start of UDP data
    udp.setsourceport(udp#BOOTP_C)
    udp.setdestport(udp#BOOTP_S)
    _txptr += udp.wr_udp_header(@_txbuff[_txptr])

    _dhcp_st := _txptr                          ' mark start of BOOTP data
    bootp.setopcode(bootp#BOOT_REQ)
    bootp.sethdwtype(bootp#ETHERNET)
    bootp.sethdwaddrlen(MACADDR_LEN)
    bootp.sethops(0)
    bootp.settransid(_xid)
    bootp.setleasestartelapsed(1)
    bootp.setbroadcastflag(true)
    bootp.setclientip($00_00_00_00)
    bootp.setyourip($00_00_00_00)
    bootp.setserverip($00_00_00_00)
    bootp.setgatewayip($00_00_00_00)
    bootp.setclientmac(@_mac_local)
    bootp.setparamsreqd(@_dhcp_params, 5)
    bootp.setipleasetime(120)                      ' request 2min lease
    bootp.setdhcpmaxmsglen(MTU_MAX)
    _txptr += bootp.wr_dhcp_msg(@_txbuff[_txptr], bootp#DHCPDISCOVER)

    { update UDP header with length: UDP header + DHCP message }
    setptr(@_txbuff+_udp_st+udp#DGRAMLEN)
    wrword_msbf(udp.headerlen{} + bootp.setdhcpmsglen{})

    { update IP header with length: IP header + UDP header + DHCP message }
    ip.settotallen((ip.headerlen*4)+udp.headerlen{}+bootp.setdhcpmsglen{})
    ip.wr_ip_header(@_txbuff[_ip_st])
    ipchk := crc.inetchksum(@_txbuff[_ip_st], ip.headerlen{}*4)
    setptr(@_txbuff+_ip_st+ip#IPCKSUM)
    wrword_msbf(ipchk)
'    ser.hexdump(@_txbuff, 0, 4, _txptr, 16)
    ser.printf1(@"[TX: %d][IPv4][UDP][BOOTP][REQUEST][DHCPDISCOVER]\n", _txptr)
    eth.txpayload(@_txbuff, _txptr)
    sendframe{}

PUB Request{} | ipchk
' Construct a DHCPREQUEST message, and transmit it
    wordfill(@_ethii_st, 0, 4)
    setptr(@_txbuff)
    startframe{}
    _ethii_st := _txptr
    ethii.setdestaddr(@_mac_bcast)
    ethii.setsrcaddr(@_mac_local)
    ethii.setethertype(ETYP_IPV4)
    _txptr += ethii.wr_ethii_frame(@_txbuff[_txptr])

    _ip_st := _txptr
    ip.setversion(4)
    ip.setheaderlen(5)
    ip.setdscp(0)
    ip.setecn(0)
    ip.settotallen(0)
    ip.setmsgident($0001)
    ip.setflags(%010)   'XXX why?
    ip.setfragoffset(0)
    ip.settimetolive(128)
    ip.setlayer4proto(ip#UDP)
    ip.sethdrchksum($0000)
    ip.setsourceaddr($00_00_00_00)
    ip.setdestaddr($ff_ff_ff_ff)
    _txptr += ip.wr_ip_header(@_txbuff[_txptr])

    _udp_st := _txptr
    udp.setsourceport(udp#BOOTP_C)
    udp.setdestport(udp#BOOTP_S)
    udp.setlength(0)
    udp.setchecksum($0000)
    _txptr += udp.wr_udp_header(@_txbuff[_txptr])

    _dhcp_st := _txptr
    bootp.setopcode(bootp#BOOT_REQ)
    bootp.sethdwtype(bootp#ETHERNET)
    bootp.sethdwaddrlen(MACADDR_LEN)
    bootp.settransid(_xid)
    bootp.setleasestartelapsed(1)
    bootp.setbroadcastflag(true)
    bootp.setclientmac(@_mac_local)
    bootp.setparamsreqd(@_dhcp_params, 5)
    bootp.setdhcpmaxmsglen(MTU_MAX)
    bootp.setipleasetime(120)  '2min
    _txptr += bootp.wr_dhcp_msg(@_txbuff[_txptr], bootp#DHCPREQUEST)

    { update UDP header with length: UDP header + DHCP message }
    setptr(@_txbuff+_udp_st+udp#DGRAMLEN)
    wrword_msbf(udp.headerlen{} + bootp.setdhcpmsglen{})

    { update IP header with length: IP header + UDP header + DHCP message }
    ip.settotallen((ip.headerlen*4)+udp.headerlen{}+bootp.setdhcpmsglen{})
    ip.wr_ip_header(@_txbuff[_ip_st])
    ipchk := crc.inetchksum(@_txbuff[_ip_st], ip.headerlen{}*4)
    setptr(@_txbuff+_ip_st+ip#IPCKSUM)
    wrword_msbf(ipchk)

    ser.printf1(@"[TX: %d][IPv4][UDP][BOOTP][REQUEST][DHCPREQUEST]\n", _txptr)

    eth.txpayload(@_txbuff, _txptr)
    sendframe{}

PUB ARP_Reply{}
' Construct ARP reply message
    ethii.setsrcaddr(@_mac_local)
    ethii.setdestaddr(arp.senderhwaddr{})
    ethii.setethertype(ETYP_ARP)
    arp.sethwtype(arp#HRD_ETH)
    arp.setprototype(ETYP_IPV4)
    arp.sethwaddrlen(MACADDR_LEN)
    arp.setprotoaddrlen(IPV4ADDR_LEN)
    arp.setopcode(arp#ARP_REPL)
    arp.settargethwaddr(arp.senderhwaddr{})
    arp.settargetprotoaddr(arp.senderprotoaddr{})
    arp.setsenderprotoaddr(_my_ip)
    { is at }
    arp.setsenderhwaddr(@_mac_local)

    _txptr += ethii.wr_ethii_frame(@_txbuff[_txptr])
    _txptr += arp.wr_arp_msg(@_txbuff[_txptr])

    eth.txpayload(@_txbuff, _txptr)

PUB GetFrame{} | rdptr
' Receive frame from ethernet device
    { get receive status vector }
    eth.fifordptr(_nxtpkt)
    eth.rxpayload(@_nxtpkt, 6)

    ser.printf1(@"[RX: %d]", _rxlen)
    { reject oversized packets }
    if (_rxlen =< MTU_MAX)
        eth.rxpayload(@_rxbuff, _rxlen)
    else
        ser.strln(@"[OVERSIZED]")

    { ERRATA: read pointer start must be odd; subtract 1 }
    rdptr := _nxtpkt-1

    if ((rdptr < RXSTART) or (rdptr > RXSTOP))
        rdptr := RXSTOP

    eth.pktdec{}

    eth.fiforxrdptr(rdptr)

PRI ProcessArp(ptr_buff) | opcode
' Process ARP message
    arp.rd_arp_msg(ptr_buff)
    showarpmsg(opcode := arp.opcode{})
    case opcode
        arp#ARP_REQ:
            { if we're currently bound to an IP, and the ARP request is for
                our IP, send a reply confirming we have it }
            if (_dhcp_state => BOUND)
                if (arp.targetprotoaddr{} == _my_ip)
                    startframe{}
                    arp_reply{}
                    ser.printf1(@"[TX: %d]", _txptr)
                    ser.str(@"[ARP]")
                    ser.str(@"[REPLY] ")
                    showarpmsg(arp#ARP_REPL)
                    sendframe{}
        arp#ARP_REPL:

PRI ProcessFrame{} | ether_t
' Hand off the frame data to the appropriate handler
'    ser.hexdump(@_rxbuff, 0, 4, _rxlen, 16)
    _rxptr := 0
    _rxptr += ethii.rd_ethii_frame(@_rxbuff[_rxptr])

    ether_t := ethii.ethertype{}

    { ARP? }
    if (ether_t == ETYP_ARP)
        ser.str(@"[ARP]")
        processarp(@_rxbuff[_rxptr])
    { IPv4? }
    elseif (ether_t == ETYP_IPV4)
        ser.str(@"[IPv4]")
        _rxptr += ip.rd_ip_header(@_rxbuff[_rxptr])
        { UDP? }
        if (ip.layer4proto{} == ip#UDP)
            ser.str(@"[UDP]")
            _rxptr += udp.rd_udp_header(@_rxbuff[_rxptr])
            { BOOTP? }
            if (udp.destport{} == udp#BOOTP_C)
                ser.str(@"[BOOTP]")
                _rxptr += bootp.rd_bootp_msg(@_rxbuff[_rxptr])
                bootp.resetptr{}
                { BOOTP reply? }
                if (bootp.opcode{} == bootp#BOOT_REPL)
                    ser.str(@"[REPLY]")
                    if (bootp.dhcpmsgtype{} == bootp#DHCPOFFER)
                        ser.strln(@"[DHCPOFFER]")
                        return bootp#DHCPOFFER
                    if (bootp.dhcpmsgtype{} == bootp#DHCPACK)
                        ser.strln(@"[DHCPACK]")
                        return bootp#DHCPACK
                    bootp.resetptr{}
        ser.newline{}
    else
        ser.str(@"[Unknown ethertype: ")
        ser.hex(ether_t, 4)
        ser.strln(@"]")

    bytefill(@_rxbuff, 0, RXSTOP-RXSTART)

PRI SendFrame{}
{ show raw packet }
'    ser.hexdump(@_buff, 0, 4, _txptr, 16)
'    repeat
{ send packet }
    eth.fifotxstart(TXSTART)        'ETXSTL: TXSTART
    eth.fifotxend(TXSTART+_txptr)   'ETXNDL: TXSTART+_txptr
    eth.txenabled(true)             'send

    bytefill(@_txbuff, 0, 512)
    bootp.resetptr{}

PRI SetPtr(ptr_buff)
' Set pointer to following read/write operations
    _ptr_buff := ptr_buff

PRI ShowARPMsg(opcode)
' Show Wireshark-ish messages about the ARP message received
    case opcode
        arp#ARP_REQ:
            showipaddr(@"Who has ", arp.targetprotoaddr{})
            showipaddr(@"? Tell ", arp.senderprotoaddr{})
            ser.newline{}
        arp#ARP_REPL:
            showipaddr(0, arp.senderprotoaddr{})
            showmacaddr(@" is at ", arp.senderhwaddr{})
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
    _ptr := 0
    _txptr := 0
    _txbuff[_txptr++] := $00                      ' per-frame control byte

PRI WrWord_MSBF(wd) 'XXX add LSBF, byte, and long variants
' Write word to buffer, MSByte-first
    byte[_ptr_buff][_ptr] := wd.byte[1]
    byte[_ptr_buff][_ptr+1] := wd.byte[0]

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
