// Copyright (c) 2015, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>
#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "mii.h"
#include "xta_test_pragmas.h"
#include "debug_print.h"
#include "syscall.h"

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
