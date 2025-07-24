import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:rfid_project/gpio_output.dart';
import 'dart:convert'; // Added for jsonDecode
import 'package:shared_preferences/shared_preferences.dart';
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

// --- ConfigTab (to be implemented) ---
class ConfigTab extends StatefulWidget {
  final AppConfig appConfig;
  const ConfigTab({super.key, required this.appConfig});

  @override
  State<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<ConfigTab> {
  List<Map<String, dynamic>> groups = [];

  // Track used items for each dropdown
  Set<int> usedInputAntennas = {};
  Set<int> usedOutputAntennas = {};
  Set<int> usedInputLimitSwitches = {};
  Set<int> usedOutputLimitSwitches = {};
  Set<int> usedAlarmOutputs = {};

  static const String _groupsKey = 'config_groups';

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final groupsJson = prefs.getString(_groupsKey);
    if (groupsJson != null) {
      final List<dynamic> decoded = jsonDecode(groupsJson);
      groups = decoded.cast<Map<String, dynamic>>();
      // Rebuild used sets
      usedInputAntennas.clear();
      usedOutputAntennas.clear();
      usedInputLimitSwitches.clear();
      usedOutputLimitSwitches.clear();
      usedAlarmOutputs.clear();
      for (final g in groups) {
        if (g['inputAntenna'] != null) {
          usedInputAntennas.add(g['inputAntenna']);
        }
        if (g['outputAntenna'] != null) {
          usedOutputAntennas.add(g['outputAntenna']);
        }
        if (g['inputLimitSwitch'] != null) {
          usedInputLimitSwitches.add(g['inputLimitSwitch']);
        }
        if (g['outputLimitSwitch'] != null) {
          usedOutputLimitSwitches.add(g['outputLimitSwitch']);
        }
        if (g['alarmOutput'] != null) {
          usedAlarmOutputs.add(g['alarmOutput']);
        }
      }
      setState(() {});
    }
  }

