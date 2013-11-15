#ifndef __ethernet_board_defaults_h__
#define __ethernet_board_defaults_h__

/*  Port defines for the STAR slice */
#define SLICEKIT_STAR_ETH_TILE 0
#define SLICEKIT_STAR_MII_PORTS(clk1, clk2)  \
  on tile[0]: { \
    clk1, clk2, \
    XS1_PORT_1B, /* RXCLK */ \
    XS1_PORT_4D, /* RXERR */ \
    XS1_PORT_4A, /* RXD */ \
    XS1_PORT_1C, /* RXDV */ \
    XS1_PORT_1G, /* TXCLK */ \
    XS1_PORT_1F, /* TXEN */ \
    XS1_PORT_4B  /* TXD */ }
#define SLICEKIT_STAR_SMI_PORTS on tile[0]: { null, XS1_PORT_4C }

/*  Port defines for the TRIANGLE slice */
#define SLICEKIT_TRIANGLE_ETH_TILE 0
#define SLICEKIT_TRIANGLE_MII_PORTS(clk1, clk2)  \
  on tile[0]: { \
    clk1, clk2, \
    XS1_PORT_1J, /* RXCLK */ \
    XS1_PORT_1P, /* RXERR */ \
    XS1_PORT_4E, /* RXD */ \
    XS1_PORT_1K, /* RXDV */ \
    XS1_PORT_1I, /* TXCLK */ \
    XS1_PORT_1L, /* TXEN */ \
    XS1_PORT_4F  /* TXD */ }
#define SLICEKIT_TRIANGLE_SMI_PORTS on tile[0]: { XS1_PORT_1M, XS1_PORT_1N }

/*  Port defines for the SQUARE slice */
#define SLICEKIT_SQUARE_ETH_TILE 1
#define SLICEKIT_SQUARE_MII_PORTS(clk1, clk2)  \
  on tile[1]: { \
    clk1, clk2, \
    XS1_PORT_1B, /* RXCLK */ \
    XS1_PORT_4D, /* RXERR */ \
    XS1_PORT_4A, /* RXD */ \
    XS1_PORT_1C, /* RXDV */ \
    XS1_PORT_1G, /* TXCLK */ \
    XS1_PORT_1F, /* TXEN */ \
    XS1_PORT_4B  /* TXD */ }
#define SLICEKIT_SQUARE_SMI_PORTS on tile[1]: { null, XS1_PORT_4C }

/*  Port defines for the CIRCLE slice */
#define SLICEKIT_CIRCLE_ETH_TILE 1
#define SLICEKIT_CIRCLE_MII_PORTS(clk1, clk2)  \
  on tile[1]: { \
    clk1, clk2, \
    XS1_PORT_1J, /* RXCLK */ \
    XS1_PORT_1P, /* RXERR */ \
    XS1_PORT_4E, /* RXD */ \
    XS1_PORT_1K, /* RXDV */ \
    XS1_PORT_1I, /* TXCLK */ \
    XS1_PORT_1L, /* TXEN */ \
    XS1_PORT_4F  /* TXD */ }
#define SLICEKIT_CIRCLE_SMI_PORTS on tile[1]: { XS1_PORT_1M, XS1_PORT_1N }

// Generic defines (default to the CIRCLE slice)
#define XMOS_DEV_BOARD_ETH_TILE              SLICEKIT_CIRCLE_ETH_TILE
#define XMOS_DEV_BOARD_MII_PORTS(clk1, clk2) SLICEKIT_CIRCLE_MII_PORTS(clk1, clk2)
#define XMOS_DEV_BOARD_SMI_PORTS             SLICEKIT_CIRCLE_SMI_PORTS

#define XMOS_DEV_BOARD_RESET_PORT null
#define XMOS_DEV_BOARD_PHY_ADDRESS 0

#define SMI_MDC_BIT 0
#define SMI_MDIO_BIT 1
#endif // __ethernet_board_defaults_h__
