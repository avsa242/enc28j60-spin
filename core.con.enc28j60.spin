{
    --------------------------------------------
    Filename: core.con.enc28j60.spin
    Author: Jesse Burt
    Description: ENC28J60-specific constants
    Copyright (c) 2022
    Started Feb 21, 2022
    Updated Feb 22, 2022
    See end of file for terms of use.
    --------------------------------------------
}

CON

{ SPI Configuration }
    SPI_MAX_FREQ    = 20_000_000                ' device max SPI bus freq
    SPI_MODE        = 0
    T_POR           = 0                         ' startup time (usecs)

    DEVID_RESP      = $00                       ' device ID expected response

{ Instruction set }
'           opcode____ ______address            ' data
'                  ||| |||||
    RD_CTRL     = %000_00000                    ' n/a
    RD_BUFF     = %001_11010                    ' n/a
    WR_CTRL     = %010_00000                    ' byte 1 ...
    WR_BUFF     = %011_11010                    ' byte 1 ...
    BFS         = %100_00000                    ' byte 1 ...
    BFC         = %101_00000                    ' byte 1 ...
    SRC         = %111_11111                    ' n/a

{ Register definitions }
    { bank 0 }
    ERDPTL          = $00
    ERDPTH          = $01

    EWRPTL          = $02
    EWRPTH          = $03

    ETXSTL          = $04
    ETXSTH          = $05

    ETXNDL          = $06
    ETXNDH          = $07

    ERXSTL          = $08
    ERXSTH          = $09

    ERXNDL          = $0A
    ERXNDH          = $0B

    ERXRDPTL        = $0C
    ERXRDPTH        = $0D

    ERXWRPTL        = $0E
    ERXWRPTH        = $0F

    EDMASTL         = $10
    EDMASTH         = $11

    EDMANDL         = $12
    EDMANDH         = $13

    EDMADSTL        = $14
    EDMADSTH        = $15

    EDMACSL         = $16
    EDMACSH         = $17

    { bank 1 }
    EHT0            = $00
    EHT1            = $01
    EHT2            = $02
    EHT3            = $03
    EHT4            = $04
    EHT5            = $05
    EHT6            = $06
    EHT7            = $07

    EPMM0           = $08
    EPMM1           = $09
    EPMM2           = $0A
    EPMM3           = $0B
    EPMM4           = $0C
    EPMM5           = $0D
    EPMM6           = $0E
    EPMM7           = $0F

    EPMCSL          = $10
    EPMCSH          = $11

    EPMOL           = $14
    EPMOH           = $15

    ERXFCON         = $18
    ERXFCON_MASK    = $FF
        UCEN        = 7
        ANDOR       = 6
        CRCEN       = 5
        PMEN        = 4
        MPEN        = 3
        HTEN        = 2
        MCEN        = 1
        BCEN        = 0
        UCEN_MASK   = (1 << UCEN) ^ ERXFCON_MASK
        ANDOR_MASK  = (1 << ANDOR) ^ ERXFCON_MASK
        CRCEN_MASK  = (1 << CRCEN) ^ ERXFCON_MASK
        PMEN_MASK   = (1 << PMEN) ^ ERXFCON_MASK
        MPEN_MASK   = (1 << MPEN) ^ ERXFCON_MASK
        HTEN_MASK   = (1 << HTEN) ^ ERXFCON_MASK
        MCEN_MASK   = (1 << MCEN) ^ ERXFCON_MASK
        BCEN_MASK   = (1 << BCEN) ^ ERXFCON_MASK

    EPKTCNT         = $19

    { bank 2 }
    MACON1          = $00
    MACON3          = $02
    MACON4          = $03
    MABBIPG         = $04

    MAIPGL          = $06
    MAIPGH          = $07

    MACLCON1        = $08
    MACLCON2        = $09

    MAMXFLL         = $0A
    MAMXFLH         = $0B

    MICMD           = $12

    MIREGADR        = $14

    MIWRL           = $16
    MIWRH           = $17

    MIRDL           = $18
    MIRDH           = $19

    { bank 3 }
    MAADR5          = $00
    MAADR6          = $01
    MAADR3          = $02
    MAADR4          = $03
    MAADR1          = $04
    MAADR2          = $05

    EBSTSD          = $06

    EBSTCON         = $07

    EBSTCSL         = $08
    EBSTCSH         = $09

    MISTAT          = $0A

    EREVID          = $12

    ECOCON          = $15

    EFLOCON         = $17

    EPAUSL          = $18
    EPAUSH          = $19


{ bank-agnostic regs }
    EIE             = $1B

    EIR             = $1C

    ESTAT           = $1D
    ESTAT_MASK      = $D7
        INT         = 7
        BUFER       = 6
        LATECOL     = 4
        RXBUSY      = 2
        TXABRT      = 1
        CLKRDY      = 0
        BUFER_MASK  = (1 << BUFER) ^ ESTAT_MASK
        LATECOL_MASK= (1 << LATECOL) ^ ESTAT_MASK
        TXABRT_MASK = (1 << TXABRT) ^ ESTAT_MASK
        CLKRDY_MASK = (1 << CLKRDY) ^ ESTAT_MASK

    ECON2           = $1E
    ECON2_MASK      = $FF

    ECON1           = $1F
    ECON1_MASK      = $FF
        TXRST       = 7
        RXRST       = 6
        DMAST       = 5
        CSUMEN      = 4
        TXRTS       = 3
        RXEN        = 2
        BSEL        = 0
        BSEL_BITS   = %11
        TXRST_MASK  = (1 << TXRST) ^ ECON1_MASK
        RXRST_MASK  = (1 << RXRST) ^ ECON1_MASK
        DMAST_MASK  = (1 << DMAST) ^ ECON1_MASK
        CSUMEN_MASK = (1 << CSUMEN) ^ ECON1_MASK
        TXRTS_MASK  = (1 << TXRTS) ^ ECON1_MASK
        RXEN_MASK   = (1 << RXEN) ^ ECON1_MASK
        BSEL_MASK   = BSEL_BITS ^ ECON1_MASK

PUB Null{}
' This is not a top-level object

