/// Test target configuration — flip these when switching between devices.
/// Never commit with isPhysicalDeviceTest = true to production branches.
class DevTargets {
  DevTargets._();

  static const bool isPhysicalDeviceTest = true;
  static const bool isEmulatorTest = false;

  /// LAN IP of your dev machine (run `ipconfig` to pick Wi-Fi IPv4).
  static const String physicalDeviceIp = '10.129.71.67';
  static const String emulatorIp = '10.0.2.2';
  static const int devPort = 8000;

  static String get _host {
    if (isPhysicalDeviceTest) return physicalDeviceIp;
    if (isEmulatorTest) return emulatorIp;
    return emulatorIp;
  }

  static String get devApiBaseUrl => 'http://$_host:$devPort';
  static String get devWsBaseUrl => 'ws://$_host:$devPort';
}
