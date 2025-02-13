# Copyright 2024-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import pytest
import random
import sys
from pathlib import Path
import subprocess
import platform

pkg_dir = Path(__file__).parent

def pytest_addoption(parser):
    parser.addoption(
        "--seed",
        action = "store",
        default = None,
        type = int,
        help = "Seed used for initialising the random number generator in tests",
    )
    parser.addoption(
        "--level",
        action="store",
        default="smoke",
        choices=["smoke", "nightly"],
        help="Test coverage level",
    )
    parser.addoption(
        "--adapter-id",
        action="store",
        default=None,
        help="DUT adapter-id when running HW tests",
    )
    parser.addoption(
        "--eth-intf",
        action="store",
        default=None,
        help="DUT adapter-id when running HW tests",
    )
    parser.addoption(
        "--test-duration",
        action="store",
        default=None,
        help="Test duration in seconds",
    )

def build_xcope_control_host():
    print("In build_xcope_control_host()")
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
    xscope_controller_app = xscope_controller_dir / "build" / "xscope_controller"
    assert xscope_controller_app.exists(), f"xscope_controller not present at {xscope_controller_app}"

def build_socket_host():
    print("In build_socket_host()")
    if platform.system() in ["Linux"]:
        socket_host_dir = pkg_dir / "host" / "socket"
        # Build the xscope controller host application
        ret = subprocess.run(["cmake", "-B", "build"],
                            capture_output=True,
                            text=True,
                            cwd=socket_host_dir)

        assert ret.returncode == 0, (
            f"socket host cmake command failed"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )

        ret = subprocess.run(["make", "-C", "build"],
                            capture_output=True,
                            text=True,
                            cwd=socket_host_dir)

        assert ret.returncode == 0, (
            f"socket host make command failed"
            + f"\nstdout:\n{ret.stdout}"
            + f"\nstderr:\n{ret.stderr}"
        )

        socket_send_app = socket_host_dir / "build" / "socket_send"
        assert socket_send_app.exists(), f"socket host app {socket_send_app} doesn't exist"

        socket_send_recv_app = socket_host_dir / "build" / "socket_send_recv"
        assert socket_send_recv_app.exists(), f"socket host app {socket_send_recv_app} doesn't exist"

        socket_recv_app = socket_host_dir / "build" / "socket_recv"
        assert socket_recv_app.exists(), f"socket host app {socket_recv_app} doesn't exist"
    else:
        print(f"Sending using sockets only supported on Linux")


def pytest_configure(config):
    if config.pluginmanager.hasplugin("xdist"):
        if hasattr(config, 'workerinput'): # skip if worker node
            return
    # We're here if either master node in xdist or running without xdist
    # Perform setup that should happen only once here
    seed_value = config.getoption("--seed")
    if seed_value == None:
        seed_value = random.randint(0, sys.maxsize) # Set a random seed
    config.seed = seed_value
    print(f"Set seed to {config.seed}")

    # Build the host applications used in HW testing
    build_xcope_control_host()
    build_socket_host()


def pytest_configure_node(node):
    # Propagate the value to each worker. This is called only for worker nodes
    node.workerinput['seed'] = node.config.seed

@pytest.fixture(scope="session")
def seed(request):
    if hasattr(request.config, 'workerinput'): # Called for all nodes so check for worker node here
        return request.config.workerinput['seed']
    else:
        return request.config.seed

@pytest.fixture
def level(pytestconfig):
    return pytestconfig.getoption("level")
