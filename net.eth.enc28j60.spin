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

PUB FIFORXPos(rxpos): curr_ptr
' Set position within FIFO for next RX operation
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

PUB FIFOTXPtr(ptr): curr_ptr
' Set position within FIFO for next RX operation
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

PUB Reset{}
' Perform soft-reset
    cmd(core#SRC)

PRI bankSel(bank_nr): curr_bank
' Select register bank
'   Valid values: 0..3
'   Any other value polls the chip and returns the current setting
    if (bank_nr == _curr_bank)                  ' leave the bank set as-is if
        return                                  ' it matches the last setting

    curr_bank := 0
    readreg(core#ECON1, 1, @curr_bank)
    case bank_nr
        0..3:
            _curr_bank := bank_nr
        other:
            return (curr_bank & core#BSEL_BITS)
    bank_nr := ((curr_bank & core#BSEL_MASK) | bank_nr)
    writereg(core#ECON1, 1, @bank_nr)

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
