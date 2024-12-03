xsim  bin/tx4b_rx1b/test_rmii_tx4b_rx1b.xe  --max-cycles 800000 \
 --trace-plugin VcdPlugin.dll '-tile tile[0] -o trace.vcd -xe bin/tx4b_rx1b/test_rmii_tx4b_rx1b.xe -ports -ports-detailed -cores -instructions -clock-blocks' \
 --plugin LoopbackPort.dll '-port tile[0] XS1_PORT_4B 1 0 -port tile[0] XS1_PORT_1A 1 0' \
 --plugin LoopbackPort.dll '-port tile[0] XS1_PORT_4B 1 1 -port tile[0] XS1_PORT_1B 1 0' \
 --plugin LoopbackPort.dll '-port tile[0] XS1_PORT_1K 1 0 -port tile[0] XS1_PORT_1L 1 0' \
 --plugin LoopbackPort.dll '-port tile[0] XS1_PORT_1I 1 0 -port tile[0] XS1_PORT_1J 1 0' \
 --trace-to trace.txt


 # --xscope "-offline trace.xmt"