ifeq ($(USING_XWAF),1)
all:
	xwaf configure build --config $(CONFIG)
else # USING_XWAF
# The TARGET variable determines what target system the application is 
# compiled for. It either refers to an XN file in the source directories
# or a valid argument for the --target option when compiling.

TARGET = XK-1A

# The APP_NAME variable determines the name of the final .xe file. It should
# not include the .xe postfix. If left blank the name will default to 
# the project name

APP_NAME =

# The flags passed to xcc when building the application
# You can also set the following to override flags for a particular language:
#
#    XCC_XC_FLAGS, XCC_C_FLAGS, XCC_ASM_FLAGS, XCC_CPP_FLAGS
#
# If the variable XCC_MAP_FLAGS is set it overrides the flags passed to
# xcc for the final link (mapping) stage.

SHARED_CODE = ../../include

COMMON_FLAGS = -g -report -DDEBUG_PRINT_ENABLE -save-temps -Os -Xmapper --map -Xmapper MAPFILE -I$(SHARED_CODE)

XCC_FLAGS_rt_mii       = $(COMMON_FLAGS) -DRT=1 -DRGMII=0
XCC_FLAGS_rt_rgmii     = $(COMMON_FLAGS) -DRT=0 -DRGMII=1 -fno-xta-info

ifeq ($(CONFIG),rt_mii)
	TARGET = STARTKIT
endif

ifeq ($(CONFIG),rt_rgmii)
	TARGET = XCORE-200-EXPLORER
endif

# The USED_MODULES variable lists other module used by the application.

USED_MODULES = lib_ethernet

#=============================================================================
# The following part of the Makefile includes the common build infrastructure
# for compiling XMOS applications. You should not need to edit below here.

XMOS_MAKE_PATH ?= ../..
include $(XMOS_MAKE_PATH)/xcommon/module_xcommon/build/Makefile.common
endif # USING_XWAF
