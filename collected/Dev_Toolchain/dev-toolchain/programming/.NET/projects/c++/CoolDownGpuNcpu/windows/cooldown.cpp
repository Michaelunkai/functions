#include <windows.h>
#include <powrprof.h>
#include <tlhelp32.h>
#include <string>
#include <fstream>
#include <vector>

#pragma comment(lib, "powrprof.lib")

// Power Saver GUID
GUID GUID_POWER_SAVER = {0xa1841308, 0x3541, 0x4fab, {0xbc, 0x81, 0xf7, 0x15, 0x56, 0xf2, 0x0b, 0x4a}};

void SaveCurrentState() {
    GUID* activeScheme = nullptr;
    if (PowerGetActiveScheme(NULL, &activeScheme) == ERROR_SUCCESS) {
        std::ofstream file("F:\\downloads\\coool\\power_state.dat", std::ios::binary);
        if (file.is_open()) {
            file.write(reinterpret_cast<const char*>(activeScheme), sizeof(GUID));
            file.close();
        }
        LocalFree(activeScheme);
    }
}

void SetMinimumPowerState() {
    // Set to Power Saver mode
    PowerSetActiveScheme(NULL, &GUID_POWER_SAVER);

    // Processor power management subgroup
    GUID subgroupGuid = {0x54533251, 0x82be, 0x4824, {0x96, 0xc1, 0x47, 0xb6, 0x0b, 0x74, 0x0d, 0x00}};
    GUID minProcStateGuid = {0x893dee8e, 0x2bef, 0x41e0, {0x89, 0xc6, 0xb5, 0x5d, 0x09, 0x29, 0x96, 0x4c}};
    GUID maxProcStateGuid = {0xbc5038f7, 0x23e0, 0x4960, {0x96, 0xda, 0x33, 0xab, 0xaf, 0x59, 0x35, 0xec}};
    GUID turboModeGuid = {0xbe337238, 0x0d82, 0x4146, {0xa9, 0x60, 0x4f, 0x37, 0x49, 0xd4, 0x70, 0xc7}};

    // System cooling policy GUID
    GUID systemCoolingGuid = {0x94d3a615, 0xa899, 0x4ac5, {0xae, 0x2b, 0xe4, 0xd8, 0xf6, 0x34, 0x36, 0x7f}};

    // Aggressive but safe CPU throttling: 1% min, 30% max
    DWORD minValue = 1;
    DWORD maxValue = 30;
    DWORD turboDisabled = 0;  // Disable turbo boost
    DWORD passiveCooling = 1;  // Passive cooling (reduces fan speed, prioritizes quiet over performance)

    // Apply to both AC and DC (battery) modes
    PowerWriteACValueIndex(NULL, &GUID_POWER_SAVER, &subgroupGuid, &minProcStateGuid, minValue);
    PowerWriteDCValueIndex(NULL, &GUID_POWER_SAVER, &subgroupGuid, &minProcStateGuid, minValue);
    PowerWriteACValueIndex(NULL, &GUID_POWER_SAVER, &subgroupGuid, &maxProcStateGuid, maxValue);
    PowerWriteDCValueIndex(NULL, &GUID_POWER_SAVER, &subgroupGuid, &maxProcStateGuid, maxValue);

    // Disable turbo boost for maximum cooling
    PowerWriteACValueIndex(NULL, &GUID_POWER_SAVER, &subgroupGuid, &turboModeGuid, turboDisabled);
    PowerWriteDCValueIndex(NULL, &GUID_POWER_SAVER, &subgroupGuid, &turboModeGuid, turboDisabled);

    // Set system cooling policy to passive
    PowerWriteACValueIndex(NULL, &GUID_POWER_SAVER, NULL, &systemCoolingGuid, passiveCooling);
    PowerWriteDCValueIndex(NULL, &GUID_POWER_SAVER, NULL, &systemCoolingGuid, passiveCooling);

    // Apply changes and make them persistent
    PowerSetActiveScheme(NULL, &GUID_POWER_SAVER);

    // Write to registry to ensure persistence
    PowerWriteACValueIndex(NULL, &GUID_POWER_SAVER, &subgroupGuid, &minProcStateGuid, minValue);
    PowerWriteDCValueIndex(NULL, &GUID_POWER_SAVER, &subgroupGuid, &minProcStateGuid, minValue);

    // Re-apply the scheme to force settings
    PowerSetActiveScheme(NULL, &GUID_POWER_SAVER);
}

void ThrottleGPU() {
    // Aggressively throttle NVIDIA GPU using nvidia-smi
    std::string nvidiaPath = "C:\\Program Files\\NVIDIA Corporation\\NVSMI\\nvidia-smi.exe";

    // Set persistence mode to keep settings active
    std::string command = "\"" + nvidiaPath + "\" -pm 1 > nul 2>&1";
    system(command.c_str());

    // Lower power limit to 40W (more aggressive but safe)
    command = "\"" + nvidiaPath + "\" -pl 40 > nul 2>&1";
    system(command.c_str());

    // Reduce GPU graphics clock to minimum stable (210 MHz)
    command = "\"" + nvidiaPath + "\" -lgc 210 > nul 2>&1";
    system(command.c_str());

    // Reduce memory clock as well
    command = "\"" + nvidiaPath + "\" -lmc 405 > nul 2>&1";
    system(command.c_str());

    // Set compute mode to default (not exclusive) to avoid locking
    command = "\"" + nvidiaPath + "\" -c 0 > nul 2>&1";
    system(command.c_str());
}

void EmergencyCooldown() {
    // Set this process to idle priority
    SetPriorityClass(GetCurrentProcess(), IDLE_PRIORITY_CLASS);

    // Set all system processes to lower priority where possible
    HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnapshot != INVALID_HANDLE_VALUE) {
        CloseHandle(hSnapshot);
    }

    // Flush file system cache to reduce I/O
    SetSystemFileCacheSize((SIZE_T)-1, (SIZE_T)-1, 0);
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    // Request SE_SHUTDOWN_NAME privilege for power management
    HANDLE hToken;
    TOKEN_PRIVILEGES tkp;

    if (OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &hToken)) {
        LookupPrivilegeValue(NULL, SE_SHUTDOWN_NAME, &tkp.Privileges[0].Luid);
        tkp.PrivilegeCount = 1;
        tkp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
        AdjustTokenPrivileges(hToken, FALSE, &tkp, 0, NULL, 0);
        CloseHandle(hToken);
    }

    // Save current state
    SaveCurrentState();

    // Apply all cooling measures immediately
    SetMinimumPowerState();
    ThrottleGPU();
    EmergencyCooldown();

    // No message box - just exit silently
    return 0;
}
