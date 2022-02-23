{
    --------------------------------------------
    Filename: net.eth.enc28j60.spin
    Author: Jesse Burt
    Description: Driver for the ENC28J60 Ethernet Transceiver
    Copyright (c) 2022
    Started Feb 21, 2022
    Updated Feb 22, 2022
    See end of file for terms of use.
    --------------------------------------------
}

CON

    FIFO_MAX    = 8192-1

' FramePadding() options
    VLAN        = %101
    PAD64       = %011
    PAD60       = %001
    NONE        = %000


VAR

    long _CS
    long _curr_bank

OBJ

    spi : "com.spi.fast-nocs"                   ' PASM SPI engine (20MHz W/10R)
    core: "core.con.enc28j60"                   ' hw-specific constants
    time: "time"                                ' Basic timing functions

PUB Null{}
' This is not a top-level object

PUB Startx(CS_PIN, SCK_PIN, MOSI_PIN, MISO_PIN): status
' Start using custom IO pins
    if lookdown(CS_PIN: 0..31) and lookdown(SCK_PIN: 0..31) and {
}   lookdown(MOSI_PIN: 0..31) and lookdown(MISO_PIN: 0..31)
        if (status := spi.init(SCK_PIN, MOSI_PIN, MISO_PIN, core#SPI_MODE))
            time.msleep(core#T_POR)             ' wait for device startup
            _CS := CS_PIN                       ' copy i/o pin to hub var
            outa[_CS] := 1
            dira[_CS] := 1

            repeat until clkready{}
            reset
            time.msleep(5)
            return
    ' if this point is reached, something above failed
    ' Re-check I/O pin assignments, bus speed, connections, power
    ' Lastly - make sure you have at least one free core/cog
    return FALSE

PUB Stop{}

    spi.deinit{}

PUB Defaults{}
' Set factory defaults

PUB ClkReady{}: status
' Flag indicating clock is ready
'   Returns: TRUE (-1) or FALSE (0)
    status := 0
    readreg(core#ESTAT, 1, @status)
    return ((status & 1) == 1)

PUB FIFORdPtr(rxpos): curr_ptr
' Set read position within FIFO
'   Valid values: 0..8191
'   Any other value polls the chip and returns the current setting
    banksel(0)
    case ptr
        0..FIFO_MAX:
            writereg(core#ERDPTL, 2, @ptr)
        other:
            curr_ptr := 0
            readreg(core#ERDPTL, 2, @curr_ptr)
            return curr_ptr

PUB FIFORXEnd(rxe): curr_ptr
' Set ending position within FIFO for RX region
'   Valid values: 0..8191
'   Any other value polls the chip and returns the current setting
    banksel(0)
    case rxe
        0..FIFO_MAX:
            writereg(core#ERXNDL, 2, @rxe)
        other:
            curr_ptr := 0
            readreg(core#ERXNDL, 2, @curr_ptr)
            return curr_ptr

PUB FIFORXRdPtr(rxrd): curr_rdpos
' Set receive read pointer XXX clarify
'   Valid values: 0..8191
'   Any other value polls the chip and returns the current setting
    banksel(0)
    case rxrd
        0..FIFO_MAX:
            writereg(core#ERXRDPTL, 2, @rxrd)
        other:
            curr_rdpos := 0
            readreg(core#ERXRDPTL, 2, @curr_rdpos)
            return curr_rdpos

PUB FIFORXWrPtr(rxwr): curr_wrpos
' Set receive write pointer XXX clarify
'   Valid values: 0..8191
'   Any other value polls the chip and returns the current setting
    banksel(0)
    case rxwr
        0..FIFO_MAX:
            writereg(core#ERXWRPTL, 2, @rxwr)
        other:
            curr_wrpos := 0
            readreg(core#ERXWRPTL, 2, @curr_wrpos)
            return curr_wrpos

PUB FIFORXStart(rxs): curr_ptr
' Set starting position within FIFO for RX region
'   Valid values: 0..8191
'   Any other value polls the chip and returns the current setting
    banksel(0)
    case rxs
        0..FIFO_MAX:
            writereg(core#ERXSTL, 2, @rxs)
        other:
            curr_ptr := 0
            readreg(core#ERXSTL, 2, @curr_ptr)
            return curr_ptr

PUB FIFOTXEnd(ptr): curr_ptr
' Set starting position within FIFO for TX region
'   Valid values: 0..8191
'   Any other value polls the chip and returns the current setting
    banksel(0)
    case ptr
        0..FIFO_MAX:
            writereg(core#ETXNDL, 2, @ptr)
        other:
            curr_ptr := 0
            readreg(core#ETXNDL, 2, @curr_ptr)
            return curr_ptr

PUB FIFOTXStart(ptr): curr_ptr
' Set starting position within FIFO for TX region
'   Valid values: 0..8191
'   Any other value polls the chip and returns the current setting
    banksel(0)
    case ptr
        0..FIFO_MAX:
            writereg(core#ETXSTL, 2, @ptr)
        other:
            curr_ptr := 0
            readreg(core#ETXSTL, 2, @curr_ptr)
            return curr_ptr

PUB FIFOWrPtr(ptr): curr_ptr
' Set write position within FIFO
'   Valid values: 0..8191
'   Any other value polls the chip and returns the current setting
    banksel(0)
    case ptr
        0..FIFO_MAX:
            writereg(core#EWRPTL, 2, @ptr)
        other:
            curr_ptr := 0
            readreg(core#EWRPTL, 2, @curr_ptr)
            return curr_ptr

PUB FramePadding(mode): curr_md     'XXX tentatively named
' Set frame padding mode
'   Valid values:
'       VLAN (%101):
'           If MAC detects VLAN protocol frame ($8100 type field),
'               frame will be padded to 64 bytes.
'           Otherwise, 60 bytes padding. CRC appended in both cases.
'       PAD64 (%011, %111): all short frames padded to 64 bytes (CRC appended)
'       PAD60 (%001): all short frames padded to 60 bytes (CRC appended)
'       NONE (%000, %010, %100, %110): no padding of short frames
'   Any other value polls the chip and returns the current setting
    banksel(2)
    case mode
        %000..%111:
            regbits_clr(core#MACON3, core#PADCFG_BITS)
            mode <<= core#PADCFG
            if (lookdown(mode: %001, %011, %111, %101))
                mode |= core#TXCRCEN_BITS       ' mandatory for above modes
            regbits_set(core#MACON3, mode)
        other:
            curr_md := 0
            readreg(core#MACON3, 1, @curr_md)
            return (curr_md >> core#PADCFG)

PUB FullDuplex(state): curr_state
' Enable full-duplex
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    banksel(2)
    case ||(state)
        0:
            regbits_clr(core#MACON3, core#FULDPX_BITS)
        1:
            regbits_set(core#MACON3, core#FULDPX_BITS)
        other:
            curr_state := 0
            readreg(core#MACON3, 1, @curr_state)
            return ((curr_state & 1) == 1)

PUB MACRXEnabled(state): curr_state 'XXX tentative name
' Enable MAC reception of frames
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    banksel(2)
    case ||(state)
        0:
            regbits_clr(core#MACON1, core#MARXEN_BITS)
        1:
            regbits_set(core#MACON1, core#MARXEN_BITS)
        other:
            curr_state := 0
            readreg(core#MACON1, 1, @curr_state)
            return ((curr_state & 1) == 1)

PUB PktFilter(mask): curr_mask  'XXX tentative name and interface
' Set ethernet receive filter mask
'   Bits: 7..0
'   7: unicast filter enable
'   6: and/or
'       1: reject packets unless all enabled filters accept the packet
'       0: accept packets unless all enabled filters reject the packet
'   5: post-filter CRC check enabled
'       1: discard packets with invalid CRC
'       0: ignore CRC
'   4: pattern match filter enable
'       if and/or == 1
'           1: packets discarded unless they meet pattern match criteria
'           0: filter disabled
'       if and/or == 0
'           1: packets accepted if they meet pattern match criteria
'           0: filter disabled
'   3: magic packet filter enable
'       if and/or == 1
'           1: packets discarded unless they're magic packets for this MAC
'           0: filter disabled
'       if and/or == 0
'           1: packets accepted if they're magic packets for this MAC
'           0: filter disabled
'   2: hash table filter enable
'       if and/or == 1
'           1: packets discarded unless they meet hash table criteria
'           0: filter disabled
'       if and/or == 0
'           1: packets accepted if they meet hash table criteria
'           0: filter disabled
'   1: multicast filter enable
'       if and/or == 1
'           1: packets discarded unless the dest address LSB is set
'           0: filter disabled
'       if and/or == 0
'           1: packets accepted if the dest addr LSB is set
'           0: filter disabled
'   0: broadcast filter enable
'       if and/or == 1
'           1: packets discarded unless dest addr is FF:FF:FF:FF:FF:FF
'           0: filter disabled
'       if and/or == 0
'           1: packets accepted if the dest addr is FF:FF:FF:FF:FF:FF
'           0: filter disabled
    if (mask => %0000_0000 and mask =< %1111_1111)
        writereg(core#ERXFCON, 1, @mask)
    else
        curr_mask := 0
        readreg(core#ERXFCON, 1, @curr_mask)

PUB Reset{}
' Perform soft-reset
    cmd(core#SRC)

PUB RXFlowCtrl(state): curr_state   'XXX tentatively named
' Enable receive flow control
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    banksel(2)
    case ||(state)
        0:
            regbits_clr(core#MACON1, core#RXPAUS_BITS)
        1:
            regbits_set(core#MACON1, core#RXPAUS_BITS)
        other:
            curr_state := 0
            readreg(core#MACON1, 1, @curr_state)
            return (((curr_state >> core#RXPAUS) & 1) == 1)

PUB TXFlowCtrl(state): curr_state   'XXX tentatively named
' Enable transmit flow control
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    banksel(2)
    case ||(state)
        0:
            regbits_clr(core#MACON1, core#TXPAUS_BITS)
        1:
            regbits_set(core#MACON1, core#TXPAUS_BITS)
        other:
            curr_state := 0
            readreg(core#MACON1, 1, @curr_state)
            return (((curr_state >> core#TXPAUS) & 1) == 1)

PRI bankSel(bank_nr): curr_bank
' Select register bank
'   Valid values: 0..3
'   Any other value polls the chip and returns the current setting
    if (bank_nr == _curr_bank)                  ' leave the bank set as-is if
        return                                  ' it matches the last setting

    case bank_nr
        0..3:
            regbits_clr(core#ECON1, core#BSEL_BITS)
            regbits_set(core#ECON1, bank_nr)
            _curr_bank := bank_nr
        other:
            curr_bank := 0
            readreg(core#ECON1, 1, @curr_bank)
            return (curr_bank & core#BSEL_BITS)

PRI cmd(cmd_nr)
' Send simple command
    case cmd_nr
        core#RD_BUFF, core#WR_BUFF, core#SRC:
            outa[_CS] := 0
            spi.wr_byte(cmd_nr)
            outa[_CS] := 1
        other:
            return

PRI readReg(reg_nr, nr_bytes, ptr_buff) | i
' Read nr_bytes from the device into ptr_buff
    case reg_nr                                 ' validate register num
        $00..$19, $1b..$1f:
            repeat i from 0 to nr_bytes-1
                outa[_CS] := 0
                spi.wr_byte(core#RD_CTRL | reg_nr+i)
                byte[ptr_buff][i] := spi.rd_byte{}
                outa[_CS] := 1
            return
        other:                                  ' invalid reg_nr
            return

PRI regBits_Clr(reg, field)
' Clear bitfield 'field' in register 'reg'
    outa[_CS] := 0
    spi.wr_byte(core#BFC | reg)
    spi.wr_byte(field)
    outa[_CS] := 1

PRI regBits_Set(reg, field)
' Set bitfield 'field' in register 'reg'
    outa[_CS] := 0
    spi.wr_byte(core#BFS | reg)
    spi.wr_byte(field)
    outa[_CS] := 1

PRI writeReg(reg_nr, nr_bytes, ptr_buff) | i
' Write nr_bytes to the device from ptr_buff
    case reg_nr
        $00..$19, $1b..$1f:
            repeat i from 0 to nr_bytes-1
                outa[_CS] := 0
                spi.wr_byte(core#WR_CTRL | reg_nr+i)
                spi.wr_byte(byte[ptr_buff][i])
                outa[_CS] := 1
        other:
            return

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
