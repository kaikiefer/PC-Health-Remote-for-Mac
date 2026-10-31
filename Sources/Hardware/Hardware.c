// Read-only SMC and IOReport interfaces, adapted from vladkens/macmon (MIT).
// See ThirdParty/macmon-LICENSE and ThirdParty/README.md.
#include "Hardware.h"
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } SMCLimits;
typedef struct { uint32_t size, type; uint8_t attributes; } SMCInfo;
typedef struct {
    uint32_t key; SMCVersion version; SMCLimits limits; SMCInfo info;
    uint8_t result, status, command; uint32_t index; uint8_t bytes[32];
} SMCData;
_Static_assert(sizeof(SMCData) == 80, "SMC ABI must be 80 bytes");
typedef struct { uint32_t key; SMCInfo info; int kind; } Sensor;
struct PHRHardware {
    io_connect_t smc;
    Sensor sensors[128]; int sensorCount;
    void *library;
    CFDictionaryRef (*copyChannels)(uint64_t, uint64_t);
    CFTypeRef (*subscribe)(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, void *);
    CFDictionaryRef (*samples)(CFTypeRef, CFMutableDictionaryRef, void *);
    CFDictionaryRef (*delta)(CFDictionaryRef, CFDictionaryRef, void *);
    CFStringRef (*group)(CFDictionaryRef);
    CFStringRef (*subgroup)(CFDictionaryRef);
    CFStringRef (*name)(CFDictionaryRef);
    int32_t (*stateCount)(CFDictionaryRef);
    CFStringRef (*stateName)(CFDictionaryRef, int32_t);
    int64_t (*residency)(CFDictionaryRef, int32_t);
    CFTypeRef subscription;
    CFMutableDictionaryRef channels;
    CFDictionaryRef previous;
    uint32_t efficiency[64], performance[64]; int efficiencyCount, performanceCount;
};

