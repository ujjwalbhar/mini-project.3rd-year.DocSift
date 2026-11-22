import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../autofill/autofill_sync_service.dart';
import '../../ocr/domain/extraction_queue.dart';
import '../domain/models/vault_item.dart';
import '../domain/models/vault_templates.dart';
import '../domain/vault_service.dart';
import 'dashboard_screen.dart';
import 'item_detail_screen.dart';

// ─── Router landing — dispatches to the correct typed form ───────────────────
class AddTextItemScreen extends ConsumerWidget {
  const AddTextItemScreen({
    super.key,
    required this.categoryId,
    this.itemToEdit,
    this.initialContent,
  });

  final String categoryId;
  final VaultItem? itemToEdit;
  final String? initialContent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveCategoryId = itemToEdit?.categoryId ?? categoryId;
    switch (effectiveCategoryId) {
      case 'passwords':
        return _AddPasswordScreen(
          itemToEdit: itemToEdit,
          initialContent: initialContent,
        );
      case 'identity':
        return _AddIdentityScreen(
          itemToEdit: itemToEdit,
          initialContent: initialContent,
        );
      case 'cards':
        return _AddCardScreen(
          itemToEdit: itemToEdit,
          initialContent: initialContent,
        );
      case 'notes':
      default:
        return _AddNoteScreen(
          itemToEdit: itemToEdit,
          initialContent: initialContent,
        );
    }
  }
}

// ─── Custom User-Defined Field Entry ──────────────────────────────────────────

class _CustomFieldControllers {
  _CustomFieldControllers({
    String label = '',
    String value = '',
    this.isSecret = false,
  })  : labelCtrl = TextEditingController(text: label),
        valueCtrl = TextEditingController(text: value);

  final TextEditingController labelCtrl;
  final TextEditingController valueCtrl;
  bool isSecret;

  void dispose() {
    labelCtrl.dispose();
    valueCtrl.dispose();
  }
}

List<_CustomFieldControllers> _parseCustomFields(Map<String, dynamic> data) {
  final raw = data['customFields'];
  if (raw is! List) return <_CustomFieldControllers>[];
  final out = <_CustomFieldControllers>[];
  for (final item in raw) {
    if (item is Map) {
      out.add(
        _CustomFieldControllers(
          label: item['label']?.toString() ?? '',
          value: item['value']?.toString() ?? '',
          isSecret: item['isSecret'] == true,
        ),
      );
    }
  }
  return out;
}

List<Map<String, dynamic>> _serializeCustomFields(
  List<_CustomFieldControllers> rows,
) {
  return rows
      .where(
        (r) =>
            r.labelCtrl.text.trim().isNotEmpty &&
            r.valueCtrl.text.trim().isNotEmpty,
      )
      .map(
        (r) => <String, dynamic>{
          'label': r.labelCtrl.text.trim(),
          'value': r.valueCtrl.text.trim(),
          'isSecret': r.isSecret,
        },
      )
      .toList();
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  const _FormCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardCanvas,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(children: children),
    );
  }
}

class _FieldRow extends StatefulWidget {
  const _FieldRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.controller,
    this.isPassword = false,
    this.keyboardType,
    this.isLast = false,
    this.inputFormatters,
    this.maxLength,
    this.hint = '',
    this.trailingAction,
    this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final TextEditingController controller;
  final bool isPassword;
  final TextInputType? keyboardType;
  final bool isLast;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final String hint;
  final Widget? trailingAction;
  final ValueChanged<String>? onChanged;

  @override
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, color: widget.iconColor, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                    TextField(
                      controller: widget.controller,
                      obscureText: widget.isPassword && _obscure,
                      keyboardType: widget.keyboardType,
                      inputFormatters: widget.inputFormatters,
                      maxLength: widget.maxLength,
                      onChanged: widget.onChanged,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        hintStyle: const TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        counterText: '',
                        suffixIcon: widget.isPassword
                            ? GestureDetector(
                                onTap: () =>
                                    setState(() => _obscure = !_obscure),
                                child: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18,
                                  color: AppColors.textMuted,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.trailingAction != null) ...[
                const SizedBox(width: 6),
                widget.trailingAction!,
              ],
            ],
          ),
        ),
        if (!widget.isLast)
          const Divider(height: 1, indent: 66, color: AppColors.borderLight),
      ],
    );
  }
}

class _CustomFieldsSection extends StatelessWidget {
  const _CustomFieldsSection({
    required this.fields,
    required this.accentColor,
    required this.accentBg,
    required this.onAdd,
    required this.onRemove,
    required this.onToggleSecret,
  });

  final List<_CustomFieldControllers> fields;
  final Color accentColor;
  final Color accentBg;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onToggleSecret;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'CUSTOM FIELDS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppColors.textMuted,
              ),
            ),
            TextButton.icon(
              onPressed: onAdd,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: accentColor,
              ),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
              label: const Text(
                'Add Field',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        if (fields.isNotEmpty)
          _FormCard(
            children: List.generate(fields.length, (i) {
              final row = fields[i];
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: TextField(
                            controller: row.labelCtrl,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryNavy,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Field name',
                              isDense: true,
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 28,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          color: AppColors.borderLight,
                        ),
                        Expanded(
                          flex: 6,
                          child: TextField(
                            controller: row.valueCtrl,
                            obscureText: row.isSecret,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Value',
                              isDense: true,
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: row.isSecret ? 'Masked secret' : 'Plain text',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onToggleSecret(i),
                          icon: Icon(
                            row.isSecret
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            size: 17,
                            color: row.isSecret
                                ? accentColor
                                : AppColors.textMuted,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove field',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onRemove(i),
                          icon: const Icon(
                            Icons.remove_circle_outline_rounded,
                            size: 18,
                            color: AppColors.destructiveRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i < fields.length - 1)
                    const Divider(height: 1, color: AppColors.borderLight),
                ],
              );
            }),
          ),
      ],
    );
  }
}

