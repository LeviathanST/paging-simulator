const std = @import("std");

// Configuration
const PHYSICAL_MEMORY_SIZE: usize = 65536; // 64KB total physical memory
const MAX_PROCESSES: usize = 8;
const MAX_PAGES: usize = 256;

// Page Table Entry
const PageTableEntry = struct {
    frame_number: ?u16 = null,
    present: bool = false,
    dirty: bool = false,
    referenced: bool = false,
};

// Frame info
const FrameInfo = struct {
    pid: ?u8 = null,
    page_number: ?u16 = null,
    in_use: bool = false,
    load_time: u64 = 0,
};

// Statistics for analysis
const SimulationStats = struct {
    page_size: usize,
    num_frames: usize,
    page_faults: u64 = 0,
    page_hits: u64 = 0,
    total_accesses: u64 = 0,
    total_internal_fragmentation: usize = 0,
    total_allocated_memory: usize = 0,
    total_requested_memory: usize = 0,
    num_processes: usize = 0,

    pub fn pageFaultRate(self: SimulationStats) f64 {
        if (self.total_accesses == 0) return 0;
        return @as(f64, @floatFromInt(self.page_faults)) /
            @as(f64, @floatFromInt(self.total_accesses)) * 100.0;
    }

    pub fn hitRate(self: SimulationStats) f64 {
        if (self.total_accesses == 0) return 0;
        return @as(f64, @floatFromInt(self.page_hits)) /
            @as(f64, @floatFromInt(self.total_accesses)) * 100.0;
    }

    pub fn fragmentationPercent(self: SimulationStats) f64 {
        if (self.total_allocated_memory == 0) return 0;
        return @as(f64, @floatFromInt(self.total_internal_fragmentation)) /
            @as(f64, @floatFromInt(self.total_allocated_memory)) * 100.0;
    }

    pub fn avgFragmentationPerProcess(self: SimulationStats) f64 {
        if (self.num_processes == 0) return 0;
        return @as(f64, @floatFromInt(self.total_internal_fragmentation)) /
            @as(f64, @floatFromInt(self.num_processes));
    }
};

// Process
const Process = struct {
    pid: u8,
    page_table: [MAX_PAGES]PageTableEntry,
    num_pages: u16 = 0,
    memory_requested: usize = 0,
    memory_allocated: usize = 0,
    internal_fragmentation: usize = 0,

    pub fn init(pid: u8) Process {
        return .{
            .pid = pid,
            .page_table = [_]PageTableEntry{.{}} ** MAX_PAGES,
        };
    }
};