  Future<void> _saveGroups() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_groupsKey, jsonEncode(groups));
  }

  void _deleteGroup(int idx) {
    final g = groups[idx];
    setState(() {
      if (g['inputAntenna'] != null) {
        usedInputAntennas.remove(g['inputAntenna']);
      }
      if (g['outputAntenna'] != null) {
        usedOutputAntennas.remove(g['outputAntenna']);
      }
      if (g['inputLimitSwitch'] != null) {
        usedInputLimitSwitches.remove(g['inputLimitSwitch']);
      }
      if (g['outputLimitSwitch'] != null) {
        usedOutputLimitSwitches.remove(g['outputLimitSwitch']);
      }
      if (g['alarmOutput'] != null) {
        usedAlarmOutputs.remove(g['alarmOutput']);
      }
      groups.removeAt(idx);
    });
    _saveGroups();
  }

  void _showAddGroupDialog({int? editIdx}) async {
    int? inputAntenna;
    int? outputAntenna;
    int? inputLimitSwitch;
    int? outputLimitSwitch;
    int? alarmOutput;
    String apiAddress = '';
    int readTime = 1000;
    int groupOutputDuration = 120; // default 120 seconds (2 minutes)
    final formKey = GlobalKey<FormState>();

    // If editing, pre-fill values
    if (editIdx != null) {
      final g = groups[editIdx];
      inputAntenna = g['inputAntenna'];
      outputAntenna = g['outputAntenna'];
      inputLimitSwitch = g['inputLimitSwitch'];
      outputLimitSwitch = g['outputLimitSwitch'];
      alarmOutput = g['alarmOutput'];
      apiAddress = g['apiAddress'] ?? '';
      readTime = g['readTime'] ?? 1000;
      groupOutputDuration = g['groupOutputDuration'] ?? 120;
    }

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            editIdx == null
                ? 'Add Group Configuration'
                : 'Edit Group Configuration',
          ),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int?>(
                        value: inputAntenna,
                        decoration: const InputDecoration(
                          labelText: 'Input Antenna',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('None'),
                          ),
                          ...List.generate(appConfig.antennaCount, (i) => i + 1)
                              .where(
                                (e) =>
                                    ((!usedInputAntennas.contains(e) &&
                                            !usedOutputAntennas.contains(e)) ||
                                        e == inputAntenna) &&
                                    e !=
                                        outputAntenna, // Prevent using same antenna for input and output in the same group
                              )
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text('Antenna $e'),
                                ),
                              ),
                        ],
                        onChanged: (v) => setState(() => inputAntenna = v),
                      ),
                      DropdownButtonFormField<int?>(
                        value: outputAntenna,
                        decoration: const InputDecoration(
                          labelText: 'Output Antenna',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('None'),
                          ),
                          ...List.generate(appConfig.antennaCount, (i) => i + 1)
                              .where(
                                (e) =>
                                    ((!usedInputAntennas.contains(e) &&
                                            !usedOutputAntennas.contains(e)) ||
                                        e == outputAntenna) &&
                                    e !=
                                        inputAntenna, // Prevent using same antenna for input and output in the same group
                              )
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text('Antenna $e'),
                                ),
                              ),
                        ],
                        onChanged: (v) => setState(() => outputAntenna = v),
                      ),
                      DropdownButtonFormField<int?>(
                        value: inputLimitSwitch,
                        decoration: const InputDecoration(
                          labelText: 'Input Limit Switch',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('None'),
                          ),
                          ...List.generate(appConfig.antennaCount, (i) => i + 1)
                              .where(
                                (e) =>
                                    (!usedInputLimitSwitches.contains(e) ||
                                        e == inputLimitSwitch) &&
                                    e !=
                                        outputLimitSwitch, // Prevent using same limit switch for input and output in the same group
                              )
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text('Limit Switch $e'),
                                ),
                              ),
                        ],
                        onChanged: (v) => setState(() => inputLimitSwitch = v),
                      ),
                      DropdownButtonFormField<int?>(
                        value: outputLimitSwitch,
                        decoration: const InputDecoration(
                          labelText: 'Output Limit Switch',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('None'),
                          ),
                          ...List.generate(appConfig.antennaCount, (i) => i + 1)
                              .where(
                                (e) =>
                                    (!usedOutputLimitSwitches.contains(e) ||
                                        e == outputLimitSwitch) &&
                                    e !=
                                        inputLimitSwitch, // Prevent using same limit switch for input and output in the same group
                              )
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text('Limit Switch $e'),
                                ),
                              ),
                        ],
                        onChanged: (v) => setState(() => outputLimitSwitch = v),
                      ),
                      DropdownButtonFormField<int?>(
                        value: alarmOutput,
                        decoration: const InputDecoration(
                          labelText: 'Alarm Output',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('None'),
                          ),
                          ...List.generate(appConfig.antennaCount, (i) => i + 1)
                              .where(
                                (e) =>
                                    !usedAlarmOutputs.contains(e) ||
                                    e == alarmOutput,
                              )
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text('Alarm $e'),
                                ),
                              ),
                        ],
                        onChanged: (v) => setState(() => alarmOutput = v),
                      ),
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'API Address',
                        ),
                        initialValue: apiAddress,
                        onChanged: (v) => apiAddress = v,
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Enter API address' : null,
                      ),
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Read Time (ms)',
                        ),
                        initialValue: readTime.toString(),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => readTime = int.tryParse(v) ?? 1000,
                        validator: (v) => (v == null || int.tryParse(v) == null)
                            ? 'Enter valid number'
                            : null,
                      ),
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Group Output Duration (seconds)',
                        ),
                        initialValue: groupOutputDuration.toString(),
                        keyboardType: TextInputType.number,
                        onChanged: (v) =>
                            groupOutputDuration = int.tryParse(v) ?? 120,
                        validator: (v) => (v == null || int.tryParse(v) == null)
                            ? 'Enter valid number'
                            : null,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  setState(() {
                    // Remove old used values if editing
                    if (editIdx != null) {
                      final old = groups[editIdx];
                      if (old['inputAntenna'] != null) {
                        usedInputAntennas.remove(old['inputAntenna']);
                      }
                      if (old['outputAntenna'] != null) {
                        usedOutputAntennas.remove(old['outputAntenna']);
                      }
                      // Remove from both sets if antenna was used as both input and output in the same group
                      if (old['inputAntenna'] != null &&
                          usedOutputAntennas.contains(old['inputAntenna'])) {
                        usedOutputAntennas.remove(old['inputAntenna']);
                      }
                      if (old['outputAntenna'] != null &&
                          usedInputAntennas.contains(old['outputAntenna'])) {
                        usedInputAntennas.remove(old['outputAntenna']);
                      }
                    }
                    final newGroup = {
                      'inputAntenna': inputAntenna,
                      'outputAntenna': outputAntenna,
                      'inputLimitSwitch': inputLimitSwitch,
                      'outputLimitSwitch': outputLimitSwitch,
                      'alarmOutput': alarmOutput,
                      'apiAddress': apiAddress,
                      'readTime': readTime,
                      'groupOutputDuration': groupOutputDuration,
                    };
                    if (editIdx != null) {
                      groups[editIdx] = newGroup;
                    } else {
                      groups.add(newGroup);
                    }
                    // Add to both sets if antenna is used as input or output
                    if (inputAntenna != null) {
                      usedInputAntennas.add(inputAntenna!);
                      usedOutputAntennas.add(inputAntenna!);
                    }
                    if (outputAntenna != null) {
                      usedInputAntennas.add(outputAntenna!);
                      usedOutputAntennas.add(outputAntenna!);
                    }
                    if (inputLimitSwitch != null) {
                      usedInputLimitSwitches.add(inputLimitSwitch!);
                    }
                    if (outputLimitSwitch != null) {
                      usedOutputLimitSwitches.add(outputLimitSwitch!);
                    }
                    if (alarmOutput != null) {
                      usedAlarmOutputs.add(alarmOutput!);
                    }
                  });
                  _saveGroups();
                  Navigator.of(context).pop();
                }
              },
              child: Text(editIdx == null ? 'Add' : 'Save'),
            ),
          ],
        );
      },
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Build a map of antenna assignments
    Map<int, String> antennaAssignments = {};
    for (int i = 1; i <= appConfig.antennaCount; i++) {
      String assignment = '';
      for (int idx = 0; idx < groups.length; idx++) {
        final g = groups[idx];
        if (g['inputAntenna'] == i) {
          assignment += 'Input (Group ${idx + 1}) ';
        }
        if (g['outputAntenna'] == i) {
          assignment += 'Output (Group ${idx + 1}) ';
        }
      }
      antennaAssignments[i] = assignment.isEmpty ? 'Free' : assignment.trim();
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Number of Antennas:'),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: widget.appConfig.antennaCount,
                  items: [4, 8]
                      .map(
                        (count) => DropdownMenuItem(
                          value: count,
                          child: Text('$count'),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        widget.appConfig.setAntennaCount(val);
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Antenna assignment summary at the very top
            Text(
              'Antenna Assignments',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (int i = 1; i <= appConfig.antennaCount; i++)
                  Chip(
                    avatar: Icon(
                      antennaAssignments[i] == 'Free'
                          ? Icons.radio_button_unchecked
                          : Icons.check_circle,
                      color: antennaAssignments[i] == 'Free'
                          ? Colors.grey
                          : Colors.blue,
                    ),
                    label: Text('Antenna $i: ${antennaAssignments[i]}'),
                    backgroundColor: antennaAssignments[i] == 'Free'
                        ? Colors.grey[200]
                        : Colors.blue[100],
                  ),
              ],
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Groups',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                ElevatedButton.icon(
                  onPressed: () => _showAddGroupDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            groups.isEmpty
                ? const Center(child: Text('No groups configured.'))
                : Column(
                    children: List.generate(groups.length, (idx) {
                      final g = groups[idx];
                      return SizedBox(
                        width: 320,
                        child: Card(
                          margin: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 8,
                          ),
                          child: ListTile(
                            title: Text('Group ${idx + 1}'),
                            subtitle: SizedBox(
                              height: 200, // or 220, 240, etc. as needed
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Input Antenna:  ${g['inputAntenna'] ?? 'None'}',
                                  ),
                                  Text(
                                    'Output Antenna:  ${g['outputAntenna'] ?? 'None'}',
                                  ),
                                  Text(
                                    'Input Limit Switch:  ${g['inputLimitSwitch'] ?? 'None'}',
                                  ),
                                  Text(
                                    'Output Limit Switch:  ${g['outputLimitSwitch'] ?? 'None'}',
                                  ),
                                  Text(
                                    'Alarm Output:  ${g['alarmOutput'] ?? 'None'}',
                                  ),
                                  Text('API Address:  ${g['apiAddress']}'),
                                  Text('Read Time:  ${g['readTime']} ms'),
                                  Text(
                                    'Output Duration:  ${g['groupOutputDuration']} s',
                                  ),
                                ],
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.blue,
                                  ),
                                  onPressed: () =>
                                      _showAddGroupDialog(editIdx: idx),
                                  tooltip: 'Edit Group',
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _deleteGroup(idx),
                                  tooltip: 'Delete Group',
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
          ],
        ),
      ),
    );
  }
}

