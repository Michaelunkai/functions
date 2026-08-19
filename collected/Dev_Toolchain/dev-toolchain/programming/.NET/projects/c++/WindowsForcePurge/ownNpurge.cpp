#include <windows.h>
#include <iostream>
#include <string>
#include <vector>
#include <shlobj.h>
#include <sddl.h>
#include <aclapi.h>
#include <psapi.h>
#include <io.h>
#include <sys/stat.h>

class OwnNPurge {
private:
    bool isRecursive;
    
    // Helper function to convert wide string to UTF-8
    std::string wideStringToUTF8(const std::wstring& wstr) {
        if (wstr.empty()) return std::string();
        
        int size_needed = WideCharToMultiByte(CP_UTF8, 0, &wstr[0], (int)wstr.size(), NULL, 0, NULL, NULL);
        std::string result(size_needed, 0);
        WideCharToMultiByte(CP_UTF8, 0, &wstr[0], (int)wstr.size(), &result[0], size_needed, NULL, NULL);
        return result;
    }
    
    // Helper function to convert UTF-8 to wide string
    std::wstring utf8ToWideString(const std::string& str) {
        if (str.empty()) return std::wstring();
        
        int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
        std::wstring result(size_needed, 0);
        MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &result[0], size_needed);
        return result;
    }
    
    // Function to take ownership of a single file/directory
    bool takeOwnership(const std::wstring& path) {
        // Get current process token
        HANDLE hToken = NULL;
        TOKEN_PRIVILEGES tp;
        LUID luid;
        
        // Open process token
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &hToken)) {
            std::wcout << L"[-] Failed to open process token. Error: " << GetLastError() << std::endl;
            return false;
        }
        
        // Get the LUID for SE_TAKE_OWNERSHIP_NAME privilege
        if (!LookupPrivilegeValue(NULL, SE_TAKE_OWNERSHIP_NAME, &luid)) {
            std::wcout << L"[-] Failed to lookup privilege value. Error: " << GetLastError() << std::endl;
            CloseHandle(hToken);
            return false;
        }
        
        // Enable the privilege
        tp.PrivilegeCount = 1;
        tp.Privileges[0].Luid = luid;
        tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
        
        if (!AdjustTokenPrivileges(hToken, FALSE, &tp, sizeof(TOKEN_PRIVILEGES), NULL, NULL)) {
            std::wcout << L"[-] Failed to adjust token privileges. Error: " << GetLastError() << std::endl;
            CloseHandle(hToken);
            return false;
        }
        
        CloseHandle(hToken);
        
        // Get current user's SID
        HANDLE hProcessToken = NULL;
        DWORD dwSize = 0;
        PTOKEN_USER pTokenUser = NULL;
        PSID pUserSID = NULL;
        
        if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &hProcessToken)) {
            GetTokenInformation(hProcessToken, TokenUser, NULL, 0, &dwSize);
            pTokenUser = (PTOKEN_USER)LocalAlloc(LPTR, dwSize);
            
            if (pTokenUser && GetTokenInformation(hProcessToken, TokenUser, pTokenUser, dwSize, &dwSize)) {
                DWORD sidLength = GetLengthSid(pTokenUser->User.Sid);
                pUserSID = LocalAlloc(LPTR, sidLength);
                if (pUserSID) {
                    if (!CopySid(sidLength, pUserSID, pTokenUser->User.Sid)) {
                        LocalFree(pUserSID);
                        pUserSID = NULL;
                    }
                }
            }
            CloseHandle(hProcessToken);
        }
        
        if (!pUserSID) {
            // Fallback: try to get current user's SID using different method
            wchar_t username[256];
            DWORD username_len = 256;
            if (GetUserNameW(username, &username_len)) {
                SID_NAME_USE sidType;
                DWORD sidSize = 0;
                wchar_t domain[256];
                DWORD domainSize = 256;
                
                // First call to get required SID size
                LookupAccountNameW(NULL, username, NULL, &sidSize, domain, &domainSize, &sidType);
                if (sidSize > 0) {
                    pUserSID = LocalAlloc(LPTR, sidSize);
                    if (pUserSID) {
                        if (!LookupAccountNameW(NULL, username, pUserSID, &sidSize, domain, &domainSize, &sidType)) {
                            LocalFree(pUserSID);
                            pUserSID = NULL;
                        }
                    }
                }
            }
        }
        
        if (!pUserSID) {
            std::wcout << L"[-] Failed to get user SID" << std::endl;
            return false;
        }
        
        // Set ownership
        DWORD result = SetNamedSecurityInfoW(const_cast<LPWSTR>(path.c_str()), SE_FILE_OBJECT, 
                                           OWNER_SECURITY_INFORMATION, pUserSID, NULL, NULL, NULL);
        
        LocalFree(pUserSID);
        
        if (result != ERROR_SUCCESS) {
            std::wcout << L"[-] Failed to set ownership. Error: " << result << std::endl;
            return false;
        }
        
        return true;
    }
    
    
    // Recursive function to take ownership of all files and subdirectories
    bool takeOwnershipRecursive(const std::wstring& path) {
        WIN32_FIND_DATAW findData;
        std::wstring searchPath = path + L"\\*";
        HANDLE hFind = FindFirstFileW(searchPath.c_str(), &findData);
        
        if (hFind == INVALID_HANDLE_VALUE) {
            return false;
        }
        
        do {
            if (wcscmp(findData.cFileName, L".") == 0 || wcscmp(findData.cFileName, L"..") == 0) {
                continue;
            }
            
            std::wstring fullPath = path + L"\\" + findData.cFileName;
            
            if (findData.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
                // Recursively process subdirectory
                if (!takeOwnershipRecursive(fullPath)) {
                    std::wcout << L"[!] Warning: Could not take ownership of directory: " << fullPath << std::endl;
                }
            } else {
                // Take ownership of file
                if (!takeOwnership(fullPath)) {
                    std::wcout << L"[!] Warning: Could not take ownership of file: " << fullPath << std::endl;
                }
            }
        } while (FindNextFileW(hFind, &findData));
        
        FindClose(hFind);
        
        // Take ownership of the parent directory itself
        return takeOwnership(path);
    }
    
    // Function to delete a single file
    bool deleteFile(const std::wstring& filePath) {
        // Remove read-only, hidden, and system attributes
        DWORD attributes = GetFileAttributesW(filePath.c_str());
        if (attributes != INVALID_FILE_ATTRIBUTES) {
            attributes &= ~(FILE_ATTRIBUTE_READONLY | FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM);
            SetFileAttributesW(filePath.c_str(), attributes);
        }
        
        // Try to delete the file normally first
        if (DeleteFileW(filePath.c_str())) {
            return true;
        }
        
        // If normal delete fails, try with backup semantics
        HANDLE hFile = CreateFileW(filePath.c_str(), 
                                 DELETE | FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES,
                                 FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                 NULL, OPEN_EXISTING, 
                                 FILE_FLAG_BACKUP_SEMANTICS | FILE_ATTRIBUTE_NORMAL, NULL);
        
        if (hFile != INVALID_HANDLE_VALUE) {
            FILE_DISPOSITION_INFO dispositionInfo;
            dispositionInfo.Delete = TRUE;
            
            if (SetFileInformationByHandle(hFile, FileDispositionInfo, &dispositionInfo, sizeof(dispositionInfo))) {
                CloseHandle(hFile);
                return true;
            }
            CloseHandle(hFile);
        }
        
        // If still failing, try alternative methods for stubborn files
        // Method 1: Try moving to temp location then deleting
        wchar_t tempPath[MAX_PATH];
        GetTempPathW(MAX_PATH, tempPath);
        std::wstring tempFile = std::wstring(tempPath) + L"temp_delete_" + std::to_wstring(GetCurrentProcessId()) + L"_" + std::to_wstring(GetTickCount64());
        
        if (MoveFileW(filePath.c_str(), tempFile.c_str())) {
            // If moved successfully, try to delete from temp location
            if (DeleteFileW(tempFile.c_str())) {
                return true;
            } else {
                // If temp delete fails, try backup semantics on temp file
                HANDLE hTemp = CreateFileW(tempFile.c_str(), 
                                         DELETE | FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES,
                                         FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                         NULL, OPEN_EXISTING, 
                                         FILE_FLAG_BACKUP_SEMANTICS | FILE_ATTRIBUTE_NORMAL, NULL);
                if (hTemp != INVALID_HANDLE_VALUE) {
                    FILE_DISPOSITION_INFO dispositionInfo;
                    dispositionInfo.DeleteFile = TRUE;
                    if (SetFileInformationByHandle(hTemp, FileDispositionInfo, &dispositionInfo, sizeof(dispositionInfo))) {
                        CloseHandle(hTemp);
                        return true;
                    }
                    CloseHandle(hTemp);
                }
            }
            // If temp move didn't work, try to move back
            MoveFileW(tempFile.c_str(), filePath.c_str());
        }
        
        // Method 2: Try renaming and then deleting (for locked files)
        std::wstring renamedPath = filePath + L".tmp_delete";
        if (MoveFileW(filePath.c_str(), renamedPath.c_str())) {
            if (DeleteFileW(renamedPath.c_str())) {
                return true;
            } else {
                // Try backup semantics on renamed file
                HANDLE hRenamed = CreateFileW(renamedPath.c_str(), 
                                            DELETE | FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES,
                                            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                            NULL, OPEN_EXISTING, 
                                            FILE_FLAG_BACKUP_SEMANTICS | FILE_ATTRIBUTE_NORMAL, NULL);
                if (hRenamed != INVALID_HANDLE_VALUE) {
                    FILE_DISPOSITION_INFO dispositionInfo;
                    dispositionInfo.DeleteFile = TRUE;
                    if (SetFileInformationByHandle(hRenamed, FileDispositionInfo, &dispositionInfo, sizeof(dispositionInfo))) {
                        CloseHandle(hRenamed);
                        return true;
                    }
                    CloseHandle(hRenamed);
                }
            }
            // Try to move back if deletion failed
            MoveFileW(renamedPath.c_str(), filePath.c_str());
        }
        
        return false;
    }
    
    // Recursive function to delete directory and all contents
    bool deleteDirectoryRecursive(const std::wstring& dirPath) {
        WIN32_FIND_DATAW findData;
        std::wstring searchPath = dirPath + L"\\*";
        HANDLE hFind = FindFirstFileW(searchPath.c_str(), &findData);
        
        if (hFind == INVALID_HANDLE_VALUE) {
            return false;
        }
        
        do {
            if (wcscmp(findData.cFileName, L".") == 0 || wcscmp(findData.cFileName, L"..") == 0) {
                continue;
            }
            
            std::wstring fullPath = dirPath + L"\\" + findData.cFileName;
            
            if (findData.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
                // Recursively delete subdirectory
                if (!deleteDirectoryRecursive(fullPath)) {
                    std::wcout << L"[!] Warning: Could not delete subdirectory: " << fullPath << std::endl;
                    return false;
                }
            } else {
                // Delete file
                if (!deleteFile(fullPath)) {
                    std::wcout << L"[!] Warning: Could not delete file: " << fullPath << std::endl;
                    return false;
                }
            }
        } while (FindNextFileW(hFind, &findData));
        
        FindClose(hFind);
        
        // Finally, delete the empty directory
        DWORD attributes = GetFileAttributesW(dirPath.c_str());
        if (attributes != INVALID_FILE_ATTRIBUTES) {
            attributes &= ~(FILE_ATTRIBUTE_READONLY | FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM);
            SetFileAttributesW(dirPath.c_str(), attributes);
        }
        
        return RemoveDirectoryW(dirPath.c_str());
    }
    
    // Check if path is directory
    bool isDirectory(const std::wstring& path) {
        DWORD attributes = GetFileAttributesW(path.c_str());
        return (attributes != INVALID_FILE_ATTRIBUTES) && 
               (attributes & FILE_ATTRIBUTE_DIRECTORY);
    }
    
    // Check if path exists
    bool pathExists(const std::wstring& path) {
        return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
    }

