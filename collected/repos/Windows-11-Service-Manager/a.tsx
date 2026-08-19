import React, { useState, useEffect, useMemo } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Progress } from '@/components/ui/progress';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, BarChart, Bar } from 'recharts';
import { Activity, Cpu, MemoryStick, Zap, Shield, AlertTriangle, CheckCircle, Clock, Network, HardDrive } from 'lucide-react';

// Mock data for services
const generateMockServices = () => [
  {
    id: 1,
    name: "Windows Search",
    displayName: "Windows Search Service",
    status: "running",
    startupType: "automatic",
    cpuUsage: 15.2,
    memoryUsage: 156.8,
    category: "bloatware",
    recommendation: "disable",
    safeToDisable: true,
    dependencies: ["RpcSs", "DcomLaunch"],
    dependents: [],
    description: "Provides content indexing and property caching for files",
    performanceImpact: "high",
    lastRestart: "2h 34m ago"
  },
  {
    id: 2,
    name: "Superfetch",
    displayName: "SysMain (Superfetch)",
    status: "running",
    startupType: "automatic",
    cpuUsage: 8.7,
    memoryUsage: 89.3,
    category: "bloatware",
    recommendation: "disable",
    safeToDisable: true,
    dependencies: ["RpcSs"],
    dependents: [],
    description: "Maintains and improves system performance over time",
    performanceImpact: "medium",
    lastRestart: "5h 12m ago"
  },
  {
    id: 3,
    name: "Windows Audio",
    displayName: "Windows Audio Service",
    status: "running",
    startupType: "automatic",
    cpuUsage: 2.1,
    memoryUsage: 23.7,
    category: "essential",
    recommendation: "keep",
    safeToDisable: false,
    dependencies: ["RpcSs", "AudioEndpointBuilder"],
    dependents: ["AudioSrv"],
    description: "Manages audio for Windows-based programs",
    performanceImpact: "low",
    lastRestart: "12h 45m ago"
  },
  {
    id: 4,
    name: "Cortana",
    displayName: "Cortana Service",
    status: "running",
    startupType: "automatic",
    cpuUsage: 12.4,
    memoryUsage: 67.2,
    category: "bloatware",
    recommendation: "disable",
    safeToDisable: true,
    dependencies: ["RpcSs"],
    dependents: [],
    description: "Voice assistant and search helper",
    performanceImpact: "high",
    lastRestart: "1h 22m ago"
  },
  {
    id: 5,
    name: "Print Spooler",
    displayName: "Print Spooler Service",
    status: "running",
    startupType: "automatic",
    cpuUsage: 0.3,
    memoryUsage: 12.1,
    category: "optional",
    recommendation: "manual",
    safeToDisable: true,
    dependencies: ["RpcSs"],
    dependents: ["Fax"],
    description: "Loads files to memory for later printing",
    performanceImpact: "low",
    lastRestart: "8h 15m ago"
  },
  {
    id: 6,
    name: "Windows Defender",
    displayName: "Windows Security Service",
    status: "running",
    startupType: "automatic",
    cpuUsage: 5.8,
    memoryUsage: 145.6,
    category: "security",
    recommendation: "keep",
    safeToDisable: false,
    dependencies: ["RpcSs", "WinDefend"],
    dependents: ["SecurityHealthService"],
    description: "Provides malware protection",
    performanceImpact: "medium",
    lastRestart: "3h 45m ago"
  }
];

const generatePerformanceHistory = () => {
  const now = Date.now();
  return Array.from({ length: 20 }, (_, i) => ({
    time: new Date(now - (19 - i) * 60000).toLocaleTimeString('en-US', { 
      hour12: false, 
      hour: '2-digit', 
      minute: '2-digit' 
    }),
    cpu: Math.random() * 30 + 10,
    memory: Math.random() * 500 + 200,
    services: Math.floor(Math.random() * 10) + 120
  }));
};

