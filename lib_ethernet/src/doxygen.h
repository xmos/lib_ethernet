// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

// Contains macros and workarounds for rendering sphynx docs (with XC) and compilation

#if defined(__XC__)
#define static_const_size_t static const size_t
#define static_const_unsigned_t static const unsigned
#define in_port_t in port
#define out_port_t out port
#define typedef_interface typedef interface
#define nullable_streaming_chanend_t streaming chanend ?
#elif defined(__DOXYGEN__)
#define static_const_size_t const size_t
#define static_const_unsigned_t const unsigned
#define typedef_interface typedef struct
#endif
