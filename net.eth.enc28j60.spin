{
    --------------------------------------------
    Filename: net.eth.enc28j60.spin
    Author: Jesse Burt
    Description: Driver for the ENC28J60 Ethernet Transceiver
    Copyright (c) 2022
    Started Feb 21, 2022
    Updated Mar 17, 2022
    See end of file for terms of use.
    --------------------------------------------
}

CON

    FIFO_MAX    = 8192-1

{ FramePadding() options }
    VLAN        = %101
    PAD64       = %011
    PAD60       = %001
    NONE        = %000

{ PktFilter() filters }
    UNICAST_EN  = (1 << 7)
    ANDOR       = (1 << 6)
    PFCRC_EN    = (1 << 5)
    PATTMTCH_EN = (1 << 4)
    MAGICPKT_EN = (1 << 3)
    HASHTBL_EN  = (1 << 2)
    MCAST_EN    = (1 << 1)
    BCAST_EN    = (1 << 0)

{ PHY link states }
    DOWN        = 0
    UP          = 1

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
            _curr_bank := -1                    ' establish initial bank

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

CON
' XXX temporary
    TX_BUFFER_SIZE  = 1518
    RXSTART         = 0
    RXSTOP          = (TXSTART - 2) | 1                 '6665
    TXSTART         = 8192 - (TX_BUFFER_SIZE + 8)       '6666
    TXEND           = TXSTART + (TX_BUFFER_SIZE + 8)    '8192 (xxx - shouldn't this be 8191?)

PUB Preset_FDX
' Preset settings; full-duplex
    rxenabled(false)
    txenabled(false)

    { set up on-chip FIFO }
    fifoptrautoinc(true)
    fifordptr(RXSTART)
    fiforxstart(RXSTART)
    fiforxrdptr(RXSTOP)
    fiforxend(RXSTOP)
    fifotxstart(TXSTART)

    macrxenabled(true)      ' MACON1
    rxflowctrl(true)
    txflowctrl(true)

    framelencheck(true)     ' MACON3
    framepadding(PAD60)

    txdefer(true)           ' MACON4

    collisionwin(63)        ' MACLCON2

    interpktgap(18)         ' MAIPGL $12
    interpktgaphdx(12)      ' MAIPGH $0c

    maxframelen(1518)       ' MAMXFLL

    b2binterpktgap(18)      ' MABBIPG $12

    hdxloopback(false)      ' PHCON2

    phyloopback(false)      ' PHCON1
    phypowered(true)        ' PHCON1
    phyfullduplex(true)    ' PHCON1
    fullduplex(true)

    phyledamode(%0101)'%100)       ' PHLCON LED A: display link status
    phyledbmode(%111)       ' LED B: display tx/rx activity
    phyledstretch(true)     ' lengthen LED pulses
    rxenabled(true)