// --- RunTab (to be implemented) ---
class RunTab extends StatefulWidget {
  final AppConfig appConfig;
  const RunTab({super.key, required this.appConfig});

  @override
  State<RunTab> createState() => _RunTabState();
}

class _RunTabState extends State<RunTab> with AutomaticKeepAliveClientMixin {
  bool isRunning = false;
  bool isActivating = false; // Make sure this is false by default
  bool inputActive = false;
  bool outputActive = false;
  bool antennaActive = false;
  List<String> unauthorizedTags = [];
  String unauthorizedTagsUrl = '';
  Timer? _statusTimer;
  Timer? _unauthTagsTimer;
  static const statusEventChannel = EventChannel('rfid_status_channel');
  StreamSubscription? _statusSubscription;
  List<Map<String, dynamic>> groups = [];
  static const String _groupsKey = 'config_groups';

  @override
  void initState() {
    super.initState();
    isActivating = false; // Ensure not activating on load
    _listenToStatus();
    _startUnauthorizedTagsPolling();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final groupsJson = prefs.getString(_groupsKey);
    if (groupsJson != null) {
      final List<dynamic> decoded = jsonDecode(groupsJson);
      setState(() {
        groups = decoded.cast<Map<String, dynamic>>();
      });
    }
  }

  void _listenToStatus() {
    _statusSubscription = statusEventChannel.receiveBroadcastStream().listen((
      event,
    ) {
      if (event is Map) {
        setState(() {
          // Update antennaConfigs for all antennas (1-4)
          for (int ant = 1; ant <= appConfig.antennaCount; ant++) {
            widget.appConfig.antennaConfigs[ant] = {
              'configured': true,
              'lastStatus': event['antenna'] == true ? 'Success' : 'Failure',
              'lastTag': '', // You can update this if you have tag info
            };
          }
          inputActive = event['input'] ?? false;
          outputActive = event['output'] ?? false;
          antennaActive = event['antenna'] ?? false;
        });
      }
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _unauthTagsTimer?.cancel();
    super.dispose();
  }

  void _startRun() async {
    setState(() {
      isRunning = true;
      isActivating = true;
    });
    Future.delayed(const Duration(seconds: 1), () async {
      setState(() {
        isActivating = false;
      });
      try {
        await MethodChannel('rfid_channel').invokeMethod('startReading');
        // Real status will be updated via EventChannel
      } catch (e) {
        setState(() {
          isRunning = false;
        });
      }
      _startUnauthorizedTagsPolling();
    });
  }

  void _stopRun() async {
    setState(() {
      isRunning = false;
      isActivating = false; // Always reset on stop
    });
    try {
      await MethodChannel('rfid_channel').invokeMethod('stopReading');
    } catch (e) {
      // Intentionally ignored
    }
    _statusTimer?.cancel();
    _unauthTagsTimer?.cancel();
  }

  void _startUnauthorizedTagsPolling() {
    _fetchUnauthorizedTags();
    _unauthTagsTimer?.cancel();
    _unauthTagsTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _fetchUnauthorizedTags();
    });
  }