export default function WindowsServiceManager() {
  const [services, setServices] = useState(generateMockServices());
  const [performanceHistory, setPerformanceHistory] = useState(generatePerformanceHistory());
  const [selectedService, setSelectedService] = useState(null);
  const [isOptimizing, setIsOptimizing] = useState(false);
  const [connectionStatus, setConnectionStatus] = useState('connected');
  const [filter, setFilter] = useState('all');
  const [sortBy, setSortBy] = useState('cpuUsage');

  // Simulate real-time updates
  useEffect(() => {
    const interval = setInterval(() => {
      setServices(prev => prev.map(service => ({
        ...service,
        cpuUsage: Math.max(0, service.cpuUsage + (Math.random() - 0.5) * 2),
        memoryUsage: Math.max(0, service.memoryUsage + (Math.random() - 0.5) * 10)
      })));
      
      setPerformanceHistory(prev => {
        const newPoint = {
          time: new Date().toLocaleTimeString('en-US', { 
            hour12: false, 
            hour: '2-digit', 
            minute: '2-digit' 
          }),
          cpu: Math.random() * 30 + 10,
          memory: Math.random() * 500 + 200,
          services: Math.floor(Math.random() * 10) + 120
        };
        return [...prev.slice(1), newPoint];
      });
    }, 2000);

    return () => clearInterval(interval);
  }, []);

  const filteredServices = useMemo(() => {
    let filtered = services;
    
    if (filter !== 'all') {
      filtered = filtered.filter(service => service.category === filter);
    }
    
    return filtered.sort((a, b) => {
      if (sortBy === 'name') return a.name.localeCompare(b.name);
      return b[sortBy] - a[sortBy];
    });
  }, [services, filter, sortBy]);

  const systemMetrics = useMemo(() => {
    const totalCpu = services.reduce((sum, s) => sum + s.cpuUsage, 0);
    const totalMemory = services.reduce((sum, s) => sum + s.memoryUsage, 0);
    const bloatwareServices = services.filter(s => s.category === 'bloatware').length;
    const potentialSavings = services
      .filter(s => s.safeToDisable)
      .reduce((sum, s) => sum + s.memoryUsage, 0);
    
    return { totalCpu, totalMemory, bloatwareServices, potentialSavings };
  }, [services]);

  const optimizeServices = async () => {
    setIsOptimizing(true);
    
    // Simulate optimization process
    await new Promise(resolve => setTimeout(resolve, 3000));
    
    setServices(prev => prev.map(service => {
      if (service.safeToDisable && service.recommendation === 'disable') {
        return { ...service, status: 'stopped', cpuUsage: 0, memoryUsage: 0 };
      }
      if (service.recommendation === 'manual') {
        return { ...service, startupType: 'manual' };
      }
      return service;
    }));
    
    setIsOptimizing(false);
  };

  const getCategoryIcon = (category) => {
    switch (category) {
      case 'bloatware': return <AlertTriangle className="h-4 w-4 text-orange-500" />;
      case 'essential': return <Shield className="h-4 w-4 text-green-500" />;
      case 'security': return <Shield className="h-4 w-4 text-blue-500" />;
      case 'optional': return <Clock className="h-4 w-4 text-gray-500" />;
      default: return <Activity className="h-4 w-4" />;
    }
  };

  const getCategoryBadgeColor = (category) => {
    switch (category) {
      case 'bloatware': return 'bg-orange-100 text-orange-800 border-orange-200';
      case 'essential': return 'bg-green-100 text-green-800 border-green-200';
      case 'security': return 'bg-blue-100 text-blue-800 border-blue-200';
      case 'optional': return 'bg-gray-100 text-gray-800 border-gray-200';
      default: return 'bg-gray-100 text-gray-800 border-gray-200';
    }
  };

  const getStatusColor = (status) => {
    return status === 'running' ? 'text-green-600' : 'text-red-600';
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-50 to-slate-100 p-6">
      <div className="mx-auto max-w-7xl space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-4xl font-bold bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-transparent">
              Windows 11 Service Manager
            </h1>
            <p className="text-lg text-gray-600 mt-2">
              Intelligent service optimization for maximum performance
            </p>
          </div>
          <div className="flex items-center gap-4">
            <Badge 
              variant="outline" 
              className={`px-3 py-1 ${connectionStatus === 'connected' ? 'border-green-200 bg-green-50 text-green-700' : 'border-red-200 bg-red-50 text-red-700'}`}
            >
              <div className={`w-2 h-2 rounded-full mr-2 ${connectionStatus === 'connected' ? 'bg-green-500' : 'bg-red-500'}`} />
              {connectionStatus === 'connected' ? 'Connected to Windows 11' : 'Disconnected'}
            </Badge>
            <Button 
              onClick={optimizeServices} 
              disabled={isOptimizing}
              className="bg-gradient-to-r from-blue-600 to-purple-600 hover:from-blue-700 hover:to-purple-700"
            >
              {isOptimizing ? (
                <div className="flex items-center gap-2">
                  <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                  Optimizing...
                </div>
              ) : (
                <div className="flex items-center gap-2">
                  <Zap className="h-4 w-4" />
                  Auto-Optimize
                </div>
              )}
            </Button>
          </div>
        </div>

        {/* System Overview */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
          <Card className="border-0 shadow-lg bg-white/70 backdrop-blur-sm">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Total CPU Usage</CardTitle>
              <Cpu className="h-4 w-4 text-blue-500" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold text-blue-600">
                {systemMetrics.totalCpu.toFixed(1)}%
              </div>
              <Progress value={systemMetrics.totalCpu} className="mt-2" />
              <p className="text-xs text-gray-500 mt-2">
                From {services.filter(s => s.status === 'running').length} active services
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 shadow-lg bg-white/70 backdrop-blur-sm">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Memory Usage</CardTitle>
              <MemoryStick className="h-4 w-4 text-green-500" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold text-green-600">
                {(systemMetrics.totalMemory / 1024).toFixed(1)} GB
              </div>
              <Progress value={(systemMetrics.totalMemory / 1024) * 10} className="mt-2" />
              <p className="text-xs text-gray-500 mt-2">
                {systemMetrics.totalMemory.toFixed(0)} MB total
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 shadow-lg bg-white/70 backdrop-blur-sm">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Bloatware Detected</CardTitle>
              <AlertTriangle className="h-4 w-4 text-orange-500" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold text-orange-600">
                {systemMetrics.bloatwareServices}
              </div>
              <p className="text-xs text-gray-500 mt-2">
                Services safe to disable
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 shadow-lg bg-white/70 backdrop-blur-sm">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Potential Savings</CardTitle>
              <Zap className="h-4 w-4 text-purple-500" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold text-purple-600">
                {(systemMetrics.potentialSavings / 1024).toFixed(1)} GB
              </div>
              <p className="text-xs text-gray-500 mt-2">
                Memory that can be freed
              </p>
            </CardContent>
          </Card>
        </div>

        {/* Performance Chart */}
        <Card className="border-0 shadow-lg bg-white/70 backdrop-blur-sm">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Activity className="h-5 w-5 text-blue-500" />
              Real-time Performance Monitor
            </CardTitle>
            <CardDescription>
              Live system metrics updated every 2 seconds
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={performanceHistory}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                  <XAxis dataKey="time" stroke="#64748b" />
                  <YAxis stroke="#64748b" />
                  <Tooltip 
                    contentStyle={{ 
                      backgroundColor: 'rgba(255, 255, 255, 0.95)',
                      border: 'none',
                      borderRadius: '8px',
                      boxShadow: '0 4px 6px -1px rgba(0, 0, 0, 0.1)'
                    }}
                  />
                  <Line 
                    type="monotone" 
                    dataKey="cpu" 
                    stroke="#3b82f6" 
                    strokeWidth={2}
                    name="CPU Usage (%)"
                  />
                  <Line 
                    type="monotone" 
                    dataKey="memory" 
                    stroke="#10b981" 
                    strokeWidth={2}
                    name="Memory Usage (MB)"
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </CardContent>
        </Card>

        {/* Services Management */}
        <Card className="border-0 shadow-lg bg-white/70 backdrop-blur-sm">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Network className="h-5 w-5 text-green-500" />
              Service Management
            </CardTitle>
            <CardDescription>
              Intelligent recommendations based on your usage patterns
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Tabs defaultValue="services" className="w-full">
              <TabsList className="grid w-full grid-cols-3">
                <TabsTrigger value="services">Active Services</TabsTrigger>
                <TabsTrigger value="recommendations">Smart Recommendations</TabsTrigger>
                <TabsTrigger value="dependencies">Dependency Map</TabsTrigger>
              </TabsList>
              
              <TabsContent value="services" className="mt-6">
                <div className="flex gap-4 mb-6">
                  <select 
                    value={filter} 
                    onChange={(e) => setFilter(e.target.value)}
                    className="px-3 py-2 border border-gray-200 rounded-md bg-white"
                  >
                    <option value="all">All Services</option>
                    <option value="bloatware">Bloatware</option>
                    <option value="essential">Essential</option>
                    <option value="security">Security</option>
                    <option value="optional">Optional</option>
                  </select>
                  
                  <select 
                    value={sortBy} 
                    onChange={(e) => setSortBy(e.target.value)}
                    className="px-3 py-2 border border-gray-200 rounded-md bg-white"
                  >
                    <option value="cpuUsage">Sort by CPU</option>
                    <option value="memoryUsage">Sort by Memory</option>
                    <option value="name">Sort by Name</option>
                  </select>
                </div>

                <div className="space-y-3">
                  {filteredServices.map((service) => (
                    <Card 
                      key={service.id}
                      className={`transition-all duration-200 hover:shadow-md cursor-pointer border-l-4 ${
                        service.category === 'bloatware' ? 'border-l-orange-400' :
                        service.category === 'essential' ? 'border-l-green-400' :
                        service.category === 'security' ? 'border-l-blue-400' : 'border-l-gray-400'
                      }`}
                      onClick={() => setSelectedService(service)}
                    >
                      <CardContent className="p-4">
                        <div className="flex items-center justify-between">
                          <div className="flex items-center gap-3">
                            {getCategoryIcon(service.category)}
                            <div>
                              <h3 className="font-semibold text-gray-900">
                                {service.displayName}
                              </h3>
                              <p className="text-sm text-gray-500">
                                {service.name}
                              </p>
                            </div>
                            <Badge className={getCategoryBadgeColor(service.category)}>
                              {service.category}
                            </Badge>
                          </div>
                          
                          <div className="flex items-center gap-4 text-right">
                            <div>
                              <p className="text-sm font-medium">
                                CPU: {service.cpuUsage.toFixed(1)}%
                              </p>
                              <p className="text-sm text-gray-500">
                                RAM: {service.memoryUsage.toFixed(0)} MB
                              </p>
                            </div>
                            
                            <div className={`text-sm font-medium ${getStatusColor(service.status)}`}>
                              {service.status.toUpperCase()}
                            </div>
                            
                            {service.recommendation === 'disable' && (
                              <Badge variant="destructive">Disable</Badge>
                            )}
                            {service.recommendation === 'manual' && (
                              <Badge variant="secondary">Manual</Badge>
                            )}
                            {service.recommendation === 'keep' && (
                              <Badge variant="default" className="bg-green-100 text-green-800">Keep</Badge>
                            )}
                          </div>
                        </div>
                      </CardContent>
                    </Card>
                  ))}
                </div>
              </TabsContent>
              
              <TabsContent value="recommendations" className="mt-6">
                <div className="space-y-4">
                  <Alert className="border-orange-200 bg-orange-50">
                    <AlertTriangle className="h-4 w-4 text-orange-600" />
                    <AlertDescription className="text-orange-800">
                      <strong>High Impact Optimization Available:</strong> Disabling 3 bloatware services could free up 313 MB RAM and reduce CPU usage by 36.3%
                    </AlertDescription>
                  </Alert>

                  <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <Card>
                      <CardHeader>
                        <CardTitle className="text-lg">Services to Disable</CardTitle>
                        <CardDescription>Safe to disable with no system impact</CardDescription>
                      </CardHeader>
                      <CardContent className="space-y-3">
                        {services
                          .filter(s => s.recommendation === 'disable')
                          .map(service => (
                            <div key={service.id} className="flex items-center justify-between p-3 bg-red-50 rounded-lg border border-red-100">
                              <div>
                                <p className="font-medium text-red-900">{service.displayName}</p>
                                <p className="text-sm text-red-600">Impact: {service.performanceImpact}</p>
                              </div>
                              <div className="text-right">
                                <p className="text-sm font-medium text-red-800">
                                  -{service.memoryUsage.toFixed(0)} MB
                                </p>
                                <p className="text-xs text-red-600">
                                  -{service.cpuUsage.toFixed(1)}% CPU
                                </p>
                              </div>
                            </div>
                          ))}
                      </CardContent>
                    </Card>

                    <Card>
                      <CardHeader>
                        <CardTitle className="text-lg">Startup Type Changes</CardTitle>
                        <CardDescription>Set these to manual start</CardDescription>
                      </CardHeader>
                      <CardContent className="space-y-3">
                        {services
                          .filter(s => s.recommendation === 'manual')
                          .map(service => (
                            <div key={service.id} className="flex items-center justify-between p-3 bg-yellow-50 rounded-lg border border-yellow-100">
                              <div>
                                <p className="font-medium text-yellow-900">{service.displayName}</p>
                                <p className="text-sm text-yellow-600">Change to manual startup</p>
                              </div>
                              <Badge variant="secondary">Manual</Badge>
                            </div>
                          ))}
                      </CardContent>
                    </Card>
                  </div>
                </div>
              </TabsContent>
              
              <TabsContent value="dependencies" className="mt-6">
                <div className="space-y-4">
                  <Alert>
                    <Network className="h-4 w-4" />
                    <AlertDescription>
                      Service dependency mapping helps prevent breaking system functionality when disabling services
                    </AlertDescription>
                  </Alert>
                  
                  <Card>
                    <CardHeader>
                      <CardTitle>Dependency Analysis</CardTitle>
                    </CardHeader>
                    <CardContent>
                      <div className="space-y-4">
                        {services.slice(0, 3).map(service => (
                          <div key={service.id} className="border rounded-lg p-4">
                            <h4 className="font-semibold mb-2">{service.displayName}</h4>
                            <div className="grid grid-cols-2 gap-4 text-sm">
                              <div>
                                <p className="font-medium text-gray-600 mb-1">Dependencies:</p>
                                <div className="flex flex-wrap gap-1">
                                  {service.dependencies.map(dep => (
                                    <Badge key={dep} variant="outline" className="text-xs">{dep}</Badge>
                                  ))}
                                </div>
                              </div>
                              <div>
                                <p className="font-medium text-gray-600 mb-1">Dependents:</p>
                                <div className="flex flex-wrap gap-1">
                                  {service.dependents.length > 0 ? (
                                    service.dependents.map(dep => (
                                      <Badge key={dep} variant="outline" className="text-xs">{dep}</Badge>
                                    ))
                                  ) : (
                                    <span className="text-xs text-gray-400">None</span>
                                  )}
                                </div>
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>
            </Tabs>
          </CardContent>
        </Card>

        {/* Service Details Modal */}
        {selectedService && (
          <Card className="border-0 shadow-xl bg-white/90 backdrop-blur-sm">
            <CardHeader>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  {getCategoryIcon(selectedService.category)}
                  <div>
                    <CardTitle>{selectedService.displayName}</CardTitle>
                    <CardDescription>{selectedService.description}</CardDescription>
                  </div>
                </div>
                <Button 
                  variant="outline" 
                  onClick={() => setSelectedService(null)}
                >
                  Close
                </Button>
              </div>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                <div>
                  <h4 className="font-semibold mb-3">Current Status</h4>
                  <div className="space-y-2">
                    <div className="flex justify-between">
                      <span className="text-gray-600">Status:</span>
                      <span className={`font-medium ${getStatusColor(selectedService.status)}`}>
                        {selectedService.status.toUpperCase()}
                      </span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">Startup:</span>
                      <span className="font-medium">{selectedService.startupType}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">Last Restart:</span>
                      <span className="font-medium">{selectedService.lastRestart}</span>
                    </div>
                  </div>
                </div>
                
                <div>
                  <h4 className="font-semibold mb-3">Performance Impact</h4>
                  <div className="space-y-2">
                    <div className="flex justify-between">
                      <span className="text-gray-600">CPU Usage:</span>
                      <span className="font-medium">{selectedService.cpuUsage.toFixed(1)}%</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">Memory Usage:</span>
                      <span className="font-medium">{selectedService.memoryUsage.toFixed(0)} MB</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">Impact Level:</span>
                      <Badge 
                        className={
                          selectedService.performanceImpact === 'high' ? 'bg-red-100 text-red-800' :
                          selectedService.performanceImpact === 'medium' ? 'bg-yellow-100 text-yellow-800' :
                          'bg-green-100 text-green-800'
                        }
                      >
                        {selectedService.performanceImpact}
                      </Badge>
                    </div>
                  </div>
                </div>
                
                <div>
                  <h4 className="font-semibold mb-3">Recommendation</h4>
                  <div className="space-y-3">
                    <Badge 
                      className={
                        selectedService.recommendation === 'disable' ? 'bg-red-100 text-red-800 border-red-200' :
                        selectedService.recommendation === 'manual' ? 'bg-yellow-100 text-yellow-800 border-yellow-200' :
                        'bg-green-100 text-green-800 border-green-200'
                      }
                    >
                      {selectedService.recommendation === 'disable' ? 'Safe to Disable' :
                       selectedService.recommendation === 'manual' ? 'Set to Manual' :
                       'Keep Running'}
                    </Badge>
                    
                    {selectedService.safeToDisable && (
                      <div className="flex items-center gap-2 text-green-600">
                        <CheckCircle className="h-4 w-4" />
                        <span className="text-sm">Safe to modify</span>
                      </div>
                    )}
                    
                    <div className="space-y-1">
                      <p className="text-xs text-gray-500">Dependencies:</p>
                      <div className="flex flex-wrap gap-1">
                        {selectedService.dependencies.map(dep => (
                          <Badge key={dep} variant="outline" className="text-xs">{dep}</Badge>
                        ))}
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}
