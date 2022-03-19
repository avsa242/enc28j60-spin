# enc28j60-spin 
---------------

This is a P8X32A/Propeller, P2X8C4M64P/Propeller 2 driver object for the ENC28J60 10BaseT Ethernet Controller

**IMPORTANT**: This software is meant to be used with the [spin-standard-library](https://github.com/avsa242/spin-standard-library) (P8X32A) or [p2-spin-standard-library](https://github.com/avsa242/p2-spin-standard-library) (P2X8C4M64P). Please install the applicable library first before attempting to use this code, otherwise you will be missing several files required to build the project.

## Salient Features

* SPI connection at 20MHz W/10MHz R (P1)
* Half and Full-duplex operation
* FIFO control: auto-increment pointer, manually set read and write pointers, set read and write regions within FIFO
* Frame control: Optional frame padding (none, 60, 64 bytes), maximum frame length
* Collision control: backoff, collision window
* Packet timing: inter-packet gap delay, (back-to-back and not, full and half-duplex independently)
* Interrupt flags: received packet, DMA operation, PHY link status, TX complete/error, RX error
* PHY control: LED modes, hysteresis, loopback
* Packet filtering: unicast, CRC check, pattern match, magic packet, hash table, multicast, broadcast
* Flow control: TX, RX

## Requirements

P1/SPIN1:
* spin-standard-library

~~P2/SPIN2:~~
* ~~p2-spin-standard-library~~

## Compiler Compatibility

* P1/SPIN1 OpenSpin (bytecode): Untested (deprecated)
* P1/SPIN1 FlexSpin (bytecode): OK, tested with 5.9.9-beta
* P1/SPIN1 FlexSpin (native): OK, tested with 5.9.9-beta
* ~~P2/SPIN2 FlexSpin (nu-code):~~ _(not yet implemented)_
* ~~P2/SPIN2 FlexSpin (native):~~ _(not yet implemented)_
* ~~BST~~ (incompatible - no preprocessor)
* ~~Propeller Tool~~ (incompatible - no preprocessor)
* ~~PNut~~ (incompatible - no preprocessor)

## Limitations

* Very early in development - may malfunction, or outright fail to build
* Draft version - __WARNING__: Preliminary/unstable API
* Duplex is not advertised automatically by the chip; when switching between half/full duplex in the driver, the same __must__ be manually configured on the remote node

