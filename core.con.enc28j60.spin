{
    --------------------------------------------
    Filename: core.con.enc28j60.spin
    Author: Jesse Burt
    Description: ENC28J60-specific constants
    Copyright (c) 2022
    Started Feb 21, 2022
    Updated Mar 19, 2022
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
'               opcode____ ______address        ' data
'                      ||| |||||
    RD_CTRL         = %000_00000                ' n/a
    RD_BUFF         = %001_11010                ' n/a
    WR_CTRL         = %010_00000                ' byte 1 ...
    WR_BUFF         = %011_11010                ' byte 1 ...
    BFS             = %100_00000                ' byte 1 ...
    BFC             = %101_00000                ' byte 1 ...
    SRC             = %111_11111                ' n/a

{ Register definitions }
    BANK            = 1
    TYPE            = 2

    ETH             = 0
    MAC             = 1 << (TYPE * 8)
    MII             = 2 << (TYPE * 8)
    PHY             = 3 << (TYPE * 8)

    B0              = 0
    B1              = 1 << (BANK * 8)
    B2              = 2 << (BANK * 8)
    B3              = 3 << (BANK * 8)

    { define regs with format: $xx_subsystem_bank_reg# }
    { bank 0 }
    ERDPTL          = ETH | B0 | $00
    ERDPTH          = ETH | B0 | $01

    EWRPTL          = ETH | B0 | $02
    EWRPTH          = ETH | B0 | $03

    ETXSTL          = ETH | B0 | $04
    ETXSTH          = ETH | B0 | $05

    ETXNDL          = ETH | B0 | $06
    ETXNDH          = ETH | B0 | $07

    ERXSTL          = ETH | B0 | $08
    ERXSTH          = ETH | B0 | $09

    ERXNDL          = ETH | B0 | $0A
    ERXNDH          = ETH | B0 | $0B

    ERXRDPTL        = ETH | B0 | $0C
    ERXRDPTH        = ETH | B0 | $0D

    ERXWRPTL        = ETH | B0 | $0E
    ERXWRPTH        = ETH | B0 | $0F

    EDMASTL         = ETH | B0 | $10
    EDMASTH         = ETH | B0 | $11

    EDMANDL         = ETH | B0 | $12
    EDMANDH         = ETH | B0 | $13

    EDMADSTL        = ETH | B0 | $14
    EDMADSTH        = ETH | B0 | $15

    EDMACSL         = ETH | B0 | $16
    EDMACSH         = ETH | B0 | $17

    { bank 1 }
    EHT0            = ETH | B1 | $00
    EHT1            = ETH | B1 | $01
    EHT2            = ETH | B1 | $02
    EHT3            = ETH | B1 | $03
    EHT4            = ETH | B1 | $04
    EHT5            = ETH | B1 | $05
    EHT6            = ETH | B1 | $06
    EHT7            = ETH | B1 | $07

    EPMM0           = ETH | B1 | $08
    EPMM1           = ETH | B1 | $09
    EPMM2           = ETH | B1 | $0A
    EPMM3           = ETH | B1 | $0B
    EPMM4           = ETH | B1 | $0C
    EPMM5           = ETH | B1 | $0D
    EPMM6           = ETH | B1 | $0E
    EPMM7           = ETH | B1 | $0F

    EPMCSL          = ETH | B1 | $10
    EPMCSH          = ETH | B1 | $11

    EPMOL           = ETH | B1 | $14
    EPMOH           = ETH | B1 | $15

    ERXFCON         = ETH | B1 | $18
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

    EPKTCNT         = ETH | B1 | $19

    { bank 2 }
    MACON1          = MAC | B2 | $00
    MACON1_MASK     = $0F
        TXPAUS      = 3
        RXPAUS      = 2
        PASSALL     = 1
        MARXEN      = 0
        TXPAUS_BITS = (1 << TXPAUS)
        RXPAUS_BITS = (1 << RXPAUS)
        PASSALL_BITS= (1 << PASSALL)
        MARXEN_BITS = 1
        TXPAUS_MASK = TXPAUS_BITS ^ MACON1_MASK
        RXPAUS_MASK = RXPAUS_BITS ^ MACON1_MASK
        PASSALL_MASK= PASSALL_BITS ^ MACON1_MASK
        MARXEN_MASK = MARXEN_BITS ^ MACON1_MASK

    MACON3          = MAC | B2 | $02
    MACON3_MASK     = $FF
        PADCFG      = 5
        TXCRCEN     = 4
        PHDREN      = 3
        HFRMEN      = 2
        FRMLNEN     = 1
        FULDPX      = 0
        PADCFG_BITS = (%111 << PADCFG)
        TXCRCEN_BITS= (1 << TXCRCEN)
        PHDREN_BITS = (1 << PHDREN)
        HFRMEN_BITS = (1 << HFRMEN)
        FRMLNEN_BITS= (1 << FRMLNEN)
        FULDPX_BITS = 1
        PADCFG_MASK = PADCFG_BITS ^ MACON3_MASK
        TXCRCEN_MASK= TXCRCEN_BITS ^ MACON3_MASK
        PHDREN_MASK = PHDREN_BITS ^ MACON3_MASK
        HFRMEN_MASK = HFRMEN_BITS ^ MACON3_MASK
        FRMLNEN_MASK= FRMLNEN_BITS ^ MACON3_MASK
        FULDPX_MASK = FULDPX_BITS ^ MACON3_MASK

    MACON4          = MAC | B2 | $03
    MACON4_MASK     = $70
        DEFER       = 6
        BPEN        = 5
        NOBKOFF     = 4
        DEFER_BITS  = (1 << DEFER)
        BPEN_BITS   = (1 << BPEN)
        NOBKOFF_BITS= (1 << NOBKOFF)
        DEFER_MASK  = DEFER_BITS ^ MACON4_MASK
        BPEN_MASK   = BPEN_BITS ^ MACON4_MASK
        NOBKOFF_MASK= NOBKOFF_BITS ^ MACON4_MASK

    MABBIPG         = MAC | B2 | $04

    MAIPGL          = MAC | B2 | $06
    MAIPGH          = MAC | B2 | $07

    MACLCON1        = MAC | B2 | $08
    MACLCON2        = MAC | B2 | $09
    MACLCON2_MASK   = $3F
        COLWIN      = 0
        COLWIN_BITS = %111111
        COLWIN_MASK = COLWIN_BITS ^ MACLCON2_MASK

    MAMXFLL         = MAC | B2 | $0A
    MAMXFLH         = MAC | B2 | $0B

    MICMD           = MII | B2 | $12
    MICMD_MASK      = $03
        MIISCAN     = 1
        MIIRD       = 0
        MIISCAN_BITS= (1 << MIISCAN)
        MIIRD_BITS  = 1
        MIISCAN_MASK= MIISCAN_BITS ^ MICMD_MASK
        MIIRD_MASK  = MIIRD_BITS ^ MICMD_MASK

    MIREGADR        = MII | B2 | $14
    MIREGADR_MASK   = $1F

    MIWRL           = MII | B2 | $16
    MIWRH           = MII | B2 | $17

    MIRDL           = MII | B2 | $18
    MIRDH           = MII | B2 | $19

    { bank 3 }
    MAADR5          = MAC | B3 | $00
    MAADR6          = MAC | B3 | $01
    MAADR3          = MAC | B3 | $02
    MAADR4          = MAC | B3 | $03
    MAADR1          = MAC | B3 | $04
    MAADR2          = MAC | B3 | $05

    EBSTSD          = ETH | B3 | $06

    EBSTCON         = ETH | B3 | $07

    EBSTCSL         = ETH | B3 | $08
    EBSTCSH         = ETH | B3 | $09

    MISTAT          = MII | B3 | $0A
    MISTAT_MASK     = $07
        NVALID      = 2
        SCAN        = 1
        BUSY        = 0
        NVALID_BITS = (1 << NVALID)
        SCAN_BITS   = (1 << SCAN)
        BUSY_BITS   = 1

    EREVID          = ETH | B3 | $12

    ECOCON          = ETH | B3 | $15

    EFLOCON         = ETH | B3 | $17

    EPAUSL          = ETH | B3 | $18
    EPAUSH          = ETH | B3 | $19

{ PHY regs }
    PHCON1          = PHY | $00
    PHCON1_MASK     = $C900
        PRST        = 15
        PLOOPBK     = 14
        PPWRSV      = 11
        PDPXMD      = 8
        PRST_BITS   = (1 << PRST)
        PLOOPBK_BITS= (1 << PLOOPBK)
        PPWRSV_BITS = (1 << PPWRSV)
        PDPXMD_BITS = (1 << PDPXMD)
        PRST_MASK   = PRST_BITS ^ PHCON1_MASK
        PLOOPBK_MASK= PLOOPBK_BITS ^ PHCON1_MASK
        PPWRSV_MASK = PPWRSV_BITS ^ PHCON1_MASK
        PDPXMD_MASK = PDPXMD_BITS ^ PHCON1_MASK

    PHSTAT1         = PHY | $01
    PHSTAT1_MASK    = $1806
        PFDPX       = 12
        PHDPX       = 11
        LLSTAT      = 2
        JBSTAT      = 1
        PFDPX_BITS  = (1 << PFDPX)
        PHDPX_BITS  = (1 << PHDPX)
        LLSTAT_BITS = (1 << LLSTAT)
        JBSTAT_BITS = (1 << JBSTAT)

    PHID1           = PHY | $02
    PHID1_MASK      = $FFFF
        OUI3_18     = 0

    PHID2           = PHY | $03
    PHID2_MASK      = $FFFF
        OUI19_24    = 10
        PHYPN       = 4
        PHYREV      = 0

    PHCON2          = PHY | $10
    PHCON2_MASK     = $6500
        FRCLNK      = 14
        TXDIS       = 13
        JABBER      = 10
        HDLDIS      = 8
        FRCLNK_BITS = (1 << FRCLNK)
        TXDIS_BITS  = (1 << TXDIS)
        JABBER_BITS = (1 << JABBER)
        HDLDIS_BITS = (1 << HDLDIS)
        FRCLNK_MASK = FRCLNK_BITS ^ PHCON2_MASK
        TXDIS_MASK  = TXDIS_BITS ^ PHCON2_MASK
        JABBER_MASK = JABBER_BITS ^ PHCON2_MASK
        HDLDIS_MASK = HDLDIS_BITS ^ PHCON2_MASK

    PHSTAT2         = PHY | $11
    PHSTAT2_MASK    = $3E20
        TXSTAT      = 13
        RXSTAT      = 12
        COLSTAT     = 11
        LSTAT       = 10
        DPXSTAT     = 9
        PLRITY      = 5
        TXSTAT_BITS = (1 << TXSTAT)
        RXSTAT_BITS = (1 << RXSTAT)
        COLSTAT_BITS= (1 << COLSTAT)
        LSTAT_BITS  = (1 << LSTAT)
        DPXSTAT_BITS= (1 << DPXSTAT)
        PLRITY_BITS = (1 << PLRITY)

    PHIE            = PHY | $12
    PHIE_MASK       = $0012
        PLNKIE      = 4
        PGEIE       = 1

    PHIR            = PHY | $13
    PHIR_MASK       = $0014
        PLNKIF      = 4
        PGIF        = 2
        PLNKIF_BITS = (1 << PLNKIF)
        PGIF_BITS   = (1 << PGIF)
        PLNKIF_MASK = PLNKIF_BITS ^ PHIR_MASK
        PGIF_MASK   = PGIF_BITS ^ PHIR_MASK

    PHLCON          = PHY | $14
    PHLCON_MASK     = $3FFE
        RSVDSET     = 12                        ' rsvd bits 13..12 must be set
        LACFG       = 8
        LBCFG       = 4
        LFRQ        = 2
        STRCH       = 1
        RSVDSET_BITS= (%11 << RSVDSET)
        LACFG_BITS  = (%1111 << LACFG)
        LBCFG_BITS  = (%1111 << LBCFG)
        LFRQ_BITS   = (%11 << LFRQ)
        STRCH_BITS  = (1 << STRCH)
        LACFG_MASK  = LACFG_BITS ^ PHLCON_MASK
        LBCFG_MASK  = LBCFG_BITS ^ PHLCON_MASK
        LFRQ_MASK   = LFRQ_BITS ^ PHLCON_MASK
        STRCH_MASK  = STRCH_BITS ^ PHLCON_MASK

{ bank-agnostic regs }
    EIE             = ETH | $1B

    EIR             = ETH | $1C
    EIR_MASK        = $7B
        PKTIF       = 6
        DMAIF       = 5
        LINKIF      = 4
        TXIF        = 3
        TXERIF      = 1
        RXERIF      = 0
        PKTIF_BITS  = (1 << PKTIF)
        DMAIF_BITS  = (1 << DMAIF)
        LINKIF_BITS = (1 << LINKIF)
        TXIF_BITS   = (1 << TXIF)
        TXERIF_BITS = (1 << TXERIF)
        RXERIF_BITS = 1
        EIR_CLRBITS = DMAIF | TXIF | TXERIF | RXERIF

    ESTAT           = ETH | $1D
    ESTAT_MASK      = $D7
        INT         = 7
        BUFER       = 6
        LATECOL     = 4
        RXBUSY      = 2
        TXABRT      = 1
        CLKRDY      = 0
        INT_BITS    = (1 << INT)
        BUFER_BITS  = (1 << BUFER)
        LATECOL_BITS= (1 << LATECOL)
        RXBUSY_BITS = (1 << RXBUSY)
        TXABRT_BITS = (1 << TXABRT)
        CLKRDY_BITS = 1
        BUFER_MASK  = BUFER_BITS ^ ESTAT_MASK
        LATECOL_MASK= LATECOL_BITS ^ ESTAT_MASK
        RXBUSY_MASK = RXBUSY_BITS ^ ESTAT_MASK
        TXABRT_MASK = TXABRT_BITS ^ ESTAT_MASK
        CLKRDY_MASK = CLKRDY_BITS ^ ESTAT_MASK

    ECON2           = ETH | $1E
    ECON2_MASK      = $E8
        AUTOINC     = 7
        PKTDEC      = 6
        PWRSV       = 5
        VRPS        = 3
        AUTOINC_BITS= (1 << AUTOINC)
        PKTDEC_BITS = (1 << PKTDEC)
        PWRSV_BITS  = (1 << PWRSV)
        VRPS_BITS   = (1 << VRPS)
        AUTOINC_MASK= AUTOINC_BITS ^ ECON2_MASK
        PKTDEC_MASK = PKTDEC_BITS ^ ECON2_MASK
        PWRSV_MASK  = PWRSV_BITS ^ ECON2_MASK
        VRPS_MASK   = VRPS_BITS ^ ECON2_MASK

    ECON1           = ETH | $1F
    ECON1_MASK      = $FF
        TXRST       = 7
        RXRST       = 6
        DMAST       = 5
        CSUMEN      = 4
        TXRTS       = 3
        RXEN        = 2
        BSEL        = 0
        TXRST_BITS  = (1 << TXRST)
        RXRST_BITS  = (1 << RXRST)
        DMAST_BITS  = (1 << DMAST)
        CSUMEN_BITS = (1 << CSUMEN)
        TXRTS_BITS  = (1 << TXRTS)
        RXEN_BITS   = (1 << RXEN)
        BSEL_BITS   = %11
        TXRST_MASK  = TXRST_BITS ^ ECON1_MASK
        RXRST_MASK  = RXRST_BITS ^ ECON1_MASK
        DMAST_MASK  = DMAST_BITS ^ ECON1_MASK
        CSUMEN_MASK = CSUMEN_BITS ^ ECON1_MASK
        TXRTS_MASK  = TXRTS_BITS ^ ECON1_MASK
        RXEN_MASK   = RXEN_BITS ^ ECON1_MASK
        BSEL_MASK   = BSEL_BITS ^ ECON1_MASK

PUB null{}
' This is not a top-level object

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