public:
    OwnNPurge() : isRecursive(true) {}
    
    bool run(const std::string& path) {
        if (path.empty()) {
            std::cout << "[-] Error: No path provided." << std::endl;
            return false;
        }
        
        std::wstring wPath = utf8ToWideString(path);
        
        if (!pathExists(wPath)) {
            std::wcout << L"[-] Error: Path does not exist: " << wPath << std::endl;
            return false;
        }
        
        std::wcout << L"[+] Target path: " << wPath << std::endl;
        std::wcout << L"[+] Taking ownership of all files and directories..." << std::endl;
        
        // Take ownership
        bool ownershipSuccess = false;
        if (isDirectory(wPath)) {
            ownershipSuccess = takeOwnershipRecursive(wPath);
        } else {
            ownershipSuccess = takeOwnership(wPath);
        }
        
        if (!ownershipSuccess) {
            std::wcout << L"[!] Warning: Some files/directories may not have had ownership taken." << std::endl;
        } else {
            std::wcout << L"[+] Ownership taken successfully." << std::endl;
        }
        
        std::wcout << L"[+] Purging files and directories..." << std::endl;
        
        // Delete files/directories
        bool deleteSuccess = false;
        if (isDirectory(wPath)) {
            deleteSuccess = deleteDirectoryRecursive(wPath);
        } else {
            deleteSuccess = deleteFile(wPath);
        }
        
        if (deleteSuccess) {
            std::wcout << L"[+] Successfully purged: " << wPath << std::endl;
            return true;
        } else {
            std::wcout << L"[-] Failed to purge: " << wPath << std::endl;
            std::wcout << L"[-] Error code: " << GetLastError() << std::endl;
            return false;
        }
    }
    
    bool runMultiple(const std::vector<std::string>& paths) {
        bool allSuccess = true;
        int processedCount = 0;
        int successCount = 0;
        
        for (const auto& path : paths) {
            std::wcout << L"[*] Processing path " << processedCount + 1 << L" of " << paths.size() << L": " << utf8ToWideString(path) << std::endl;
            std::wcout << L"--------------------------------------------------------" << std::endl;
            
            bool success = run(path);
            if (success) {
                successCount++;
            } else {
                allSuccess = false;
            }
            processedCount++;
            
            std::wcout << L"[*] Finished processing path " << processedCount << L" of " << paths.size() << std::endl;
            std::wcout << L"--------------------------------------------------------" << std::endl;
            std::wcout << std::endl;
        }
        
        std::wcout << L"[+] Summary: " << successCount << L" out of " << processedCount << L" paths processed successfully." << std::endl;
        if (!allSuccess) {
            std::wcout << L"[-] Some paths failed to process completely." << std::endl;
        }
        return allSuccess;
    }
    
    void printUsage() {
        std::cout << "Usage: ownNpurge.exe <Path1> [Path2] [Path3] ... [PathN]" << std::endl;
        std::cout << "This application will take ownership of the specified file/folder and force delete it." << std::endl;
        std::cout << "Multiple paths can be specified to purge multiple locations in one execution." << std::endl;
        std::cout << "Note: This application may require administrator privileges for some operations." << std::endl;
    }
};

