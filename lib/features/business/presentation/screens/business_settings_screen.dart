import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';
import '../providers/business_providers.dart';
import 'package:loantrack/core/di/providers.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/models/business_profile_entity.dart';

class BusinessSettingsScreen extends ConsumerStatefulWidget {
  const BusinessSettingsScreen({super.key});
  @override
  ConsumerState<BusinessSettingsScreen> createState() =>
      _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState
    extends ConsumerState<BusinessSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _regCtrl = TextEditingController();
  String? _logoPath;
  bool _hasPrefilled = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ownerCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _regCtrl.dispose();
    super.dispose();
  }

  void _prefill(BusinessProfile? profile) {
    if (profile == null || _hasPrefilled) return;
    _nameCtrl.text = profile.name;
    _ownerCtrl.text = profile.ownerName;
    _addressCtrl.text = profile.address;
    _phoneCtrl.text = profile.phone;
    _emailCtrl.text = profile.email;
    _regCtrl.text = profile.regNo;
    _logoPath = profile.logoPath;
    _hasPrefilled = true;
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final saved = await ref
        .read(storageServiceProvider)
        .saveDocument(File(picked.path), 'business_assets', 'logo.png');
    setState(() => _logoPath = saved);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = BusinessProfile(
      id: '1',
      name: _nameCtrl.text.trim(),
      logoPath: _logoPath,
      ownerName: _ownerCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      regNo: _regCtrl.text.trim(),
    );
    await ref.read(businessProfileProvider.notifier).saveProfile(profile);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Business profile saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(businessProfileProvider);

    profileAsync.whenData((profile) {
      _prefill(profile);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Business Profile')),
      drawer: const AppDrawer(currentRoute: '/settings/business'),
      body: profileAsync.when(
        data: (_) => Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _pickLogo,
                    child: CircleAvatar(
                      radius: 50,
                      backgroundImage: _logoPath != null
                          ? FileImage(File(_logoPath!))
                          : null,
                      child: _logoPath == null
                          ? const Icon(Icons.add_a_photo)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                    controller: _nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Business Name'),
                    validator: (v) => v!.isEmpty ? 'Required' : null),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _ownerCtrl,
                    decoration: const InputDecoration(labelText: 'Owner Name')),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _addressCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Business Address')),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _phoneCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Business Phone')),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _emailCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Email Address')),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _regCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Registration Number')),
                const SizedBox(height: 20),
                ElevatedButton(
                    onPressed: _save, child: const Text('Save Profile')),
              ],
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text('Error loading profile: $error')),
      ),
    );
  }
}
