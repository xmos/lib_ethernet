import subprocess
import platform
from pathlib import Path

from hardware_test_tools.XcoreApp import XcoreApp

pkg_dir = Path(__file__).parent

class XcoreAppControl(XcoreApp):
    def __init__(self, adapter_id, xe_name, attach=None):

        super().__init__(xe_name, adapter_id, attach=attach)

        xscope_controller_dir = pkg_dir / "host"/ "xscope_controller"

        assert xscope_controller_dir.exists() and xscope_controller_dir.is_dir(), f"xscope_controller path {xscope_controller_dir} invalid"

        # Build the xscope controller host application
        ret = subprocess.run(["cmake", "-B", "build"],
                            capture_output=True,
                            text=True,
                            cwd=xscope_controller_dir)

        assert ret.returncode == 0, (
            f"xscope controller cmake command failed"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )

        ret = subprocess.run(["make", "-C", "build"],
                            capture_output=True,
                            text=True,
                            cwd=xscope_controller_dir)

        assert ret.returncode == 0, (
            f"xscope controller make command failed"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )

        self.xscope_controller_app = xscope_controller_dir / "build" / "xscope_controller"
        assert self.xscope_controller_app.exists(), f"xscope_controller not present at {self.xscope_controller_app}"


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
        assert platform.system() in ["Darwin", "Linux"]

        stdout, stderr = self.xscope_controller_do_command(self.xscope_controller_app, "connect", timeout)
        return stdout, stderr

    def xscope_controller_cmd_shutdown(self, timeout=30):
        assert self.attach == "xscope_app"
        assert platform.system() in ["Darwin", "Linux"]

        stdout, stderr = self.xscope_controller_do_command(self.xscope_controller_app, "shutdown", timeout)
        return stdout, stderr
