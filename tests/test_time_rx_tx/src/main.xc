// Copyright 2014-2021 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "mii.h"
#include "debug_print.h"
#include "syscall.h"
#include "seed.inc"

#if RMII
#include "ports_rmii.h"
#else
#include "ports.h"
port p_test_ctrl = on tile[0]: XS1_PORT_1C;
#endif

#include "control.xc"

#include "helpers.xc"


#if RGMII
  #include "main_rgmii.h"
#else
  #if RT
    #include "main_mii_rt.h"
  #else
    #include "main_mii_standard.h"
  #endif
#endif