// Memory Management Unit (parameterized by page size)
const MMU = struct {
    page_size: usize,
    num_frames: usize,
    frames: []FrameInfo,
    processes: [MAX_PROCESSES]?Process,
    time_counter: u64 = 0,
    stats: SimulationStats,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, page_size: usize) !MMU {
        const num_frames = PHYSICAL_MEMORY_SIZE / page_size;
        const frames = try allocator.alloc(FrameInfo, num_frames);
        @memset(frames, FrameInfo{});

        return .{
            .page_size = page_size,
            .num_frames = num_frames,
            .frames = frames,
            .processes = [_]?Process{null} ** MAX_PROCESSES,
            .stats = .{
                .page_size = page_size,
                .num_frames = num_frames,
            },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MMU) void {
        self.allocator.free(self.frames);
    }

    // Create process with specific memory requirement
    pub fn createProcess(self: *MMU, memory_size: usize) !u8 {
        for (&self.processes, 0..) |*proc, i| {
            if (proc.* == null) {
                var p = Process.init(@intCast(i));

                // Calculate pages needed and internal fragmentation
                const pages_needed = (memory_size + self.page_size - 1) / self.page_size;
                const allocated_memory = pages_needed * self.page_size;
                const fragmentation = allocated_memory - memory_size;

                p.num_pages = @intCast(pages_needed);
                p.memory_requested = memory_size;
                p.memory_allocated = allocated_memory;
                p.internal_fragmentation = fragmentation;

                proc.* = p;

                // Update stats
                self.stats.num_processes += 1;
                self.stats.total_requested_memory += memory_size;
                self.stats.total_allocated_memory += allocated_memory;
                self.stats.total_internal_fragmentation += fragmentation;

                return @intCast(i);
            }
        }
        return error.NoProcessSlots;
    }

    pub fn terminateProcess(self: *MMU, pid: u8) void {
        if (self.processes[pid]) |_| {
            for (self.frames) |*frame| {
                if (frame.in_use and frame.pid == pid) {
                    frame.* = .{};
                }
            }
            self.processes[pid] = null;
        }
    }

    // Access memory (simulates page access)
    pub fn accessMemory(self: *MMU, pid: u8, virtual_page: u16, write: bool) !void {
        self.time_counter += 1;
        self.stats.total_accesses += 1;

        var proc = &(self.processes[pid] orelse return error.InvalidProcess);

        if (virtual_page >= proc.num_pages) return error.InvalidPage;

        var pte = &proc.page_table[virtual_page];

        if (pte.present) {
            // Page hit
            self.stats.page_hits += 1;
            pte.referenced = true;
            if (write) pte.dirty = true;
            if (pte.frame_number) |frame| {
                self.frames[frame].load_time = self.time_counter;
            }
        } else {
            // Page fault
            self.stats.page_faults += 1;

            const frame = try self.allocateFrame(pid, virtual_page);

            pte.frame_number = frame;
            pte.present = true;
            pte.referenced = true;
            pte.dirty = write;
        }
    }

    fn allocateFrame(self: *MMU, pid: u8, page: u16) !u16 {
        // Find free frame
        for (self.frames, 0..) |*frame, i| {
            if (!frame.in_use) {
                frame.* = .{
                    .pid = pid,
                    .page_number = page,
                    .in_use = true,
                    .load_time = self.time_counter,
                };
                return @intCast(i);
            }
        }

        // Evict using FIFO
        return self.evictAndAllocate(pid, page);
    }

    fn evictAndAllocate(self: *MMU, pid: u8, page: u16) !u16 {
        var oldest_time: u64 = std.math.maxInt(u64);
        var victim: usize = 0;

        for (self.frames, 0..) |frame, i| {
            if (frame.in_use and frame.load_time < oldest_time) {
                oldest_time = frame.load_time;
                victim = i;
            }
        }

        const victim_frame = &self.frames[victim];
        const victim_pid = victim_frame.pid.?;
        const victim_page = victim_frame.page_number.?;

        // Update victim's page table
        if (self.processes[victim_pid]) |*proc| {
            var pte = &proc.page_table[victim_page];
            pte.present = false;
            pte.frame_number = null;
            pte.dirty = false;
            pte.referenced = false;
        }

        // Allocate to new page
        victim_frame.* = .{
            .pid = pid,
            .page_number = page,
            .in_use = true,
            .load_time = self.time_counter,
        };

        return @intCast(victim);
    }
};

// Generate realistic memory access pattern (locality of reference)
fn generateAccessPattern(allocator: std.mem.Allocator, num_pages: u16, num_accesses: usize) ![]u16 {
    var prng = std.Random.DefaultPrng.init(12345);
    const random = prng.random();

    const accesses = try allocator.alloc(u16, num_accesses);

    var current_locality: u16 = 0;
    var locality_counter: usize = 0;

    for (accesses) |*access| {
        // Change locality region periodically (simulates working set changes)
        if (locality_counter == 0) {
            current_locality = random.intRangeAtMost(u16, 0, num_pages -| 1);
            locality_counter = random.intRangeAtMost(usize, 5, 20);
        }
        locality_counter -= 1;

        // Access within locality (80%) or random (20%)
        if (random.float(f32) < 0.8) {
            const offset = random.intRangeAtMost(u16, 0, @min(4, num_pages -| 1));
            access.* = @min(current_locality +| offset, num_pages -| 1);
        } else {
            access.* = random.intRangeAtMost(u16, 0, num_pages -| 1);
        }
    }

    return accesses;
}

