import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rfid_project/main.dart';
import 'package:rfid_project/rfid_logic.dart';

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
        // Call onTagRead when a tag is read
        await onTagRead(tagId, widget.appConfig.antenna);
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
        _status = 'Failed to read tag: $e.message}';
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