PUB B2BInterPktGap(dly): curr_dly  'XXX tentatively named
' Set inter-packet gap delay for back-to-back packets
'   Valid values: 0..127
'   Any other value polls the chip and returns the current setting
'   NOTE: When FullDuplex() == 1, recommended setting is $15
'       When FullDuplex() == 0, recommended setting is $12
    case dly
        0..127:
            writereg(core#MABBIPG, 1, @dly)
        other:
            curr_dly := 0
            readreg(core#MABBIPG, 1, @curr_dly)
            return

PUB BackOff(state): curr_state  'XXX tentatively named
' Enable backoff
'   Valid values:
'      *TRUE (-1 or 1): after collision, MAC will delay using
'           Binary Exponential Backoff algorithm, before retransmitting
'       FALSE (0): MAC after collision, MAC will immediately begin
'           retransmitting
'   Any other value polls the chip and returns the current setting
    curr_state := 0
    readreg(core#MACON4, 1, @curr_state)
    case ||(state)
        0:
            state := ||(state) << core#NOBKOFF
        other:
            return !(((curr_state >> core#NOBKOFF) & 1) == 1)

    state := ((curr_state & core#NOBKOFF_MASK) | state)
    writereg(core#MACON4, 1, @state)

PUB BackPressBackOff(state): curr_state 'XXX tentatively named
' Enable backoff during backpressure
'   Valid values:
'      *TRUE (-1 or 1): after causing a collision, MAC will delay using
'           Binary Exponential Backoff algorithm, before retransmitting
'       FALSE (0): MAC after collision, MAC will immediately begin
'           retransmitting
'   Any other value polls the chip and returns the current setting
    curr_state := 0
    readreg(core#MACON4, 1, @curr_state)
    case ||(state)
        0:
            state := ||(state) << core#BPEN
        other:
            return !(((curr_state >> core#BPEN) & 1) == 1)

    state := ((curr_state & core#BPEN_MASK) | state)
    writereg(core#MACON4, 1, @state)

PUB ClkReady{}: status
' Flag indicating clock is ready
'   Returns: TRUE (-1) or FALSE (0)
    status := 0
    readreg(core#ESTAT, 1, @status)
    return ((status & core#CLKRDY_BITS) == 1)

PUB CollisionWin(nr_bytes): curr_nr 'XXX tentatively named
' Set collision window, in number of bytes
'   Valid values: 0..63 (default: 55)
'   Any other value polls the chip and returns the current setting
'   NOTE: Applies only when FullDuplex() == 0
    case nr_bytes
        0..63:
            writereg(core#MACLCON2, 1, @nr_bytes)
        other:
            curr_nr := 0
            readreg(core#MACLCON2, 1, @curr_nr)
            return

PUB FIFOPtrAutoInc(state): curr_state
' Auto-increment FIFO pointer when writing
'   Valid values: TRUE (-1) or FALSE (0)
'   Any other value polls the chip and returns the current setting
'   NOTE: When reached the end of the FIFO, the pointer wraps to the start
    case ||(state)
        0:
            regbits_clr(core#ECON2, core#AUTOINC_BITS)
        1:
            regbits_set(core#ECON2, core#AUTOINC_BITS)
        other:
            curr_state := 0
            readreg(core#ECON2, 1, @curr_state)
            return (((curr_state >> core#AUTOINC) & 1) == 1)

PUB FIFORdPtr(rxpos): curr_ptr
' Set read position within FIFO
'   Valid values: 0..8191
'   Any other value polls the chip and returns the current setting
    case rxpos
        0..FIFO_MAX:
            writereg(core#ERDPTL, 2, @rxpos)
        other:
            curr_ptr := 0
            readreg(core#ERDPTL, 2, @curr_ptr)
            return curr_ptr

PUB FIFORXEnd(rxe): curr_ptr
' Set ending position within FIFO for RX region
'   Valid values: 0..8191
'   Any other value polls the chip and returns the current setting
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
    case ptr
        0..FIFO_MAX:
            writereg(core#EWRPTL, 2, @ptr)
        other:
            curr_ptr := 0
            readreg(core#EWRPTL, 2, @curr_ptr)
            return curr_ptr

PUB FrameLenCheck(state): curr_state    'XXX tentatively named
' Enable frame length checking
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    curr_state := 0
    readreg(core#MACON3, 1, @curr_state)
    case ||(state)
        0, 1:
            state := ||(state) << core#FRMLNEN
        other:
            return (((curr_state >> core#FRMLNEN) & 1) == 1)

    state := ((curr_state & core#FRMLNEN_MASK) | state)
    writereg(core#MACON3, 1, @state)

PUB FramePadding(mode): curr_md | txcrcen    'XXX tentatively named
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
    curr_md := txcrcen := 0
    readreg(core#MACON3, 1, @curr_md)
    case mode
        %000..%111:
            mode <<= core#PADCFG
            { if mode is any of the four below, appending of CRC to all
                frames is required - set the TXCRCEN bit}
            if (lookdown(mode: %001, %011, %111, %101))
                txcrcen := core#TXCRCEN_BITS
        other:
            return (curr_md >> core#PADCFG)

    mode := ((curr_md & core#PADCFG_MASK) | mode) | txcrcen
    writereg(core#MACON3, 1, @mode)

PUB FullDuplex(state): curr_state
' Enable full-duplex
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    curr_state := 0
    readreg(core#MACON3, 1, @curr_state)
    case ||(state)
        0, 1:
            state := ||(state)
        other:
            return ((curr_state & 1) == 1)

    state := ((curr_state & core#FULDPX_MASK) | state)
    writereg(core#MACON3, 1, @state)

PUB GetNodeAddress(ptr_addr)
' Get this node's currently set MAC address
'   NOTE: Buffer pointed to by ptr_addr must be 6 bytes long
    readreg(core#MAADR1, 1, ptr_addr+5)         '
    readreg(core#MAADR2, 1, ptr_addr+4)         ' OUI
    readreg(core#MAADR3, 1, ptr_addr+3)         '
    readreg(core#MAADR4, 1, ptr_addr+2)
    readreg(core#MAADR5, 1, ptr_addr+1)
    readreg(core#MAADR6, 1, ptr_addr)

PUB HDXLoopback(state): curr_state
' Enable loopback mode when operating in half-duplex
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
'   NOTE: When FullDuplex() == TRUE, this setting is ignored.
    curr_state := 0
    readreg(core#PHCON2, 1, @curr_state)
    case ||(state)
        0, 1:
            { invert logic before setting bit - description of field
             actually reads as 'PHY half-duplex loopback _disable_ bit' }
            state := ((!state) & 1) << core#HDLDIS
        other:
            return (((curr_state >> core#HDLDIS) & 1) == 0)

    state := ((curr_state & core#HDLDIS_MASK) | state)
    writereg(core#PHCON2, 1, @state)

PUB IntClear(mask)
' Clear interrupts
'   Valid values:
'       Bits: 5, 3, 1, 0 (set a bit to clear the corresponding interrupt flag)
'       5: DMA copy or checksum calculation has completed
'       3: transmit has ended
'       1: transmit error
'       0: receive error: insufficient buffer space
'   Any other value is ignored
    mask &= core#EIR_CLRBITS
    writereg(core#EIR, 1, @mask)

PUB InterPktGap(dly): curr_dly  'XXX tentatively named
' Set inter-packet gap delay for _non_-back-to-back packets
'   Valid values: 0..127
'   Any other value polls the chip and returns the current setting
'   NOTE: Recommended setting is $12
    case dly
        0..127:
            writereg(core#MAIPGL, 1, @dly)
        other:
            curr_dly := 0
            readreg(core#MAIPGL, 1, @curr_dly)
            return

PUB InterPktGapHDX(dly): curr_dly  'XXX tentatively named
' Set inter-packet gap delay for _non_-back-to-back packets (for half-duplex)
'   Valid values: 0..127
'   Any other value polls the chip and returns the current setting
'   NOTE: Recommended setting is $0C
    case dly
        0..127:
            writereg(core#MAIPGH, 1, @dly)
        other:
            curr_dly := 0
            readreg(core#MAIPGH, 1, @curr_dly)
            return

PUB Interrupt{}: int_src
' Interrupt flags
'   Returns: bits 6..0
'       6: receive packet pending
'       5: DMA copy or checksum calculation has completed
'       4: PHY link state has changed
'       3: transmit has ended
'       1: transmit error
'       0: receive error: insufficient buffer space
'           or PktCnt() => 255 (call PktDec())
    int_src := 0
    readreg(core#EIR, 1, @int_src)

PUB MACRXEnabled(state): curr_state 'XXX tentative name
' Enable MAC reception of frames
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    curr_state := 0
    readreg(core#MACON1, 1, @curr_state)
    case ||(state)
        0, 1:
            state := ||(state)
        other:
            return ((curr_state & 1) == 1)

    state := ((curr_state & core#MARXEN_MASK) | state)
    writereg(core#MACON1, 1, @state)

PUB MaxFrameLen(len): curr_len
' Set maximum frame length
'   Valid values: 0..65535
'   Any other value polls the chip and returns the current setting
    case len
        0..65535:
            writereg(core#MAMXFLL, 2, @len)
        other:
            curr_len := 0
            readreg(core#MAMXFLL, 2, @curr_len)
            return curr_len

PUB MaxRetransmits(max_nr): curr_max
' Set maximum number of retransmissions
'   Valid values: 0..15 (default: 15)
'   Any other value polls the chip and returns the current setting
'   NOTE: Applies only when FullDuplex() == 0
    case max_nr
        0..15:
            writereg(core#MACLCON1, 1, @max_nr)
        other:
            curr_max := 0
            readreg(core#MACLCON1, 1, @curr_max)

PUB NodeAddress(ptr_addr)
' Set this node's MAC address
'   Valid values: pointer to six 8-bit values
    writereg(core#MAADR1, 1, ptr_addr+5)        '
    writereg(core#MAADR2, 1, ptr_addr+4)        ' OUI
    writereg(core#MAADR3, 1, ptr_addr+3)        '
    writereg(core#MAADR4, 1, ptr_addr+2)
    writereg(core#MAADR5, 1, ptr_addr+1)
    writereg(core#MAADR6, 1, ptr_addr)

PUB PHYFullDuplex(state): curr_state    'XXX tentatively named
' Set PHY to full-duplex
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    curr_state := 0
    readreg(core#PHCON1, 1, @curr_state)
    case ||(state)
        0, 1:
            state := ||(state) << core#PDPXMD
        other:
            return (((curr_state >> core#PDPXMD) & 1) == 1)

    state := ((curr_state & core#PDPXMD_MASK) | state)
    writereg(core#PHCON1, 1, @state)

PUB PHYLEDAMode(mode): curr_md  'XXX tentatively named
' Configure PHY LED A mode
'   Valid values:
'       %0001: display transmit activity
'       %0010: display receive activity
'       %0011: display collision activity
'       %0100: display link status
'       %0101: display duplex status
'       %0111: display transmit and receive activity
'       %1000: always on
'       %1001: always off
'       %1010: blink fast
'       %1011: blink slow
'       %1100: display link status and receive activity
'       %1101: display link status and tx/rx activity
'       %1110: display duplex status and collision activity
    curr_md := 0
    readreg(core#PHLCON, 1, @curr_md)
    case mode
        %0001..%0101, %0111..%1110:
            mode <<= core#LACFG
        other:
            return ((curr_md >> core#LACFG) & core#LACFG_BITS)

    mode := ((curr_md & core#LACFG_MASK) | mode)
    writereg(core#PHLCON, 1, @mode)

PUB PHYLEDBMode(mode): curr_md    'XXX tentatively named
' Configure PHY LED B mode
'   Valid values:
'       %0001: display transmit activity
'       %0010: display receive activity
'       %0011: display collision activity
'       %0100: display link status
'       %0101: display duplex status
'       %0111: display transmit and receive activity
'       %1000: always on
'       %1001: always off
'       %1010: blink fast
'       %1011: blink slow
'       %1100: display link status and receive activity
'       %1101: display link status and tx/rx activity
'       %1110: display duplex status and collision activity
    curr_md := 0
    readreg(core#PHLCON, 1, @curr_md)
    case mode
        %0001..%0101, %0111..%1110:
            mode <<= core#LBCFG
        other:
            return ((curr_md >> core#LBCFG) & core#LBCFG_BITS)

    mode := ((curr_md & core#LBCFG_MASK) | mode)
    writereg(core#PHLCON, 1, @mode)

PUB PHYLEDStretch(state): curr_state    'XXX tentatively named
' Lengthen LED pulses
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    curr_state := 0
    readreg(core#PHLCON, 1, @curr_state)
    case ||(state)
        0, 1:
            state := ||(state) << core#STRCH
        other:
            return (((curr_state >> core#STRCH) & 1) == 1)

    state := ((curr_state & core#STRCH_MASK) | state)
    writereg(core#PHLCON, 1, @state)

PUB PHYLinkState{}: state    'XXX tentatively named
' Get PHY Link state
'   Returns:
'       DOWN (0): link down
'       UP (1): link up
    state := 0
    readreg(core#PHSTAT2, 1, @state)
    return ((state >> core#LSTAT) & 1)

PUB PHYLoopback(state): curr_state    'XXX tentatively named
' Loop-back all data transmitted and disable interface to twisted-pair
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    curr_state := 0
    readreg(core#PHCON1, 1, @curr_state)
    case ||(state)
        0, 1:
            state := ||(state) << core#PLOOPBK
        other:
            return (((curr_state >> core#PLOOPBK) & 1) == 1)

    state := ((curr_state & core#PLOOPBK_MASK) | state)
    writereg(core#PHCON1, 1, @state)

PUB PHYPowered(state): curr_state    'XXX tentatively named
' Power down PHY
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    curr_state := 0
    readreg(core#PHCON1, 1, @curr_state)
    case ||(state)
        0, 1:
            { invert logic before setting bit - description of field
             actually reads as 'PHY power-_down_ bit' }
            state := (! ||(state) ) << core#PPWRSV
        other:
            return (((curr_state >> core#PPWRSV) & 1) == 0)

    state := ((curr_state & core#PPWRSV_MASK) | state)
    writereg(core#PHCON1, 1, @state)

PUB PHYReset{} | tmp    'XXX tentatively named
' Reset PHY
    tmp := core#PRST_BITS
    writereg(core#PHCON1, 1, @tmp)
    tmp := 0

    { poll the chip and wait for the PRST bit to clear automatically }
    repeat
        readreg(core#PHCON1, 1, @tmp)
    while (tmp & core#PRST_BITS)

PUB PktCnt{}: pcnt
' Get count of packets received
'   Returns: u8
'   NOTE: If this value reaches/exceeds 255, any new packets received will be
'       aborted, even if space exists in the device's FIFO.
'       Bit 0 (RXERIF) will be set in Interrupt()
'       When packets are "read", the counter must be decremented using PktDec()
    pcnt := 0
    readreg(core#EPKTCNT, 1, @pcnt)

PUB PktCtrl(mask)
' Set per-packet control mask
'   Bits: 3..0
'       3: huge frame enable
'           1: packet will be transmitted in whole
'           0: MAC will transmit up to MaxFrameLen() bytes, after which
'               the packet will be aborted
'       2: padding enable
'           1: packet will be zero-padded to 60 bytes
'           0: no padding will be added
'       1: CRC enable
'           1: if 'override' == 1, CRC will be appended to frame
'           0: no CRC will be appended; the last four bytes of the frame
'               will be checked for validity as a CRC
'       0: override
'           1: the above bits will override configuration defined by:
'               FramePadding(), XXX TBD
'           0: the above bits will be ignored and configuration will be
'               defined by FramePadding(), XXX TBD
    mask &= $0f
    txpayload(@mask, 1)

PUB PktDec{}
' Decrement packet counter
'   NOTE: This _must_ be performed after considering a packet to be "read"
    regbits_set(core#ECON2, core#PKTDEC_BITS)

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

PUB RevID{}: id
' Get device revision
    id := 0
    readreg(core#EREVID, 1, @id)

PUB RXEnabled(state): curr_state
' Enable reception of packets
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    case ||(state)
        0:
            regbits_clr(core#ECON1, core#RXEN_BITS)
        1:
            regbits_set(core#ECON1, core#RXEN_BITS)
        other:
            curr_state := 0
            readreg(core#ECON1, 1, @curr_state)
            return (((curr_state >> core#RXEN) & 1) == 1)

PUB RXFlowCtrl(state): curr_state   'XXX tentatively named
' Enable receive flow control
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    curr_state := 0
    readreg(core#MACON1, 1, @curr_state)
    case ||(state)
        0, 1:
            state := ||(state) << core#RXPAUS
        other:
            return (((curr_state >> core#RXPAUS) & 1) == 1)

    state := ((curr_state & core#RXPAUS_MASK) | state)
    writereg(core#MACON1, 1, @state)

PUB RXPayload(ptr_buff, nr_bytes)
' Receive payload from FIFO
'   Valid values:
'       nr_bytes: 1..8191 (dependent on RX and TX FIFO settings)
'   NOTE: ptr_buff must point to a buffer at least nr_bytes long
    case nr_bytes
        1..8191:
            outa[_CS] := 0
            spi.wr_byte(core#RD_BUFF)
            spi.rdblock_lsbf(ptr_buff, nr_bytes)
            outa[_CS] := 1

PUB TXDefer(state): curr_state  'XXX tentatively named
' Defer transmission
'   Valid values:
'       TRUE (-1 or 1): MAC waits indefinitely for medium to become free
'           if it's occupied (when attempting to transmit)
'       FALSE (0): MAC aborts transmission after deferral limit reached
'   Any other value polls the chip and returns the current setting
'   NOTE: Applies _only_ when FullDuplex() == FALSE
'   NOTE: Set to TRUE for IEEE 802.3 compliance
    curr_state := 0
    readreg(core#MACON4, 1, @curr_state)
    case ||(state)
        0, 1:
            state := ||(state) << core#DEFER
        other:
            return (((curr_state >> core#DEFER) & 1) == 1)

    state := ((curr_state & core#DEFER_MASK) | state)
    writereg(core#MACON4, 1, @state)

PUB TXEnabled(state): curr_state | checked
' Enable transmission of packets
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    case ||(state)
        0:
            regbits_clr(core#ECON1, core#TXRTS_BITS)
        1:
            { ERRATA: (B5): #10 - Reset transmit logic before send }
            regbits_set(core#ECON1, core#TXRST_BITS)
            regbits_clr(core#ECON1, core#TXRST_BITS)
            regbits_set(core#ECON1, core#TXRTS_BITS)
            repeat checked from 1 to 15
                if (interrupt{} & (core#TXERIF | core#TXIF))
                    quit
                if (checked => 15)
                    curr_state := core#TXERIF   'XXX establish error codes
                time.usleep(250)
        other:
            curr_state := 0
            readreg(core#ECON1, 1, @curr_state)
            return (((curr_state >> core#TXRTS) & 1) == 1)
    regbits_clr(core#ECON1, core#TXRTS_BITS)

PUB TXFlowCtrl(state): curr_state   'XXX tentatively named
' Enable transmit flow control
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    curr_state := 0
    readreg(core#MACON1, 1, @curr_state)
    case ||(state)
        0, 1:
            state := ||(state) << core#TXPAUS
        other:
            return (((curr_state >> core#TXPAUS) & 1) == 1)

    state := ((curr_state & core#TXPAUS_MASK) | state)
    writereg(core#MACON1, 1, @state)

PUB TXPayload(ptr_buff, nr_bytes)
' Queue payload to be transmitted
'   Valid values:
'       nr_bytes: 1..8191 (dependent on RX and TX FIFO settings)
'   NOTE: ptr_buff must point to a buffer at least nr_bytes long
    case nr_bytes
        1..8191:
            outa[_CS] := 0
            spi.wr_byte(core#WR_BUFF)
            spi.wrblock_lsbf(ptr_buff, nr_bytes)
            outa[_CS] := 1

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
            _curr_bank := (curr_bank & core#BSEL_BITS)
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

PRI MIIReady{}: flag
' Get MII readiness status
'   Returns: TRUE (-1) or FALSE (0)
    banksel(3)
    flag := 0
    outa[_CS] := 0
    spi.wr_byte(core#RD_CTRL | core#MISTAT)
    spi.rd_byte{}                               ' dummy read
    { flag logic: is BUSY bit clear? i.e., are you _not_ busy? }
    flag := ((spi.rd_byte & core#BUSY_BITS) == 0)
    outa[_CS] := 1

CON

    { register definition byte indexes }
    REGNR   = 0
    BANK    = 1
    TYPE    = 2

    { device submodule }
    ETH     = 0
    MAC     = 1
    MII     = 2
    PHY     = 3

PRI readReg(reg_nr, nr_bytes, ptr_buff) | i
' Read nr_bytes from the device into ptr_buff
    case reg_nr.byte[TYPE]
        ETH:                                    ' Ethernet regs
            banksel(reg_nr.byte[BANK])
            case reg_nr.byte[REGNR]             ' validate register num
                $00..$19, $1b..$1f:
                    repeat i from 0 to nr_bytes-1
                        outa[_CS] := 0
                        spi.wr_byte(core#RD_CTRL | reg_nr.byte[REGNR]+i)
                        byte[ptr_buff][i] := spi.rd_byte{}
                        outa[_CS] := 1
                    return
                other:                          ' invalid reg_nr
                    return
        MAC, MII:                               ' MAC or MII regs
            banksel(reg_nr.byte[BANK])
            case reg_nr.byte[REGNR]
                $00..$19, $1b..$1f:
                    repeat i from 0 to nr_bytes-1
                        outa[_CS] := 0
                        spi.wr_byte(core#RD_CTRL | reg_nr.byte[REGNR]+i)
                        spi.rd_byte{}           ' dummy read (required)
                        byte[ptr_buff][i] := spi.rd_byte{}
                        outa[_CS] := 1
                    return
                other:
                    return
        PHY:                                    ' PHY regs
            banksel(2)                          ' for MIREGADR
            outa[_CS] := 0
            spi.wr_byte(core#WR_CTRL | core#MIREGADR)
            spi.wr_byte(reg_nr.byte[REGNR])
            outa[_CS] := 1

            outa[_CS] := 0
            spi.wr_byte(core#WR_CTRL | core#MICMD)
            spi.wr_byte(core#MIIRD_BITS)
            outa[_CS] := 1
            time.usleep(11)                     ' 10.24uS

            repeat until miiready{}

            banksel(2)
            outa[_CS] := 0
            spi.wr_byte(core#WR_CTRL | core#MICMD)
            spi.wr_byte(0)
            outa[_CS] := 1

            outa[_CS] := 0
            spi.wr_byte(core#RD_CTRL | core#MIRDL)
            spi.rd_byte{}                       ' dummy read
            byte[ptr_buff][0] := spi.rd_byte{}
            outa[_CS] := 1

            outa[_CS] := 0
            spi.wr_byte(core#RD_CTRL | core#MIRDH)
            spi.rd_byte{}
            byte[ptr_buff][1] := spi.rd_byte{}
            outa[_CS] := 1

PRI regBits_Clr(reg, field)
' Clear bitfield 'field' in Ethernet register 'reg'
    outa[_CS] := 0
    spi.wr_byte(core#BFC | reg)
    spi.wr_byte(field)
    outa[_CS] := 1

PRI regBits_Set(reg, field)
' Set bitfield 'field' in Ethernet register 'reg'
    outa[_CS] := 0
    spi.wr_byte(core#BFS | reg)
    spi.wr_byte(field)
    outa[_CS] := 1

PRI writeReg(reg_nr, nr_bytes, ptr_buff) | i
' Write nr_bytes to the device from ptr_buff
    case reg_nr.byte[TYPE]
        ETH, MAC, MII:                          ' Ethernet, MAC, MII regs
            banksel(reg_nr.byte[BANK])
            case reg_nr.byte[REGNR]
                $00..$19, $1b..$1f:
                    repeat i from 0 to nr_bytes-1
                        outa[_CS] := 0
                        spi.wr_byte(core#WR_CTRL | reg_nr.byte[REGNR]+i)
                        spi.wr_byte(byte[ptr_buff][i])
                        outa[_CS] := 1
                other:
                    return
        PHY:                                    ' PHY regs
            banksel(2)                          ' for MIREGADR
            outa[_CS] := 0
            spi.wr_byte(core#WR_CTRL | core#MIREGADR)
            spi.wr_byte(reg_nr.byte[REGNR])
            outa[_CS] := 1

            outa[_CS] := 0
            spi.wr_byte(core#WR_CTRL | core#MIWRL)
            spi.wr_byte(byte[ptr_buff][0])
            outa[_CS] := 1

            outa[_CS] := 0
            spi.wr_byte(core#WR_CTRL | core#MIWRH)
            spi.wr_byte(byte[ptr_buff][1])
            outa[_CS] := 1

            repeat until miiready{}

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
