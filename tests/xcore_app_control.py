import platform
from hardware_test_tools.XcoreApp import XcoreApp
from xscope_host import XscopeControl

class XcoreAppControl(XcoreApp):
    """
    Class containing host side functions used for communicating with the XMOS device (DUT) over xscope port.
    These are wrapper functions that run the C++ xscope host application which actually communicates with the DUT over xscope.
    It is derived from XcoreApp which xruns the DUT application with the --xscope-port option.
    """
    def __init__(self, adapter_id, xe_name, attach=None, verbose=False):
        """
        Initialise the XcoreAppControl class. This compiles the xscope host application (host/xscope_controller).
        It also calls init for the base class XcoreApp, which xruns the XMOS device application (DUT) such that the host app
        can communicate to it over xscope port

        Parameter: compiled DUT application binary
        adapter-id: adapter ID of the XMOS device
        """
        self.verbose = verbose
        assert platform.system() in ["Darwin", "Linux"]
        super().__init__(xe_name, adapter_id, attach=attach)
        assert self.attach == "xscope_app"
        self.xscope_host = None

    def __enter__(self):
        super().__enter__()
        # self.xscope_port is only set in XcoreApp.__enter__(), so xscope_host can only be created here and not in XcoreAppControl's constructor
        self.xscope_host = XscopeControl("localhost", f"{self.xscope_port}", verbose=self.verbose)
        return self
