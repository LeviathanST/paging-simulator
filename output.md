# Sample output
╔══════════════════════════════════════════════════════════════════════════════╗
║           PAGE SIZE ANALYSIS: Page Faults vs Internal Fragmentation          ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ Physical Memory:  65536 bytes | Processes: 5 | Accesses per process: 200     ║
╚══════════════════════════════════════════════════════════════════════════════╝

┌─────────────┬─────────┬─────────────┬────────────┬─────────────┬──────────────┐
│ Page Size   │ Frames  │ Page Faults │ Fault Rate │ Int. Frag.  │ Frag. Rate   │
├─────────────┼─────────┼─────────────┼────────────┼─────────────┼──────────────┤
│     64 B    │   1024  │        309  │    30.90%  │       80 B  │      0.27%   │
│    128 B    │    512  │        209  │    20.90%  │       80 B  │      0.27%   │
│    256 B    │    256  │        117  │    11.70%  │      464 B  │      1.52%   │
│    512 B    │    128  │         61  │     6.10%  │     1232 B  │      3.94%   │
│   1024 B    │     64  │         32  │     3.20%  │     2768 B  │      8.45%   │
│   2048 B    │     32  │         16  │     1.60%  │     2768 B  │      8.45%   │
│   4096 B    │     16  │          9  │     0.90%  │     6864 B  │     18.62%   │
│   8192 B    │      8  │          6  │     0.60%  │    19152 B  │     38.96%   │
│  16384 B    │      4  │          5  │     0.50%  │    51920 B  │     63.38%   │
│  24576 B    │      2  │          5  │     0.50%  │    92880 B  │     75.59%   │
└─────────────┴─────────┴─────────────┴────────────┴─────────────┴──────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                              ANALYSIS SUMMARY                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  PAGE FAULT ANALYSIS:                                                        │
│    • Lowest page faults:   16384 B page size ->    5 faults                  │
│    • Highest page faults:     64 B page size ->  309 faults                  │
│                                                                              │
│  INTERNAL FRAGMENTATION ANALYSIS:                                            │
│    • Lowest fragmentation:      64 B page size ->    80 bytes wasted         │
│    • Highest fragmentation:  24576 B page size -> 92880 bytes wasted         │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│  KEY INSIGHTS:                                                               │
│                                                                              │
│  * SMALLER pages -> MORE page faults (more pages to manage, less spatial     │
│                     locality benefit per page)                               │
│                                                                              │
│  * SMALLER pages -> LESS internal fragmentation (less wasted space in        │
│                     the last page of each process)                           │
│                                                                              │
│  * LARGER pages  -> FEWER page faults (better spatial locality, fewer        │
│                     page table entries)                                      │
│                                                                              │
│  * LARGER pages  -> MORE internal fragmentation (average waste = pagesize/2) │
│                                                                              │
│  TRADE-OFF: Must balance page fault overhead vs memory waste!                │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                         VISUAL COMPARISON CHART                              │
├──────────────────────────────────────────────────────────────────────────────┤
│  Legend: [#] Page Faults    [=] Internal Fragmentation                       │
│                                                                              │
│  Page Size  0%              50%              100%                            │
│             |----------------|----------------|                              │
│      64B   [###################################]  30.9% faults               │
│            [                                   ]   0.3% frag                 │
│                                                                              │
│     128B   [#######################            ]  20.9% faults               │
│            [                                   ]   0.3% frag                 │
│                                                                              │
│     256B   [#############                      ]  11.7% faults               │
│            [                                   ]   1.5% frag                 │
│                                                                              │
│     512B   [######                             ]   6.1% faults               │
│            [                                   ]   3.9% frag                 │
│                                                                              │
│    1024B   [###                                ]   3.2% faults               │
│            [=                                  ]   8.4% frag                 │
│                                                                              │
│    2048B   [#                                  ]   1.6% faults               │
│            [=                                  ]   8.4% frag                 │
│                                                                              │
│    4096B   [#                                  ]   0.9% faults               │
│            [==                                 ]  18.6% frag                 │
│                                                                              │
│    8192B   [                                   ]   0.6% faults               │
│            [=======                            ]  39.0% frag                 │
│                                                                              │
│   16384B   [                                   ]   0.5% faults               │
│            [===================                ]  63.4% frag                 │
│                                                                              │
│   24576B   [                                   ]   0.5% faults               │
│            [===================================]  75.6% frag                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
