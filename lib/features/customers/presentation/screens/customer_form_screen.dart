import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/di/providers.dart';
import '../../data/customer_repository.dart';
import '../../data/models/customer_entity.dart';
import '../providers/customer_providers.dart';
import '../../../groups/presentation/providers/group_providers.dart';

class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({super.key, this.customer});
  final Customer? customer;

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final Map<String, TextEditingController> _fields;
  int _step = 0;
  String? _passportPath;
  CustomerStatus _status = CustomerStatus.active;
  String? _groupId;
  bool _saving = false;

  static const _keys = [
    'fullName',
    'gender',
    'dateOfBirth',
    'phone',
    'altPhone',
    'email',
    'residentialAddress',
    'businessAddress',
    'occupation',
    'employer',
    'maritalStatus',
    'nationality',
    'state',
    'lga',
    'nin',
    'bvn',
    'idType',
    'idNumber',
    'nextOfKin',
    'nextOfKinRelation',
    'nextOfKinPhone',
    'guarantor1Name',
    'guarantor2Name',
    'guarantorPhone',
    'guarantorAddress',
    'notes',
  ];

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    _passportPath = customer?.passportPath;
    _status = customer?.status ?? CustomerStatus.active;
    _groupId = customer?.groupId;
    final values = <String, String?>{
      'fullName': customer?.fullName,
      'gender': customer?.gender,
      'dateOfBirth': customer?.dateOfBirth,
      'phone': customer?.phone,
      'altPhone': customer?.altPhone,
      'email': customer?.email,
      'residentialAddress': customer?.residentialAddress,
      'businessAddress': customer?.businessAddress,
      'occupation': customer?.occupation,
      'employer': customer?.employer,
      'maritalStatus': customer?.maritalStatus,
      'nationality': customer?.nationality,
      'state': customer?.state,
      'lga': customer?.lga,
      'nin': customer?.nin,
      'bvn': customer?.bvn,
      'idType': customer?.idType,
      'idNumber': customer?.idNumber,
      'nextOfKin': customer?.nextOfKin,
      'nextOfKinRelation': customer?.nextOfKinRelation,
      'nextOfKinPhone': customer?.nextOfKinPhone,
      'guarantor1Name': customer?.guarantor1Name,
      'guarantor2Name': customer?.guarantor2Name,
      'guarantorPhone': customer?.guarantorPhone,
      'guarantorAddress': customer?.guarantorAddress,
      'notes': customer?.notes,
    };
    _fields = {
      for (final key in _keys)
        key: TextEditingController(text: values[key] ?? '')
    };
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _title =>
      widget.customer == null ? 'Add Customer' : 'Edit Customer';
  String _value(String key) => _fields[key]!.text.trim();
  String? _optional(String key) {
    final value = _value(key);
    return value.isEmpty ? null : value;
  }

  Future<void> _pickPassport(ImageSource source) async {
    final image = await _picker.pickImage(
        source: source, imageQuality: 85, maxWidth: 1200);
    if (image == null) return;
    final saved = await ref.read(storageServiceProvider).saveDocument(
          File(image.path),
          'customer_passports',
          'passport_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
    if (mounted) setState(() => _passportPath = saved);
  }

  Future<void> _selectDateOfBirth() async {
    final eighteenYearsAgo = DateTime.now().subtract(const Duration(days: 365 * 18));
    final initial = DateTime.tryParse(_value('dateOfBirth')) ?? eighteenYearsAgo;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      _fields['dateOfBirth']!.text = date.toIso8601String().split('T').first;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final existing = widget.customer;
    final customer = Customer(
      id: existing?.id ?? 'CUS-${DateTime.now().microsecondsSinceEpoch}',
      passportPath: _passportPath,
      fullName: _value('fullName'),
      gender: _optional('gender'),
      dateOfBirth: _optional('dateOfBirth'),
      phone: _value('phone'),
      altPhone: _optional('altPhone'),
      email: _optional('email'),
      residentialAddress: _optional('residentialAddress'),
      businessAddress: _optional('businessAddress'),
      occupation: _optional('occupation'),
      employer: _optional('employer'),
      maritalStatus: _optional('maritalStatus'),
      nationality: _optional('nationality'),
      state: _optional('state'),
      lga: _optional('lga'),
      nin: _optional('nin'),
      bvn: _optional('bvn'),
      idType: _optional('idType'),
      idNumber: _optional('idNumber'),
      nextOfKin: _optional('nextOfKin'),
      nextOfKinRelation: _optional('nextOfKinRelation'),
      nextOfKinPhone: _optional('nextOfKinPhone'),
      guarantor1Name: _optional('guarantor1Name'),
      guarantor2Name: _optional('guarantor2Name'),
      guarantorPhone: _optional('guarantorPhone'),
      guarantorAddress: _optional('guarantorAddress'),
      notes: _optional('notes'),
      dateRegistered:
          existing?.dateRegistered ?? DateTime.now().toIso8601String(),
      status: _status,
      creditScore: existing?.creditScore ?? 0,
      groupId: _groupId,
    );
    try {
      await ref.read(customerRepositoryProvider).save(customer);
      ref.invalidate(customerListProvider);
      ref.invalidate(customerProvider(customer.id));
      if (mounted) context.pop();
    } on DuplicateCustomerException catch (error) {
      _showMessage(error.toString());
    } catch (_) {
      _showMessage('Unable to save this customer. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Widget _field(String key, String label,
      {bool required = false,
      int maxLines = 1,
      TextInputType? type,
      VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _fields[key],
        maxLines: maxLines,
        keyboardType: type,
        readOnly: onTap != null,
        onTap: onTap,
        decoration: InputDecoration(labelText: label),
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                ? '$label is required'
                : null
            : null,
      ),
    );
  }

  Widget _imagePicker() => Column(children: [
        CircleAvatar(
          radius: 48,
          backgroundImage:
              _passportPath == null ? null : FileImage(File(_passportPath!)),
          child:
              _passportPath == null ? const Icon(Icons.person, size: 42) : null,
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
              onPressed: () => _pickPassport(ImageSource.camera),
              icon: const Icon(Icons.photo_camera),
              label: const Text('Camera')),
          OutlinedButton.icon(
              onPressed: () => _pickPassport(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('Gallery')),
        ]),
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Form(
        key: _formKey,
        child: Stepper(
          currentStep: _step,
          onStepTapped: (value) => setState(() => _step = value),
          onStepContinue: () {
            if (_step < 3) {
              setState(() => _step++);
            } else {
              _save();
            }
          },
          onStepCancel:
              _step == 0 ? () => context.pop() : () => setState(() => _step--),
          controlsBuilder: (context, details) => Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(children: [
              FilledButton(
                  onPressed: _saving ? null : details.onStepContinue,
                  child: Text(_step == 3 ? 'Save customer' : 'Continue')),
              const SizedBox(width: 8),
              TextButton(
                  onPressed: _saving ? null : details.onStepCancel,
                  child: Text(_step == 0 ? 'Cancel' : 'Back')),
            ]),
          ),
          steps: [
            Step(
                title: const Text('Personal'),
                isActive: _step >= 0,
                content: Column(children: [
                  _imagePicker(),
                  const SizedBox(height: 16),
                  _field('fullName', 'Full name', required: true),
                  _field('gender', 'Gender'),
                  _field('dateOfBirth', 'Date of birth',
                      onTap: _selectDateOfBirth),
                  _field('phone', 'Phone number',
                      required: true, type: TextInputType.phone),
                  _field('altPhone', 'Alternative phone',
                      type: TextInputType.phone),
                  _field('email', 'Email address',
                      type: TextInputType.emailAddress),
                  _field('maritalStatus', 'Marital status'),
                  _field('nationality', 'Nationality'),
                ])),
            Step(
                title: const Text('Address & identity'),
                isActive: _step >= 1,
                content: Column(children: [
                  _field('residentialAddress', 'Residential address',
                      maxLines: 2),
                  _field('businessAddress', 'Business address', maxLines: 2),
                  _field('occupation', 'Occupation'),
                  _field('employer', 'Employer'),
                  _field('state', 'State'),
                  _field('lga', 'LGA'),
                  _field('nin', 'NIN', type: TextInputType.number),
                  _field('bvn', 'BVN', type: TextInputType.number),
                  _field('idType', 'Means of identification'),
                  _field('idNumber', 'ID number'),
                ])),
            Step(
                title: const Text('Next of kin & guarantors'),
                isActive: _step >= 2,
                content: Column(children: [
                  _field('nextOfKin', 'Next of kin'),
                  _field('nextOfKinRelation', 'Relationship'),
                  _field('nextOfKinPhone', 'Next of kin phone',
                      type: TextInputType.phone),
                  _field('guarantor1Name', 'Guarantor 1'),
                  _field('guarantor2Name', 'Guarantor 2'),
                  _field('guarantorPhone', 'Guarantor phone',
                      type: TextInputType.phone),
                  _field('guarantorAddress', 'Guarantor address', maxLines: 2),
                ])),
            Step(
                title: const Text('Review'),
                isActive: _step >= 3,
                content: Column(children: [
                  DropdownButtonFormField<CustomerStatus>(
                      value: _status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: CustomerStatus.values
                          .map((status) => DropdownMenuItem(
                              value: status, child: Text(status.name)))
                          .toList(),
                      onChanged: (status) =>
                          setState(() => _status = status!)),
                  const SizedBox(height: 12),
                  // Group selector
                  Consumer(builder: (context, ref, _) {
                    final groupsAsync = ref.watch(groupListProvider);
                    return groupsAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (groups) => groups.isEmpty
                          ? const SizedBox.shrink()
                          : DropdownButtonFormField<String?>(
                              value: _groupId,
                              decoration: const InputDecoration(
                                  labelText: 'Customer Group (optional)'),
                              items: [
                                const DropdownMenuItem(
                                    value: null, child: Text('None')),
                                ...groups.map((g) => DropdownMenuItem(
                                    value: g.id, child: Text(g.name))),
                              ],
                              onChanged: (id) =>
                                  setState(() => _groupId = id)),
                    );
                  }),
                  const SizedBox(height: 12),
                  _field('notes', 'Notes', maxLines: 4),
                ])),
          ],
        ),
      ),
    );
  }
}