AppBar _buildAppBar(
  BuildContext context,
  String title,
  Color accentColor,
  VoidCallback onSave,
) {
  return AppBar(
    backgroundColor: AppColors.cardCanvas,
    elevation: 0,
    leading: IconButton(
      icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
      onPressed: () => context.pop(),
    ),
    title: Text(
      title,
      style: const TextStyle(
        color: AppColors.primaryNavy,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    centerTitle: true,
    actions: [
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: TextButton(
          onPressed: onSave,
          style: TextButton.styleFrom(
            backgroundColor: accentColor.withValues(alpha: 0.12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(
            'Save',
            style: TextStyle(
              color: accentColor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    ],
  );
}

void _showSaved(BuildContext context, String name) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Flexible(child: Text('$name saved securely')),
        ],
      ),
      backgroundColor: AppColors.accentEmerald,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ),
  );
}

// ─── 1. PASSWORD & SECRETS (Templates + Generator + Autofill Metadata) ───────

class _AddPasswordScreen extends ConsumerStatefulWidget {
  const _AddPasswordScreen({this.itemToEdit, this.initialContent});
  final VaultItem? itemToEdit;
  final String? initialContent;

  @override
  ConsumerState<_AddPasswordScreen> createState() => _AddPasswordScreenState();
}

class _AddPasswordScreenState extends ConsumerState<_AddPasswordScreen> {
  PasswordSubTemplate _subTemplate = PasswordSubTemplate.appLogin;
  String? _selectedPresetId;
  String _presetSearch = '';
  List<String> _boundDomains = <String>[];
  List<String> _boundPackages = <String>[];

  final _presetSearchCtrl = TextEditingController();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _urlController = TextEditingController();
  final _notesController = TextEditingController();

  // Wi-Fi specific
  final _securityTypeController = TextEditingController(text: 'WPA2/WPA3');
  final _routerIpController = TextEditingController();

  // NetBanking specific
  final _accountNumberController = TextEditingController();
  final _ifscController = TextEditingController();
  final _txPasswordController = TextEditingController();
  final _upiPinController = TextEditingController();

  // API Key specific
  final _apiKeyController = TextEditingController();
  final _environmentController = TextEditingController(text: 'Production');
  final _expiryController = TextEditingController();

  List<_CustomFieldControllers> _customFields = <_CustomFieldControllers>[];
  String _usernameHint = 'Enter username or email';

  @override
  void initState() {
    super.initState();
    if (widget.itemToEdit != null) {
      _nameController.text = widget.itemToEdit!.name;
    }
    if (widget.initialContent != null) {
      try {
        final data = jsonDecode(widget.initialContent!);
        if (data is Map<String, dynamic>) {
          _subTemplate =
              PasswordSubTemplate.fromKey(data['subType'] as String?);
          _selectedPresetId = data['presetId'] as String?;
          _nameController.text =
              data['title']?.toString() ?? _nameController.text;
          _usernameController.text =
              data['username']?.toString() ?? data['customerId']?.toString() ?? '';
          _passwordController.text = data['password']?.toString() ?? '';
          _urlController.text = data['url']?.toString() ?? '';
          _notesController.text = data['notes']?.toString() ?? '';

          _securityTypeController.text =
              data['securityType']?.toString() ?? 'WPA2/WPA3';
          _routerIpController.text = data['routerIp']?.toString() ?? '';
          _accountNumberController.text =
              data['accountNumber']?.toString() ?? '';
          _ifscController.text = data['ifscCode']?.toString() ?? '';
          _txPasswordController.text =
              data['transactionPassword']?.toString() ?? '';
          _upiPinController.text = data['upiPin']?.toString() ?? '';
          _apiKeyController.text = data['apiKey']?.toString() ?? '';
          _environmentController.text =
              data['environment']?.toString() ?? 'Production';
          _expiryController.text = data['expiry']?.toString() ?? '';

          _boundDomains = (data['domains'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              <String>[];
          _boundPackages = (data['androidPackages'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              <String>[];
          _customFields = _parseCustomFields(data);
        }
      } catch (_) {
        final lines = widget.initialContent!.split('\n');
        for (final line in lines) {
          if (line.startsWith('Name: ')) {
            _nameController.text = line.substring(6);
          }
          if (line.startsWith('Username: ')) {
            _usernameController.text = line.substring(10);
          }
          if (line.startsWith('Password: ')) {
            _passwordController.text = line.substring(10);
          }
          if (line.startsWith('URL: ')) _urlController.text = line.substring(5);
          if (line.startsWith('Notes: ')) {
            _notesController.text = line.substring(7);
          }
        }
      }
    }
  }

  void _applyPreset(PasswordServicePreset preset) {
    setState(() {
      _selectedPresetId = preset.id;
      _nameController.text = preset.name;
      _urlController.text = preset.defaultUrl;
      _usernameHint = preset.usernameHint;
      _boundDomains = List<String>.from(preset.domains);
      _boundPackages = List<String>.from(preset.androidPackages);
    });
  }

  void _showPasswordGeneratorSheet() {
    int length = 18;
    bool useUpper = true;
    bool useLower = true;
    bool useDigits = true;
    bool useSymbols = true;
    String generated = VaultTemplates.generateStrongPassword(length: length);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardCanvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void regenerate() {
            setModalState(() {
              generated = VaultTemplates.generateStrongPassword(
                length: length,
                uppercase: useUpper,
                lowercase: useLower,
                digits: useDigits,
                symbols: useSymbols,
              );
            });
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Strong Password Generator',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                    IconButton(
                      onPressed: regenerate,
                      icon: const Icon(Icons.refresh_rounded,
                          color: AppColors.accentEmerald),
                    ),
                  ],
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceNeutral,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: SelectableText(
                    generated,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryNavy,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Length: $length',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: length.toDouble(),
                        min: 10,
                        max: 32,
                        divisions: 22,
                        activeColor: AppColors.accentEmerald,
                        onChanged: (v) {
                          length = v.round();
                          regenerate();
                        },
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final opt in <(String, bool, ValueChanged<bool>)>[
                      ('A–Z', useUpper, (v) => useUpper = v),
                      ('a–z', useLower, (v) => useLower = v),
                      ('0–9', useDigits, (v) => useDigits = v),
                      ('!@#\$', useSymbols, (v) => useSymbols = v),
                    ])
                      FilterChip(
                        label: Text(
                          opt.$1,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: opt.$2 ? Colors.white : AppColors.primaryNavy,
                          ),
                        ),
                        selected: opt.$2,
                        selectedColor: AppColors.accentEmerald,
                        backgroundColor: AppColors.surfaceNeutral,
                        surfaceTintColor: Colors.transparent,
                        checkmarkColor: Colors.white,
                        side: BorderSide(
                          color: opt.$2
                              ? AppColors.accentEmerald
                              : AppColors.borderLight,
                        ),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: opt.$2 ? Colors.white : AppColors.primaryNavy,
                        ),
                        onSelected: (v) {
                          opt.$3(v);
                          regenerate();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _passwordController.text = generated;
                      });
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Use This Password'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    final title = _nameController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a name or pick a template above'),
          backgroundColor: AppColors.destructiveRed,
        ),
      );
      return;
    }

    final targets = VaultTemplates.resolveAutofillTargets(
      title: title,
      url: _urlController.text.trim(),
      explicitDomains: _boundDomains,
      explicitPackages: _boundPackages,
    );

    final data = <String, dynamic>{
      'subType': _subTemplate.name,
      if (_selectedPresetId != null) 'presetId': _selectedPresetId,
      'title': title,
      'username': _usernameController.text.trim(),
      'password': _passwordController.text,
      'url': _urlController.text.trim(),
      'domains': targets.domains,
      'androidPackages': targets.packages,
      'notes': _notesController.text.trim(),
    };

    if (_subTemplate == PasswordSubTemplate.wifi) {
      data['ssid'] = title;
      data['securityType'] = _securityTypeController.text.trim();
      data['routerIp'] = _routerIpController.text.trim();
    } else if (_subTemplate == PasswordSubTemplate.bankLogin) {
      data['customerId'] = _usernameController.text.trim();
      data['accountNumber'] = _accountNumberController.text.trim();
      data['ifscCode'] = _ifscController.text.trim().toUpperCase();
      data['transactionPassword'] = _txPasswordController.text;
      data['upiPin'] = _upiPinController.text.trim();
    } else if (_subTemplate == PasswordSubTemplate.apiKey) {
      data['apiKey'] = _apiKeyController.text.trim();
      data['apiSecret'] = _passwordController.text;
      data['environment'] = _environmentController.text.trim();
      data['expiry'] = _expiryController.text.trim();
    }

    final custom = _serializeCustomFields(_customFields);
    if (custom.isNotEmpty) {
      data['customFields'] = custom;
    }

    if (widget.itemToEdit != null) {
      final updatedItem = await ref.read(vaultServiceProvider).updateJsonItem(
            widget.itemToEdit!,
            title,
            data,
          );
      ref.read(extractionQueueProvider).enqueue(updatedItem);
      ref.invalidate(vaultItemProvider(widget.itemToEdit!.id));
    } else {
      final newItem = await ref.read(vaultServiceProvider).importJsonItem(
            title,
            data,
            'passwords',
          );
      ref.read(extractionQueueProvider).enqueue(newItem);
    }

    ref.invalidate(vaultItemsProvider);
    ref.invalidate(categoryCountsProvider);
    ref.invalidate(recentItemsProvider);

    // Sync updated login list to Android OS Autofill service
    ref.read(autofillSyncServiceProvider).syncVaultAndImportCapturedLogins();

    if (mounted) {
      _showSaved(context, title);
      context.pop();
    }
  }

  @override
  void dispose() {
    _presetSearchCtrl.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    _securityTypeController.dispose();
    _routerIpController.dispose();
    _accountNumberController.dispose();
    _ifscController.dispose();
    _txPasswordController.dispose();
    _upiPinController.dispose();
    _apiKeyController.dispose();
    _environmentController.dispose();
    _expiryController.dispose();
    for (final c in _customFields) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strength =
        VaultTemplates.evaluatePasswordStrength(_passwordController.text);
    final filteredPresets = VaultTemplates.passwordPresets.where((p) {
      if (_presetSearch.isEmpty) return true;
      return p.name.toLowerCase().contains(_presetSearch) ||
          p.id.toLowerCase().contains(_presetSearch) ||
          p.domains.any((d) => d.contains(_presetSearch));
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.surfaceNeutral,
      appBar: _buildAppBar(
        context,
        widget.itemToEdit != null ? 'Edit Secret' : 'Add Secret',
        AppColors.categoryPasswordsColor,
        _save,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Sub-type selector (Login / Wi-Fi / NetBanking / API Key)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: PasswordSubTemplate.values.map((st) {
                final selected = _subTemplate == st;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    showCheckmark: false,
                    surfaceTintColor: Colors.transparent,
                    avatar: Icon(
                      st.icon,
                      size: 16,
                      color: selected
                          ? Colors.white
                          : AppColors.categoryPasswordsColor,
                    ),
                    label: Text(
                      st.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : AppColors.primaryNavy,
                      ),
                    ),
                    selected: selected,
                    selectedColor: AppColors.categoryPasswordsColor,
                    backgroundColor: AppColors.cardCanvas,
                    side: BorderSide(
                      color: selected
                          ? AppColors.categoryPasswordsColor
                          : AppColors.borderLight,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppColors.primaryNavy,
                    ),
                    onSelected: (_) => setState(() => _subTemplate = st),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Quick Service Presets for App / Website Logins
          if (_subTemplate == PasswordSubTemplate.appLogin) ...[
            const Text(
              'QUICK APP TEMPLATES (AUTO-BINDS AUTOFILL)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.cardCanvas,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded,
                      size: 17, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _presetSearchCtrl,
                      onChanged: (v) =>
                          setState(() => _presetSearch = v.trim().toLowerCase()),
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText:
                            'Filter apps (Gmail, Amazon, Netflix, GitHub...)',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_presetSearch.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _presetSearchCtrl.clear();
                        setState(() => _presetSearch = '');
                      },
                      child: const Icon(Icons.close_rounded,
                          size: 16, color: AppColors.textMuted),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: filteredPresets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final preset = filteredPresets[i];
                  final isSelected = _selectedPresetId == preset.id;
                  return ActionChip(
                    surfaceTintColor: Colors.transparent,
                    avatar: Icon(
                      preset.icon,
                      size: 16,
                      color: isSelected ? Colors.white : preset.accentColor,
                    ),
                    backgroundColor: isSelected
                        ? preset.accentColor
                        : AppColors.cardCanvas,
                    side: BorderSide(
                      color: isSelected
                          ? preset.accentColor
                          : AppColors.borderLight,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.primaryNavy,
                    ),
                    label: Text(
                      preset.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : AppColors.primaryNavy,
                      ),
                    ),
                    onPressed: () => _applyPreset(preset),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Quick Bank Chips for NetBanking
          if (_subTemplate == PasswordSubTemplate.bankLogin) ...[
            const Text(
              'POPULAR BANKS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: VaultTemplates.popularBanks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final bank = VaultTemplates.popularBanks[i];
                  final isSelected = _nameController.text.trim().toLowerCase() ==
                      bank.toLowerCase();
                  return ActionChip(
                    surfaceTintColor: Colors.transparent,
                    avatar: Icon(
                      Icons.account_balance_rounded,
                      size: 15,
                      color: isSelected
                          ? Colors.white
                          : AppColors.categoryPasswordsColor,
                    ),
                    backgroundColor: isSelected
                        ? AppColors.categoryPasswordsColor
                        : AppColors.cardCanvas,
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.categoryPasswordsColor
                          : AppColors.borderLight,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.primaryNavy,
                    ),
                    label: Text(
                      bank,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : AppColors.primaryNavy,
                      ),
                    ),
                    onPressed: () => setState(() => _nameController.text = bank),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],

          Text(
            _subTemplate.label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),

          _buildSubTemplateFields(),

          if (_passwordController.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: strength.score,
                      minHeight: 5,
                      backgroundColor: AppColors.borderLight,
                      color: strength.score < 0.4
                          ? AppColors.destructiveRed
                          : strength.score < 0.75
                              ? AppColors.categoryCardsColor
                              : AppColors.accentEmerald,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  strength.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: strength.score < 0.4
                        ? AppColors.destructiveRed
                        : strength.score < 0.75
                            ? AppColors.categoryCardsColor
                            : AppColors.accentEmerald,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 18),
          _CustomFieldsSection(
            fields: _customFields,
            accentColor: AppColors.categoryPasswordsColor,
            accentBg: AppColors.categoryPasswordsBg,
            onAdd: () =>
                setState(() => _customFields.add(_CustomFieldControllers())),
            onRemove: (idx) => setState(() {
              _customFields[idx].dispose();
              _customFields.removeAt(idx);
            }),
            onToggleSecret: (idx) => setState(() {
              _customFields[idx].isSecret = !_customFields[idx].isSecret;
            }),
          ),

          const SizedBox(height: 16),
          const Text(
            'NOTES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          _FormCard(
            children: [
              _FieldRow(
                icon: Icons.notes_rounded,
                iconColor: AppColors.categoryPasswordsColor,
                iconBg: AppColors.categoryPasswordsBg,
                label: 'ADDITIONAL NOTES',
                controller: _notesController,
                hint: 'Recovery codes, 2FA backup hints, etc.',
                isLast: true,
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildGenerateButton() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() {
              _passwordController.text = VaultTemplates.generateStrongPassword();
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.categoryPasswordsBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_fix_high_rounded,
                    size: 14, color: AppColors.categoryPasswordsColor),
                SizedBox(width: 4),
                Text(
                  'Gen',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.categoryPasswordsColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _showPasswordGeneratorSheet,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.tune_rounded,
                size: 16, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _buildSubTemplateFields() {
    switch (_subTemplate) {
      case PasswordSubTemplate.appLogin:
        return _FormCard(
          children: [
            _FieldRow(
              icon: Icons.label_outline_rounded,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'APP / SERVICE NAME',
              controller: _nameController,
              hint: 'e.g. Google / Gmail, Amazon, Netflix',
            ),
            _FieldRow(
              icon: Icons.person_outline_rounded,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'USERNAME / EMAIL / PHONE',
              controller: _usernameController,
              keyboardType: TextInputType.emailAddress,
              hint: _usernameHint,
            ),
            _FieldRow(
              icon: Icons.lock_outline_rounded,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'PASSWORD',
              controller: _passwordController,
              isPassword: true,
              hint: 'Enter or generate password',
              onChanged: (_) => setState(() {}),
              trailingAction: _buildGenerateButton(),
            ),
            _FieldRow(
              icon: Icons.link_rounded,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'WEBSITE URL',
              controller: _urlController,
              keyboardType: TextInputType.url,
              hint: 'https://example.com',
              isLast: true,
            ),
          ],
        );

      case PasswordSubTemplate.wifi:
        return _FormCard(
          children: [
            _FieldRow(
              icon: Icons.wifi_rounded,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'NETWORK NAME (SSID)',
              controller: _nameController,
              hint: 'e.g. Home_5G_Fiber',
            ),
            _FieldRow(
              icon: Icons.lock_outline_rounded,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'WI-FI PASSWORD',
              controller: _passwordController,
              isPassword: true,
              hint: 'Enter Wi-Fi password',
              onChanged: (_) => setState(() {}),
              trailingAction: _buildGenerateButton(),
            ),
            _FieldRow(
              icon: Icons.shield_outlined,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'SECURITY PROTOCOL',
              controller: _securityTypeController,
              hint: 'WPA2 / WPA3 / Open',
            ),
            _FieldRow(
              icon: Icons.router_outlined,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'ROUTER ADMIN IP (OPTIONAL)',
              controller: _routerIpController,
              hint: '192.168.1.1',
              isLast: true,
            ),
          ],
        );

      case PasswordSubTemplate.bankLogin:
        return _FormCard(
          children: [
            _FieldRow(
              icon: Icons.account_balance_rounded,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'BANK NAME',
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              hint: 'e.g. HDFC Bank, SBI',
            ),
            _FieldRow(
              icon: Icons.badge_outlined,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'CUSTOMER ID / USER ID',
              controller: _usernameController,
              hint: 'Customer / CIF / NetBanking ID',
            ),
            _FieldRow(
              icon: Icons.numbers_rounded,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'ACCOUNT NUMBER',
              controller: _accountNumberController,
              keyboardType: TextInputType.number,
              isPassword: true,
              hint: 'Bank account number',
            ),
            _FieldRow(
              icon: Icons.qr_code_rounded,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'IFSC / SWIFT CODE',
              controller: _ifscController,
              inputFormatters: [_UpperCaseTextFormatter()],
              hint: 'e.g. HDFC0001234',
            ),
            _FieldRow(
              icon: Icons.lock_outline_rounded,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'LOGIN PASSWORD',
              controller: _passwordController,
              isPassword: true,
              hint: 'NetBanking login password',
              onChanged: (_) => setState(() {}),
              trailingAction: _buildGenerateButton(),
            ),
            _FieldRow(
              icon: Icons.verified_user_outlined,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'TRANSACTION PASSWORD (OPTIONAL)',
              controller: _txPasswordController,
              isPassword: true,
              hint: 'Profile / transaction password',
            ),
            _FieldRow(
              icon: Icons.pin_outlined,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'UPI / MPIN (OPTIONAL)',
              controller: _upiPinController,
              keyboardType: TextInputType.number,
              isPassword: true,
              maxLength: 6,
              hint: '4 or 6 digit PIN',
              isLast: true,
            ),
          ],
        );

      case PasswordSubTemplate.apiKey:
        return _FormCard(
          children: [
            _FieldRow(
              icon: Icons.terminal_rounded,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'SERVICE / PROVIDER',
              controller: _nameController,
              hint: 'e.g. AWS Prod, OpenAI, GitHub PAT',
            ),
            _FieldRow(
              icon: Icons.vpn_key_outlined,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'KEY ID / CLIENT ID',
              controller: _apiKeyController,
              hint: 'Access key ID or public identifier',
            ),
            _FieldRow(
              icon: Icons.lock_outline_rounded,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'SECRET TOKEN / PRIVATE KEY',
              controller: _passwordController,
              isPassword: true,
              hint: 'sk-... / ghp_...',
              onChanged: (_) => setState(() {}),
            ),
            _FieldRow(
              icon: Icons.layers_outlined,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'ENVIRONMENT',
              controller: _environmentController,
              hint: 'Production / Staging / Local',
            ),
            _FieldRow(
              icon: Icons.event_outlined,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'EXPIRY DATE (OPTIONAL)',
              controller: _expiryController,
              hint: 'DD/MM/YYYY',
              isLast: true,
            ),
          ],
        );
    }
  }
}

// ─── 2. IDENTITY DOCUMENTS (Dynamic Per-Document Schema) ─────────────────────

class _AddIdentityScreen extends ConsumerStatefulWidget {
  const _AddIdentityScreen({this.itemToEdit, this.initialContent});
  final VaultItem? itemToEdit;
  final String? initialContent;

  @override
  ConsumerState<_AddIdentityScreen> createState() => _AddIdentityScreenState();
}

class _AddIdentityScreenState extends ConsumerState<_AddIdentityScreen> {
  late IdentityDocTemplate _selectedTemplate;
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final Map<String, TextEditingController> _fieldCtrls =
      <String, TextEditingController>{};
  List<_CustomFieldControllers> _customFields = <_CustomFieldControllers>[];

  TextEditingController _ctrlFor(String key) {
    return _fieldCtrls.putIfAbsent(key, () => TextEditingController());
  }

  @override
  void initState() {
    super.initState();
    _selectedTemplate = VaultTemplates.identityTemplates.first; // Aadhaar default
    _nameController.text = _selectedTemplate.displayName;

    if (widget.itemToEdit != null) {
      _nameController.text = widget.itemToEdit!.name;
    }

    if (widget.initialContent != null) {
      try {
        final data = jsonDecode(widget.initialContent!);
        if (data is Map<String, dynamic>) {
          _selectedTemplate = VaultTemplates.inferIdentityTemplate(data);
          _nameController.text =
              data['documentName']?.toString() ?? _nameController.text;
          _notesController.text = data['notes']?.toString() ?? '';
          for (final entry in data.entries) {
            if (entry.key == 'documentName' ||
                entry.key == 'docType' ||
                entry.key == 'notes' ||
                entry.key == 'customFields') {
              continue;
            }
            if (entry.value != null) {
              _ctrlFor(entry.key).text = entry.value.toString();
            }
          }
          _customFields = _parseCustomFields(data);
        }
      } catch (_) {
        _selectedTemplate = VaultTemplates.identityTemplateById('custom');
        final lines = widget.initialContent!.split('\n');
        for (final line in lines) {
          if (line.startsWith('Document Name: ')) {
            _nameController.text = line.substring(15);
          }
          if (line.startsWith('ID Number: ')) {
            _ctrlFor('idNumber').text = line.substring(11);
          }
          if (line.startsWith('Date of Birth: ')) {
            _ctrlFor('dob').text = line.substring(15);
          }
          if (line.startsWith('Issued By: ')) {
            _ctrlFor('issuedBy').text = line.substring(11);
          }
          if (line.startsWith('Expiry Date: ')) {
            _ctrlFor('expiry').text = line.substring(13);
          }
          if (line.startsWith('Notes: ')) {
            _notesController.text = line.substring(7);
          }
        }
      }
    }
  }

  void _selectTemplate(IdentityDocTemplate next) {
    final prevDefault = _selectedTemplate.displayName;
    setState(() {
      _selectedTemplate = next;
      if (_nameController.text.trim().isEmpty ||
          _nameController.text.trim() == prevDefault) {
        _nameController.text =
            next.id == 'custom' ? '' : next.displayName;
      }
    });
  }

  Future<void> _save() async {
    final docName = _nameController.text.trim();
    if (docName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a document title'),
          backgroundColor: AppColors.destructiveRed,
        ),
      );
      return;
    }

    final data = <String, dynamic>{
      'docType': _selectedTemplate.id,
      'documentName': docName,
    };

    for (final spec in _selectedTemplate.fields) {
      final val = _ctrlFor(spec.key).text.trim();
      data[spec.key] = spec.uppercase ? val.toUpperCase() : val;
    }
    data['notes'] = _notesController.text.trim();

    final custom = _serializeCustomFields(_customFields);
    if (custom.isNotEmpty) {
      data['customFields'] = custom;
    }

    if (widget.itemToEdit != null) {
      final updatedItem = await ref.read(vaultServiceProvider).updateJsonItem(
            widget.itemToEdit!,
            docName,
            data,
          );
      ref.read(extractionQueueProvider).enqueue(updatedItem);
      ref.invalidate(vaultItemProvider(widget.itemToEdit!.id));
    } else {
      final newItem = await ref.read(vaultServiceProvider).importJsonItem(
            docName,
            data,
            'identity',
          );
      ref.read(extractionQueueProvider).enqueue(newItem);
    }

    ref.invalidate(vaultItemsProvider);
    ref.invalidate(categoryCountsProvider);
    ref.invalidate(recentItemsProvider);

    if (mounted) {
      _showSaved(context, docName);
      context.pop();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    for (final c in _fieldCtrls.values) {
      c.dispose();
    }
    for (final c in _customFields) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceNeutral,
      appBar: _buildAppBar(
        context,
        widget.itemToEdit != null ? 'Edit Identity' : 'Add Identity',
        AppColors.categoryIdentityColor,
        _save,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'SELECT DOCUMENT TEMPLATE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: VaultTemplates.identityTemplates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final tpl = VaultTemplates.identityTemplates[i];
                final selected = tpl.id == _selectedTemplate.id;
                return ChoiceChip(
                  showCheckmark: false,
                  surfaceTintColor: Colors.transparent,
                  avatar: Icon(
                    tpl.icon,
                    size: 16,
                    color: selected
                        ? Colors.white
                        : AppColors.categoryIdentityColor,
                  ),
                  label: Text(
                    tpl.shortLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppColors.primaryNavy,
                    ),
                  ),
                  selected: selected,
                  selectedColor: AppColors.categoryIdentityColor,
                  backgroundColor: AppColors.cardCanvas,
                  side: BorderSide(
                    color: selected
                        ? AppColors.categoryIdentityColor
                        : AppColors.borderLight,
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppColors.primaryNavy,
                  ),
                  onSelected: (_) => _selectTemplate(tpl),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '${_selectedTemplate.displayName.toUpperCase()} DETAILS',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          _FormCard(
            children: [
              _FieldRow(
                icon: Icons.label_outline_rounded,
                iconColor: AppColors.categoryIdentityColor,
                iconBg: AppColors.categoryIdentityBg,
                label: 'DOCUMENT TITLE IN VAULT',
                controller: _nameController,
                hint: 'e.g. My ${_selectedTemplate.displayName}',
              ),
              for (int i = 0; i < _selectedTemplate.fields.length; i++)
                _buildIdentitySpecRow(
                  _selectedTemplate.fields[i],
                  isLast: i == _selectedTemplate.fields.length - 1,
                ),
            ],
          ),
          const SizedBox(height: 18),
          _CustomFieldsSection(
            fields: _customFields,
            accentColor: AppColors.categoryIdentityColor,
            accentBg: AppColors.categoryIdentityBg,
            onAdd: () =>
                setState(() => _customFields.add(_CustomFieldControllers())),
            onRemove: (idx) => setState(() {
              _customFields[idx].dispose();
              _customFields.removeAt(idx);
            }),
            onToggleSecret: (idx) => setState(() {
              _customFields[idx].isSecret = !_customFields[idx].isSecret;
            }),
          ),
          const SizedBox(height: 16),
          const Text(
            'NOTES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          _FormCard(
            children: [
              _FieldRow(
                icon: Icons.notes_rounded,
                iconColor: AppColors.categoryIdentityColor,
                iconBg: AppColors.categoryIdentityBg,
                label: 'NOTES',
                controller: _notesController,
                hint: 'Any extra remarks',
                isLast: true,
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildIdentitySpecRow(IdentityFieldSpec spec, {required bool isLast}) {
    final formatters = <TextInputFormatter>[
      if (spec.uppercase) _UpperCaseTextFormatter(),
      if (spec.aadhaarGrouped) ...[
        FilteringTextInputFormatter.digitsOnly,
        _CardNumberFormatter(), // 4-4-4 spacing matches 12-digit Aadhaar cleanly
      ],
      if (spec.isDate) _DateSlashFormatter(),
    ];

    TextInputType? kb;
    if (spec.aadhaarGrouped) {
      kb = TextInputType.number;
    } else if (spec.isDate) {
      kb = TextInputType.datetime;
    }

    return _FieldRow(
      icon: spec.icon,
      iconColor: AppColors.categoryIdentityColor,
      iconBg: AppColors.categoryIdentityBg,
      label: spec.label,
      controller: _ctrlFor(spec.key),
      hint: spec.hint,
      keyboardType: kb,
      maxLength: spec.maxLength ?? (spec.isDate ? 10 : null),
      inputFormatters: formatters.isEmpty ? null : formatters,
      isLast: isLast,
    );
  }
}

// ─── 3. PAYMENT CARD (Bank Presets + Card Network Detection) ─────────────────

class _AddCardScreen extends ConsumerStatefulWidget {
  const _AddCardScreen({this.itemToEdit, this.initialContent});
  final VaultItem? itemToEdit;
  final String? initialContent;

  @override
  ConsumerState<_AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends ConsumerState<_AddCardScreen> {
  String _cardType = 'Credit';
  final _nameController = TextEditingController();
  final _cardholderController = TextEditingController();
  final _numberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();
  final _pinController = TextEditingController();
  final _notesController = TextEditingController();
  List<_CustomFieldControllers> _customFields = <_CustomFieldControllers>[];

  @override
  void initState() {
    super.initState();
    if (widget.itemToEdit != null) {
      _nameController.text = widget.itemToEdit!.name;
    }
    if (widget.initialContent != null) {
      try {
        final data = jsonDecode(widget.initialContent!);
        if (data is Map<String, dynamic>) {
          _cardType = data['cardType']?.toString() ?? 'Credit';
          _nameController.text = data['bankName']?.toString() ??
              data['title']?.toString() ??
              _nameController.text;
          _cardholderController.text = data['cardHolder']?.toString() ?? '';
          _numberController.text = data['cardNumber']?.toString() ?? '';
          _expiryController.text = data['expiry']?.toString() ?? '';
          _cvvController.text = data['cvv']?.toString() ?? '';
          _pinController.text = data['pin']?.toString() ?? '';
          _notesController.text = data['notes']?.toString() ?? '';
          _customFields = _parseCustomFields(data);
        }
      } catch (_) {
        final lines = widget.initialContent!.split('\n');
        for (final line in lines) {
          if (line.startsWith('Card Label: ')) {
            _nameController.text = line.substring(12);
          }
          if (line.startsWith('Cardholder: ')) {
            _cardholderController.text = line.substring(12);
          }
          if (line.startsWith('Number: ')) {
            _numberController.text = line.substring(8);
          }
          if (line.startsWith('Expiry: ')) {
            _expiryController.text = line.substring(8);
          }
          if (line.startsWith('CVV: ')) _cvvController.text = line.substring(5);
          if (line.startsWith('PIN: ')) _pinController.text = line.substring(5);
          if (line.startsWith('Notes: ')) {
            _notesController.text = line.substring(7);
          }
        }
      }
    }
  }

  Future<void> _save() async {
    final label = _nameController.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter or select a bank / card label'),
          backgroundColor: AppColors.destructiveRed,
        ),
      );
      return;
    }

    final network = VaultTemplates.detectCardNetwork(_numberController.text);
    final data = <String, dynamic>{
      'bankName': label,
      'cardType': _cardType,
      'network': network,
      'cardHolder': _cardholderController.text.trim(),
      'cardNumber': _numberController.text.trim(),
      'expiry': _expiryController.text.trim(),
      'cvv': _cvvController.text,
      'pin': _pinController.text,
      'notes': _notesController.text.trim(),
    };
    final custom = _serializeCustomFields(_customFields);
    if (custom.isNotEmpty) {
      data['customFields'] = custom;
    }

    if (widget.itemToEdit != null) {
      final updatedItem = await ref.read(vaultServiceProvider).updateJsonItem(
            widget.itemToEdit!,
            label,
            data,
          );
      ref.read(extractionQueueProvider).enqueue(updatedItem);
      ref.invalidate(vaultItemProvider(widget.itemToEdit!.id));
    } else {
      final newItem = await ref.read(vaultServiceProvider).importJsonItem(
            label,
            data,
            'cards',
          );
      ref.read(extractionQueueProvider).enqueue(newItem);
    }
    ref.invalidate(vaultItemsProvider);
    ref.invalidate(categoryCountsProvider);
    ref.invalidate(recentItemsProvider);

    if (mounted) {
      _showSaved(context, label);
      context.pop();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cardholderController.dispose();
    _numberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _pinController.dispose();
    _notesController.dispose();
    for (final c in _customFields) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final network = VaultTemplates.detectCardNetwork(_numberController.text);
    return Scaffold(
      backgroundColor: AppColors.surfaceNeutral,
      appBar: _buildAppBar(
        context,
        widget.itemToEdit != null ? 'Edit Card' : 'Add Card',
        AppColors.categoryCardsColor,
        _save,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: ['Credit', 'Debit', 'Forex'].map((t) {
              final selected = _cardType == t;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  checkmarkColor: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  label: Text(
                    '$t Card',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppColors.primaryNavy,
                    ),
                  ),
                  selected: selected,
                  selectedColor: AppColors.categoryCardsColor,
                  backgroundColor: AppColors.cardCanvas,
                  side: BorderSide(
                    color: selected
                        ? AppColors.categoryCardsColor
                        : AppColors.borderLight,
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppColors.primaryNavy,
                  ),
                  onSelected: (_) {
                    final prevSuffix = ' $_cardType';
                    setState(() {
                      if (_nameController.text.endsWith(prevSuffix)) {
                        _nameController.text =
                            '${_nameController.text.substring(0, _nameController.text.length - prevSuffix.length)} $t';
                      }
                      _cardType = t;
                    });
                  },
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          const Text(
            'QUICK BANK TEMPLATES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: VaultTemplates.popularBanks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final bank = VaultTemplates.popularBanks[i];
                final currentName = _nameController.text.trim().toLowerCase();
                final bankLower = bank.toLowerCase();
                final isSelected = currentName == bankLower ||
                    currentName == '$bankLower ${_cardType.toLowerCase()}';
                return ActionChip(
                  surfaceTintColor: Colors.transparent,
                  avatar: Icon(
                    Icons.account_balance_rounded,
                    size: 15,
                    color: isSelected
                        ? Colors.white
                        : AppColors.categoryCardsColor,
                  ),
                  backgroundColor: isSelected
                      ? AppColors.categoryCardsColor
                      : AppColors.cardCanvas,
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.categoryCardsColor
                        : AppColors.borderLight,
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.primaryNavy,
                  ),
                  label: Text(
                    bank,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.primaryNavy,
                    ),
                  ),
                  onPressed: () => setState(
                    () => _nameController.text = '$bank $_cardType',
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'CARD DETAILS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          _FormCard(
            children: [
              _FieldRow(
                icon: Icons.label_outline_rounded,
                iconColor: AppColors.categoryCardsColor,
                iconBg: AppColors.categoryCardsBg,
                label: 'CARD LABEL',
                controller: _nameController,
                onChanged: (_) => setState(() {}),
                hint: 'e.g. HDFC Regalia Credit',
              ),
              _FieldRow(
                icon: Icons.person_outline_rounded,
                iconColor: AppColors.categoryCardsColor,
                iconBg: AppColors.categoryCardsBg,
                label: 'CARDHOLDER NAME',
                controller: _cardholderController,
                hint: 'Name printed on card',
              ),
              _FieldRow(
                icon: Icons.credit_card_rounded,
                iconColor: AppColors.categoryCardsColor,
                iconBg: AppColors.categoryCardsBg,
                label: 'CARD NUMBER',
                controller: _numberController,
                keyboardType: TextInputType.number,
                maxLength: 19,
                onChanged: (_) => setState(() {}),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  _CardNumberFormatter(),
                ],
                hint: '•••• •••• •••• ••••',
                trailingAction: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.categoryCardsBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    network,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.categoryCardsColor,
                    ),
                  ),
                ),
              ),
              _FieldRow(
                icon: Icons.event_outlined,
                iconColor: AppColors.categoryCardsColor,
                iconBg: AppColors.categoryCardsBg,
                label: 'EXPIRY DATE',
                controller: _expiryController,
                keyboardType: TextInputType.datetime,
                maxLength: 5,
                inputFormatters: [_ExpiryFormatter()],
                hint: 'MM/YY',
              ),
              _FieldRow(
                icon: Icons.lock_outline_rounded,
                iconColor: AppColors.categoryCardsColor,
                iconBg: AppColors.categoryCardsBg,
                label: 'CVV',
                controller: _cvvController,
                isPassword: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                hint: '•••',
              ),
              _FieldRow(
                icon: Icons.pin_outlined,
                iconColor: AppColors.categoryCardsColor,
                iconBg: AppColors.categoryCardsBg,
                label: 'ATM / CARD PIN',
                controller: _pinController,
                isPassword: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                hint: '••••',
                isLast: true,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _CustomFieldsSection(
            fields: _customFields,
            accentColor: AppColors.categoryCardsColor,
            accentBg: AppColors.categoryCardsBg,
            onAdd: () =>
                setState(() => _customFields.add(_CustomFieldControllers())),
            onRemove: (idx) => setState(() {
              _customFields[idx].dispose();
              _customFields.removeAt(idx);
            }),
            onToggleSecret: (idx) => setState(() {
              _customFields[idx].isSecret = !_customFields[idx].isSecret;
            }),
          ),
          const SizedBox(height: 16),
          const Text(
            'NOTES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          _FormCard(
            children: [
              _FieldRow(
                icon: Icons.notes_rounded,
                iconColor: AppColors.categoryCardsColor,
                iconBg: AppColors.categoryCardsBg,
                label: 'NOTES',
                controller: _notesController,
                hint: 'Billing day, credit limit, helpline...',
                isLast: true,
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─── 4. SECURE NOTE ──────────────────────────────────────────────────────────

class _AddNoteScreen extends ConsumerStatefulWidget {
  const _AddNoteScreen({this.itemToEdit, this.initialContent});
  final VaultItem? itemToEdit;
  final String? initialContent;

  @override
  ConsumerState<_AddNoteScreen> createState() => _AddNoteScreenState();
}

class _AddNoteScreenState extends ConsumerState<_AddNoteScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.itemToEdit != null) {
      _titleController.text = widget.itemToEdit!.name;
    }
    if (widget.initialContent != null) {
      try {
        final data = jsonDecode(widget.initialContent!);
        _titleController.text = data['title'] ?? _titleController.text;
        _contentController.text = data['content'] ?? '';
      } catch (_) {
        _contentController.text = widget.initialContent!;
      }
    }
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a note title'),
          backgroundColor: AppColors.destructiveRed,
        ),
      );
      return;
    }

    final data = {
      'title': _titleController.text.trim(),
      'content': _contentController.text,
    };

    if (widget.itemToEdit != null) {
      final VaultItem updatedItem;
      if (widget.itemToEdit!.fileType == FileType.txt ||
          widget.itemToEdit!.fileType == FileType.md) {
        updatedItem = await ref.read(vaultServiceProvider).updateTextItem(
              widget.itemToEdit!,
              _titleController.text.trim(),
              _contentController.text,
            );
      } else {
        updatedItem = await ref.read(vaultServiceProvider).updateJsonItem(
              widget.itemToEdit!,
              _titleController.text.trim(),
              data,
            );
      }
      ref.read(extractionQueueProvider).enqueue(updatedItem);
      ref.invalidate(vaultItemProvider(widget.itemToEdit!.id));
    } else {
      final newItem = await ref.read(vaultServiceProvider).importJsonItem(
            _titleController.text.trim(),
            data,
            'notes',
          );
      ref.read(extractionQueueProvider).enqueue(newItem);
    }
    ref.invalidate(vaultItemsProvider);
    ref.invalidate(categoryCountsProvider);
    ref.invalidate(recentItemsProvider);

    if (mounted) {
      _showSaved(context, _titleController.text.trim());
      context.pop();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceNeutral,
      appBar: _buildAppBar(
        context,
        widget.itemToEdit != null ? 'Edit Note' : 'Secure Note',
        AppColors.categoryNotesColor,
        _save,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardCanvas,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppColors.cardShadow,
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryNavy,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Note title...',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintStyle: TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  const Divider(height: 24, color: AppColors.borderLight),
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: TextField(
                      controller: _contentController,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                        height: 1.6,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Write your secure note here...',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintStyle: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.categoryNotesBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 16,
                    color: AppColors.categoryNotesColor,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This note is encrypted with AES-256-GCM before storage.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.categoryNotesColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
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

// ─── Input Formatters ─────────────────────────────────────────────────────────

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(' ', '');
    final buffer = StringBuffer();
    for (int i = 0; i < digitsOnly.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digitsOnly[i]);
    }
    final string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.replaceAll('/', '');
    if (text.length > 2) {
      text = '${text.substring(0, 2)}/${text.substring(2)}';
    }
    return newValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _DateSlashFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final sb = StringBuffer();
    for (int i = 0; i < digits.length && i < 8; i++) {
      if (i == 2 || i == 4) sb.write('/');
      sb.write(digits[i]);
    }
    final s = sb.toString();
    return newValue.copyWith(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
