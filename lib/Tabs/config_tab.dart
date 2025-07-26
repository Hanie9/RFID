import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:rfid_project/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
