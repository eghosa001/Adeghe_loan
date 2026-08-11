import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:loantrack/core/constants/app_constants.dart';
import 'package:loantrack/core/di/providers.dart';
import 'package:loantrack/core/utils/input_formatters.dart';
import 'package:loantrack/core/widgets/keyboard_scrollable.dart';
import '../providers/business_providers.dart';
import '../../data/models/business_profile_entity.dart';

class BusinessDetailsTab extends ConsumerStatefulWidget {
  const BusinessDetailsTab({super.key});
  @override
  ConsumerState<BusinessDetailsTab> createState() =>
      _BusinessDetailsTabState();
}

class _BusinessDetailsTabState extends ConsumerState<BusinessDetailsTab> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _regCtrl = TextEditingController();
  String? _logoPath;
  bool _hasPrefilled = false;
  bool _isEditing = false;

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
    if (!mounted) return;
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
    if (!mounted) return;
    setState(() => _isEditing = false);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business profile saved')));
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileView(BusinessProfile? profile) {
    if (profile == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.business_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('No business profile yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Tap the edit button to add your business details',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    )),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Center(
          child: CircleAvatar(
            radius: 50,
            backgroundImage:
                profile.logoPath != null ? FileImage(File(profile.logoPath!)) : null,
            child: profile.logoPath == null
                ? const Icon(Icons.business, size: 40)
                : null,
          ),
        ),
        const SizedBox(height: 24),
        _buildDetailRow('Business Name', profile.name),
        const Divider(),
        _buildDetailRow('Owner', profile.ownerName),
        const Divider(),
        _buildDetailRow('Address', profile.address),
        const Divider(),
        _buildDetailRow('Phone', profile.phone),
        const Divider(),
        _buildDetailRow('Email', profile.email),
        const Divider(),
        _buildDetailRow('Reg. No.', profile.regNo),
      ],
    );
  }

  Widget _buildEditForm(BusinessProfile? profile) {
    _prefill(profile);
    return Padding(
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
                inputFormatters:
                    textFormatters(maxLength: AppConstants.maxNameLength),
                validator: (v) => v!.isEmpty ? 'Required' : null),
            const SizedBox(height: 12),
            TextFormField(
                controller: _ownerCtrl,
                decoration: const InputDecoration(labelText: 'Owner Name'),
                inputFormatters:
                    textFormatters(maxLength: AppConstants.maxNameLength)),
            const SizedBox(height: 12),
            TextFormField(
                controller: _addressCtrl,
                decoration:
                    const InputDecoration(labelText: 'Business Address'),
                maxLines: 2,
                inputFormatters:
                    textFormatters(maxLength: AppConstants.maxAddressLength)),
            const SizedBox(height: 12),
            TextFormField(
                controller: _phoneCtrl,
                decoration:
                    const InputDecoration(labelText: 'Business Phone'),
                inputFormatters:
                    textFormatters(maxLength: AppConstants.maxPhoneLength)),
            const SizedBox(height: 12),
            TextFormField(
                controller: _emailCtrl,
                decoration:
                    const InputDecoration(labelText: 'Email Address'),
                inputFormatters:
                    textFormatters(maxLength: AppConstants.maxEmailLength)),
            const SizedBox(height: 12),
            TextFormField(
                controller: _regCtrl,
                decoration: const InputDecoration(
                    labelText: 'Registration Number'),
                inputFormatters: textFormatters(
                    maxLength: AppConstants.maxReferenceLength)),
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: _save, child: const Text('Save Profile')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(businessProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Business Profile')),
      body: KeyboardScrollable(
        child: profileAsync.when(
          data: (profile) => _isEditing
              ? _buildEditForm(profile)
              : _buildProfileView(profile),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text('Error loading profile: $error')),
      ),
      ),
      floatingActionButton: profileAsync.whenOrNull(
        data: (_) => FloatingActionButton(
          onPressed: () {
            if (_isEditing) {
              if (_formKey.currentState?.validate() ?? false) {
                _save();
              }
            } else {
              setState(() {
                _isEditing = true;
                _hasPrefilled = false;
              });
            }
          },
          child: Icon(_isEditing ? Icons.check : Icons.edit),
        ),
      ),
    );
  }
}