fn runSimulation(allocator: std.mem.Allocator, page_size: usize) !SimulationStats {
    var mmu = try MMU.init(allocator, page_size);
    defer mmu.deinit();

    // Create processes with various memory sizes (realistic sizes)
    const process_sizes = [_]usize{
        1500, // 1.5 KB
        3200, // 3.2 KB
        7800, // 7.8 KB
        12000, // 12 KB
        5500, // 5.5 KB
    };

    var pids: [5]u8 = undefined;
    for (process_sizes, 0..) |size, i| {
        pids[i] = try mmu.createProcess(size);
    }

    // Generate and execute memory accesses for each process
    const accesses_per_process: usize = 200;

    for (pids, 0..) |pid, i| {
        const proc = mmu.processes[pid].?;
        const pattern = try generateAccessPattern(allocator, proc.num_pages, accesses_per_process);
        defer allocator.free(pattern);

        for (pattern) |page| {
            mmu.accessMemory(pid, page, i % 2 == 0) catch {};
        }
    }

    // Cleanup
    for (pids) |pid| {
        mmu.terminateProcess(pid);
    }

    return mmu.stats;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const print = std.debug.print;

    print("\n", .{});
    print("╔══════════════════════════════════════════════════════════════════════════════╗\n", .{});
    print("║           PAGE SIZE ANALYSIS: Page Faults vs Internal Fragmentation          ║\n", .{});
    print("╠══════════════════════════════════════════════════════════════════════════════╣\n", .{});
    print("║ Physical Memory: {d:>6} bytes | Processes: 5 | Accesses per process: 200     ║\n", .{PHYSICAL_MEMORY_SIZE});
    print("╚══════════════════════════════════════════════════════════════════════════════╝\n\n", .{});

    // Test different page sizes
    const page_sizes = [_]usize{ 64, 128, 256, 512, 1024, 2048, 4096, 8192, 8192 * 2, 8192 * 3 };

    var results: [page_sizes.len]SimulationStats = undefined;

    for (page_sizes, 0..) |page_size, i| {
        results[i] = try runSimulation(allocator, page_size);
    }

    // Print detailed results table
    print("┌─────────────┬─────────┬─────────────┬────────────┬─────────────┬──────────────┐\n", .{});
    print("│ Page Size   │ Frames  │ Page Faults │ Fault Rate │ Int. Frag.  │ Frag. Rate   │\n", .{});
    print("├─────────────┼─────────┼─────────────┼────────────┼─────────────┼──────────────┤\n", .{});

    for (results) |stats| {
        print("│ {d:>6} B    │ {d:>6}  │ {d:>10}  │ {d:>8.2}%  │ {d:>8} B  │ {d:>9.2}%   │\n", .{
            stats.page_size,
            stats.num_frames,
            stats.page_faults,
            stats.pageFaultRate(),
            stats.total_internal_fragmentation,
            stats.fragmentationPercent(),
        });
    }

    print("└─────────────┴─────────┴─────────────┴────────────┴─────────────┴──────────────┘\n\n", .{});

    // Print analysis summary
    print("┌──────────────────────────────────────────────────────────────────────────────┐\n", .{});
    print("│                              ANALYSIS SUMMARY                                │\n", .{});
    print("├──────────────────────────────────────────────────────────────────────────────┤\n", .{});

    // Find best/worst cases
    var min_faults: u64 = std.math.maxInt(u64);
    var max_faults: u64 = 0;
    var min_frag: usize = std.math.maxInt(usize);
    var max_frag: usize = 0;
    var best_fault_size: usize = 0;
    var worst_fault_size: usize = 0;
    var best_frag_size: usize = 0;
    var worst_frag_size: usize = 0;

    for (results) |stats| {
        if (stats.page_faults < min_faults) {
            min_faults = stats.page_faults;
            best_fault_size = stats.page_size;
        }
        if (stats.page_faults > max_faults) {
            max_faults = stats.page_faults;
            worst_fault_size = stats.page_size;
        }
        if (stats.total_internal_fragmentation < min_frag) {
            min_frag = stats.total_internal_fragmentation;
            best_frag_size = stats.page_size;
        }
        if (stats.total_internal_fragmentation > max_frag) {
            max_frag = stats.total_internal_fragmentation;
            worst_frag_size = stats.page_size;
        }
    }

    print("│                                                                              │\n", .{});
    print("│  PAGE FAULT ANALYSIS:                                                        │\n", .{});
    print("│    • Lowest page faults:  {d:>6} B page size -> {d:>4} faults                │\n", .{ best_fault_size, min_faults });
    print("│    • Highest page faults: {d:>6} B page size -> {d:>4} faults                │\n", .{ worst_fault_size, max_faults });
    print("│                                                                              │\n", .{});
    print("│  INTERNAL FRAGMENTATION ANALYSIS:                                            │\n", .{});
    print("│    • Lowest fragmentation:  {d:>6} B page size -> {d:>5} bytes wasted        │\n", .{ best_frag_size, min_frag });
    print("│    • Highest fragmentation: {d:>6} B page size -> {d:>5} bytes wasted        │\n", .{ worst_frag_size, max_frag });
    print("│                                                                              │\n", .{});
    print("├──────────────────────────────────────────────────────────────────────────────┤\n", .{});
    print("│  KEY INSIGHTS:                                                               │\n", .{});
    print("│                                                                              │\n", .{});
    print("│  * SMALLER pages -> MORE page faults (more pages to manage, less spatial     │\n", .{});
    print("│                     locality benefit per page)                               │\n", .{});
    print("│                                                                              │\n", .{});
    print("│  * SMALLER pages -> LESS internal fragmentation (less wasted space in        │\n", .{});
    print("│                     the last page of each process)                           │\n", .{});
    print("│                                                                              │\n", .{});
    print("│  * LARGER pages  -> FEWER page faults (better spatial locality, fewer        │\n", .{});
    print("│                     page table entries)                                      │\n", .{});
    print("│                                                                              │\n", .{});
    print("│  * LARGER pages  -> MORE internal fragmentation (average waste = pagesize/2) │\n", .{});
    print("│                                                                              │\n", .{});
    print("│  TRADE-OFF: Must balance page fault overhead vs memory waste!                │\n", .{});
    print("└──────────────────────────────────────────────────────────────────────────────┘\n\n", .{});

    // Print ASCII chart for visualization
    print("┌──────────────────────────────────────────────────────────────────────────────┐\n", .{});
    print("│                         VISUAL COMPARISON CHART                              │\n", .{});
    print("├──────────────────────────────────────────────────────────────────────────────┤\n", .{});
    print("│  Legend: [#] Page Faults    [=] Internal Fragmentation                       │\n", .{});
    print("│                                                                              │\n", .{});
    print("│  Page Size  0%              50%              100%                            │\n", .{});
    print("│             |----------------|----------------|                              │\n", .{});

    const max_bar_len: usize = 35;

    for (results) |stats| {
        const fault_bar_len: usize = @intFromFloat(
            @as(f64, @floatFromInt(stats.page_faults)) / @as(f64, @floatFromInt(max_faults)) * @as(f64, max_bar_len),
        );
        const frag_bar_len: usize = @intFromFloat(
            @as(f64, @floatFromInt(stats.total_internal_fragmentation)) / @as(f64, @floatFromInt(max_frag)) * @as(f64, max_bar_len),
        );

        // Fault bar line
        print("│  {d:>6}B   [", .{stats.page_size});
        var j: usize = 0;
        while (j < fault_bar_len) : (j += 1) print("#", .{});
        while (j < max_bar_len) : (j += 1) print(" ", .{});
        print("] {d:>5.1}% faults               │\n", .{stats.pageFaultRate()});

        // Fragmentation bar line
        print("│            [", .{});
        j = 0;
        while (j < frag_bar_len) : (j += 1) print("=", .{});
        while (j < max_bar_len) : (j += 1) print(" ", .{});
        print("] {d:>5.1}% frag                 │\n", .{stats.fragmentationPercent()});

        print("│                                                                              │\n", .{});
    }

    print("└──────────────────────────────────────────────────────────────────────────────┘\n", .{});
}
