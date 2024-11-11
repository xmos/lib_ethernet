// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

// Contains macros and workarounds for both rendering sphynx docs (with XC) and compilation

#if defined(__XC__)
#define static_const_size_t static const size_t
#define static_const_unsigned_t static const unsigned
#define in_port_t in port
#define out_port_t out port
#define typedef_interface typedef interface
#define nullable_streaming_chanend_t streaming chanend ?
#define XC_COMBINABLE [[combinable]]
#define XC_NOTIFICATION [[notification]]
#define XC_CLEARS_NOTIFICATION [[clears_notification]]
#define XC_DISTRIBUTABLE [[distributable]]
#elif defined(__DOXYGEN__)
#define XC_DISTRIBUTABLE
#define static_const_size_t const size_t
#define static_const_unsigned_t const unsigned
#define typedef_interface typedef struct
// Other predefinitions for doxy can be found in docs/Doxyfile.inc
#endif
