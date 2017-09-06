// Copyright (c) 2014-2017, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "mii.h"
#include "debug_print.h"
#include "syscall.h"
#include "seed.inc"

#include "ports.h"

port p_ctrl = on tile[0]: XS1_PORT_1C;
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
