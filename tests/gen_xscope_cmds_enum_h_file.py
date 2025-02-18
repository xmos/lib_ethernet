import sys
from xcore_app_control import XscopeControl

def call_enum_method(filename):
    XscopeControl.XscopeCommands.write_to_h_file(filename)

if __name__ == "__main__":
    assert len(sys.argv) == 2, ("Error: filename not provided" +
                    "\nUsage: python generate_xscope_cmds_enum_h_file.py <.h file name, eg. enum.h>\n")

    call_enum_method(sys.argv[1])
