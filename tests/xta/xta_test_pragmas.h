// Time for worst case with 8 threads running
#pragma xta command "config tasks tile[0] 8"
#if RT
// Set the operating frequency to 500 MHz for the RT Ethernet component
// It is only supported on 500 MHz parts 
#pragma xta command "config freq 0 500"
#endif