# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import platform
from hardware_test_tools.XcoreApp import XcoreApp
from xscope_host import XscopeControl

class XcoreAppControl(XcoreApp):
    """
    Class responsible for running the xcore application with xrun --xscope-port

    This class implements the context management protocol with `__enter__` and `__exit__`.
    """
    def __init__(self, adapter_id, xe_name, verbose=False, xrun_xcore_app=True):
        """
        Initialise the XcoreAppControl class.

        This sets the various class variables to the parameters passed to the __init__() function

        Args:
        adapter_id (str): Target xTAG adapter serial number
        xe_name (str): compiled DUT application binary
        verbose (str, optional, default=False): Enable verbose printing
        run_xcore_app (bool, optional, default=True): Whether or not to run the xcore application. This is useful for debugging
        where the user might want to run the xcore application from a different terminal and see its behaviour.
        For eg. when debugging a suspected crash when running the xcore application.
        """
        self.xrun_app = xrun_xcore_app
        self.verbose = verbose
        assert platform.system() in ["Darwin", "Linux"]
        if self.xrun_app: # This is the default behaviour where the xcore application is also run as part of this class
            super().__init__(xe_name, adapter_id, attach="xscope_app")
            assert self.attach == "xscope_app"
        else: # User responsible for xrunning the xcore application. Only do the xscope control stuff
            # note that this is a debug only option and the xscope_port is hardcoded to '12345'
            # The user is expected to do  'xrun --xscope-port localhost:12345 <xe application>' in a separate terminal
            # This is useful when debugging a suspected crash of the xe application.
            self.xscope_port = "12345"
        self.xscope_host = None



    def __enter__(self):
        """
        Enter the runtime context related to this object.

        This method is called when the `with` statement is executed.
        For example: with XcoreAppControl(adapter_id, xe_name, verbose=verbose) as xcoreapp:

        It starts the xrun --xscope-port <app binary> process.
        It also creates an instance of the XscopeControl() object that can be used later to communicate with the
        device over xscope.
        For example:

        with XcoreAppControl(adapter_id, xe_name, verbose=verbose) as xcoreapp:
            xcoreapp.xscope_host.xscope_controller_cmd_connect()

        Returns:
            XcoreAppControl: The instance of the class.

        """
        if self.xrun_app: # Start the xrun process
            super().__enter__()
        # self.xscope_port is only set in XcoreApp.__enter__(), so xscope_host can only be created here and not in XcoreAppControl's constructor
        self.xscope_host = XscopeControl("localhost", f"{self.xscope_port}", verbose=self.verbose)
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """
        Exit the runtime context.

        It calls the terminate() method of XcoreApp() that terminates the xrun process

        This method is called at the end of the `with` statement block.
        """
        if self.xrun_app: # Kill the xrun process
            super().__exit__(exc_type, exc_val, exc_tb)
            if self.verbose:
                print("After terminating xrun:\n")
                print(f"stdout: {self.proc_stdout}")
                print(f"stderr: {self.proc_stderr}")