static uint32_t fourcc(const char *s) {
    return (uint32_t)(uint8_t)s[0]<<24 | (uint32_t)(uint8_t)s[1]<<16 | (uint32_t)(uint8_t)s[2]<<8 | (uint8_t)s[3];
}
static int request(PHRHardware *h, SMCData *in, SMCData *out) {
    memset(out, 0, sizeof(*out)); size_t size = sizeof(*out);
    return IOConnectCallStructMethod(h->smc, 2, in, sizeof(*in), out, &size) == KERN_SUCCESS && size == sizeof(*out) && out->result == 0;
}
static int info(PHRHardware *h, uint32_t key, SMCInfo *result) {
    SMCData in = {.key=key, .command=9}, out;
    if (!request(h, &in, &out) || out.info.size > 32) return 0;
    *result = out.info; return 1;
}
static int value(PHRHardware *h, uint32_t key, SMCInfo info, SMCData *out) {
    SMCData in = {.key=key, .info=info, .command=5}; return request(h, &in, out);
}
static double numeric(PHRHardware *h, Sensor sensor) {
    SMCData out;
    if (!value(h, sensor.key, sensor.info, &out)) return NAN;
    if (sensor.info.type == fourcc("flt ") && sensor.info.size == 4) {
        float f; memcpy(&f, out.bytes, 4); return f;
    }
    if (sensor.info.type == fourcc("sp78") && sensor.info.size == 2)
        return (int16_t)((out.bytes[0]<<8) | out.bytes[1]) / 256.0;
    if (sensor.info.type == fourcc("fpe2") && sensor.info.size == 2)
        return ((out.bytes[0]<<8) | out.bytes[1]) / 4.0;
    if (sensor.info.type == fourcc("ui16") && sensor.info.size == 2)
        return (out.bytes[0]<<8) | out.bytes[1];
    return NAN;
}
static void initSMC(PHRHardware *h) {
    io_iterator_t it = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &it) != KERN_SUCCESS) return;
    io_service_t service;
    while ((service = IOIteratorNext(it))) {
        if (!h->smc) IOServiceOpen(service, mach_task_self(), 0, &h->smc);
        IOObjectRelease(service);
    }
    IOObjectRelease(it);
    if (!h->smc) return;
    SMCInfo keyInfo; SMCData out;
    if (!info(h, fourcc("#KEY"), &keyInfo) || !value(h, fourcc("#KEY"), keyInfo, &out)) return;
    uint32_t count = ((uint32_t)out.bytes[0]<<24) | ((uint32_t)out.bytes[1]<<16) | ((uint32_t)out.bytes[2]<<8) | out.bytes[3];
    if (count > 20000) return;
    for (uint32_t i=0; i<count && h->sensorCount<128; i++) {
        SMCData in = {.command=8, .index=i};
        if (!request(h, &in, &out)) continue;
        char key[5] = {out.key>>24, out.key>>16, out.key>>8, out.key, 0};
        int kind = 0;
        if (key[0]=='T' && (key[1]=='p' || key[1]=='e' || key[1]=='s' || key[1]=='C')) kind = 1;
        if (key[0]=='T' && (key[1]=='g' || key[1]=='G')) kind = 2;
        if (key[0]=='F' && key[2]=='A' && key[3]=='c') kind = 3;
        Sensor sensor = {.key=out.key, .kind=kind};
        if (kind && info(h, sensor.key, &sensor.info) && isfinite(numeric(h, sensor))) h->sensors[h->sensorCount++] = sensor;
    }
}
static int text(CFStringRef s, char *out, size_t size) {
    return s && CFStringGetCString(s, out, size, kCFStringEncodingUTF8);
}
static void frequencies(io_service_t service, CFStringRef key, uint32_t *values, int *count) {
    if (*count) return;
    CFTypeRef obj = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);
    if (!obj) return;
    if (CFGetTypeID(obj) == CFDataGetTypeID()) {
        CFDataRef data = (CFDataRef)obj;
        CFIndex size = CFDataGetLength(data); const uint8_t *bytes = CFDataGetBytePtr(data);
        if (size % 8 == 0) for (CFIndex i=0; i<size && *count<64; i+=8) {
            uint32_t hz; memcpy(&hz, bytes+i, 4); uint32_t mhz = hz / 1000000;
            if (mhz>0 && mhz<10000) values[(*count)++] = mhz;
        }
    }
    CFRelease(obj);
}
static void initClock(PHRHardware *h) {
    io_iterator_t it = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMIODevice"), &it) == KERN_SUCCESS) {
        io_service_t service;
        while ((service=IOIteratorNext(it))) {
            io_name_t name;
            if (IORegistryEntryGetName(service, name)==KERN_SUCCESS && !strcmp(name,"pmgr")) {
                frequencies(service, CFSTR("voltage-states1-sram"), h->efficiency, &h->efficiencyCount);
                frequencies(service, CFSTR("voltage-states5-sram"), h->performance, &h->performanceCount);
            }
            IOObjectRelease(service);
        }
        IOObjectRelease(it);
    }
    if (!h->efficiencyCount && !h->performanceCount) return;
    h->library = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY | RTLD_LOCAL);
    if (!h->library) return;
#define LOAD(field, symbol) do { *(void **)(&h->field)=dlsym(h->library, symbol); if (!h->field) return; } while(0)
    LOAD(copyChannels,"IOReportCopyAllChannels"); LOAD(subscribe,"IOReportCreateSubscription");
    LOAD(samples,"IOReportCreateSamples"); LOAD(delta,"IOReportCreateSamplesDelta");
    LOAD(group,"IOReportChannelGetGroup"); LOAD(subgroup,"IOReportChannelGetSubGroup"); LOAD(name,"IOReportChannelGetChannelName");
    LOAD(stateCount,"IOReportStateGetCount"); LOAD(stateName,"IOReportStateGetNameForIndex"); LOAD(residency,"IOReportStateGetResidency");
