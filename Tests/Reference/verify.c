#include "protocol.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    unsigned char frame[49];
    FILE* file = fopen("build/test-telemetry.bin", "rb");
    assert(file);
    size_t n = fread(frame, 1, sizeof(frame), file);
    fclose(file);
    PhrTelemetry t;
    assert(phr_parse_telemetry(frame, n, &t));
    assert(t.seq == 255 && t.flags == 33);
    assert(t.cpu_load == 77 && t.ram_load == 42 && t.disk_load == 63);
    assert(t.battery == 85 && t.ram_total_dgb == 160 && t.uptime_h == 432);
    assert(t.top_cpu_pct == 14 && t.top_ram_pct == 22);
    assert(strcmp(t.top_cpu_name, "LongProcessN") == 0);
    assert(strcmp(t.top_ram_name, "M?moire") == 0);
    frame[6] ^= 1;
    assert(!phr_parse_telemetry(frame, n, &t));
    file = fopen("build/test-sensors.bin", "rb");
    assert(file);
    n = fread(frame, 1, sizeof(frame), file); fclose(file);
    assert(phr_parse_telemetry(frame, n, &t));
    assert(t.flags == 125 && t.cpu_temp == 107 && t.gpu_temp == 102 && t.gpu_load == 58);
    assert(t.vram_load == 12 && t.vram_total_dgb == 172 && t.cpu_clock_mhz == 2400 && t.fan_rpm == 1750);
    puts("PASS: actual upstream Flipper decoder accepts Mac telemetry and rejects corruption");
    return 0;
}
