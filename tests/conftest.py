# Copyright 2024 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

def pytest_addoption(parser):
    parser.addoption(
        "--seed",
        action = "store",
        default = None,
        type = int,
        help = "Seed used for initialising the random number generator in tests",
    )
