import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:rfid_project/Tabs/config_tab.dart';
import 'package:rfid_project/Tabs/wrire_tab.dart';
import 'package:rfid_project/Tabs/run_tab.dart';
import 'dart:convert'; // Added for jsonDecode
import 'status_card.dart';

void main() {
  runApp(const MyApp());
}

class AppConfig extends ChangeNotifier {
  int antenna = 1;
  int group = 1;
  String url = '';
  int interval = 1000;
  bool isInitialized = false;
  bool isReading = false;
  Map<int, Map<String, dynamic>> antennaConfigs = {};
  Map<int, List<int>> groupInputs = {}; // group -> list of input indices
  Map<int, String> groupInputLogic =
      {}; // group -> logic type ("AND", "OR", etc.)
  Map<int, List<int>> groupOutputs = {}; // group -> list of output indices
  // Remove per-group JSON URL and duration
  // Map<int, String> groupJsonUrls = {}; // group -> JSON URL
  // Map<int, int> groupOutputDurations = {}; // group -> output duration (seconds)
  Map<int, Set<String>> groupAllowedIds = {}; // group -> allowed IDs from JSON

  // Add global JSON URL and output duration
  String jsonUrl = '';
  int outputDuration = 2;

  // Add methods to update and notify listeners
  void updateAntenna(int newAntenna) {
    antenna = newAntenna;
  }

  void updateAntennaConfig(int antenna, int group, String url, int interval) {
    antennaConfigs[antenna] = {
      'group': group,
      'url': url,
      'interval': interval,
      'lastStatus': 'Idle',
      'lastTag': '',
    };
    notifyListeners();
  }

  void updateAntennaStatus(int antenna, String status, String tag) {
    if (antennaConfigs.containsKey(antenna)) {
      antennaConfigs[antenna]!['lastStatus'] = status;
      antennaConfigs[antenna]!['lastTag'] = tag;
      notifyListeners();
    }
  }

  bool isAntennaConfigured(int antenna) {
    return antennaConfigs.containsKey(antenna);
  }

  void setGroupInputs(int group, List<int> inputs) {
    groupInputs[group] = inputs;
    notifyListeners();
  }

  void setGroupInputLogic(int group, String logic) {
    groupInputLogic[group] = logic;
    notifyListeners();
  }

  void setGroupOutputs(int group, List<int> outputs) {
    groupOutputs[group] = outputs;
    notifyListeners();
  }

  // Remove per-group setters for JSON URL and duration
  // void setGroupJsonUrl(int group, String url) {
  //   groupJsonUrls[group] = url;
  //   notifyListeners();
  // }
  // void setGroupOutputDuration(int group, int duration) {
  //   groupOutputDurations[group] = duration;
  //   notifyListeners();
  // }

  void setGroupAllowedIds(int group, Set<String> ids) {
    groupAllowedIds[group] = ids;
    notifyListeners();
  }

  // New setters for global JSON URL and output duration
  void setJsonUrl(String url) {
    jsonUrl = url;
    notifyListeners();
  }

  void setOutputDuration(int duration) {
    outputDuration = duration;
    notifyListeners();
  }

  int antennaCount = 4; // default to 4, can be set to 8
  void setAntennaCount(int count) {
    antennaCount = count;
    notifyListeners();
  }

  // ... other updaters
}

final AppConfig appConfig = AppConfig();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RFID U300',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  static const platform = MethodChannel('rfid_channel');
  String _deviceStatus = 'Not initialized';
  final String _readingStatus = 'Idle';

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermissions();
    _startGroupJsonPolling();
  }

  Timer? _jsonPollingTimer;

  void _startGroupJsonPolling() {
    // Run immediately, then every 10 minutes
    _fetchAllGroupJsons();
    _jsonPollingTimer?.cancel();
    _jsonPollingTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _fetchAllGroupJsons();
    });
  }

  Future<void> _fetchAllGroupJsons() async {
    final url = appConfig.jsonUrl;
    if (url.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          final List<dynamic> data = List<dynamic>.from(
            jsonDecode(response.body),
          );
          // Assume each item is a map with an 'id' and 'group' field
          // Clear all groupAllowedIds first
          for (var g = 1; g <= 4; g++) {
            appConfig.setGroupAllowedIds(g, {});
          }
          for (final item in data) {
            if (item is Map && item['id'] != null && item['group'] != null) {
              final group = int.tryParse(item['group'].toString());
              if (group != null && group >= 1 && group <= 4) {
                final ids = appConfig.groupAllowedIds[group] ?? <String>{};
                ids.add(item['id'].toString());
                appConfig.setGroupAllowedIds(group, ids);
              }
            }
          }
        }
      } catch (e) {
        // Ignore errors, keep previous cache
      }
    }
  }

  Future<void> _checkAndRequestPermissions() async {
    // List of permissions needed for RFID
    final permissions = [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ];
    bool allGranted = true;
    for (final perm in permissions) {
      if (await perm.isDenied || await perm.isPermanentlyDenied) {
        final status = await perm.request();
        if (!status.isGranted) {
          allGranted = false;
        }
      }
    }
    if (!allGranted) {
      _showPermissionDialog();
    } else {
      _initializeReader();
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Permissions Required'),
        content: const Text(
          'This app requires Bluetooth and Location permissions to function. Please grant them in settings.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _initializeReader() async {
    try {
      final bool? success = await platform.invokeMethod('initializeReader');
      setState(() {
        appConfig.isInitialized = success == true;
        _deviceStatus = success == true
            ? 'Device initialized'
            : 'Failed to initialize device';
      });
    } catch (e) {
      setState(() {
        appConfig.isInitialized = false;
        _deviceStatus = 'Error initializing device: $e';
      });
    }
  }

  @override
  void dispose() {
    platform.invokeMethod('releaseReader'); // Release reader when app closes
    _jsonPollingTimer?.cancel();
    super.dispose();
  }

  // Refactored pages for new tab structure
  static final List<Widget> _pages = <Widget>[
    ConfigTab(appConfig: appConfig),
    TagWritePage(appConfig: appConfig),
    RunTab(appConfig: appConfig),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RFID U300 Control'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: Column(
        children: [
          StatusCard(
            deviceStatus: _deviceStatus,
            readingStatus: _readingStatus,
            appConfig: appConfig,
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _pages[_selectedIndex],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.settings), label: 'Config'),
          NavigationDestination(icon: Icon(Icons.edit), label: 'Read Write'),
          NavigationDestination(icon: Icon(Icons.play_circle), label: 'Run'),
        ],
      ),
    );
  }
}
