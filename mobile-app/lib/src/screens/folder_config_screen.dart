import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:saf/saf.dart';
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
  int _intervalSeconds = 86400; // Default: 1 day
  String _safety = 'safe';
  bool _skipTagging = false;
  bool _isLoading = false;
  bool _isSaving = false;

  final List<Map<String, dynamic>> _intervalOptions = [
    {'label': 'Every 15 minutes', 'seconds': 900},
    {'label': 'Every 30 minutes', 'seconds': 1800},
    {'label': 'Every hour', 'seconds': 3600},
    {'label': 'Every 6 hours', 'seconds': 21600},
    {'label': 'Every 12 hours', 'seconds': 43200},
    {'label': 'Every day', 'seconds': 86400},
    {'label': 'Every week', 'seconds': 604800},
  ];

  final List<String> _safetyOptions = ['safe', 'sketchy', 'unsafe'];

  @override
  void initState() {
    super.initState();
    
    if (widget.folder != null) {
      _nameController.text = widget.folder!.name;
      _selectedFolderUri = widget.folder!.uri;
      _selectedFolderName = widget.folder!.name;
      _intervalSeconds = widget.folder!.intervalSeconds;
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
      // Use SAF to pick a folder directly
      final saf = Saf("/storage/emulated/0");
      
      // Request directory permission - this opens the native folder picker
      final granted = await saf.getDirectoryPermission(
        grantWritePermission: false,
        isDynamic: true,
      );
      
      if (!mounted) return;
      
      if (granted == true) {
        // Get the selected directory path
        final directories = await Saf.getPersistedPermissionDirectories();
        
        if (!mounted) return;
        
        if (directories != null && directories.isNotEmpty) {
          // Get the most recently selected directory
          final selectedPath = directories.last;
          
          // Extract display name from path
          final parts = selectedPath.split('/');
          final displayName = parts.lastWhere(
            (p) => p.isNotEmpty,
            orElse: () => 'Selected Folder',
          );
          
          setState(() {
            _selectedFolderUri = selectedPath;
            _selectedFolderName = Uri.decodeComponent(displayName);
            if (_nameController.text.isEmpty) {
              _nameController.text = _selectedFolderName!;
            }
          });
        } else {
          // No directory was returned
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No folder selected')),
            );
          }
        }
      } else {
        // Permission denied or user cancelled
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
        intervalSeconds: _intervalSeconds,
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
                  
                  // Interval
                  DropdownButtonFormField<int>(
                    value: _intervalSeconds,
                    decoration: const InputDecoration(
                      labelText: 'Scan Interval',
                      border: OutlineInputBorder(),
                    ),
                    items: _intervalOptions.map((option) {
                      return DropdownMenuItem(
                        value: option['seconds'] as int,
                        child: Text(option['label'] as String),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _intervalSeconds = value);
                      }
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
                  const SizedBox(height: 24),
                  
                  // Save Button
                  if (_isSaving)
                    const Center(child: CircularProgressIndicator())
                  else
                    ElevatedButton(
                      onPressed: _save,
                      child: const Text('Save Folder'),
                    ),
                ],
              ),
            ),
    );
  }
}