int main(int argc, char* argv[]) {
    std::cout << "=== OwnN'Purge - Comprehensive File/Folder Ownership and Purge Tool ===" << std::endl;
    std::cout << "Version 1.0 - Forcibly takes ownership and purges files/folders" << std::endl;
    std::cout << std::endl;
    
    if (argc < 2) {
        std::cout << "[-] Error: No paths specified." << std::endl;
        std::cout << std::endl;
        OwnNPurge().printUsage();
        return 1;
    }
    
    // Check if running as administrator
    HANDLE hToken = NULL;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &hToken)) {
        TOKEN_ELEVATION elevation;
        DWORD dwSize;
        if (GetTokenInformation(hToken, TokenElevation, &elevation, sizeof(elevation), &dwSize)) {
            if (!elevation.TokenIsElevated) {
                std::cout << "[!] Warning: Not running as administrator. Some operations may fail." << std::endl;
                std::cout << "[!] Consider running as administrator for best results." << std::endl;
                std::cout << std::endl;
            }
        }
        CloseHandle(hToken);
    }
    
    // Collect all paths from command line arguments
    std::vector<std::string> paths;
    for (int i = 1; i < argc; i++) {
        paths.push_back(argv[i]);
    }
    
    OwnNPurge purger;
    bool success = purger.runMultiple(paths);
    
    if (success) {
        std::cout << std::endl;
        std::cout << "[+] Operation completed successfully!" << std::endl;
        std::cout << "[+] Target has been purged." << std::endl;
    } else {
        std::cout << std::endl;
        std::cout << "[-] Operation failed!" << std::endl;
        std::cout << "[-] Some files may still exist." << std::endl;
        return 1;
    }
    
    return 0;
}