  Future<void> _fetchUnauthorizedTags() async {
    if (unauthorizedTagsUrl.isEmpty) return;
    try {
      final response = await http.get(Uri.parse(unauthorizedTagsUrl));
      if (response.statusCode == 200) {
        final List<dynamic> data = List<dynamic>.from(
          jsonDecode(response.body),
        );
        setState(() {
          unauthorizedTags = data.map((e) => e.toString()).toList();
        });
      }
    } catch (e) {
      // Optionally show error
    }
  }

  Widget _groupStatusCard(Map<String, dynamic> group, int idx) {
    final inputAntenna = group['inputAntenna'];
    final outputAntenna = group['outputAntenna'];
    final inputLimitSwitch = group['inputLimitSwitch'];
    final outputLimitSwitch = group['outputLimitSwitch'];
    final alarmOutput = group['alarmOutput'];
    final apiAddress = group['apiAddress'];
    final readTime = group['readTime'];
    final outputDuration = group['groupOutputDuration']; // Use the new field
    final antennaStatus = inputAntenna != null
        ? widget.appConfig.antennaConfigs[inputAntenna] ??
              {'lastStatus': 'N/A', 'lastTag': ''}
        : {'lastStatus': 'N/A', 'lastTag': ''};
    final outputAntennaStatus = outputAntenna != null
        ? widget.appConfig.antennaConfigs[outputAntenna] ??
              {'lastStatus': 'N/A', 'lastTag': ''}
        : {'lastStatus': 'N/A', 'lastTag': ''};
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Group ${idx + 1}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Input Antenna: ${inputAntenna ?? 'None'} (Status: ${antennaStatus['lastStatus']}, Last Tag: ${antennaStatus['lastTag']})',
            ),
            Text(
              'Output Antenna: ${outputAntenna ?? 'None'} (Status: ${outputAntennaStatus['lastStatus']}, Last Tag: ${outputAntennaStatus['lastTag']})',
            ),
            Text('Input Limit Switch: ${inputLimitSwitch ?? 'None'}'),
            Text('Output Limit Switch: ${outputLimitSwitch ?? 'None'}'),
            Text('Alarm Output: ${alarmOutput ?? 'None'}'),
            Text('API Address: $apiAddress'),
            Text('Read Time: ${readTime ?? 'None'} ms'),
            Text('Output Duration: ${outputDuration ?? 'None'} s'),
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Important: call super.build when using keep alive
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: isRunning ? null : _startRun,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start'),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: isRunning ? _stopRun : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (isRunning || isActivating) ...[
              Text('Status:', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (groups.isEmpty)
                const Text('No groups configured.')
              else
                ...groups.asMap().entries.map(
                  (entry) => _groupStatusCard(entry.value, entry.key),
                ),
              const SizedBox(height: 24),
            ],
            Text(
              'Unauthorized Tags URL:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Enter unauthorized tags JSON URL',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                setState(() {
                  unauthorizedTagsUrl = v;
                });
                if (isRunning) _fetchUnauthorizedTags();
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Unauthorized Tags:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200, // Set a fixed height for the list
              child: unauthorizedTags.isEmpty
                  ? const Text('No unauthorized tags detected.')
                  : ListView.builder(
                      itemCount: unauthorizedTags.length,
                      itemBuilder: (context, idx) => ListTile(
                        leading: const Icon(
                          Icons.warning,
                          color: Colors.orange,
                        ),
                        title: Text(unauthorizedTags[idx]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- TagWritePage ---
class TagWritePage extends StatefulWidget {
  final AppConfig appConfig;
  const TagWritePage({super.key, required this.appConfig});

  @override
  State<TagWritePage> createState() => _TagWritePageState();
}

class _TagWritePageState extends State<TagWritePage> {
  String _originalTagId = '';
  final _tagDataController = TextEditingController();
  String _status = '';
  bool _isWriting = false;
  static const platform = MethodChannel('rfid_channel');

  Future<void> _readTagForWrite() async {
    setState(() {
      _status = 'Reading tag...';
    });
    try {
      await platform.invokeMethod('setAntennaConfiguration', {
        'antenna': widget.appConfig.antenna,
      });
      final String? tagId = await platform.invokeMethod<String>(
        'readSingleTag',
      );
      if (tagId != null && tagId.isNotEmpty) {
        setState(() {
          _originalTagId = tagId;
          _tagDataController.text = tagId;
          _status = 'Tag Read: $tagId';
        });
      } else {
        setState(() {
          _originalTagId = '';
          _tagDataController.text = '';
          _status = 'No tag found or empty ID.';
        });
      }
    } on PlatformException catch (e) {
      setState(() {
        _originalTagId = '';
        _tagDataController.text = '';
        _status = 'Failed to read tag: ${e.message}';
      });
    }
  }

  Future<void> _writeTagData() async {
    if (_tagDataController.text.isEmpty) {
      setState(() {
        _status = 'Tag data cannot be empty to write.';
      });
      return;
    }
    if (_isWriting) return;

    setState(() {
      _isWriting = true;
      _status = 'Writing tag...';
    });

    try {
      final String dataToWrite = _tagDataController.text;
      final bool? success = await platform.invokeMethod<bool>('writeTagData', {
        'currentEpc': _originalTagId,
        'newEpc': dataToWrite,
      });

      setState(() {
        if (success == true) {
          _status = 'Tag written successfully with new ID: $dataToWrite';
          _originalTagId = dataToWrite;
        } else {
          _status =
              'Failed to write tag. SDK returned failure or tag not found.';
        }
      });
    } on PlatformException catch (e) {
      setState(() {
        _status = 'Failed to write tag (Platform Exception): ${e.message}';
      });
    } finally {
      setState(() {
        _isWriting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton(
            onPressed: _readTagForWrite,
            child: const Text('Read Tag to Write/Edit'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tagDataController,
            decoration: const InputDecoration(
              labelText: 'Tag ID / Data to Write',
              hintText: 'Read a tag or enter data manually',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: (_originalTagId.isNotEmpty && !_isWriting)
                ? _writeTagData
                : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isWriting
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Write Data to Tag'),
          ),
          const SizedBox(height: 24),
          Text(_status, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// --- Enhanced Status Box ---
// StatusBox class removed; StatusCard is now used in the widget tree where needed.

Future<bool> getLimitSwitchState(int group, String type) async {
  // type: 'input' or 'output'
  // Read group config to get the correct limit switch index
  final prefs = await SharedPreferences.getInstance();
  final groupsJson = prefs.getString('config_groups');
  if (groupsJson == null) return false;
  final List<dynamic> decoded = jsonDecode(groupsJson);
  final groupConfig = decoded.cast<Map<String, dynamic>>().firstWhere(
    (g) => g['inputAntenna'] == group || g['outputAntenna'] == group,
    orElse: () => {},
  );
  int? switchIndex;
  if (type == 'input') {
    switchIndex = groupConfig['inputLimitSwitch'];
  } else if (type == 'output') {
    switchIndex = groupConfig['outputLimitSwitch'];
  }
  if (switchIndex == null) return false;
  try {
    const platform = MethodChannel('rfid_channel');
    final Map<dynamic, dynamic>? gpioStates = await platform
        .invokeMethod<Map<dynamic, dynamic>>('readGpioValues');
    if (gpioStates != null && gpioStates.containsKey('gpio$switchIndex')) {
      return gpioStates['gpio$switchIndex'] == true;
    }
  } catch (_) {}
  return false;
}

Future<void> onTagRead(String tagId, int antenna) async {
  final config = appConfig.antennaConfigs[antenna];
  if (config == null) return;
  final group = config['group'] as int?;
  if (group == null) return;
  final allowedIds = appConfig.groupAllowedIds[group] ?? {};
  final isValid = allowedIds.contains(tagId);
  final apiAddress = config['url'] as String?;
  // Get group config for output duration
  final prefs = await SharedPreferences.getInstance();
  final groupsJson = prefs.getString('config_groups');
  int groupOutputDuration = 120;
  if (groupsJson != null) {
    final List<dynamic> decoded = jsonDecode(groupsJson);
    final groupConfig = decoded.cast<Map<String, dynamic>>().firstWhere(
      (g) => g['inputAntenna'] == antenna || g['outputAntenna'] == antenna,
      orElse: () => {},
    );
    groupOutputDuration = groupConfig['groupOutputDuration'] ?? 120;
  }
  // Read limit switch states
  final outputLimitActive = await getLimitSwitchState(group, 'output');
  final inputLimitActive = await getLimitSwitchState(group, 'input');
  // Scenario 1
  if (outputLimitActive) {
    await setGroupOutputsActive(appConfig, group, false);
    if (apiAddress != null && apiAddress.isNotEmpty) {
      final payload = {
        'tag': tagId,
        'antenna': antenna,
        'signalType': 'not valid',
      };
      try {
        await http.post(
          Uri.parse(apiAddress),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
      } catch (e) {
        //
      }
    }
    return;
  }
  // Scenario 2
  if (!outputLimitActive && inputLimitActive) {
    await setGroupOutputsActive(appConfig, group, true);
    if (apiAddress != null && apiAddress.isNotEmpty) {
      final payload = {'tag': tagId, 'antenna': antenna, 'signalType': 'valid'};
      try {
        await http.post(
          Uri.parse(apiAddress),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
      } catch (e) {
        //
      }
    }
    return;
  }
  // Scenario 3
  if (!outputLimitActive && !inputLimitActive) {
    await setGroupOutputsActive(appConfig, group, false);
    if (apiAddress != null && apiAddress.isNotEmpty) {
      final payload = {
        'tag': tagId,
        'antenna': antenna,
        'signalType': 'not valid',
      };
      try {
        await http.post(
          Uri.parse(apiAddress),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
      } catch (e) {
        //
      }
    }
    return;
  }
  // Scenario 4: Input antenna reads a valid tag (from JSON), activate group output for groupOutputDuration seconds, no request
  if (isValid && config['inputAntenna'] == antenna) {
    await setGroupOutputsActive(appConfig, group, true);
    Future.delayed(Duration(seconds: groupOutputDuration), () async {
      await setGroupOutputsActive(appConfig, group, false);
    });
    return;
  }
}
