# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import platform
from hardware_test_tools.XcoreApp import XcoreApp
from xscope_host import XscopeControl

class XcoreAppControl(XcoreApp):
    """
    Class containing host side functions used for communicating with the XMOS device (DUT) over xscope port.
    These are wrapper functions that run the C++ xscope host application which actually communicates with the DUT over xscope.
    It is derived from XcoreApp which xruns the DUT application with the --xscope-port option.
    """
    def __init__(self, adapter_id, xe_name, attach=None, verbose=False, xrun_xcore_app=True):
        """
        Initialise the XcoreAppControl class. This compiles the xscope host application (host/xscope_controller).
        It also calls init for the base class XcoreApp, which xruns the XMOS device application (DUT) such that the host app
        can communicate to it over xscope port

        Parameter: compiled DUT application binary
        adapter-id: adapter ID of the XMOS device
        """
        self.xrun_app = xrun_xcore_app
        self.verbose = verbose
        assert platform.system() in ["Darwin", "Linux"]
        if self.xrun_app: # This is the default behaviour where the xcore application is also run as part of this class
            super().__init__(xe_name, adapter_id, attach=attach)
            assert self.attach == "xscope_app"
        else: # User responsible for xrunning the xcore application. Only do the xscope control stuff
            # note that this is a debug only option and the xscope_port is hardcoded to '12345'
            # The user is expected to do  'xrun --xscope-port localhost:12345 <xe application>' in a separate terminal
            # This is useful when debugging a suspected crash of the xe application.
            self.xscope_port = "12345"
        self.xscope_host = None



    def __enter__(self):
        if self.xrun_app: # Start the xrun process
            super().__enter__()
        # self.xscope_port is only set in XcoreApp.__enter__(), so xscope_host can only be created here and not in XcoreAppControl's constructor
        self.xscope_host = XscopeControl("localhost", f"{self.xscope_port}", verbose=self.verbose)
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.xrun_app: # Kill the xrun process
            self.terminate()
