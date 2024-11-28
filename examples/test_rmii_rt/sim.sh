xsim bin/test_rmii.xe --max-cycles 200000 \
 --trace-plugin VcdPlugin.dll '-tile tile[0] -o trace.vcd -xe bin/test_rmii.xe -ports -ports-detailed -cores -instructions -clock-blocks' \
 --plugin LoopbackPort.dll '-port tile[0] XS1_PORT_4A 4 0 -port tile[0] XS1_PORT_4B 4 0' \
 --plugin LoopbackPort.dll '-port tile[0] XS1_PORT_1K 1 0 -port tile[0] XS1_PORT_1L 1 0' \
 --plugin LoopbackPort.dll '-port tile[0] XS1_PORT_1I 1 0 -port tile[0] XS1_PORT_1J 1 0' 