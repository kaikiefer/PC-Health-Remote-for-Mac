#pragma once
typedef struct PHRHardware PHRHardware;
typedef struct {
    double cpuTemperature, gpuTemperature;
    int fanRPM, cpuMHz;
} PHRSensors;
PHRHardware *phr_hardware_create(void);
void phr_hardware_destroy(PHRHardware *hardware);
PHRSensors phr_hardware_sample(PHRHardware *hardware);
