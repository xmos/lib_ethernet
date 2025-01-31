import subprocess
import platform
from pathlib import Path

from hardware_test_tools.XcoreApp import XcoreApp

pkg_dir = Path(__file__).parent

class XcoreAppControl(XcoreApp):
    def __init__(self, adapter_id, xe_name, attach=None):

        super().__init__(xe_name, adapter_id, attach=attach)

    def xscope_controller_do_command(self, xscope_controller, cmd, timeout):
        ret = subprocess.run(
            [xscope_controller, "localhost", f"{self.xscope_port}", cmd],
            capture_output=True,
            text=True,
            timeout=timeout
        )
        assert ret.returncode == 0, (
            f"xscope controller command failed on port {self.xscope_port} with commands {cmd}"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )

        return ret.stdout, ret.stderr


    def xscope_controller_cmd_connect(self, timeout=30):
        assert self.attach == "xscope_app"
        assert platform.system() in ["Darwin"]

        base_dir = pkg_dir / "xscope_controller" / "build"
        xscope_controller = base_dir / "xscope_controller"

        assert xscope_controller.exists(), f"xscope_controller not present at {xscope_controller}"

        stdout, stderr = self.xscope_controller_do_command(xscope_controller, "connect", timeout)
        return stdout, stderr

    def xscope_controller_cmd_shutdown(self, timeout=30):
        assert self.attach == "xscope_app"
        assert platform.system() in ["Darwin"]

        base_dir = pkg_dir / "xscope_controller" / "build"
        xscope_controller = base_dir / "xscope_controller"

        assert xscope_controller.exists(), f"xscope_controller not present at {xscope_controller}"

        stdout, stderr = self.xscope_controller_do_command(xscope_controller, "shutdown", timeout)
        return stdout, stderr


