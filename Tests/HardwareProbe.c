#include "../Sources/Hardware/Hardware.h"
#include <stdio.h>
#include <unistd.h>
int main(void) {
    PHRHardware *hardware=phr_hardware_create();
    for(int i=0;i<3;i++) {
        PHRSensors s=phr_hardware_sample(hardware);
        printf("CPU %.1f C, GPU %.1f C, clock %d MHz, fan %d RPM (-1=absent)\n",s.cpuTemperature,s.gpuTemperature,s.cpuMHz,s.fanRPM);
        sleep(1);
    }
    phr_hardware_destroy(hardware);
    return 0;
}
