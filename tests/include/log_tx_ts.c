// Copyright 2014-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <xs1.h>
#include <platform.h>
#include <stdlib.h>
#include <debug_print.h>
#include <xscope.h>
#include <assert.h>
#include "log_tx_ts.h"

unsigned tx_start_timestamps[TOTAL_NUM_TS_ENTRIES];

mii_tx_ts_fifo_t tx_ts_queue;

void init_tx_ts_queue()
{
    tx_ts_queue.rd_index = 0; // first unread
    tx_ts_queue.wr_index = 0; // next index to write
    tx_ts_queue.num_entries = TOTAL_NUM_TS_ENTRIES;
    tx_ts_queue.fifo = tx_start_timestamps;
}

unsigned tx_ts_queue_size()
{
    if(tx_ts_queue.rd_index == tx_ts_queue.wr_index)
    {
        return 0;
    }
    if(tx_ts_queue.rd_index < tx_ts_queue.wr_index)
    {
        return tx_ts_queue.wr_index - tx_ts_queue.rd_index;
    }
    else
    {
        return (tx_ts_queue.num_entries - tx_ts_queue.rd_index + tx_ts_queue.wr_index);
    }
}

void increment_tx_ts_queue_write_index()
{
    tx_ts_queue.wr_index += 1;
    if(tx_ts_queue.wr_index == TOTAL_NUM_TS_ENTRIES)
    {
        tx_ts_queue.wr_index = 0;
    }
    if(tx_ts_queue.wr_index == tx_ts_queue.rd_index)
    {
        debug_printf("ERROR: TX Timestamp queue full!!\n");
        assert(0);
    }
}
void tx_timestamp_probe()
{
    init_tx_ts_queue();
    while(1)
    {
        if(tx_ts_queue_size() > 1000)
        {
            // output 1000 entries at a time
            xscope_bytes(2, 1000*sizeof(unsigned), (const unsigned char *)&tx_ts_queue.fifo[tx_ts_queue.rd_index]);
            tx_ts_queue.rd_index += 1000;
            if(tx_ts_queue.rd_index >= TOTAL_NUM_TS_ENTRIES)
            {
                tx_ts_queue.rd_index = tx_ts_queue.rd_index - TOTAL_NUM_TS_ENTRIES;
            }
        }
    }
}
