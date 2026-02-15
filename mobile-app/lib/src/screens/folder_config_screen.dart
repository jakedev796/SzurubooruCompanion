import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/scheduled_folder.dart';
import '../services/settings_model.dart';

/// Screen for configuring a scheduled folder
class FolderConfigScreen extends StatefulWidget {
  final ScheduledFolder? folder; // null for new folder

  const FolderConfigScreen({super.key, this.folder});

  @override
  State<FolderConfigScreen> createState() => _FolderConfigScreenState();
}

class _FolderConfigScreenState extends State<FolderConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _tagsController = TextEditingController();
  
  String? _selectedFolderUri;
  String? _selectedFolderName;
  String _safety = 'safe';
  bool _skipTagging = false;
  bool _isLoading = false;
  bool _isSaving = false;

  final List<String> _safetyOptions = ['safe', 'sketchy', 'unsafe'];

  @override
  void initState() {
    super.initState();
    
    if (widget.folder != null) {
      _nameController.text = widget.folder!.name;
      _selectedFolderUri = widget.folder!.uri;
      _selectedFolderName = widget.folder!.name;
      _safety = widget.folder!.defaultSafety ?? 'safe';
      _skipTagging = widget.folder!.skipTagging;
      
      if (widget.folder!.defaultTags?.isNotEmpty == true) {
        _tagsController.text = widget.folder!.defaultTags!.join(', ');
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    setState(() => _isLoading = true);

    try {
      // Use file_picker to select a directory
      final result = await FilePicker.platform.getDirectoryPath();

      if (!mounted) return;

      if (result != null) {
        // Verify the directory exists
        final directory = Directory(result);
        if (!await directory.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Selected directory does not exist')),
            );
          }
          setState(() => _isLoading = false);
          return;
        }

        // Convert absolute path to relative path if it's under /storage/emulated/0/
        String folderUri = result;
        const storagePrefix = '/storage/emulated/0/';
        if (result.startsWith(storagePrefix)) {
          folderUri = result.substring(storagePrefix.length);
        }

        // Extract display name from path
        final parts = result.split('/');
        final displayName = parts.lastWhere(
          (p) => p.isNotEmpty,
          orElse: () => 'Selected Folder',
        );

        setState(() {
          _selectedFolderUri = folderUri;
          _selectedFolderName = Uri.decodeComponent(displayName);
          if (_nameController.text.isEmpty) {
            _nameController.text = _selectedFolderName!;
          }
        });
      } else {
        // User cancelled
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Folder selection cancelled')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking folder: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    if (_selectedFolderUri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a folder')),
      );
      return;
    }

    setState(() => _isSaving = true);
    
    try {
      final settings = context.read<SettingsModel>();
      
      // Parse tags
      final tagsText = _tagsController.text.trim();
      final tags = tagsText.isEmpty
          ? <String>[]
          : tagsText.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
      
      final folder = ScheduledFolder(
        id: widget.folder?.id ?? const Uuid().v4(),
        name: _nameController.text.trim(),
        uri: _selectedFolderUri!,
        intervalSeconds: 900,
        lastRunTimestamp: widget.folder?.lastRunTimestamp ?? 0,
        enabled: widget.folder?.enabled ?? true,
        defaultTags: tags.isEmpty ? null : tags,
        defaultSafety: _safety,
        skipTagging: _skipTagging,
      );
      
      if (widget.folder != null) {
        await settings.updateScheduledFolder(folder);
      } else {
        await settings.addScheduledFolder(folder);
      }
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Folder "${folder.name}" saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving folder: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folder != null ? 'Edit Folder' : 'Add Folder'),
        actions: [
          if (!_isSaving)
            TextButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Folder Selection
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text(_selectedFolderName ?? 'Select Folder'),
                      subtitle: _selectedFolderUri != null
                          ? const Text('Tap to change folder')
                          : const Text('Tap to browse'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickFolder,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Name
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Folder Name',
                      hintText: 'e.g., Camera Uploads',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Safety
                  DropdownButtonFormField<String>(
                    value: _safety,
                    decoration: const InputDecoration(
                      labelText: 'Default Safety Rating',
                      border: OutlineInputBorder(),
                    ),
                    items: _safetyOptions.map((safety) {
                      return DropdownMenuItem(
                        value: safety,
                        child: Text(safety[0].toUpperCase() + safety.substring(1)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _safety = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Tags
                  TextFormField(
                    controller: _tagsController,
                    decoration: const InputDecoration(
                      labelText: 'Default Tags',
                      hintText: 'tag1, tag2, tag3',
                      border: OutlineInputBorder(),
                      helperText: 'Comma-separated tags to apply to all uploads',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  
                  // Skip Tagging
                  SwitchListTile(
                    title: const Text('Skip AI Tagging'),
                    subtitle: const Text(
                      'Disable automatic tag suggestions from WD14',
                    ),
                    value: _skipTagging,
                    onChanged: (value) {
                      setState(() => _skipTagging = value);
                    },
                  ),
                ],
              ),
            ),
    );
  }
}
