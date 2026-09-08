using System;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;
using System.Threading;

public static class GMenuPayload20260907 {
    public static Action<string,long,long> RuntimeProgress;
    private static readonly object HeartbeatGate=new object();
    private static Timer HeartbeatTimer;
    private static long HeartbeatStarted;
    private static string HeartbeatPhase;
    public static void StartHeartbeat(string phase) {
        lock(HeartbeatGate) {
            HeartbeatPhase=phase;
            if(HeartbeatTimer!=null)return;
            HeartbeatStarted=Stopwatch.GetTimestamp();
            HeartbeatTimer=new Timer(delegate(object state) {
                try {
                    long elapsed=(Stopwatch.GetTimestamp()-HeartbeatStarted)*1000/Stopwatch.Frequency;
                    Console.WriteLine("GMENU_HEARTBEAT phase="+(HeartbeatPhase??"working")+" elapsed_ms="+elapsed);
                    Console.Out.Flush();
                } catch {}
            },null,0,1000);
        }
    }
    public static void SetHeartbeatPhase(string phase) { HeartbeatPhase=phase; }
    public static void StopHeartbeat() {
        lock(HeartbeatGate) {
            if(HeartbeatTimer!=null) {HeartbeatTimer.Dispose();HeartbeatTimer=null;}
        }
    }
    public sealed class Part { public string Name; public long Length; public string Sha256; }
    public sealed class PackedParts { public long Files; public long Bytes; public string Mac; public Part[] Parts; }
    private sealed class Record { public string Path; public string Name; public bool Directory; public long Length; public DateTime Modified; public FileAttributes Attributes; }
    private sealed class Progress {
        private Action<string,long,long> callback; private long last; private string phase;
        public Progress(Action<string,long,long> callback) {this.callback=callback;}
        public void Report(string stage,long done,long total,bool force) {
            long now=Stopwatch.GetTimestamp();
            if(callback!=null && (force || phase!=stage || now-last>Stopwatch.Frequency/5)) {last=now;phase=stage;callback(stage,done,total);}
        }
    }
    private static List<Record> Inventory(string[] roots,Progress progress,string phase) {
        var records=new List<Record>(); long files=0;
        progress.Report(phase,0,0,true);
        for(int i=0;i<roots.Length;i++) {
            string root=Extended(roots[i]).TrimEnd('\\'); string prefix=i==0?"app/":"data"+(i-1)+"/";
            var pending=new Stack<string>(); pending.Push(root);
            while(pending.Count>0) {
                string dir=pending.Pop();
                records.Add(new Record{Path=dir,Name=prefix+(dir==root?"":dir.Substring(root.Length+1).Replace('\\','/')+"/"),Directory=true});
                foreach(string path in Directory.EnumerateFileSystemEntries(dir)) {
                    var attrs=File.GetAttributes(path);
                    if((attrs&FileAttributes.ReparsePoint)!=0) continue;
                    if((attrs&FileAttributes.Directory)!=0) {pending.Push(path);continue;}
                    var info=new FileInfo(path);
                    records.Add(new Record{Path=path,Name=prefix+path.Substring(root.Length+1).Replace('\\','/'),Length=info.Length,Modified=info.LastWriteTimeUtc,Attributes=attrs});
                    files++;progress.Report(phase,files,0,false);
                }
            }
        }
        progress.Report(phase,files,Math.Max(1,files),true);return records;
    }
    private sealed class PartStream : Stream {
        private string directory; private long limit; private HMACSHA256 mac; private SHA256 hash; private FileStream file; private long length;
        public List<Part> Parts=new List<Part>(); public string Mac;
        public PartStream(string directory,long limit,byte[] key) {this.directory=directory;this.limit=limit;mac=new HMACSHA256(key);}
        private void ClosePart() {
            if(file==null)return;file.Dispose();hash.TransformFinalBlock(new byte[0],0,0);
            Parts.Add(new Part{Name=System.IO.Path.GetFileName(file.Name),Length=length,Sha256=BitConverter.ToString(hash.Hash).Replace("-","").ToLowerInvariant()});
            hash.Dispose();file=null;length=0;
        }
        public override void Write(byte[] buffer,int offset,int count) {
            while(count>0) {
                if(file==null) {file=new FileStream(System.IO.Path.Combine(directory,"gmenu-payload-"+Parts.Count.ToString("D5")+".bin"),FileMode.CreateNew,FileAccess.Write,FileShare.None,1048576);hash=SHA256.Create();}
                int n=(int)Math.Min(count,limit-length);file.Write(buffer,offset,n);
                hash.TransformBlock(buffer,offset,n,null,0);mac.TransformBlock(buffer,offset,n,null,0);
                length+=n;offset+=n;count-=n;if(length==limit)ClosePart();
            }
        }
        public void Complete() {ClosePart();mac.TransformFinalBlock(new byte[0],0,0);Mac=Convert.ToBase64String(mac.Hash);}
        protected override void Dispose(bool disposing) {if(disposing){if(file!=null)file.Dispose();if(hash!=null)hash.Dispose();mac.Dispose();}base.Dispose(disposing);}
        public override bool CanRead{get{return false;}} public override bool CanSeek{get{return false;}} public override bool CanWrite{get{return true;}}
        public override long Length{get{throw new NotSupportedException();}} public override long Position{get{throw new NotSupportedException();}set{throw new NotSupportedException();}}
        public override void Flush(){if(file!=null)file.Flush();} public override int Read(byte[] b,int o,int n){throw new NotSupportedException();}
        public override long Seek(long o,SeekOrigin s){throw new NotSupportedException();} public override void SetLength(long n){throw new NotSupportedException();}
    }
    // One source read, one temporary ZIP, encryption + part hashing in a single pass.
    public static PackedParts PackParts(string[] roots,string manifest,string directory,byte[] key,byte[] iv,byte[] macKey,long partSize,Action<string,long,long> callback) {
        if(partSize<16)throw new ArgumentOutOfRangeException("partSize");
        var progress=new Progress(callback);var before=Inventory(roots,progress,"scan-snapshot");
        long files=0,total=0;foreach(var r in before)if(!r.Directory){files++;total+=r.Length;}
        string zipPath=Extended(System.IO.Path.Combine(directory,"payload.zip.partial"));Directory.CreateDirectory(directory);
        byte[] buffer=new byte[1048576];long done=0;
        try {
            progress.Report("archive",0,Math.Max(1,total),true);
            using(var stream=new FileStream(zipPath,FileMode.CreateNew,FileAccess.ReadWrite,FileShare.None,1048576))
            using(var zip=new ZipArchive(stream,ZipArchiveMode.Create,false)) {
                using(var writer=new StreamWriter(zip.CreateEntry("gmenu-manifest.json").Open(),new UTF8Encoding(false)))writer.Write(manifest);
                foreach(var r in before) {
                    var entry=zip.CreateEntry(r.Name,CompressionLevel.Fastest);if(r.Directory)continue;
                    if(r.Modified.Year>=1980 && r.Modified.Year<2108)entry.LastWriteTime=r.Modified;entry.ExternalAttributes=(int)r.Attributes;
                    long copied=0;
                    using(var input=new FileStream(r.Path,FileMode.Open,FileAccess.Read,FileShare.Read,1048576))
                    using(var output=entry.Open()) {int n;while((n=input.Read(buffer,0,buffer.Length))>0){output.Write(buffer,0,n);done+=n;copied+=n;progress.Report("archive",done,Math.Max(1,total),false);}}
                    if(copied!=r.Length)throw new IOException("Source changed during archive: "+r.Name);
                }
            }
            progress.Report("archive",Math.Max(1,total),Math.Max(1,total),true);
            var after=Inventory(roots,progress,"verify-snapshot");
            if(before.Count!=after.Count)throw new IOException("Source entries changed during archive.");
            var map=new Dictionary<string,Record>(StringComparer.OrdinalIgnoreCase);foreach(var r in before)map.Add(r.Name,r);
            foreach(var r in after){Record old;if(!map.TryGetValue(r.Name,out old) || r.Directory!=old.Directory || r.Length!=old.Length || r.Modified!=old.Modified || r.Attributes!=old.Attributes)throw new IOException("Source changed during archive: "+r.Name);}
            using(var parts=new PartStream(directory,partSize,macKey))
            using(var aes=Aes.Create()) {
                aes.Key=key;aes.IV=iv;
                using(var input=File.OpenRead(zipPath)) {
                    done=0;progress.Report("encrypt",0,input.Length,true);
                    using(var crypt=new CryptoStream(parts,aes.CreateEncryptor(),CryptoStreamMode.Write,true)) {
                        int n;while((n=input.Read(buffer,0,buffer.Length))>0){crypt.Write(buffer,0,n);done+=n;progress.Report("encrypt",done,input.Length,false);}
                    }
                    parts.Complete();progress.Report("encrypt",done,input.Length,true);
                }
                return new PackedParts{Files=files,Bytes=total,Mac=parts.Mac,Parts=parts.Parts.ToArray()};
            }
        } finally {Array.Clear(buffer,0,buffer.Length);if(File.Exists(zipPath))File.Delete(zipPath);}
    }
    private static string Extended(string path) {
        return path.StartsWith(@"\\?\")?path:@"\\?\"+Path.GetFullPath(path);
    }
    public static void CopyTree(string source,string target) {
        var progress=new Progress(RuntimeProgress);long done=0;
        progress.Report("copy-data",0,0,true);
        CopyTree(Extended(source),Extended(target),progress,ref done);
        progress.Report("copy-data",done,0,true);
    }
    private static void CopyTree(string source,string target,Progress progress,ref long done) {
        Directory.CreateDirectory(target);
        foreach(string path in Directory.GetFileSystemEntries(source)) {
            var attrs=File.GetAttributes(path);
            if((attrs&FileAttributes.ReparsePoint)!=0) throw new IOException("Unexpected link in staged data.");
            string destination=Path.Combine(target,Path.GetFileName(path));
            if((attrs&FileAttributes.Directory)!=0) CopyTree(path,destination,progress,ref done);
            else {
                File.Copy(path,destination,false);File.SetLastWriteTimeUtc(destination,File.GetLastWriteTimeUtc(path));File.SetAttributes(destination,attrs);
                done+=new FileInfo(path).Length;progress.Report("copy-data",done,0,false);
            }
        }
    }
    public static void DeleteTree(string root) {
        var progress=new Progress(RuntimeProgress);long done=0;
        progress.Report("cleanup",0,0,true);
        DeleteTree(Extended(root),progress,ref done);
        progress.Report("cleanup",done,0,true);
    }
    private static void DeleteTree(string root,Progress progress,ref long done) {
        foreach(string path in Directory.GetFileSystemEntries(root)) {
            var attrs=File.GetAttributes(path);
            if((attrs&FileAttributes.Directory)!=0) {
                if((attrs&FileAttributes.ReparsePoint)!=0) Directory.Delete(path,false);
                else DeleteTree(path,progress,ref done);
            } else {if((attrs&FileAttributes.ReadOnly)!=0)File.SetAttributes(path,attrs&~FileAttributes.ReadOnly);done+=new FileInfo(path).Length;File.Delete(path);progress.Report("cleanup",done,0,false);}
        }
        File.SetAttributes(root,FileAttributes.Directory);
        Directory.Delete(root,false);
    }
    public static string Hash(string file) {
        var progress=new Progress(RuntimeProgress);long total=new FileInfo(file).Length,done=0;
        progress.Report("hash",0,total,true);
        using (var h = SHA256.Create()) using (var s = File.OpenRead(file)) {
            var buffer=new byte[1048576];int n;
            while((n=s.Read(buffer,0,buffer.Length))>0){h.TransformBlock(buffer,0,n,null,0);done+=n;progress.Report("hash",done,total,false);}
            h.TransformFinalBlock(new byte[0],0,0);
            progress.Report("hash",done,total,true);
            return BitConverter.ToString(h.Hash).Replace("-", "").ToLowerInvariant();
        }
    }
    public static string Mac(string file, byte[] key) {
        return Mac(file,key,new Progress(RuntimeProgress));
    }
    private static string Mac(string file, byte[] key, Progress progress) {
        long total=new FileInfo(file).Length,done=0;progress.Report("verify-mac",0,total,true);
        using (var h = new HMACSHA256(key)) using (var s = File.OpenRead(file)) {
            var buffer=new byte[1048576];int n;
            while((n=s.Read(buffer,0,buffer.Length))>0){h.TransformBlock(buffer,0,n,null,0);done+=n;progress.Report("verify-mac",done,total,false);}
            h.TransformFinalBlock(new byte[0],0,0);
            progress.Report("verify-mac",done,total,true);
            return Convert.ToBase64String(h.Hash);
        }
    }
    public static byte[] Random(int length) {
        var bytes = new byte[length]; using(var rng=RandomNumberGenerator.Create()) rng.GetBytes(bytes); return bytes;
    }
    public static long[] Pack(string[] roots, string manifest, string output, byte[] key, byte[] iv) {
        long files=0,bytes=0;
        string zipPath=Extended(output+".zip.partial");
        try {
            using(var zipStream=new FileStream(zipPath,FileMode.CreateNew,FileAccess.ReadWrite,FileShare.None,1048576))
            using(var zip=new ZipArchive(zipStream,ZipArchiveMode.Create,false)) {
                using(var writer=new StreamWriter(zip.CreateEntry("gmenu-manifest.json").Open(),new UTF8Encoding(false))) writer.Write(manifest);
                for(int i=0;i<roots.Length;i++) {
                    string root=Extended(roots[i]).TrimEnd('\\');
                    string prefix=i==0?"app/":"data"+(i-1)+"/";
                    var pending=new Stack<string>(); pending.Push(root);
                    while(pending.Count>0) {
                        string dir=pending.Pop();
                        string rel=dir==root?"":dir.Substring(root.Length+1).Replace('\\','/')+"/";
                        zip.CreateEntry(prefix+rel);
                        foreach(string path in Directory.GetFileSystemEntries(dir)) {
                            FileAttributes attrs=File.GetAttributes(path);
                            if((attrs&FileAttributes.ReparsePoint)!=0) continue; // Captured separately, never followed.
                            if((attrs&FileAttributes.Directory)!=0) {pending.Push(path); continue;}
                            var before=new FileInfo(path);
                            long length=before.Length; DateTime modified=before.LastWriteTimeUtc;
                            var entry=zip.CreateEntry(prefix+path.Substring(root.Length+1).Replace('\\','/'),CompressionLevel.Fastest);
                            if(modified.Year>=1980 && modified.Year<2108) entry.LastWriteTime=modified;
                            entry.ExternalAttributes=(int)attrs;
                            using(var source=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read))
                            using(var target=entry.Open()) source.CopyTo(target,1048576);
                            var after=new FileInfo(path);
                            if(after.Length!=length || after.LastWriteTimeUtc!=modified) throw new IOException("Source changed during snapshot: "+path);
                            files++;bytes+=length;
                        }
                    }
                }
            }
            using(var aes=Aes.Create()) {
                aes.Key=key; aes.IV=iv;
                using(var source=File.OpenRead(zipPath))
                using(var destination=new FileStream(output,FileMode.CreateNew,FileAccess.Write,FileShare.None,1048576))
                using(var crypt=new CryptoStream(destination,aes.CreateEncryptor(),CryptoStreamMode.Write))
                    source.CopyTo(crypt,1048576);
            }
        } finally { if(File.Exists(zipPath)) File.Delete(zipPath); }
        return new long[]{files,bytes};
    }
    public static void Decrypt(string source,string destination,byte[] key,byte[] iv,byte[] macKey,string expectedMac) {
        var progress=new Progress(RuntimeProgress);
        byte[] actual=Convert.FromBase64String(Mac(source,macKey,progress)),expected=Convert.FromBase64String(expectedMac);
        int diff=actual.Length^expected.Length;
        for(int i=0;i<Math.Min(actual.Length,expected.Length);i++) diff|=actual[i]^expected[i];
        if(diff!=0) throw new CryptographicException("Backup authentication failed; existing application preserved.");
        using(var aes=Aes.Create()) {
            aes.Key=key;aes.IV=iv;
            using(var input=File.OpenRead(source))
            using(var decrypt=new CryptoStream(input,aes.CreateDecryptor(),CryptoStreamMode.Read))
            using(var output=new FileStream(destination,FileMode.CreateNew,FileAccess.Write,FileShare.None,1048576)) {
                long total=input.Length,done=0;var buffer=new byte[1048576];int n;progress.Report("decrypt",0,total,true);
                while((n=decrypt.Read(buffer,0,buffer.Length))>0){output.Write(buffer,0,n);done+=n;progress.Report("decrypt",done,total,false);}
                progress.Report("decrypt",done,total,true);
            }
        }
    }
    public static void Extract(string archive,string destination,long maxBytes,int expectedFiles) {
        string root=Extended(destination).TrimEnd('\\')+"\\";
        var progress=new Progress(RuntimeProgress);
        using(var zip=ZipFile.OpenRead(archive)) {
            var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            long total=0; int files=0;
            progress.Report("extract-verify",0,Math.Max(1,expectedFiles+1),true);
            foreach(var entry in zip.Entries) {
                string name=entry.FullName.Replace('/','\\');
                if(name.StartsWith("\\") || name.IndexOf(':')>=0) throw new IOException("Unsafe archive entry.");
                foreach(string segment in name.Split('\\'))
                    if(segment=="."||segment==".."||segment.EndsWith(".")||segment.EndsWith(" ")) throw new IOException("Unsafe archive segment.");
                string full=Path.GetFullPath(Path.Combine(root,name));
                if(!full.StartsWith(root,StringComparison.OrdinalIgnoreCase)||!seen.Add(full)) throw new IOException("Duplicate or escaping archive entry.");
                if(((entry.ExternalAttributes>>16)&0xF000)==0xA000) throw new IOException("Archive symbolic links are not allowed.");
                if(!name.EndsWith("\\")) {total=checked(total+entry.Length);files++;}
                if(total>maxBytes+16777216L || files>expectedFiles+1) throw new IOException("Archive exceeds recorded size.");
                progress.Report("extract-verify",files,Math.Max(1,expectedFiles+1),false);
            }
            if(files!=expectedFiles+1) throw new IOException("Archive file count mismatch.");
            progress.Report("extract",0,Math.Max(1,maxBytes),true);
            long extracted=0;int extractedFiles=0;
            foreach(var entry in zip.Entries) {
                string full=Path.GetFullPath(Path.Combine(root,entry.FullName.Replace('/','\\')));
                if(entry.FullName.EndsWith("/")) {Directory.CreateDirectory(full);continue;}
                Directory.CreateDirectory(Path.GetDirectoryName(full));
                using(var input=entry.Open()) using(var output=new FileStream(full,FileMode.CreateNew,FileAccess.Write,FileShare.None,1048576)) {
                    var buffer=new byte[1048576];int n;
                    while((n=input.Read(buffer,0,buffer.Length))>0){output.Write(buffer,0,n);extracted+=n;progress.Report("extract",extracted,Math.Max(1,maxBytes),false);}
                }
                File.SetLastWriteTimeUtc(full,entry.LastWriteTime.UtcDateTime);
                File.SetAttributes(full,(FileAttributes)(entry.ExternalAttributes&0x27));
                extractedFiles++;progress.Report("extract-files",extractedFiles,Math.Max(1,expectedFiles+1),false);
            }
            progress.Report("extract",extracted,Math.Max(1,maxBytes),true);
            progress.Report("extract-files",extractedFiles,Math.Max(1,expectedFiles+1),true);
        }
    }
    public static string Quote(string value) {
        var result=new StringBuilder("\"");int slashes=0;
        foreach(char c in value) {
            if(c=='\\') {slashes++;continue;}
            if(c=='"') {result.Append('\\',slashes*2+1);result.Append('"');slashes=0;continue;}
            result.Append('\\',slashes);slashes=0;result.Append(c);
        }
        result.Append('\\',slashes*2);result.Append('"');return result.ToString();
    }
    public static void TarMember(string tar,string layer,string member,string output,long expectedLength) {
        var progress=new Progress(RuntimeProgress);progress.Report("layer-member",0,Math.Max(1,expectedLength),true);
        var info=new ProcessStartInfo(tar,"-xOf "+Quote(layer)+" "+Quote(member));
        info.UseShellExecute=false;info.CreateNoWindow=true;info.RedirectStandardOutput=true;info.RedirectStandardError=true;
        using(var process=Process.Start(info)) {
            var errors=process.StandardError.ReadToEndAsync();
            long count=0;
            try {
                using(var target=File.Open(output,FileMode.CreateNew)) {
                    var buffer=new byte[1048576];int n;
                    while((n=process.StandardOutput.BaseStream.Read(buffer,0,buffer.Length))>0) {
                        count+=n;if(count>expectedLength) throw new IOException("Registry member exceeds recorded size.");
                        target.Write(buffer,0,n);progress.Report("layer-member",count,Math.Max(1,expectedLength),false);
                    }
                }
                process.WaitForExit();
                if(process.ExitCode!=0 || count!=expectedLength) throw new IOException("Registry member extraction failed.");
                progress.Report("layer-member",count,Math.Max(1,expectedLength),true);
            } finally {if(!process.HasExited) process.Kill();}
        }
    }
}
