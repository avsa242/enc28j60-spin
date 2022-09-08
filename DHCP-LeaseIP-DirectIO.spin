{
    --------------------------------------------
    Filename: DHCP-LeaseIP-DirectIO.spin
    Author: Jesse Burt
    Description: Demo using the ENC28J60 driver and preliminary network
        protocol objects to lease an IP address using DHCP from a remote server
        for 2 minutes, and renew when the lease expires
        (utilizes ENC28J60 native FIFO I/O)
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

    byte _attempt

DAT

    { this node's MAC address - OUI first }
    _mac_local   byte $02, $98, $0c, $06, $01, $c9

    { DHCP parameters to request }
    _dhcp_params
        byte eth#IP_LEASE_TM
        byte eth#DEF_IP_TTL
        byte eth#DNS
        byte eth#ROUTER
        byte eth#SUBNET_MASK

PUB Main{} | rn

    setup{}
'    eth.init(@_buff)

    math.rndseed(cnt)
    eth.pktfilter(0)
    eth.preset_fdx{}
    eth.nodeaddress(@_mac_local) ' set and read back MAC address
    eth.getnodeaddress(@_mac_local)
    showmacaddr(@"MAC Addr: ", @_mac_local)
    ser.newline{}
    ser.printf1(@"Chip rev: %x\n\r", eth.revid{})

    ser.str(@"waiting for PHY link...")
    repeat until eth.phylinkstate{} == eth#UP
    ser.strln(@"link UP")

'    bytefill(@_buff, 0, MTU_MAX)

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
                        if (processframe{} == eth#DHCPOFFER)
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
                        if (processframe{} == eth#DHCPACK)
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
                _my_ip := eth.bootp_yourip{}
                ser.strln(@"---")
                ser.fgcolor(ser#GREEN)
                showipaddr(@"My IP: ", _my_ip)
                ser.fgcolor(ser#WHITE)
                ser.newline{}
                ser.printf1(@"Lease time: %dsec\n\r", eth.dhcp_ipleasetime{})
                ser.printf1(@"Rebind time: %dsec\n\r", eth.dhcp_iprebindtime{})
                ser.printf1(@"Renewal time: %dsec\n\r", eth.dhcp_iprenewtime{})
                ser.strln(@"---")
                { set a timer for the lease expiry }
                _timer_set := eth.dhcp_ipleasetime{}
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
                    ser.printf1(@"Lease time remaining: %dsec\n\r", _timer_set)

PUB Discover{} | ipchk, frm_end
' Construct a DHCPDISCOVER message, and transmit it
    wordfill(@_ethii_st, 0, 4)
    startframe{}
    _ethii_st := eth.currptr{}                         ' mark start of Eth-II data
'    ser.printf1(@"Discover(): currptr() = %d\n\r", _ethii_st)
    eth.ethii_setdestaddr(@_mac_bcast)
    eth.ethii_setsrcaddr(@_mac_local)
    eth.ethii_setethertype(ETYP_IPV4)
    eth.wr_ethii_frame{}

    _ip_st := eth.currptr{}                    ' mark start of IPV4 data
'    ser.printf1(@"Discover(): _ip_st = %d\n\r", _ip_st)
    eth.ip_setversion(4)
    eth.ip_sethdrlen(20)
    eth.ip_setdscp(0)
    eth.ip_setecn(0)
    eth.ip_setdgramlen(0)
    eth.ip_setmsgident($0001)
    eth.ip_setflags(%010)   'XXX why?
    eth.ip_setfragoffset(0)
    eth.ip_setttl(128)
    eth.ip_setl4proto(eth#UDP)
    eth.ip_sethdrchk($0000)
    eth.ip_setsrcaddr($00_00_00_00)
    eth.ip_setdestaddr($ff_ff_ff_ff)
    eth.wr_ip_header{}

    _udp_st := eth.currptr{}                   ' mark start of UDP data
'    ser.printf1(@"Discover(): _udp_st = %d\n\r", _udp_st)
    eth.udp_setsrcport(svc#BOOTP_C)
    eth.udp_setdestport(svc#BOOTP_S)
    eth.udp_setchksum(0)
    eth.wr_udp_header{}

    _dhcp_st := eth.currptr{}                  ' mark start of BOOTP data
'    ser.printf1(@"Discover(): _dhcp_st = %d\n\r", _dhcp_st)
    eth.bootp_setopcode(eth#BOOT_REQ)
    eth.bootp_sethdwtype(eth#ETHERNET)
    eth.bootp_sethdwaddrlen(MACADDR_LEN)
    eth.bootp_sethops(0)
    eth.bootp_setxid(_xid)
    eth.bootp_setleaseelapsed(1)
    eth.bootp_setbcastflag(true)
    eth.bootp_setclientip($00_00_00_00)
    eth.bootp_setyourip($00_00_00_00)
    eth.bootp_setsrvip($00_00_00_00)
    eth.bootp_setgwyip($00_00_00_00)
    eth.bootp_setclientmac(@_mac_local)
    eth.dhcp_setparamsreqd(@_dhcp_params, 5)
    eth.dhcp_setipleasetime(120)                      ' request 2min lease
    eth.dhcp_setmaxmsglen(MTU_MAX)
    eth.dhcp_setmsgtype(eth#DHCPDISCOVER)
    eth.wr_dhcp_msg{}
    frm_end := eth.currptr{}
'    ser.printf2(@"Discover(): frm_end() = %d (len = %d)\n\r", frm_end, frm_end-TXSTART)
    hexdump
{
    { update UDP header with length: UDP header + DHCP message }
    eth.setptr(_udp_st+eth#UDP_DGRAM_LEN)
    eth.wrword_msbf(eth.udp_hdrlen{} + eth.dhcp_msglen{})
    eth.setptr(frm_end)

    { update IP header with length: IP header + UDP header + DHCP message }
    eth.ip_setdgramlen((eth.ip_hdrlen{}*4)+eth.udp_hdrlen{}+eth.dhcp_msglen{})
    eth.setptr(_ip_st)
    eth.wr_ip_header{}
'XXX    ipchk := crc.inetchksum(@_buff[_ip_st], eth.ip_hdrlen{}*4)
    eth.setptr(_ip_st+eth#IP_CKSUM)
    eth.wrword_msbf(ipchk)
    eth.setptr(frm_end)
}
'    ser.hexdump(@_buff, 0, 4, frm_end, 16)
    ser.printf1(@"[TX: %d][IPv4][UDP][BOOTP][REQUEST][DHCPDISCOVER]\n\r", frm_end-TXSTART)
'    eth.txpayload(@_buff, frm_end)
    sendframe{}

pub hexdump | rdptr, curr_byte, len, col

    rdptr := eth.fifowrptr(-2)
    ser.printf1(@"hexdump() start: rdptr = %d\n\r", rdptr)

    eth.fifordptr(eth.fifotxstart(-2))
    len := rdptr-TXSTART
    col := 0
    repeat len
        ser.hexs(eth.rd_byte, 2)
        ser.char(" ")
        col++
        if (col > 15)
            col := 0
            ser.newline
    ser.printf1(@"hexdump() end: rdptr = %d\n\r", rdptr)

PUB Request{} | ipchk, frm_end
' Construct a DHCPREQUEST message, and transmit it
    wordfill(@_ethii_st, 0, 4)
    startframe{}
    _ethii_st := eth.currptr{}
    eth.ethii_setdestaddr(@_mac_bcast)
    eth.ethii_setsrcaddr(@_mac_local)
    eth.ethii_setethertype(ETYP_IPV4)
    eth.wr_ethii_frame{}

    _ip_st := eth.currptr{}
    eth.ip_setversion(4)
    eth.ip_sethdrlen(20)
    eth.ip_setdscp(0)
    eth.ip_setecn(0)
    eth.ip_setdgramlen(0)
    eth.ip_setmsgident($0001)
    eth.ip_setflags(%010)   'XXX why?
    eth.ip_setfragoffset(0)
    eth.ip_setttl(128)
    eth.ip_setl4proto(eth#UDP)
    eth.ip_sethdrchk($0000)
    eth.ip_setsrcaddr($00_00_00_00)
    eth.ip_setdestaddr($ff_ff_ff_ff)
    eth.wr_ip_header{}

    _udp_st := eth.currptr{}
    eth.udp_setsrcport(svc#BOOTP_C)
    eth.udp_setdestport(svc#BOOTP_S)
    eth.udp_setdgramlen(0)   'xxx
    eth.udp_setchksum($0000)'xxx
    eth.wr_udp_header{}

    _dhcp_st := eth.currptr{}
    eth.bootp_setopcode(eth#BOOT_REQ)
    eth.bootp_sethdwtype(eth#ETHERNET)
    eth.bootp_sethdwaddrlen(MACADDR_LEN)
    eth.bootp_setxid(_xid)
    eth.bootp_setleaseelapsed(1)
    eth.bootp_setbcastflag(true)
    eth.bootp_setclientmac(@_mac_local)
    eth.dhcp_setparamsreqd(@_dhcp_params, 5)
    eth.dhcp_setmaxmsglen(MTU_MAX)
    eth.dhcp_setipleasetime(120)  '2min
    eth.dhcp_setmsgtype(eth#DHCPREQUEST)
    eth.wr_dhcp_msg{}
    frm_end := eth.currptr{}

    { update UDP header with length: UDP header + DHCP message }
    eth.setptr(_udp_st+eth#UDP_DGRAM_LEN)
    eth.wrword_msbf(eth.udp_hdrlen{} + eth.dhcp_msglen{})
    eth.setptr(frm_end)

    { update IP header with length: IP header + UDP header + DHCP message }
    eth.ip_setdgramlen((eth.ip_hdrlen{}*4)+eth.udp_hdrlen{}+eth.dhcp_msglen{})
    eth.setptr(_ip_st)
    eth.wr_ip_header{}
' XXX    ipchk := crc.inetchksum(@_buff[_ip_st], eth.ip_hdrlen{}*4)
    eth.setptr(_ip_st+eth#IP_CKSUM)
    eth.wrword_msbf(ipchk)
    eth.setptr(frm_end)

'    ser.hexdump(@_buff, 0, 4, frm_end, 16)
    ser.printf1(@"[TX: %d][IPv4][UDP][BOOTP][REQUEST][DHCPREQUEST]\n\r", eth.currptr{})
'    eth.txpayload(@_buff, eth.currptr{})
    sendframe{}

PUB ARP_Reply{}
' Construct ARP reply message
    eth.ethii_setsrcaddr(@_mac_local)
    eth.ethii_setdestaddr(eth.arp_senderhwaddr{})
    eth.ethii_setethertype(ETYP_ARP)
    eth.arp_sethwtype(eth#HRD_ETH)
    eth.arp_setprototype(ETYP_IPV4)
    eth.arp_sethwaddrlen(MACADDR_LEN)
    eth.arp_setprotoaddrlen(IPV4ADDR_LEN)
    eth.bootp_setopcode(eth#ARP_REPL)
    eth.arp_settargethwaddr(eth.arp_senderhwaddr{})
    eth.arp_settargetprotoaddr(eth.arp_senderprotoaddr{})
    eth.arp_setsenderprotoaddr(_my_ip)
    { is at }
    eth.arp_setsenderhwaddr(@_mac_local)

'    eth.init(@_buff)
    eth.wr_ethii_frame{}
    eth.wr_arp_msg{}

'    eth.txpayload(@_buff, eth.currptr{})

PUB GetFrame{} | rdptr
' Receive frame from ethernet device
    { get receive status vector }
    eth.fifordptr(_nxtpkt)
    eth.rxpayload(@_nxtpkt, 6)

    ser.printf1(@"[RX: %d]", _rxlen)
    { reject oversized packets }
    if (_rxlen =< MTU_MAX)
' XXX        eth.rxpayload(@_buff, _rxlen)
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
'    ser.hexdump(@_buff+eth.currptr{}, 0, 4, _rxlen, 16)
    eth.rd_arp_msg{}
    showarpmsg(opcode := eth.arp_opcode{})
    case opcode
        eth#ARP_REQ:
            { if we're currently bound to an IP, and the ARP request is for
                our IP, send a reply confirming we have it }
            if (_dhcp_state => BOUND)
                if (eth.arp_targetprotoaddr{} == _my_ip)
                    startframe{}
                    arp_reply{}
                    ser.printf1(@"[TX: %d]", eth.currptr{})
                    ser.str(@"[ARP]")
                    ser.str(@"[REPLY] ")
                    ser.fgcolor(ser#YELLOW)
                    showarpmsg(eth#ARP_REPL)
                    ser.fgcolor(ser#WHITE)
                    sendframe{}
        eth#ARP_REPL:

PRI ProcessFrame{} | ether_t
' Hand off the frame data to the appropriate handler
'    ser.hexdump(@_buff, 0, 4, _rxlen, 16)
'    eth.init(@_buff)
    eth.rd_ethii_frame{}
    ether_t := eth.ethii_ethertype{}

    { ARP? }
    if (ether_t == ETYP_ARP)
        ser.str(@"[ARP]")
'        ser.hexdump(@_buff, 0, 4, _rxlen, 16)
        processarp{}
    { IPv4? }
    elseif (ether_t == ETYP_IPV4)
        ser.str(@"[IPv4]")
        eth.rd_ip_header{}
        { UDP? }
        if (eth.ip_l4proto{} == eth#UDP)
            ser.str(@"[UDP]")
            eth.rd_udp_header{}
            { BOOTP? }
            if (eth.udp_destport{} == svc#BOOTP_C)
                ser.str(@"[BOOTP]")
                eth.rd_bootp_msg{}
                { BOOTP reply? }
                if (eth.bootp_opcode{} == eth#BOOT_REPL)
                    ser.str(@"[REPLY]")
                    if (eth.dhcp_msgtype{} == eth#DHCPOFFER)
                        ser.strln(@"[DHCPOFFER]")
                        return eth#DHCPOFFER
                    if (eth.dhcp_msgtype{} == eth#DHCPACK)
                        ser.strln(@"[DHCPACK]")
                        return eth#DHCPACK
        ser.newline{}
    else
        ser.str(@"[Unknown ethertype: ")
        ser.hex(ether_t, 4)
        ser.strln(@"]")

'    bytefill(@_buff, 0, MTU_MAX)

PRI SendFrame{} | ptr_tmp, t_e
{ show raw packet }
'    ser.hexdump(@_buff, 0, 4, eth.currptr{}, 16)
'    repeat
{ send packet }
    eth.fifotxstart(TXSTART)        'ETXSTL: TXSTART
    t_e := TXSTART+eth.fifowrptr(-2)
    eth.fifotxend(t_e)   'ETXNDL: TXSTART+currptr
    eth.txenabled(true)             'send

    ser.str(@"int flags: ")
    ser.bin(eth.interrupt, 8)
    ser.newline
    ptr_tmp := eth.fifowrptr(-2)
    eth.fifordptr(t_e+1)
    ser.str(@"TSV: ")
    repeat 7
        ser.hex(eth.rd_byte, 2)
        ser.char(" ")
    ser.newline
    eth.fifordptr(t_e)

'    bytefill(@_buff, 0, MTU_MAX)

PRI ShowARPMsg(opcode)
' Show Wireshark-ish messages about the ARP message received
    case opcode
        eth#ARP_REQ:
            showipaddr(@"Who has ", eth.arp_targetprotoaddr{})
            showipaddr(@"? Tell ", eth.arp_senderprotoaddr{})
            ser.newline{}
        eth#ARP_REPL:
            showipaddr(0, eth.arp_senderprotoaddr{})
            showmacaddr(@" is at ", eth.arp_senderhwaddr{})
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
'    eth.setptr(0)
    eth.wr_byte($00)                      ' per-frame control byte

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
