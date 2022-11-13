{
    --------------------------------------------
    Filename: net.eth.enc28j60.spin
    Author: Jesse Burt
    Description: Driver for the ENC28J60 Ethernet Transceiver
    Copyright (c) 2022
    Started Feb 21, 2022
    Updated Nov 13, 2022
    See end of file for terms of use.
    --------------------------------------------
}
#include "protocol.net.eth-ii.spin"
#include "protocol.net.ip.spin"
#include "protocol.net.arp.spin"
#include "protocol.net.udp.spin"
#include "protocol.net.bootp.spin"
#include "protocol.net.icmp.spin"
#include "protocol.net.tcp.spin"
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

    spi : "com.spi.20mhz"                   ' PASM SPI engine (20MHz W/10R)
    core: "core.con.enc28j60"                   ' hw-specific constants
    time: "time"                                ' Basic timing functions

PUB null{}
' This is not a top-level object

PUB startx(CS_PIN, SCK_PIN, MOSI_PIN, MISO_PIN): status
' Start using custom IO pins
    if lookdown(CS_PIN: 0..31) and lookdown(SCK_PIN: 0..31) and {
}   lookdown(MOSI_PIN: 0..31) and lookdown(MISO_PIN: 0..31)
        if (status := spi.init(SCK_PIN, MOSI_PIN, MISO_PIN, core#SPI_MODE))
            time.msleep(core#T_POR)             ' wait for device startup
            _CS := CS_PIN                       ' copy i/o pin to hub var
            outa[_CS] := 1
            dira[_CS] := 1
            _curr_bank := -1                    ' establish initial bank

            repeat until clk_ready{}
            reset{}
            time.msleep(30)
            return
    ' if this point is reached, something above failed
    ' Re-check I/O pin assignments, bus speed, connections, power
    ' Lastly - make sure you have at least one free core/cog
    return FALSE

PUB stop{}
' Stop the driver
    spi.deinit{}
    _CS := _curr_bank := 0

PUB defaults{}
' Set factory defaults

CON
' XXX temporary
    TX_BUFFER_SIZE  = 1518
    RXSTART         = 0
    RXSTOP          = (TXSTART - 2) | 1                 '6665
    TXSTART         = 8192 - (TX_BUFFER_SIZE + 8)       '6666
    TXEND           = TXSTART + (TX_BUFFER_SIZE + 8)    '8192 (xxx - shouldn't this be 8191?)

PUB preset_fdx{}
' Preset settings; full-duplex
    rx_ena(false)
    tx_ena(false)

    { set up on-chip FIFO }
    fifo_set_ptr_auto_inc(true)
    fifo_set_rd_ptr(RXSTART)
    fifo_set_rx_start(RXSTART)
    fifo_set_rx_rd_ptr(RXSTOP)
    fifo_set_rx_end(RXSTOP)
    fifo_set_tx_start(TXSTART)

    mac_rx_ena(true)
    rx_flow_ctrl_ena(true)
    tx_flow_ctrl_ena(true)

    frame_len_check_ena(true)
    frame_padding_mode(PAD60)

    tx_defer_ena(true)

    set_collision_win(63)

    set_inter_pkt_gap(18)
    set_inter_pkt_gap_hdx(12)

    set_max_frame_len(1518)

    set_b2b_inter_pkt_gap(18)

    hdx_loopback_ena(false)

    phy_loopback_ena(false)
    phy_powered(true)
    phy_full_duplex_ena(true)
    full_duplex_ena(true)

    phy_led_a_mode(%100)                        ' LED A: display link status
    phy_led_b_mode(%111)                        ' LED B: display tx/rx activity
    phy_led_stretch(true)                       ' lengthen LED pulses
    rx_ena(true)

PUB b2b_inter_pkt_gap{}: curr_dly
' Get inter-packet gap delay for back-to-back packets
    curr_dly := 0
    readreg(core#MABBIPG, 1, @curr_dly)

PUB set_b2b_inter_pkt_gap(dly)  'XXX tentatively named
' Set inter-packet gap delay for back-to-back packets
'   Valid values: 0..127
'   NOTE: When full_duplex_ena() == 1, recommended setting is 21
'       When full_duplex_ena() == 0, recommended setting is 18
    dly := 0 #> dly <# 127
    writereg(core#MABBIPG, 1, @dly)

PUB backoff(state): curr_state  'XXX tentatively named
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

PUB backpress_backoff(state): curr_state 'XXX tentatively named
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

PUB calc_chksum{}
' Use DMA engine to calculate checksum
    regbits_set(core#ECON1, core#CALC_CKSUM)

PUB clk_ready{}: status
' Flag indicating clock is ready
'   Returns: TRUE (-1) or FALSE (0)
    status := 0
    readreg(core#ESTAT, 1, @status)
    return ((status & core#CLKRDY_BITS) == 1)

PUB collision_win{}: curr_nr
' Get current collision window length
    curr_nr := 0
    readreg(core#MACLCON2, 1, @curr_nr)

PUB set_collision_win(nr_bytes): curr_nr 'XXX tentatively named
' Set collision window, in number of bytes
'   Valid values: 0..63 (default: 55)
'   NOTE: Applies only when full_duplex_ena() == 0
    nr_bytes := 0 #> nr_bytes <# 63
    writereg(core#MACLCON2, 1, @nr_bytes)

PUB dma_ready{}: flag
' Flag indicating DMA engine is ready
    flag := 0
    readreg(core#ECON1, 1, @flag)
    return ((flag & core#DMAST_BITS) == 0)

PUB fifo_ptr_auto_inc{}: curr_state

    curr_state := 0
    readreg(core#ECON2, 1, @curr_state)
    return (((curr_state >> core#AUTOINC) & 1) == 1)

PUB fifo_set_ptr_auto_inc(state)
' Auto-increment FIFO pointer when writing
'   Valid values: TRUE (-1) or FALSE (0)
'   Any other value polls the chip and returns the current setting
'   NOTE: When reached the end of the FIFO, the pointer wraps to the start
    if (state)
        regbits_set(core#ECON2, core#AUTOINC_BITS)
    else
        regbits_clr(core#ECON2, core#AUTOINC_BITS)

PUB fifo_set_rd_ptr(rxpos)
' Set read position within FIFO
'   Valid values: 0..8191
    rxpos := 0 #> rxpos <# FIFO_MAX
    writereg(core#ERDPTL, 2, @rxpos)

PUB fifo_rd_ptr{}: curr_ptr
' Get current read position within FIFO
    curr_ptr := 0
    readreg(core#ERDPTL, 2, @curr_ptr)

PUB fifo_set_rx_end(rxe)
' Set ending position within FIFO for RX region
'   Valid values: 0..8191
    rxe := 0 #> rxe <# FIFO_MAX
    writereg(core#ERXNDL, 2, @rxe)

PUB fifo_rx_end{}: r_end
' Get end of receive region within FIFO
    r_end := 0
    readreg(core#ERXNDL, 2, @r_end)

PUB fifo_set_rx_rd_ptr(rxrd)
' Set read pointer within receive region of FIFO
'   Valid values: 0..8191
    rxrd := 0 #> rxrd <# FIFO_MAX
    writereg(core#ERXRDPTL, 2, @rxrd)

PUB fifo_rx_rd_ptr{}: curr_ptr
' Get current read pointer within receive region of FIFO
    curr_ptr := 0
    readreg(core#ERXRDPTL, 2, @curr_ptr)

PUB fifo_set_rx_wr_ptr(rxwr)
' Set pointer in FIFO where received data will be written
'   Valid values: 0..8191
    rxwr := 0 #> rxwr <# FIFO_MAX
    writereg(core#ERXWRPTL, 2, @rxwr)

PUB fifo_rx_wr_ptr{}: curr_ptr
' Get current write pointer within receive region of FIFO
    curr_ptr := 0
    readreg(core#ERXWRPTL, 2, @curr_ptr)

PUB fifo_set_rx_start(rxs): curr_ptr
' Set start of receive region within FIFO
'   Valid values: 0..8191
    rxs := 0 #> rxs <# FIFO_MAX
    writereg(core#ERXSTL, 2, @rxs)

PUB fifo_rx_start{}: r_st
' Get start of receive region within FIFO
    r_st := 0
    readreg(core#ERXSTL, 2, @r_st)

PUB fifo_set_tx_end(txe)
' Set end of transmit region within FIFO
'   Valid values: 0..8191
    txe := 0 #> txe <# FIFO_MAX
    writereg(core#ETXNDL, 2, @txe)

PUB fifo_tx_end{}: t_end
' Get end of transmit region within FIFO
    t_end := 0
    readreg(core#ETXNDL, 2, @t_end)

PUB fifo_set_tx_start(txs)
' Set start of transmit region within FIFO
'   Valid values: 0..8191
    txs := 0 #> txs <# FIFO_MAX
    writereg(core#ETXSTL, 2, @txs)

PUB fifo_tx_start{}: txs
' Get start of transmit region within FIFO
    txs := 0
    readreg(core#ETXSTL, 2, @txs)

PUB fifo_set_wr_ptr(ptr)
' Set write pointer within FIFO
'   Valid values: 0..8191
    ptr := 0 #> ptr <# FIFO_MAX
    writereg(core#EWRPTL, 2, @ptr)

PUB fifo_wr_ptr{}: curr_ptr
' Get current write pointer within FIFO
    curr_ptr := 0
    readreg(core#EWRPTL, 2, @curr_ptr)

PUB frame_len_check_ena(state): curr_state    'XXX tentatively named
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

PUB frame_padding_mode(mode): curr_md | txcrcen    'XXX tentatively named
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

PUB full_duplex_ena(state): curr_state
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

PUB get_node_address(ptr_addr)
' Get this node's currently set MAC address
'   NOTE: Buffer pointed to by ptr_addr must be 6 bytes long
    readreg(core#MAADR1, 1, ptr_addr+5)         '
    readreg(core#MAADR2, 1, ptr_addr+4)         ' OUI
    readreg(core#MAADR3, 1, ptr_addr+3)         '
    readreg(core#MAADR4, 1, ptr_addr+2)
    readreg(core#MAADR5, 1, ptr_addr+1)
    readreg(core#MAADR6, 1, ptr_addr)

PUB hdx_loopback_ena(state): curr_state
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

PUB inet_chksum(ck_st, ck_end, ck_dest): chk | st, nd, ck
' Calculate checksum of frame in buffer and store the result
'   ck_st: start of frame data to checksum
'   ck_end: end of frame data to checksum
'   ck_dest: location in frame data to write checksum to
    ck_st += TXSTART+1
    ck_end += TXSTART

    writereg(core#EDMASTL, 2, @ck_st)
    writereg(core#EDMANDL, 2, @ck_end)
    readreg(core#EDMASTL, 2, @st)
    readreg(core#EDMANDL, 2, @nd)

    { ERRATA #15: Wait for receive to finish }
    repeat while rx_busy{}

    calc_chksum{}

    repeat until dma_ready{}

    ck_end := ck_dest + TXSTART+1

    chk := 0
    readreg(core#EDMACSL, 2, @chk)

    fifo_set_wr_ptr(ck_end)

    wrword_msbf(chk)

PUB int_clear(mask)
' Clear interrupts
'   Valid values:
'       Bits: 6..3, 1, 0 (set a bit to clear the corresponding interrupt flag)
'       6: packet received
'       5: DMA copy or checksum calculation has completed
'       4: link established
'       3: transmit has ended
'       1: transmit error
'       0: receive error: insufficient buffer space
'   Any other value is ignored
    mask &= core#EIR_CLRBITS
    writereg(core#EIR, 1, @mask)

PUB inter_pkt_gap{}: curr_dly
' Get inter-packet gap delay for _non_-back-to-back packets
    curr_dly := 0
    readreg(core#MAIPGL, 1, @curr_dly)

PUB set_inter_pkt_gap(dly) 'XXX tentatively named
' Set inter-packet gap delay for _non_-back-to-back packets
'   Valid values: 0..127
'   NOTE: Recommended setting is $12
    dly := 0 #> dly <# 127
    writereg(core#MAIPGL, 1, @dly)

PUB inter_pkt_gap_hdx{}: curr_dly
' Get inter-packet gap delay for _non_-back-to-back packets (half-duplex mode)
    curr_dly := 0
    readreg(core#MAIPGH, 1, @curr_dly)

PUB set_inter_pkt_gap_hdx(dly): curr_dly  'XXX tentatively named
' Set inter-packet gap delay for _non_-back-to-back packets (half-duplex mode)
'   Valid values: 0..127
'   Any other value polls the chip and returns the current setting
'   NOTE: Recommended setting is $0C
    dly := 0 #> dly <# 127
    writereg(core#MAIPGH, 1, @dly)

PUB interrupt{}: int_src
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

PUB int_mask(mask)
' Enable interrupt flags
'   Valid values:
'       Bits: 6..3, 1, 0
'       6: packet received
'       5: DMA copy or checksum calculation has completed
'       4: link established
'       3: transmit has ended
'       1: transmit error
'       0: receive error: insufficient buffer space
    mask &= core#EIE_MASK
    writereg(core#EIE, 1, @mask)

PUB mac_rx_ena(state): curr_state 'XXX tentative name
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

PUB max_frame_len{}: curr_len
' Get maximum frame length
    curr_len := 0
    readreg(core#MAMXFLL, 2, @curr_len)

PUB set_max_frame_len(len)
' Set maximum frame length
'   Valid values: 0..65535 (clamped to range)
    len := 0 #> len <# 65535
    writereg(core#MAMXFLL, 2, @len)

PUB max_retransmits{}: curr_max
' Get maximum number of retransmissions
    curr_max := 0
    readreg(core#MACLCON1, 1, @curr_max)

PUB set_max_retransmits(max_nr)
' Set maximum number of retransmissions
'   Valid values: 0..15 (clamped to range; default: 15)
'   NOTE: Applies only when full_duplex_ena() == 0
    max_nr := 0 #> max_nr <# 15
    writereg(core#MACLCON1, 1, @max_nr)

PUB node_address(ptr_addr)
' Set this node's MAC address
'   Valid values: pointer to 6-byte MAC address (OUI in MSB)
    writereg(core#MAADR1, 1, ptr_addr+5)        '
    writereg(core#MAADR2, 1, ptr_addr+4)        ' OUI
    writereg(core#MAADR3, 1, ptr_addr+3)        '
    writereg(core#MAADR4, 1, ptr_addr+2)
    writereg(core#MAADR5, 1, ptr_addr+1)
    writereg(core#MAADR6, 1, ptr_addr)

PUB phy_full_duplex_ena(state): curr_state    'XXX tentatively named
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

PUB phy_led_a_mode(mode): curr_md  'XXX tentatively named
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

PUB phy_led_b_mode(mode): curr_md    'XXX tentatively named
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

PUB phy_led_stretch(state): curr_state    'XXX tentatively named
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

PUB phy_link_state{}: state    'XXX tentatively named
' Get PHY Link state
'   Returns:
'       DOWN (0): link down
'       UP (1): link up
    state := 0
    readreg(core#PHSTAT2, 1, @state)
    return ((state >> core#LSTAT) & 1)

PUB phy_loopback_ena(state): curr_state    'XXX tentatively named
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

PUB phy_powered(state): curr_state    'XXX tentatively named
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

PUB phy_reset{} | tmp    'XXX tentatively named
' Reset PHY
    tmp := core#PRST_BITS
    writereg(core#PHCON1, 1, @tmp)
    tmp := 0

    { poll the chip and wait for the PRST bit to clear automatically }
    repeat
        readreg(core#PHCON1, 1, @tmp)
    while (tmp & core#PRST_BITS)

PUB pkt_cnt{}: pcnt
' Get count of packets received
'   Returns: u8
'   NOTE: If this value reaches/exceeds 255, any new packets received will be
'       aborted, even if space exists in the device's FIFO.
'       Bit 0 (RXERIF) will be set in Interrupt()
'       When packets are "read", the counter must be decremented using PktDec()
    pcnt := 0
    readreg(core#EPKTCNT, 1, @pcnt)

PUB pkt_ctrl(mask)
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
    tx_payload(@mask, 1)

PUB pkt_dec{}
' Decrement packet counter
'   NOTE: This _must_ be performed after considering a packet to be "read"
    regbits_set(core#ECON2, core#PKTDEC_BITS)

PUB pkt_filter{}: fmask
' Get current packet filter mask
    fmask := 0
    readreg(core#ERXFCON, 1, @fmask)

PUB set_pkt_filter(mask)  'XXX tentative name and interface
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
    mask &= $ff
    writereg(core#ERXFCON, 1, @mask)

PUB rdblk_lsbf(ptr_buff, len): ptr
' Read a block of data from the FIFO, LSByte-first
'   len: number of bytes to read
    outa[_CS] := 0
    spi.wr_byte(core#RD_BUFF)
    spi.rdblock_lsbf(ptr_buff, 1 #> len <# FIFO_MAX)
    outa[_CS] := 1

PUB rdblk_msbf(ptr_buff, len): ptr | i
' Read a block of data from the FIFO, MSByte-first
'   len: number of bytes to read
    outa[_CS] := 0
    spi.wr_byte(core#RD_BUFF)
    repeat i from (1 #> len <# FIFO_MAX)-1 to 0
        byte[ptr_buff][i] := spi.rd_byte{}
    outa[_CS] := 1

PUB rd_byte{}: b
' Read a byte of data from the FIFO
    outa[_CS] := 0
    spi.wr_byte(core#RD_BUFF)
    b := spi.rd_byte{}
    outa[_CS] := 1

PUB rdlong_lsbf{}: l
' Read a long of data from the FIFO, LSByte-first
    outa[_CS] := 0
    spi.wr_byte(core#RD_BUFF)
    l := spi.rdlong_lsbf{}
    outa[_CS] := 1

PUB rdlong_msbf{}: l | i
' Read a long of data from the FIFO, MSByte-first
    outa[_CS] := 0
    spi.wr_byte(core#RD_BUFF)
    repeat i from 3 to 0
        l.byte[i] := spi.rd_byte{}
    outa[_CS] := 1

PUB rdword_lsbf{}: w
' Read a word of data from the FIFO, LSByte-first
    outa[_CS] := 0
    spi.wr_byte(core#RD_BUFF)
    w := spi.rdword_lsbf{}
    outa[_CS] := 1

PUB rdword_msbf{}: w
' Read a word of data from the FIFO, MSByte-first
    outa[_CS] := 0
    spi.wr_byte(core#RD_BUFF)
    w.byte[1] := spi.rd_byte{}
    w.byte[0] := spi.rd_byte{}
    outa[_CS] := 1

PUB reset{}
' Perform soft-reset
    cmd(core#SRC)

PUB rev_id{}: id
' Get device revision
    id := 0
    readreg(core#EREVID, 1, @id)

PUB rx_busy{}: flag
' Flag indicating chip is busy receiving
    flag := 0
    readreg(core#ESTAT, 1, @flag)
    return ((flag & core#RXBUSY_BITS) <> 0)

PUB rx_enabled = rx_ena
PUB rx_ena(state)
' Enable reception of packets
'   Valid values: TRUE (-1 or 1), FALSE (0)
    if (state)
        regbits_set(core#ECON1, core#RXEN_BITS)
    else
        regbits_clr(core#ECON1, core#RXEN_BITS)

PUB rx_is_ena{}: rxen
' Flag indicating reception of packets is enabled
'   Returns: TRUE (-1) or FALSE
    rxen := 0
    readreg(core#ECON1, 1, @rxen)
    return (((rxen >> core#RXEN) & 1) == 1)

PUB rx_flow_ctrl_ena(state): curr_state   'XXX tentatively named
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

PUB rx_payload(ptr_buff, nr_bytes)
' Receive payload from FIFO
'   Valid values:
'       nr_bytes: 1..8191 (dependent on RX and TX FIFO settings)
'   NOTE: ptr_buff must point to a buffer at least nr_bytes long
    outa[_CS] := 0
    spi.wr_byte(core#RD_BUFF)
    spi.rdblock_lsbf(ptr_buff, 1 #> nr_bytes)
    outa[_CS] := 1

PUB tx_defer_ena(state): curr_state  'XXX tentatively named
' Defer transmission
'   Valid values:
'       TRUE (-1 or 1): MAC waits indefinitely for medium to become free
'           if it's occupied (when attempting to transmit)
'       FALSE (0): MAC aborts transmission after deferral limit reached
'   Any other value polls the chip and returns the current setting
'   NOTE: Applies _only_ when full_duplex_ena() == FALSE
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

PUB tx_enabled = tx_ena
PUB tx_ena(state): curr_state | checked
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

PUB tx_flow_ctrl_ena(state): curr_state   'XXX tentatively named
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

PUB tx_payload(ptr_buff, nr_bytes)
' Queue payload to be transmitted
'   Valid values:
'       nr_bytes: 1..8191 (dependent on RX and TX FIFO settings)
'   NOTE: ptr_buff must point to a buffer at least nr_bytes long
    outa[_CS] := 0
    spi.wr_byte(core#WR_BUFF)
    spi.wrblock_lsbf(ptr_buff, 1 #> nr_bytes <# FIFO_MAX)
    outa[_CS] := 1

PUB wrblk_lsbf(ptr_buff, len): ptr
' Write a block of data to the FIFO, LSByte-first
'   ptr_buff: pointer to buffer of data to copy from
'   len: number of bytes to write
    outa[_CS] := 0
    spi.wr_byte(core#WR_BUFF)
    spi.wrblock_lsbf(ptr_buff, 1 #> len <# FIFO_MAX)
    outa[_CS] := 1

PUB wrblk_msbf(ptr_buff, len): ptr | i
' Write a block of data to the FIFO, MSByte-first
'   ptr_buff: pointer to buffer of data to copy from
'   len: number of bytes to write
    outa[_CS] := 0
    spi.wr_byte(core#WR_BUFF)
    repeat i from len-1 to 0
        spi.wr_byte(byte[ptr_buff][i])
    outa[_CS] := 1

PUB wr_byte(b): len
' Write a byte of data to the FIFO
    outa[_CS] := 0
    spi.wr_byte(core#WR_BUFF)
    spi.wr_byte(b)
    outa[_CS] := 1
    return 1

PUB wr_byte_x(b, nr_bytes): len
' Repeatedly write a byte to the FIFO
'   b: byte to write
'   nr_bytes: number of times to write byte to the FIFO
    outa[_CS] := 0
    spi.wr_byte(core#WR_BUFF)
    repeat nr_bytes
        spi.wr_byte(b)
    outa[_CS] := 1
    return nr_bytes

PUB wrlong_lsbf(l): len
' Write a long of data to the FIFO, LSByte-first
    outa[_CS] := 0
    spi.wr_byte(core#WR_BUFF)
    spi.wrlong_lsbf(l)
    outa[_CS] := 1
    return 4

PUB wrlong_msbf(l): len | i
' Write a long of data to the FIFO, MSByte-first
    outa[_CS] := 0
    spi.wr_byte(core#WR_BUFF)
    repeat i from 3 to 0
        spi.wr_byte(l.byte[i])
    outa[_CS] := 1
    return 4

PUB wrword_lsbf(w): len
' Write a word of data to the FIFO, LSByte-first
    outa[_CS] := 0
    spi.wr_byte(core#WR_BUFF)
    spi.wrword_lsbf(w)
    outa[_CS] := 1
    return 2

PUB wrword_msbf(w): len
' Write a word of data to the FIFO, MSByte-first
    outa[_CS] := 0
    spi.wr_byte(core#WR_BUFF)
    spi.wr_byte(w.byte[1])
    spi.wr_byte(w.byte[0])
    outa[_CS] := 1
    return 2

PRI bank_sel(bank_nr)
' Select register bank
'   Valid values: 0..3
    if (bank_nr == _curr_bank)                  ' leave the bank set as-is if
        return                                  ' it matches the last setting

    regbits_clr(core#ECON1, core#BSEL_BITS)
    regbits_set(core#ECON1, 0 #> bank_nr <# 3)
    _curr_bank := bank_nr

PRI cmd(cmd_nr)
' Send simple command
    case cmd_nr
        core#RD_BUFF, core#WR_BUFF, core#SRC:
            outa[_CS] := 0
            spi.wr_byte(cmd_nr)
            outa[_CS] := 1
        other:
            return

PRI mii_ready{}: flag
' Get MII readiness status
'   Returns: TRUE (-1) or FALSE (0)
    bank_sel(3)
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

PRI readreg(reg_nr, nr_bytes, ptr_buff) | i
' Read nr_bytes from the device into ptr_buff
    case reg_nr.byte[TYPE]
        ETH:                                    ' Ethernet regs
            bank_sel(reg_nr.byte[BANK])
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
            bank_sel(reg_nr.byte[BANK])
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
            bank_sel(2)                          ' for MIREGADR
            outa[_CS] := 0
            spi.wr_byte(core#WR_CTRL | core#MIREGADR)
            spi.wr_byte(reg_nr.byte[REGNR])
            outa[_CS] := 1

            outa[_CS] := 0
            spi.wr_byte(core#WR_CTRL | core#MICMD)
            spi.wr_byte(core#MIIRD_BITS)
            outa[_CS] := 1
            time.usleep(11)                     ' 10.24uS

            repeat until mii_ready{}

            bank_sel(2)
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

PRI regbits_clr(reg_nr, field)
' Clear bitfield 'field' in Ethernet reg_nrister 'reg_nr'
    outa[_CS] := 0
    spi.wr_byte(core#BFC | reg_nr)
    spi.wr_byte(field)
    outa[_CS] := 1

PRI regbits_set(reg_nr, field)
' Set bitfield 'field' in Ethernet reg_nrister 'reg_nr'
    outa[_CS] := 0
    spi.wr_byte(core#BFS | reg_nr)
    spi.wr_byte(field)
    outa[_CS] := 1

PRI writereg(reg_nr, nr_bytes, ptr_buff) | i
' Write nr_bytes to the device from ptr_buff
    case reg_nr.byte[TYPE]
        ETH, MAC, MII:                          ' Ethernet, MAC, MII regs
            bank_sel(reg_nr.byte[BANK])
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
            bank_sel(2)                          ' for MIREGADR
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

            repeat until mii_ready{}

        other:
            return

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

