import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:rfid_project/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
