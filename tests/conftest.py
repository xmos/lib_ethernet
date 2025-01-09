# Copyright 2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import pytest
import random
import sys

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
