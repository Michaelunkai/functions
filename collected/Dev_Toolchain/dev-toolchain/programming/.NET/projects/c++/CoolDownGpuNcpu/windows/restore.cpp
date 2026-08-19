#include <windows.h>
#include <powrprof.h>
#include <string>
#include <fstream>

#pragma comment(lib, "powrprof.lib")

// Default Balanced power plan GUID
GUID GUID_BALANCED = {0x381b4222, 0xf694, 0x41f0, {0x96, 0x85, 0xff, 0x5b, 0xb2, 0x60, 0xdf, 0x2e}};

void RestorePowerState() {
    GUID savedScheme;
    bool hasSavedState = false;
    std::ifstream file("F:\\downloads\\coool\\power_state.dat", std::ios::binary);

    if (file.is_open()) {
        file.read(reinterpret_cast<char*>(&savedScheme), sizeof(GUID));
        file.close();
        hasSavedState = true;

        // Restore the saved power plan
        PowerSetActiveScheme(NULL, &savedScheme);

        // Delete the state file
        DeleteFileA("F:\\downloads\\coool\\power_state.dat");
    } else {
        // If no saved state, restore to Balanced
        PowerSetActiveScheme(NULL, &GUID_BALANCED);
    }

    // Processor power management subgroup
    GUID subgroupGuid = {0x54533251, 0x82be, 0x4824, {0x96, 0xc1, 0x47, 0xb6, 0x0b, 0x74, 0x0d, 0x00}};
    GUID minProcStateGuid = {0x893dee8e, 0x2bef, 0x41e0, {0x89, 0xc6, 0xb5, 0x5d, 0x09, 0x29, 0x96, 0x4c}};
    GUID maxProcStateGuid = {0xbc5038f7, 0x23e0, 0x4960, {0x96, 0xda, 0x33, 0xab, 0xaf, 0x59, 0x35, 0xec}};
    GUID turboModeGuid = {0xbe337238, 0x0d82, 0x4146, {0xa9, 0x60, 0x4f, 0x37, 0x49, 0xd4, 0x70, 0xc7}};

    // System cooling policy GUID
    GUID systemCoolingGuid = {0x94d3a615, 0xa899, 0x4ac5, {0xae, 0x2b, 0xe4, 0xd8, 0xf6, 0x34, 0x36, 0x7f}};

    // Restore normal processor state
    DWORD minValue = 5;
    DWORD maxValue = 100;
    DWORD turboEnabled = 1;  // Re-enable turbo boost
    DWORD activeCooling = 0;  // Active cooling (fans run at full speed for performance)

    if (hasSavedState) {
        PowerWriteACValueIndex(NULL, &savedScheme, &subgroupGuid, &minProcStateGuid, minValue);
        PowerWriteDCValueIndex(NULL, &savedScheme, &subgroupGuid, &minProcStateGuid, minValue);
        PowerWriteACValueIndex(NULL, &savedScheme, &subgroupGuid, &maxProcStateGuid, maxValue);
        PowerWriteDCValueIndex(NULL, &savedScheme, &subgroupGuid, &maxProcStateGuid, maxValue);

        // Restore turbo boost
        PowerWriteACValueIndex(NULL, &savedScheme, &subgroupGuid, &turboModeGuid, turboEnabled);
        PowerWriteDCValueIndex(NULL, &savedScheme, &subgroupGuid, &turboModeGuid, turboEnabled);

        // Restore active cooling
        PowerWriteACValueIndex(NULL, &savedScheme, NULL, &systemCoolingGuid, activeCooling);
        PowerWriteDCValueIndex(NULL, &savedScheme, NULL, &systemCoolingGuid, activeCooling);

        PowerSetActiveScheme(NULL, &savedScheme);
    } else {
        PowerWriteACValueIndex(NULL, &GUID_BALANCED, &subgroupGuid, &minProcStateGuid, minValue);
        PowerWriteDCValueIndex(NULL, &GUID_BALANCED, &subgroupGuid, &minProcStateGuid, minValue);
        PowerWriteACValueIndex(NULL, &GUID_BALANCED, &subgroupGuid, &maxProcStateGuid, maxValue);
        PowerWriteDCValueIndex(NULL, &GUID_BALANCED, &subgroupGuid, &maxProcStateGuid, maxValue);

        // Restore turbo boost
        PowerWriteACValueIndex(NULL, &GUID_BALANCED, &subgroupGuid, &turboModeGuid, turboEnabled);
        PowerWriteDCValueIndex(NULL, &GUID_BALANCED, &subgroupGuid, &turboModeGuid, turboEnabled);

        // Restore active cooling
        PowerWriteACValueIndex(NULL, &GUID_BALANCED, NULL, &systemCoolingGuid, activeCooling);
        PowerWriteDCValueIndex(NULL, &GUID_BALANCED, NULL, &systemCoolingGuid, activeCooling);

        PowerSetActiveScheme(NULL, &GUID_BALANCED);
    }
}

void RestoreGPU() {
    // Restore NVIDIA GPU to default settings
    std::string nvidiaPath = "C:\\Program Files\\NVIDIA Corporation\\NVSMI\\nvidia-smi.exe";

    // Reset graphics clock to default
    std::string command = "\"" + nvidiaPath + "\" -rgc > nul 2>&1";
    system(command.c_str());

    // Reset memory clock to default
    command = "\"" + nvidiaPath + "\" -rmc > nul 2>&1";
    system(command.c_str());

    // Reset power limit to default (0 = default)
    command = "\"" + nvidiaPath + "\" -pl 0 > nul 2>&1";
    system(command.c_str());

    // Disable persistence mode
    command = "\"" + nvidiaPath + "\" -pm 0 > nul 2>&1";
    system(command.c_str());

    // Reset compute mode to default
    command = "\"" + nvidiaPath + "\" -c 0 > nul 2>&1";
    system(command.c_str());
}

void RestoreProcessPriority() {
    // Restore this process to normal priority
    SetPriorityClass(GetCurrentProcess(), NORMAL_PRIORITY_CLASS);
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

    // Restore all settings immediately
    RestorePowerState();
    RestoreGPU();
    RestoreProcessPriority();

    // No message box - just exit silently
    return 0;
}
