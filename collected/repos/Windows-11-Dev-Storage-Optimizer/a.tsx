import React, { useState, useEffect } from 'react';
import {
  HardDrive,
  Cpu,
  BarChart3,
  Settings,
  Trash2,
  Folder,
  Database,
  RefreshCw,
  AlertTriangle,
  Check,
  Activity,
  Zap,
  Cloud,
  Monitor,
  Container,
  Layers,
  Link,
  Sparkles,
  Shield,
  Gauge,
  Wrench,
  TrendingUp,
  Info,
  X,
  Play,
  Pause,
  ChevronRight,
  Clock,
  FileText,
  Archive,
  RotateCcw
} from 'lucide-react';

function StorageOptimizer() {
  const [activeTab, setActiveTab] = useState('dashboard');
  const [notifications, setNotifications] = useState([]);
  const [isOptimizing, setIsOptimizing] = useState(false);
  const [modalOpened, setModalOpened] = useState(false);
  
  const [ssdHealth, setSsdHealth] = useState({
    temperature: 42,
    wearLevel: 15,
    totalWrites: 2.4,
    remainingLife: 85,
    badSectors: 0,
    performance: 92
  });

  const [storageData, setStorageData] = useState({
    total: 1000,
    used: 650,
    free: 350,
    systemFiles: 45,
    applications: 180,
    developmentFiles: 320,
    cache: 85,
    tempFiles: 20
  });

  const [systemInfo, setSystemInfo] = useState({
    os: 'Unknown',
    browser: 'Unknown',
    storage: { quota: 0, usage: 0 },
    connection: 'Unknown',
    cores: 0,
    memory: 0
  });

  const [devCaches, setDevCaches] = useState([
    { name: 'Node.js npm cache', size: '2.4 GB', path: 'C:\\Users\\Dev\\AppData\\Roaming\\npm-cache', status: 'active' },
    { name: 'Docker images', size: '15.8 GB', path: 'C:\\ProgramData\\Docker', status: 'active' },
    { name: 'VS Code extensions', size: '890 MB', path: 'C:\\Users\\Dev\\.vscode\\extensions', status: 'active' },
    { name: 'Yarn cache', size: '1.2 GB', path: 'C:\\Users\\Dev\\AppData\\Local\\Yarn\\Cache', status: 'active' },
    { name: 'Gradle cache', size: '3.1 GB', path: 'C:\\Users\\Dev\\.gradle\\caches', status: 'active' },
    { name: 'Maven repository', size: '5.6 GB', path: 'C:\\Users\\Dev\\.m2\\repository', status: 'active' }
  ]);

  // Fetch real system data available in browser
  useEffect(() => {
    const fetchSystemInfo = async () => {
      try {
        // Get basic system info
        const info = {
          os: navigator.platform || 'Unknown',
          browser: navigator.userAgent.split(') ')[0].split(' (')[1] || 'Unknown',
          cores: navigator.hardwareConcurrency || 0,
          memory: (navigator.deviceMemory || 0) * 1024, // Convert GB to MB
          connection: navigator.connection?.effectiveType || 'Unknown',
          storage: { quota: 0, usage: 0 }
        };

        // Get storage quota information (if supported)
        if ('storage' in navigator && 'estimate' in navigator.storage) {
          const estimate = await navigator.storage.estimate();
          info.storage = {
            quota: Math.round((estimate.quota || 0) / (1024 * 1024 * 1024)), // Convert to GB
            usage: Math.round((estimate.usage || 0) / (1024 * 1024 * 1024))   // Convert to GB
          };
          
          // Update storage data with real info
          setStorageData(prev => ({
            ...prev,
            total: info.storage.quota || prev.total,
            used: info.storage.usage || prev.used,
            free: (info.storage.quota - info.storage.usage) || prev.free
          }));
        }

        setSystemInfo(info);
        addNotification('Connected to system - displaying real browser data');
      } catch (error) {
        console.error('Error fetching system info:', error);
        addNotification('Limited system access - some data simulated');
      }
    };

    fetchSystemInfo();
  }, []);

  const addNotification = (message, type = 'success') => {
    const id = Date.now();
    setNotifications(prev => [...prev, { id, message, type }]);
    setTimeout(() => {
      setNotifications(prev => prev.filter(n => n.id !== id));
    }, 4000);
  };

  const testFileSystemAccess = async () => {
    try {
      // Try to access File System Access API (Chrome only)
      if ('showDirectoryPicker' in window) {
        const dirHandle = await window.showDirectoryPicker();
        let totalSize = 0;
        let fileCount = 0;
        
        for await (const [name, handle] of dirHandle.entries()) {
          if (handle.kind === 'file') {
            const file = await handle.getFile();
            totalSize += file.size;
            fileCount++;
          }
        }
        
        addNotification(`Scanned ${fileCount} files, ${(totalSize / 1024 / 1024).toFixed(1)} MB total`);
      } else {
        addNotification('File system access not supported in this browser');
      }
    } catch (error) {
      if (error.name !== 'AbortError') {
        addNotification('File system access denied or failed');
      }
    }
  };

  const optimizeStorage = async () => {
    setIsOptimizing(true);
    
    // Measure real performance
    const startTime = performance.now();
    
    // Simulate optimization work with real performance measurement
    await new Promise(resolve => setTimeout(resolve, 3000));
    
    const endTime = performance.now();
    const duration = ((endTime - startTime) / 1000).toFixed(2);
    
    // Try to refresh storage data
    if ('storage' in navigator && 'estimate' in navigator.storage) {
      try {
        const estimate = await navigator.storage.estimate();
        const quota = Math.round((estimate.quota || 0) / (1024 * 1024 * 1024));
        const usage = Math.round((estimate.usage || 0) / (1024 * 1024 * 1024));
        
        setStorageData(prev => ({
          ...prev,
          total: quota || prev.total,
          used: usage || prev.used,
          free: (quota - usage) || prev.free
        }));
      } catch (error) {
        console.error('Storage estimate failed:', error);
      }
    }
    
    addNotification(`Storage optimization completed in ${duration} seconds!`);
    setIsOptimizing(false);
  };

  const cleanupCache = (cacheName) => {
    addNotification(`${cacheName} cleaned successfully`);
  };

  const ProgressBar = ({ value, color = 'blue', sections = null }) => {
    if (sections) {
      let currentPos = 0;
      return (
        <div className="w-full bg-gray-700 rounded-full h-6 relative overflow-hidden">
          {sections.map((section, index) => {
            const width = section.value;
            const left = currentPos;
            currentPos += width;
            return (
              <div
                key={index}
                className={`absolute h-full ${
                  section.color === 'blue' ? 'bg-blue-500' :
                  section.color === 'cyan' ? 'bg-cyan-500' :
                  section.color === 'green' ? 'bg-green-500' :
                  section.color === 'yellow' ? 'bg-yellow-500' :
                  section.color === 'red' ? 'bg-red-500' : 'bg-gray-500'
                }`}
                style={{ left: `${left}%`, width: `${width}%` }}
              />
            );
          })}
        </div>
      );
    }
    
    return (
      <div className="w-full bg-gray-700 rounded-full h-3">
        <div
          className={`h-full rounded-full ${
            color === 'green' ? 'bg-green-500' :
            color === 'blue' ? 'bg-blue-500' :
            color === 'yellow' ? 'bg-yellow-500' :
            color === 'red' ? 'bg-red-500' :
            color === 'cyan' ? 'bg-cyan-500' : 'bg-blue-500'
          }`}
          style={{ width: `${value}%` }}
        />
      </div>
    );
  };

  const RingProgress = ({ value, size = 120, thickness = 12, color = 'green', label }) => {
    const radius = (size - thickness) / 2;
    const circumference = 2 * Math.PI * radius;
    const strokeDasharray = `${(value / 100) * circumference} ${circumference}`;
    
    return (
      <div className="relative inline-flex items-center justify-center">
        <svg width={size} height={size} className="transform -rotate-90">
          <circle
            cx={size / 2}
            cy={size / 2}
            r={radius}
            stroke="rgb(55, 65, 81)"
            strokeWidth={thickness}
            fill="none"
          />
          <circle
            cx={size / 2}
            cy={size / 2}
            r={radius}
            stroke={color === 'green' ? 'rgb(34, 197, 94)' : 'rgb(59, 130, 246)'}
            strokeWidth={thickness}
            fill="none"
            strokeDasharray={strokeDasharray}
            strokeLinecap="round"
          />
        </svg>
        <div className="absolute text-center">
          {label}
        </div>
      </div>
    );
  };

  const Card = ({ children, className = '' }) => (
    <div className={`bg-gray-800 rounded-lg p-6 border border-gray-700 ${className}`}>
      {children}
    </div>
  );

  const Button = ({ children, onClick, variant = 'primary', size = 'md', disabled = false, className = '' }) => {
    const baseClasses = 'inline-flex items-center justify-center rounded-md font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2';
    const sizeClasses = {
      xs: 'px-2 py-1 text-xs',
      sm: 'px-3 py-1.5 text-sm',
      md: 'px-4 py-2 text-sm',
      lg: 'px-6 py-3 text-base'
    };
    const variantClasses = {
      primary: 'bg-blue-600 hover:bg-blue-700 text-white focus:ring-blue-500',
      secondary: 'bg-gray-600 hover:bg-gray-700 text-white focus:ring-gray-500',
      outline: 'border border-gray-600 text-gray-300 hover:bg-gray-700 focus:ring-gray-500',
      success: 'bg-green-600 hover:bg-green-700 text-white focus:ring-green-500',
      danger: 'bg-red-600 hover:bg-red-700 text-white focus:ring-red-500',
      warning: 'bg-yellow-600 hover:bg-yellow-700 text-white focus:ring-yellow-500'
    };
    
    return (
      <button
        onClick={onClick}
        disabled={disabled}
        className={`${baseClasses} ${sizeClasses[size]} ${variantClasses[variant]} ${disabled ? 'opacity-50 cursor-not-allowed' : ''} ${className}`}
      >
        {children}
      </button>
    );
  };

  const Badge = ({ children, color = 'blue', size = 'sm' }) => (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
      color === 'green' ? 'bg-green-900 text-green-300' :
      color === 'blue' ? 'bg-blue-900 text-blue-300' :
      color === 'yellow' ? 'bg-yellow-900 text-yellow-300' :
      color === 'red' ? 'bg-red-900 text-red-300' :
      color === 'gray' ? 'bg-gray-700 text-gray-300' :
      color === 'purple' ? 'bg-purple-900 text-purple-300' :
      color === 'orange' ? 'bg-orange-900 text-orange-300' : 'bg-blue-900 text-blue-300'
    }`}>
      {children}
    </span>
  );

  const Switch = ({ label, description, defaultChecked = false, onChange }) => {
    const [checked, setChecked] = useState(defaultChecked);
    
    return (
      <div className="flex items-center justify-between">
        <div className="flex-1">
          <div className="text-sm font-medium text-white">{label}</div>
          {description && <div className="text-xs text-gray-400">{description}</div>}
        </div>
        <button
          onClick={() => {
            setChecked(!checked);
            onChange?.(!checked);
          }}
          className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 ${
            checked ? 'bg-blue-600' : 'bg-gray-600'
          }`}
        >
          <span
            className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
              checked ? 'translate-x-6' : 'translate-x-1'
            }`}
          />
        </button>
      </div>
    );
  };

  const TabButton = ({ active, onClick, icon: Icon, children }) => (
    <button
      onClick={onClick}
      className={`flex items-center px-4 py-2 text-sm font-medium rounded-md transition-colors ${
        active 
          ? 'bg-blue-600 text-white' 
          : 'text-gray-400 hover:text-white hover:bg-gray-700'
      }`}
    >
      <Icon size={16} className="mr-2" />
      {children}
    </button>
  );

  return (
    <div className="min-h-screen bg-gray-900 text-white">
      {/* Notifications */}
      <div className="fixed top-4 right-4 z-50 space-y-2">
        {notifications.map(notification => (
          <div
            key={notification.id}
            className={`flex items-center p-4 rounded-lg shadow-lg ${
              notification.type === 'success' ? 'bg-green-800 border border-green-600' : 'bg-orange-800 border border-orange-600'
            }`}
          >
            {notification.type === 'success' ? <Check size={16} className="mr-2" /> : <AlertTriangle size={16} className="mr-2" />}
            <span className="text-sm">{notification.message}</span>
          </div>
        ))}
      </div>

      {/* Header */}
      <header className="bg-gray-800 border-b border-gray-700 px-6 py-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-4">
            <HardDrive size={32} className="text-blue-400" />
            <div>
              <h1 className="text-xl font-bold">Windows 11 Dev Storage Optimizer</h1>
              <p className="text-sm text-gray-400">Professional storage management for developers</p>
            </div>
          </div>
          <Button
            onClick={optimizeStorage}
            disabled={isOptimizing}
            size="lg"
            className="bg-gradient-to-r from-blue-600 to-cyan-600"
          >
            <Zap size={16} className="mr-2" />
            {isOptimizing ? 'Optimizing...' : 'Quick Optimize'}
          </Button>
        </div>
      </header>

      {/* Navigation */}
      <nav className="bg-gray-800 border-b border-gray-700 px-6 py-2">
        <div className="flex space-x-1">
          <TabButton active={activeTab === 'dashboard'} onClick={() => setActiveTab('dashboard')} icon={BarChart3}>
            Dashboard
          </TabButton>
          <TabButton active={activeTab === 'ssd-health'} onClick={() => setActiveTab('ssd-health')} icon={Activity}>
            SSD Health
          </TabButton>
          <TabButton active={activeTab === 'optimization'} onClick={() => setActiveTab('optimization')} icon={Gauge}>
            Storage Optimization
          </TabButton>
          <TabButton active={activeTab === 'cache'} onClick={() => setActiveTab('cache')} icon={Database}>
            Cache Management
          </TabButton>
          <TabButton active={activeTab === 'cleanup'} onClick={() => setActiveTab('cleanup')} icon={Sparkles}>
            Cleanup Tools
          </TabButton>
          <TabButton active={activeTab === 'settings'} onClick={() => setActiveTab('settings')} icon={Settings}>
            Settings
          </TabButton>
        </div>
      </nav>

      {/* Main Content */}
      <main className="p-6">
        {/* Dashboard Tab */}
        {activeTab === 'dashboard' && (
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div className="lg:col-span-2 space-y-6">
              <Card>
                <div className="flex items-center justify-between mb-4">
                  <h3 className="text-lg font-semibold">Storage Overview</h3>
                  <Badge color="green">Healthy</Badge>
                </div>
                <ProgressBar
                  sections={[
                    { value: 18, color: 'blue', label: 'System' },
                    { value: 32, color: 'cyan', label: 'Development' },
                    { value: 18, color: 'green', label: 'Applications' },
                    { value: 8.5, color: 'yellow', label: 'Cache' },
                    { value: 2, color: 'red', label: 'Temp' }
                  ]}
                />
                <div className="flex justify-between mt-4 text-sm">
                  <span>{storageData.used} GB used of {storageData.total} GB</span>
                  <span className="text-green-400">{storageData.free} GB free</span>
                </div>
              </Card>

              <Card>
                <h3 className="text-lg font-semibold mb-4">🚀 Build Real Version</h3>
                <div className="space-y-4">
                  <div className="p-4 bg-green-900 border border-green-600 rounded-lg">
                    <h4 className="font-medium text-green-300 mb-2">For Full System Access, You Need:</h4>
                    <ul className="text-sm text-green-200 space-y-1">
                      <li>• Electron app with native Node.js modules</li>
                      <li>• Windows WMI integration for hardware data</li>
                      <li>• Admin privileges for system operations</li>
                      <li>• Native file system scanning</li>
                    </ul>
                  </div>
                  
                  <div className="p-3 bg-blue-900 border border-blue-600 rounded-lg">
                    <h5 className="font-medium text-blue-300 mb-1">Recommended Stack:</h5>
                    <div className="text-sm text-blue-200 space-y-1">
                      <code className="block bg-blue-800 px-2 py-1 rounded">Electron + React + Node.js</code>
                      <code className="block bg-blue-800 px-2 py-1 rounded">systeminformation npm package</code>
                      <code className="block bg-blue-800 px-2 py-1 rounded">node-wmi for Windows APIs</code>
                    </div>
                  </div>

                  <Button variant="outline" className="w-full">
                    <FileText size={16} className="mr-2" />
                    View Implementation Guide
                  </Button>
                </div>
              </Card>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <Card>
                  <div className="flex items-center justify-between mb-4">
                    <h4 className="font-semibold">DirectStorage Status</h4>
                    <div className="w-8 h-8 bg-green-600 rounded-full flex items-center justify-center">
                      <Check size={16} />
                    </div>
                  </div>
                  <p className="text-sm text-gray-400 mb-4">
                    DirectStorage API is enabled and optimized for your NVMe SSD
                  </p>
                  <div className="flex space-x-2">
                    <Badge color="green">Enabled</Badge>
                    <Badge color="blue">GPU Decompression</Badge>
                  </div>
                </Card>

                <Card>
                  <div className="flex items-center justify-between mb-4">
                    <h4 className="font-semibold">Storage Sense</h4>
                    <Switch defaultChecked />
                  </div>
                  <p className="text-sm text-gray-400 mb-4">
                    Automatic cleanup enabled with developer-optimized settings
                  </p>
                  <p className="text-xs text-green-400">Last run: 2 hours ago</p>
                </Card>
              </div>
            </div>

            <div className="space-y-6">
              <Card>
                <h4 className="font-semibold mb-4">SSD Performance</h4>
                <div className="flex justify-center mb-4">
                  <RingProgress
                    value={ssdHealth.performance}
                    size={120}
                    color="green"
                    label={
                      <div className="text-center">
                        <div className="text-2xl font-bold text-green-400">{ssdHealth.performance}%</div>
                      </div>
                    }
                  />
                </div>
                <div className="space-y-2">
                  <div className="flex justify-between text-sm">
                    <span>Temperature</span>
                    <span className={ssdHealth.temperature > 50 ? 'text-red-400' : 'text-green-400'}>
                      {ssdHealth.temperature}°C
                    </span>
                  </div>
                  <div className="flex justify-between text-sm">
                    <span>Health</span>
                    <span className="text-green-400">{ssdHealth.remainingLife}%</span>
                  </div>
                </div>
              </Card>

              <Card>
                <h4 className="font-semibold mb-4">Real System Info</h4>
                <div className="space-y-3 text-sm">
                  <div className="flex justify-between">
                    <span className="text-gray-400">OS Platform</span>
                    <span className="font-mono">{systemInfo.os}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-400">CPU Cores</span>
                    <span className="font-mono">{systemInfo.cores || 'N/A'}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-400">RAM</span>
                    <span className="font-mono">{systemInfo.memory || 'N/A'} GB</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-400">Connection</span>
                    <span className="font-mono">{systemInfo.connection}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-400">Browser Storage</span>
                    <span className="font-mono">{systemInfo.storage.usage}/{systemInfo.storage.quota} GB</span>
                  </div>
                </div>
                <div className="mt-4 p-3 bg-yellow-900 border border-yellow-600 rounded-lg">
                  <div className="flex items-start space-x-2">
                    <AlertTriangle size={14} className="text-yellow-400 mt-0.5" />
                    <div>
                      <p className="text-xs text-yellow-200">
                        Browser limitations: Hardware data simulated. For real SSD monitoring, use native desktop app.
                      </p>
                    </div>
                  </div>
                </div>
              </Card>

              <Card>
                <h4 className="font-semibold mb-4">Quick Actions</h4>
                <div className="space-y-2">
                  <Button variant="outline" className="w-full justify-start">
                    <Container size={16} className="mr-2" />
                    Clean Docker Cache
                  </Button>
                  <Button variant="outline" className="w-full justify-start">
                    <Layers size={16} className="mr-2" />
                    Clear Node Modules
                  </Button>
                  <Button variant="outline" className="w-full justify-start">
                    <Trash2 size={16} className="mr-2" />
                    Clean Build Artifacts
                  </Button>
                  <Button 
                    variant="outline" 
                    className="w-full justify-start"
                    onClick={testFileSystemAccess}
                  >
                    <Folder size={16} className="mr-2" />
                    Test File Access (Chrome)
                  </Button>
                </div>
                <div className="mt-3 p-2 bg-blue-900 border border-blue-600 rounded text-xs">
                  <Info size={12} className="inline mr-1" />
                  Click "Test File Access" to scan a real folder (Chrome only)
                </div>
              </Card>
            </div>
          </div>
        )}

        {/* SSD Health Tab */}
        {activeTab === 'ssd-health' && (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <Card>
              <h3 className="text-lg font-semibold mb-4">SSD Health Monitoring</h3>
              <div className="flex items-center justify-between mb-6">
                <div>
                  <h4 className="font-medium">Samsung 980 PRO 1TB</h4>
                  <p className="text-sm text-gray-400">NVMe PCIe 4.0 SSD</p>
                </div>
                <Badge color="green" size="lg">Excellent</Badge>
              </div>
              
              <div className="space-y-6">
                <div>
                  <div className="flex justify-between mb-2">
                    <span className="text-sm">Wear Leveling</span>
                    <span className="text-sm">{ssdHealth.wearLevel}%</span>
                  </div>
                  <ProgressBar value={ssdHealth.wearLevel} color="green" />
                </div>
                
                <div>
                  <div className="flex justify-between mb-2">
                    <span className="text-sm">Remaining Life</span>
                    <span className="text-sm">{ssdHealth.remainingLife}%</span>
                  </div>
                  <ProgressBar value={ssdHealth.remainingLife} color="blue" />
                </div>
                
                <div className="flex justify-between">
                  <span className="text-sm">Total Data Written</span>
                  <span className="text-sm font-medium">{ssdHealth.totalWrites} TB</span>
                </div>
                
                <div className="flex justify-between">
                  <span className="text-sm">Bad Sectors</span>
                  <span className={`text-sm ${ssdHealth.badSectors === 0 ? 'text-green-400' : 'text-red-400'}`}>
                    {ssdHealth.badSectors}
                  </span>
                </div>
              </div>
            </Card>

            <Card>
              <h3 className="text-lg font-semibold mb-4">Real-time Performance</h3>
              <div className="space-y-6">
                <div>
                  <div className="text-sm mb-2">Read Speed</div>
                  <div className="flex items-center space-x-3">
                    <ProgressBar value={85} color="cyan" />
                    <span className="text-sm font-medium">6,800 MB/s</span>
                  </div>
                </div>
                
                <div>
                  <div className="text-sm mb-2">Write Speed</div>
                  <div className="flex items-center space-x-3">
                    <ProgressBar value={82} color="blue" />
                    <span className="text-sm font-medium">5,100 MB/s</span>
                  </div>
                </div>
                
                <div>
                  <div className="text-sm mb-2">Random IOPS</div>
                  <div className="flex items-center space-x-3">
                    <ProgressBar value={78} color="green" />
                    <span className="text-sm font-medium">1.2M IOPS</span>
                  </div>
                </div>
                
                <div className="bg-blue-900 border border-blue-600 rounded-lg p-4">
                  <div className="flex items-start space-x-2">
                    <Info size={16} className="text-blue-400 mt-0.5" />
                    <div>
                      <h5 className="font-medium text-blue-300">DirectStorage Optimization</h5>
                      <p className="text-sm text-blue-200">
                        Your SSD supports DirectStorage for up to 40% faster game loading and asset streaming.
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            </Card>

            <div className="lg:col-span-2">
              <Card>
                <h3 className="text-lg font-semibold mb-4">Wear Leveling Analysis</h3>
                <p className="text-sm text-gray-400 mb-4">
                  Advanced wear leveling ensures even distribution of write operations across all memory cells
                </p>
                <div className="flex space-x-2">
                  <Badge color="green">Uniform Distribution</Badge>
                  <Badge color="blue">Optimal Performance</Badge>
                  <Badge color="cyan">5+ Years Expected Life</Badge>
                </div>
              </Card>
            </div>
          </div>
        )}

        {/* Storage Optimization Tab */}
        {activeTab === 'optimization' && (
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div className="lg:col-span-2 space-y-6">
              <Card>
                <h3 className="text-lg font-semibold mb-4">Windows 11 Storage Optimization</h3>
                
                <div className="space-y-6">
                  <div>
                    <div className="flex items-center justify-between mb-4">
                      <div>
                        <h4 className="font-medium">Storage Spaces Optimization</h4>
                        <p className="text-sm text-gray-400">Tiered storage for development files</p>
                      </div>
                      <Switch defaultChecked />
                    </div>
                    <ProgressBar value={75} color="blue" />
                    <p className="text-xs text-blue-400 mt-2">Active: Hot data on SSD, cold data on HDD</p>
                  </div>

                  <div>
                    <div className="flex items-center justify-between mb-4">
                      <div>
                        <h4 className="font-medium">File Compression</h4>
                        <p className="text-sm text-gray-400">NTFS compression for development archives</p>
                      </div>
                      <Switch defaultChecked />
                    </div>
                    <div className="flex justify-between">
                      <span className="text-sm">Space saved</span>
                      <span className="text-sm text-green-400">12.4 GB</span>
                    </div>
                  </div>

                  <div>
                    <div className="flex items-center justify-between mb-4">
                      <div>
                        <h4 className="font-medium">Storage Sense Automation</h4>
                        <p className="text-sm text-gray-400">Smart cleanup with developer exclusions</p>
                      </div>
                      <Switch defaultChecked />
                    </div>
                    <p className="text-xs text-gray-400">
                      Excludes: node_modules, .git, build cache, package-lock.json
                    </p>
                  </div>
                </div>
              </Card>

              <Card>
                <h3 className="text-lg font-semibold mb-4">Symbolic Link Management</h3>
                <p className="text-sm text-gray-400 mb-4">
                  Move large development dependencies to faster storage while maintaining project structure
                </p>
                
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b border-gray-700">
                        <th className="text-left py-2">Source</th>
                        <th className="text-left py-2">Target</th>
                        <th className="text-left py-2">Size</th>
                        <th className="text-left py-2">Status</th>
                        <th className="text-left py-2">Action</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr className="border-b border-gray-800">
                        <td className="py-2">
                          <code className="text-xs bg-gray-700 px-2 py-1 rounded">D:\Projects\app\node_modules</code>
                        </td>
                        <td className="py-2">
                          <code className="text-xs bg-gray-700 px-2 py-1 rounded">C:\DevCache\node_modules_app</code>
                        </td>
                        <td className="py-2">2.1 GB</td>
                        <td className="py-2"><Badge color="green">Linked</Badge></td>
                        <td className="py-2"><Button size="xs" variant="outline">Manage</Button></td>
                      </tr>
                      <tr className="border-b border-gray-800">
                        <td className="py-2">
                          <code className="text-xs bg-gray-700 px-2 py-1 rounded">D:\Projects\web\.next</code>
                        </td>
                        <td className="py-2">
                          <code className="text-xs bg-gray-700 px-2 py-1 rounded">C:\DevCache\next_web</code>
                        </td>
                        <td className="py-2">450 MB</td>
                        <td className="py-2"><Badge color="green">Linked</Badge></td>
                        <td className="py-2"><Button size="xs" variant="outline">Manage</Button></td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </Card>
            </div>

            <div className="space-y-6">
              <Card>
                <h4 className="font-semibold mb-4">Optimization Schedule</h4>
                <div className="space-y-4">
                  <div className="flex items-start space-x-3">
                    <div className="w-6 h-6 bg-green-600 rounded-full flex items-center justify-center mt-1">
                      <Check size={12} />
                    </div>
                    <div>
                      <h5 className="font-medium">Daily Cleanup</h5>
                      <p className="text-sm text-gray-400">Temp files, logs</p>
                      <p className="text-xs text-gray-500 mt-1">Completed: 6:00 AM</p>
                    </div>
                  </div>
                  <div className="flex items-start space-x-3">
                    <div className="w-6 h-6 bg-blue-600 rounded-full flex items-center justify-center mt-1">
                      <Activity size={12} />
                    </div>
                    <div>
                      <h5 className="font-medium">Weekly Optimization</h5>
                      <p className="text-sm text-gray-400">Cache analysis, defrag</p>
                      <p className="text-xs text-gray-500 mt-1">Next: Sunday 2:00 AM</p>
                    </div>
                  </div>
                  <div className="flex items-start space-x-3">
                    <div className="w-6 h-6 bg-gray-600 rounded-full flex items-center justify-center mt-1">
                      <Database size={12} />
                    </div>
                    <div>
                      <h5 className="font-medium">Monthly Deep Clean</h5>
                      <p className="text-sm text-gray-400">Full system scan</p>
                      <p className="text-xs text-gray-500 mt-1">Next: 1st at 3:00 AM</p>
                    </div>
                  </div>
                </div>
              </Card>

              <Card>
                <h4 className="font-semibold mb-4">Performance Metrics</h4>
                <div className="space-y-3">
                  <div className="flex justify-between">
                    <span className="text-sm">Boot Time</span>
                    <span className="text-sm text-green-400">8.2s (-15%)</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-sm">App Launch</span>
                    <span className="text-sm text-green-400">2.1s (-25%)</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-sm">File Operations</span>
                    <span className="text-sm text-green-400">+35% faster</span>
                  </div>
                </div>
              </Card>
            </div>
          </div>
        )}

        {/* Cache Management Tab */}
        {activeTab === 'cache' && (
          <div className="space-y-6">
            <Card>
              <div className="flex items-center justify-between mb-6">
                <h3 className="text-lg font-semibold">Development Cache Management</h3>
                <Button variant="outline">
                  <RefreshCw size={16} className="mr-2" />
                  Scan All Caches
                </Button>
              </div>
              
              <div className="space-y-4">
                {devCaches.map((cache, index) => (
                  <div key={index} className="bg-gray-700 rounded-lg p-4 border border-gray-600">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center space-x-3 flex-1">
                        <div className={`w-10 h-10 rounded-lg flex items-center justify-center ${
                          cache.name.includes('Docker') ? 'bg-blue-900 text-blue-400' :
                          cache.name.includes('Node') ? 'bg-green-900 text-green-400' :
                          'bg-gray-600 text-gray-400'
                        }`}>
                          {cache.name.includes('Docker') ? <Container size={20} /> :
                           cache.name.includes('Node') ? <Layers size={20} /> :
                           <Folder size={20} />}
                        </div>
                        <div>
                          <h4 className="font-medium">{cache.name}</h4>
                          <p className="text-xs text-gray-400">{cache.path}</p>
                        </div>
                      </div>
                      
                      <div className="flex items-center space-x-3">
                        <Badge color={cache.status === 'active' ? 'green' : 'gray'}>
                          {cache.size}
                        </Badge>
                        <Button
                          size="xs"
                          variant="warning"
                          onClick={() => cleanupCache(cache.name)}
                        >
                          Clean
                        </Button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </Card>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <Card>
                <h4 className="font-semibold mb-4">Intelligent Cache Settings</h4>
                <div className="space-y-6">
                  <div>
                    <div className="flex items-center justify-between mb-2">
                      <span className="text-sm">Auto-clean Docker images older than</span>
                      <input
                        type="number"
                        defaultValue={30}
                        min={1}
                        max={365}
                        className="w-20 px-2 py-1 text-sm bg-gray-700 border border-gray-600 rounded"
                      />
                    </div>
                    <p className="text-xs text-gray-400">days</p>
                  </div>

                  <div>
                    <div className="flex items-center justify-between mb-2">
                      <span className="text-sm">Node.js cache size limit</span>
                      <input
                        type="number"
                        defaultValue={5}
                        min={1}
                        max={50}
                        className="w-20 px-2 py-1 text-sm bg-gray-700 border border-gray-600 rounded"
                      />
                    </div>
                    <p className="text-xs text-gray-400">GB</p>
                  </div>

                  <Switch
                    label="Smart cache compression"
                    description="Compress rarely used cache files"
                    defaultChecked
                  />
                </div>
              </Card>

              <Card>
                <h4 className="font-semibold mb-4">Cache Analytics</h4>
                <div className="space-y-4">
                  <div className="flex justify-between">
                    <span className="text-sm">Total cache size</span>
                    <span className="text-sm font-medium">29.1 GB</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-sm">Frequently accessed</span>
                    <span className="text-sm text-green-400">18.2 GB</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-sm">Rarely used</span>
                    <span className="text-sm text-orange-400">10.9 GB</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-sm">Last optimization</span>
                    <span className="text-sm">2 hours ago</span>
                  </div>
                </div>
              </Card>
            </div>
          </div>
        )}

        {/* Cleanup Tools Tab */}
        {activeTab === 'cleanup' && (
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div className="lg:col-span-2 space-y-6">
              <Card>
                <h3 className="text-lg font-semibold mb-4">Automated Development Cleanup</h3>
                
                <div className="space-y-4">
                  <div className="bg-gray-700 rounded-lg p-4 border border-gray-600">
                    <div className="flex items-center justify-between">
                      <div>
                        <h4 className="font-medium">Build Artifacts</h4>
                        <p className="text-sm text-gray-400">
                          dist/, build/, target/, bin/ folders older than 7 days
                        </p>
                      </div>
                      <div className="flex items-center space-x-3">
                        <Badge color="orange">3.2 GB found</Badge>
                        <Button size="sm" variant="danger">
                          Clean Now
                        </Button>
                      </div>
                    </div>
                  </div>

                  <div className="bg-gray-700 rounded-lg p-4 border border-gray-600">
                    <div className="flex items-center justify-between">
                      <div>
                        <h4 className="font-medium">Log Files</h4>
                        <p className="text-sm text-gray-400">
                          Application logs, npm debug logs, crash dumps
                        </p>
                      </div>
                      <div className="flex items-center space-x-3">
                        <Badge color="yellow">1.8 GB found</Badge>
                        <Button size="sm" variant="danger">
                          Clean Now
                        </Button>
                      </div>
                    </div>
                  </div>

                  <div className="bg-gray-700 rounded-lg p-4 border border-gray-600">
                    <div className="flex items-center justify-between">
                      <div>
                        <h4 className="font-medium">Temporary Development Files</h4>
                        <p className="text-sm text-gray-400">
                          .tmp, .temp, temporary test data, coverage reports
                        </p>
                      </div>
                      <div className="flex items-center space-x-3">
                        <Badge color="red">890 MB found</Badge>
                        <Button size="sm" variant="danger">
                          Clean Now
                        </Button>
                      </div>
                    </div>
                  </div>

                  <div className="bg-gray-700 rounded-lg p-4 border border-gray-600">
                    <div className="flex items-center justify-between">
                      <div>
                        <h4 className="font-medium">Orphaned Node Modules</h4>
                        <p className="text-sm text-gray-400">
                          node_modules in projects not accessed in 30+ days
                        </p>
                      </div>
                      <div className="flex items-center space-x-3">
                        <Badge color="purple">12.1 GB found</Badge>
                        <Button size="sm" variant="danger">
                          Clean Now
                        </Button>
                      </div>
                    </div>
                  </div>
                </div>
              </Card>

              <Card>
                <h4 className="font-semibold mb-4">Cleanup Exclusions</h4>
                <p className="text-sm text-gray-400 mb-4">
                  Files and folders that will never be automatically cleaned
                </p>
                <ul className="text-sm space-y-1">
                  <li className="flex items-center space-x-2">
                    <div className="w-1.5 h-1.5 bg-blue-400 rounded-full"></div>
                    <span>Active project directories (accessed within 7 days)</span>
                  </li>
                  <li className="flex items-center space-x-2">
                    <div className="w-1.5 h-1.5 bg-blue-400 rounded-full"></div>
                    <span>Package-lock.json and yarn.lock files</span>
                  </li>
                  <li className="flex items-center space-x-2">
                    <div className="w-1.5 h-1.5 bg-blue-400 rounded-full"></div>
                    <span>Git repositories and .git folders</span>
                  </li>
                  <li className="flex items-center space-x-2">
                    <div className="w-1.5 h-1.5 bg-blue-400 rounded-full"></div>
                    <span>Production deployment artifacts</span>
                  </li>
                  <li className="flex items-center space-x-2">
                    <div className="w-1.5 h-1.5 bg-blue-400 rounded-full"></div>
                    <span>Environment configuration files</span>
                  </li>
                </ul>
              </Card>
            </div>

            <div className="space-y-6">
              <Card>
                <h4 className="font-semibold mb-4">Cleanup Statistics</h4>
                <div className="space-y-4">
                  <div>
                    <p className="text-sm text-gray-400">Total cleaned this week</p>
                    <p className="text-3xl font-bold text-green-400">42.3 GB</p>
                  </div>
                  <div>
                    <p className="text-sm text-gray-400">Files processed</p>
                    <p className="text-lg font-medium">127,459</p>
                  </div>
                  <div>
                    <p className="text-sm text-gray-400">Average daily cleanup</p>
                    <p className="text-lg font-medium">6.0 GB</p>
                  </div>
                </div>
              </Card>

              <Card>
                <h4 className="font-semibold mb-4">Safe Cleanup Mode</h4>
                <Switch
                  label="Enable safe mode"
                  description="Create restore points before major cleanups"
                  defaultChecked
                />
                <div className="mt-4 bg-blue-900 border border-blue-600 rounded-lg p-4">
                  <div className="flex items-start space-x-2">
                    <Shield size={16} className="text-blue-400 mt-0.5" />
                    <div>
                      <h5 className="font-medium text-blue-300">Protection Active</h5>
                      <p className="text-sm text-blue-200">
                        All cleanup operations can be safely undone within 30 days.
                      </p>
                    </div>
                  </div>
                </div>
              </Card>
            </div>
          </div>
        )}

        {/* Settings Tab */}
        {activeTab === 'settings' && (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <div className="space-y-6">
              <Card>
                <h3 className="text-lg font-semibold mb-4">General Settings</h3>
                <div className="space-y-6">
                  <Switch
                    label="Auto-optimization"
                    description="Automatically optimize storage daily"
                    defaultChecked
                  />
                  <Switch
                    label="Real-time monitoring"
                    description="Monitor SSD health continuously"
                    defaultChecked
                  />
                  <Switch
                    label="DirectStorage integration"
                    description="Optimize for DirectStorage API"
                    defaultChecked
                  />
                  <Switch
                    label="Developer mode"
                    description="Enhanced features for development workflows"
                    defaultChecked
                  />
                </div>
              </Card>

              <Card>
                <h3 className="text-lg font-semibold mb-4">Notification Settings</h3>
                <div className="space-y-6">
                  <Switch
                    label="Storage warnings"
                    description="Alert when storage is running low"
                    defaultChecked
                  />
                  <Switch
                    label="SSD health alerts"
                    description="Notify about SSD health issues"
                    defaultChecked
                  />
                  <Switch
                    label="Cleanup notifications"
                    description="Report cleanup operation results"
                    defaultChecked
                  />
                </div>
              </Card>
            </div>

            <div className="space-y-6">
              <Card>
                <h3 className="text-lg font-semibold mb-4">Advanced Configuration</h3>
                <div className="space-y-6">
                  <div>
                    <label className="block text-sm font-medium mb-2">Storage monitoring interval</label>
                    <select className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-md">
                      <option value="1">1 minute</option>
                      <option value="5" selected>5 minutes</option>
                      <option value="15">15 minutes</option>
                      <option value="30">30 minutes</option>
                    </select>
                  </div>

                  <div>
                    <label className="block text-sm font-medium mb-2">Cache cleanup threshold</label>
                    <select className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-md">
                      <option value="50">50%</option>
                      <option value="75" selected>75%</option>
                      <option value="85">85%</option>
                      <option value="90">90%</option>
                    </select>
                  </div>

                  <div>
                    <label className="block text-sm font-medium mb-2">Development project paths</label>
                    <div className="space-y-2">
                      <code className="block text-xs bg-gray-700 px-2 py-1 rounded">C:\Projects\*</code>
                      <code className="block text-xs bg-gray-700 px-2 py-1 rounded">D:\Development\*</code>
                      <code className="block text-xs bg-gray-700 px-2 py-1 rounded">C:\Users\Dev\Code\*</code>
                    </div>
                    <Button size="xs" variant="outline" className="mt-2">
                      Add Path
                    </Button>
                  </div>
                </div>
              </Card>

              <Card>
                <h3 className="text-lg font-semibold mb-4">Backup & Restore</h3>
                <div className="space-y-3">
                  <Button variant="outline" className="w-full justify-start">
                    <Database size={16} className="mr-2" />
                    Backup Configuration
                  </Button>
                  <Button variant="outline" className="w-full justify-start">
                    <RotateCcw size={16} className="mr-2" />
                    Restore Settings
                  </Button>
                  <Button variant="danger" className="w-full justify-start">
                    <Trash2 size={16} className="mr-2" />
                    Reset to Defaults
                  </Button>
                </div>
              </Card>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}

export default StorageOptimizer;