#undef LOAD
    CFDictionaryRef all = h->copyChannels(0,0);
    if (!all) return;
    CFArrayRef channels = CFDictionaryGetValue(all, CFSTR("IOReportChannels"));
    CFMutableArrayRef selected = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    if (channels && CFGetTypeID(channels)==CFArrayGetTypeID()) for (CFIndex i=0; i<CFArrayGetCount(channels); i++) {
        CFDictionaryRef channel = CFArrayGetValueAtIndex(channels,i);
        char group[128], sub[128];
        if (text(h->group(channel),group,sizeof(group)) && !strcmp(group,"CPU Stats") &&
            text(h->subgroup(channel),sub,sizeof(sub)) && !strcmp(sub,"CPU Core Performance States")) CFArrayAppendValue(selected,channel);
    }
    if (CFArrayGetCount(selected)>0) {
        CFMutableDictionaryRef request = CFDictionaryCreateMutableCopy(NULL,0,all);
        CFDictionarySetValue(request,CFSTR("IOReportChannels"),selected);
        h->subscription = h->subscribe(NULL,request,&h->channels,0,NULL);
        CFRelease(request);
    }
    CFRelease(selected); CFRelease(all);
}

static int sampleClock(PHRHardware *h) {
    if (!h->subscription || !h->channels) return 0;
    CFDictionaryRef current = h->samples(h->subscription,h->channels,NULL);
    if (!current) return 0;
    CFDictionaryRef delta = h->previous ? h->delta(h->previous,current,NULL) : NULL;
    if (h->previous) CFRelease(h->previous);
    h->previous = current;
    if (!delta) return 0;
    double weighted = 0, active = 0;
    CFArrayRef channels = CFDictionaryGetValue(delta,CFSTR("IOReportChannels"));
    if (channels && CFGetTypeID(channels)==CFArrayGetTypeID()) for (CFIndex i=0; i<CFArrayGetCount(channels); i++) {
        CFDictionaryRef channel = CFArrayGetValueAtIndex(channels,i);
        char name[128]; if (!text(h->name(channel),name,sizeof(name))) continue;
        uint32_t *table = NULL; int count=0;
        if (strstr(name,"ECPU")) { table=h->efficiency; count=h->efficiencyCount; }
        if (strstr(name,"PCPU")) { table=h->performance; count=h->performanceCount; }
        if (!table || !count) continue;
        int states=h->stateCount(channel), offset=0;
        for (; offset<states; offset++) {
            char state[64]; if (!text(h->stateName(channel,offset),state,sizeof(state))) break;
            if (strcmp(state,"IDLE") && strcmp(state,"DOWN") && strcmp(state,"OFF")) break;
        }
        // Do not map an unknown chip's state layout to a mismatched frequency table.
        if (states-offset != count) continue;
        for (int j=0; j<count; j++) {
            int64_t residency=h->residency(channel,j+offset);
            if (residency>0) { weighted+=(double)residency*table[j]; active+=(double)residency; }
        }
    }
    CFRelease(delta);
    return active>0 ? (int)round(weighted/active) : 0;
}
PHRHardware *phr_hardware_create(void) {
    PHRHardware *h=calloc(1,sizeof(*h));
    if (h) { initSMC(h); initClock(h); }
    return h;
}
void phr_hardware_destroy(PHRHardware *h) {
    if (!h) return;
    if (h->smc) IOServiceClose(h->smc);
    if (h->previous) CFRelease(h->previous);
    if (h->channels) CFRelease(h->channels);
    if (h->subscription) CFRelease(h->subscription);
    if (h->library) dlclose(h->library);
    free(h);
}
PHRSensors phr_hardware_sample(PHRHardware *h) {
    PHRSensors result={.cpuTemperature=NAN,.gpuTemperature=NAN,.fanRPM=-1,.cpuMHz=0};
    if (!h) return result;
    double cpu=0,gpu=0; int cpus=0,gpus=0;
    for (int i=0;i<h->sensorCount;i++) {
        Sensor s=h->sensors[i]; double v=numeric(h,s);
        if (!isfinite(v)) continue;
        if (s.kind==3 && v>=0 && v<65536) { if (v>result.fanRPM) result.fanRPM=(int)round(v); }
        if (v<=0 || v>150) continue;
        if (s.kind==1) { cpu+=v; cpus++; }
        if (s.kind==2) { gpu+=v; gpus++; }
    }
    if (cpus) result.cpuTemperature=cpu/cpus;
    if (gpus) result.gpuTemperature=gpu/gpus;
    result.cpuMHz=sampleClock(h);
    return result;
}
