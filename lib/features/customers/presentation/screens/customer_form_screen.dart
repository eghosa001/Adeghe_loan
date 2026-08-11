import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/input_formatters.dart';
import '../../../../core/utils/platform_utils.dart';
import '../../data/customer_repository.dart';
import '../../data/models/customer_entity.dart';
import '../providers/customer_providers.dart';
import '../../../groups/presentation/providers/group_providers.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../collection/presentation/providers/collection_provider.dart';
import '../../../reports/presentation/providers/report_provider.dart';

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
  String? _selectedGroupId;
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
    'maritalStatus',
    'state',
    'lga',
    'nin',
    'bvn',
    'guarantor1Name',
    'guarantor1Phone',
    'guarantor1Address',
    'guarantor2Name',
    'guarantor2Phone',
    'guarantor2Address',
    'notes',
  ];

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    _passportPath = customer?.passportPath;
    _status = customer?.status ?? CustomerStatus.active;
    _selectedGroupId = customer?.groupId;
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
      'maritalStatus': customer?.maritalStatus,
      'state': customer?.state,
      'lga': customer?.lga,
      'nin': customer?.nin,
      'bvn': customer?.bvn,
      'guarantor1Name': customer?.guarantor1Name,
      'guarantor1Phone': customer?.guarantor1Phone,
      'guarantor1Address': customer?.guarantor1Address,
      'guarantor2Name': customer?.guarantor2Name,
      'guarantor2Phone': customer?.guarantor2Phone,
      'guarantor2Address': customer?.guarantor2Address,
      'notes': customer?.notes,
    };
    _fields = {
      for (final key in _keys)
        key: TextEditingController(text: values[key] ?? ''),
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
      source: source,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (image == null) return;
    final saved = await ref
        .read(storageServiceProvider)
        .saveDocument(
          File(image.path),
          'customer_passports',
          'passport_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
    if (mounted) setState(() => _passportPath = saved);
  }

  Future<void> _selectDateOfBirth() async {
    final now = DateTime.now();
    final eighteenYearsAgo = DateTime(now.year - 18, now.month, now.day);
    final initial =
        DateTime.tryParse(_value('dateOfBirth')) ?? eighteenYearsAgo;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      _fields['dateOfBirth']!.text = AppDateUtils.formatForStorage(date);
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
      employer: existing?.employer,
      maritalStatus: _optional('maritalStatus'),
      nationality: existing?.nationality,
      state: _optional('state'),
      lga: _optional('lga'),
      nextOfKin: existing?.nextOfKin,
      nextOfKinRelation: existing?.nextOfKinRelation,
      nextOfKinPhone: existing?.nextOfKinPhone,
      guarantor1Name: _optional('guarantor1Name'),
      guarantor1Phone: _optional('guarantor1Phone'),
      guarantor1Address: _optional('guarantor1Address'),
      guarantor2Name: _optional('guarantor2Name'),
      guarantor2Phone: _optional('guarantor2Phone'),
      guarantor2Address: _optional('guarantor2Address'),
      guarantorPassportPath: existing?.guarantorPassportPath,
      nin: _optional('nin'),
      bvn: _optional('bvn'),
      idType: existing?.idType,
      idNumber: existing?.idNumber,
      signaturePath: existing?.signaturePath,
      notes: _optional('notes'),
      dateRegistered:
          existing?.dateRegistered ??
          AppDateUtils.formatForStorage(DateTime.now()),
      status: _status,
      creditScore: existing?.creditScore ?? 0,
      groupId: _selectedGroupId,
    );
    try {
      final repo = await ref.read(customerRepositoryProvider.future);
      await repo.save(customer);
      ref.invalidate(customerListProvider);
      ref.invalidate(customerCountProvider);
      ref.invalidate(customerProvider(customer.id));
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(collectionListProvider);
      invalidateReportData(ref.invalidate);
      if (mounted) context.pop();
    } on DuplicateCustomerException catch (error) {
      _showMessage(error.toString());
    } catch (error) {
      // Avoid logging the full error or stack trace which may contain PII or
      // sensitive data. Log only a minimal non-sensitive summary.
      developer.log('Customer save error: ${error.runtimeType}');
      _showMessage('Unable to save customer');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Widget _field(
    String key,
    String label, {
    bool required = false,
    int maxLines = 1,
    TextInputType? type,
    VoidCallback? onTap,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _fields[key],
        maxLines: maxLines,
        keyboardType: type,
        readOnly: onTap != null,
        onTap: onTap,
        inputFormatters:
            inputFormatters ??
            (maxLength != null ? textFormatters(maxLength: maxLength) : null),
        decoration: InputDecoration(labelText: label),
        validator:
            validator ??
            (required
                ? (value) => value == null || value.trim().isEmpty
                      ? '$label is required'
                      : null
                : null),
      ),
    );
  }

  List<TextInputFormatter> _nameFormatters() => [
    TextInputFormatter.withFunction(
      (oldValue, newValue) =>
          newValue.copyWith(text: newValue.text.toUpperCase()),
    ),
    ...textFormatters(maxLength: AppConstants.maxNameLength),
  ];

  String? _validatePhone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    return RegExp(r'^\+?[0-9]{7,15}$').hasMatch(v)
        ? null
        : 'Enter a valid phone number';
  }

  String? _validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)
        ? null
        : 'Enter a valid email address';
  }

  String? Function(String?) _validateNinBvn(String label) {
    return (value) {
      final v = value?.trim() ?? '';
      if (v.isEmpty) return null;
      return RegExp(r'^\d{11}$').hasMatch(v)
          ? null
          : '$label must be 11 digits';
    };
  }

  Widget _imagePicker() => Column(
    children: [
      CircleAvatar(
        radius: 48,
        backgroundImage: _passportPath == null
            ? null
            : FileImage(File(_passportPath!)),
        child: _passportPath == null
            ? const Icon(Icons.person, size: 42)
            : null,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          if (canUseCamera)
            OutlinedButton.icon(
              onPressed: () => _pickPassport(ImageSource.camera),
              icon: const Icon(Icons.photo_camera),
              label: const Text('Camera'),
            ),
          OutlinedButton.icon(
            onPressed: () => _pickPassport(ImageSource.gallery),
            icon: const Icon(Icons.photo_library),
            label: const Text('Gallery'),
          ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupListProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Form(
        key: _formKey,
        child: Stepper(
          currentStep: _step,
          onStepTapped: (value) => setState(() => _step = value),
          onStepContinue: () {
            if (_step < 2) {
              setState(() => _step++);
            } else {
              _save();
            }
          },
          onStepCancel: _step == 0
              ? () => context.pop()
              : () => setState(() => _step--),
          controlsBuilder: (context, details) => Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                FilledButton(
                  onPressed: _saving ? null : details.onStepContinue,
                  child: Text(_step == 2 ? 'Save customer' : 'Continue'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _saving ? null : details.onStepCancel,
                  child: Text(_step == 0 ? 'Cancel' : 'Back'),
                ),
              ],
            ),
          ),
          steps: [
            Step(
              title: const Text('Personal'),
              isActive: _step >= 0,
              content: Column(
                children: [
                  _imagePicker(),
                  const SizedBox(height: 16),
                  _field(
                    'fullName',
                    'Full name',
                    required: true,
                    maxLength: AppConstants.maxNameLength,
                    inputFormatters: _nameFormatters(),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DropdownButtonFormField<String>(
                      initialValue: _value('gender').isEmpty
                          ? null
                          : _value('gender'),
                      decoration: const InputDecoration(labelText: 'Gender'),
                      items: const [
                        DropdownMenuItem(value: 'Male', child: Text('Male')),
                        DropdownMenuItem(
                          value: 'Female',
                          child: Text('Female'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _fields['gender']!.text = value ?? ''),
                    ),
                  ),
                  _field(
                    'dateOfBirth',
                    'Date of birth',
                    onTap: _selectDateOfBirth,
                  ),
                  _field(
                    'phone',
                    'Phone number',
                    required: true,
                    type: TextInputType.phone,
                    maxLength: AppConstants.maxPhoneLength,
                    validator: _validatePhone,
                  ),
                  _field(
                    'altPhone',
                    'Alternative phone',
                    type: TextInputType.phone,
                    maxLength: AppConstants.maxPhoneLength,
                    validator: _validatePhone,
                  ),
                  _field(
                    'email',
                    'Email address',
                    type: TextInputType.emailAddress,
                    maxLength: AppConstants.maxEmailLength,
                    validator: _validateEmail,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DropdownButtonFormField<String>(
                      initialValue: _value('maritalStatus').isEmpty
                          ? null
                          : _value('maritalStatus'),
                      decoration: const InputDecoration(
                        labelText: 'Marital status',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Single',
                          child: Text('Single'),
                        ),
                        DropdownMenuItem(
                          value: 'Married',
                          child: Text('Married'),
                        ),
                        DropdownMenuItem(
                          value: 'Divorced',
                          child: Text('Divorced'),
                        ),
                      ],
                      onChanged: (value) => setState(
                        () => _fields['maritalStatus']!.text = value ?? '',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Step(
              title: const Text('Address & identity'),
              isActive: _step >= 1,
              content: Column(
                children: [
                  _field(
                    'residentialAddress',
                    'Residential address',
                    maxLines: 2,
                    maxLength: AppConstants.maxAddressLength,
                  ),
                  _field(
                    'businessAddress',
                    'Business address',
                    maxLines: 2,
                    maxLength: AppConstants.maxAddressLength,
                  ),
                  _field(
                    'occupation',
                    'Occupation',
                    maxLength: AppConstants.maxNameLength,
                  ),
                  _field(
                    'state',
                    'State',
                    maxLength: AppConstants.maxNameLength,
                  ),
                  _field('lga', 'LGA', maxLength: AppConstants.maxNameLength),
                  _field(
                    'nin',
                    'NIN',
                    type: TextInputType.number,
                    maxLength: AppConstants.maxIdentifierLength,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(
                        AppConstants.maxIdentifierLength,
                      ),
                    ],
                    validator: _validateNinBvn('NIN'),
                  ),
                  _field(
                    'bvn',
                    'BVN',
                    type: TextInputType.number,
                    maxLength: AppConstants.maxIdentifierLength,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(
                        AppConstants.maxIdentifierLength,
                      ),
                    ],
                    validator: _validateNinBvn('BVN'),
                  ),
                ],
              ),
            ),
            Step(
              title: const Text('Guarantors & review'),
              isActive: _step >= 2,
              content: Column(
                children: [
                  Text(
                    'Guarantor 1',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _field(
                    'guarantor1Name',
                    'Name',
                    maxLength: AppConstants.maxNameLength,
                    inputFormatters: _nameFormatters(),
                  ),
                  _field(
                    'guarantor1Phone',
                    'Phone',
                    type: TextInputType.phone,
                    maxLength: AppConstants.maxPhoneLength,
                    validator: _validatePhone,
                  ),
                  _field(
                    'guarantor1Address',
                    'Address',
                    maxLines: 2,
                    maxLength: AppConstants.maxAddressLength,
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Guarantor 2',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _field(
                    'guarantor2Name',
                    'Name',
                    maxLength: AppConstants.maxNameLength,
                    inputFormatters: _nameFormatters(),
                  ),
                  _field(
                    'guarantor2Phone',
                    'Phone',
                    type: TextInputType.phone,
                    maxLength: AppConstants.maxPhoneLength,
                    validator: _validatePhone,
                  ),
                  _field(
                    'guarantor2Address',
                    'Address',
                    maxLines: 2,
                    maxLength: AppConstants.maxAddressLength,
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: groupsAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, _) => const SizedBox.shrink(),
                      data: (groups) => DropdownButtonFormField<String?>(
                        initialValue: _selectedGroupId,
                        decoration: const InputDecoration(
                          labelText: 'Customer group',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('— No group —'),
                          ),
                          ...groups.map(
                            (g) => DropdownMenuItem(
                              value: g.id,
                              child: Text(g.name),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _selectedGroupId = value),
                      ),
                    ),
                  ),
                  DropdownButtonFormField<CustomerStatus>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: CustomerStatus.values
                        .map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(status.name),
                          ),
                        )
                        .toList(),
                    onChanged: (status) => setState(() => _status = status!),
                  ),
                  const SizedBox(height: 12),
                  _field(
                    'notes',
                    'Notes',
                    maxLines: 4,
                    maxLength: AppConstants.maxNotesLength,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
