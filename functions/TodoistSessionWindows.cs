using System;
using System.IO;
using System.Security.Cryptography;
using Microsoft.Win32;
internal static class TodoistSessionWindows {
 const string KeyPath = @"Software\Micha\DockerAppRestore\Todoist";
 static byte[] Input() {
  string value = Console.In.ReadToEnd();
  if(value.Length > 96 * 1024 * 1024) throw new InvalidDataException();
  return Convert.FromBase64String(value.Trim());
 }
 static void Output(byte[] data) { try { Console.Out.Write(Convert.ToBase64String(data)); } finally { Array.Clear(data,0,data.Length); } }
 static int Main(string[] args) {
  try {
   if(args.Length != 1) { Console.Error.Write("INVALID_OPERATION"); return 2; }
   if(args[0] == "unprotect-key") {
    byte[] encrypted = Input();
    Output(ProtectedData.Unprotect(encrypted,null,DataProtectionScope.CurrentUser)); return 0;
   }
   using(RegistryKey hive = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser,RegistryView.Registry64)) {
    if(args[0] == "read") {
     using(RegistryKey key = hive.OpenSubKey(KeyPath,false)) {
      if(key == null) { Console.Error.Write("STORE_MISSING"); return 3; }
      byte[] data = key.GetValue("Session") as byte[];
      if(data == null || data.Length == 0) { Console.Error.Write("SESSION_MISSING"); return 3; }
      Output(ProtectedData.Unprotect(data,null,DataProtectionScope.CurrentUser)); return 0;
     }
    }
    if(args[0] == "write") {
     byte[] clear = Input(); byte[] encrypted;
     try { encrypted = ProtectedData.Protect(clear,null,DataProtectionScope.CurrentUser); }
     finally { Array.Clear(clear,0,clear.Length); }
     using(RegistryKey key = hive.CreateSubKey(KeyPath)) { key.SetValue("Session",encrypted,RegistryValueKind.Binary); key.Flush(); }
     return 0;
    }
   }
   Console.Error.Write("INVALID_OPERATION"); return 2;
  } catch(CryptographicException) { Console.Error.Write("WINDOWS_USER_DECRYPTION_FAILED"); return 4; }
    catch(UnauthorizedAccessException) { Console.Error.Write("STORE_ACCESS_DENIED"); return 5; }
    catch(FormatException) { Console.Error.Write("INVALID_PROTECTED_DATA"); return 6; }
    catch(Exception) { Console.Error.Write("WINDOWS_STORE_IO_FAILED"); return 7; }
 }
}