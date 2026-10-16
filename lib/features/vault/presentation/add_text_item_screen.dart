import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../domain/models/vault_item.dart';
import '../domain/vault_service.dart';
import 'dashboard_screen.dart';

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
        return _AddPasswordScreen(itemToEdit: itemToEdit, initialContent: initialContent);
      case 'identity':
        return _AddIdentityScreen(itemToEdit: itemToEdit, initialContent: initialContent);
      case 'cards':
        return _AddCardScreen(itemToEdit: itemToEdit, initialContent: initialContent);
      case 'notes':
      default:
        return _AddNoteScreen(itemToEdit: itemToEdit, initialContent: initialContent);
    }
  }
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                                onTap: () => setState(() => _obscure = !_obscure),
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
            ],
          ),
        ),
        if (!widget.isLast)
          const Divider(height: 1, indent: 66, color: AppColors.borderLight),
      ],
    );
  }
}

AppBar _buildAppBar(BuildContext context, String title, Color accentColor,
    VoidCallback onSave) {
  return AppBar(
    backgroundColor: AppColors.cardCanvas,
    elevation: 0,
    leading: IconButton(
      icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
      onPressed: () => context.pop(),
    ),
    title: Text(title,
        style: const TextStyle(
            color: AppColors.primaryNavy,
            fontSize: 17,
            fontWeight: FontWeight.w600)),
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
          child: Text('Save',
              style: TextStyle(
                  color: accentColor, fontWeight: FontWeight.bold, fontSize: 14)),
        ),
      ),
    ],
  );
}

void _showSaved(BuildContext context, String name) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Text('$name saved securely'),
      ]),
      backgroundColor: AppColors.accentEmerald,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ),
  );
}

// ─── 1. PASSWORD ─────────────────────────────────────────────────────────────
class _AddPasswordScreen extends ConsumerStatefulWidget {
  const _AddPasswordScreen({this.itemToEdit, this.initialContent});
  final VaultItem? itemToEdit;
  final String? initialContent;

  @override
  ConsumerState<_AddPasswordScreen> createState() => _AddPasswordScreenState();
}

class _AddPasswordScreenState extends ConsumerState<_AddPasswordScreen> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _urlController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.itemToEdit != null) {
      _nameController.text = widget.itemToEdit!.name;
    }
    if (widget.initialContent != null) {
      try {
        final data = jsonDecode(widget.initialContent!);
        _nameController.text = data['title'] ?? _nameController.text;
        _usernameController.text = data['username'] ?? '';
        _passwordController.text = data['password'] ?? '';
        _urlController.text = data['url'] ?? '';
        _notesController.text = data['notes'] ?? '';
      } catch (e) {
        final lines = widget.initialContent!.split('\n');
        for (final line in lines) {
          if (line.startsWith('Name: ')) _nameController.text = line.substring(6);
          if (line.startsWith('Username: ')) _usernameController.text = line.substring(10);
          if (line.startsWith('Password: ')) _passwordController.text = line.substring(10);
          if (line.startsWith('URL: ')) _urlController.text = line.substring(5);
          if (line.startsWith('Notes: ')) _notesController.text = line.substring(7);
        }
      }
    }
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter a name for this login'),
        backgroundColor: AppColors.destructiveRed,
      ));
      return;
    }

    final data = {
      'title': _nameController.text.trim(),
      'username': _usernameController.text.trim(),
      'password': _passwordController.text,
      'url': _urlController.text.trim(),
      'notes': _notesController.text.trim(),
    };

    if (widget.itemToEdit != null) {
      await ref.read(vaultServiceProvider).updateJsonItem(
        widget.itemToEdit!,
        _nameController.text.trim(),
        data,
      );
    } else {
      await ref.read(vaultServiceProvider).importJsonItem(
        _nameController.text.trim(),
        data,
        'passwords',
      );
    }
    ref.invalidate(vaultItemsProvider);
    ref.invalidate(categoryCountsProvider);
    ref.invalidate(recentItemsProvider);
    
    if (mounted) {
      _showSaved(context, _nameController.text.trim());
      context.pop();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceNeutral,
      appBar: _buildAppBar(
          context, widget.itemToEdit != null ? 'Edit Password' : 'Add Password', AppColors.categoryPasswordsColor, _save),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Category badge
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.categoryPasswordsBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.key_rounded,
                      size: 16, color: AppColors.categoryPasswordsColor),
                  SizedBox(width: 6),
                  Text('Login Credentials',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.categoryPasswordsColor)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('LOGIN DETAILS',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.textMuted)),
          const SizedBox(height: 8),
          _FormCard(children: [
            _FieldRow(
              icon: Icons.label_outline_rounded,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'NAME',
              controller: _nameController,
              hint: 'e.g. Gmail, Netflix',
            ),
            _FieldRow(
              icon: Icons.person_outline_rounded,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'USERNAME / EMAIL',
              controller: _usernameController,
              keyboardType: TextInputType.emailAddress,
              hint: 'Enter username or email',
            ),
            _FieldRow(
              icon: Icons.lock_outline_rounded,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'PASSWORD',
              controller: _passwordController,
              isPassword: true,
              hint: 'Enter password',
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
          ]),
          const SizedBox(height: 20),
          const Text('NOTES',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.textMuted)),
          const SizedBox(height: 8),
          _FormCard(children: [
            _FieldRow(
              icon: Icons.notes_rounded,
              iconColor: AppColors.categoryPasswordsColor,
              iconBg: AppColors.categoryPasswordsBg,
              label: 'ADDITIONAL NOTES',
              controller: _notesController,
              hint: 'Any extra info (recovery codes, etc.)',
              isLast: true,
            ),
          ]),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─── 2. IDENTITY ──────────────────────────────────────────────────────────────
class _AddIdentityScreen extends ConsumerStatefulWidget {
  const _AddIdentityScreen({this.itemToEdit, this.initialContent});
  final VaultItem? itemToEdit;
  final String? initialContent;

  @override
  ConsumerState<_AddIdentityScreen> createState() => _AddIdentityScreenState();
}

class _AddIdentityScreenState extends ConsumerState<_AddIdentityScreen> {
  final _nameController = TextEditingController();
  final _dobController = TextEditingController();
  final _idNumberController = TextEditingController();
  final _issuedByController = TextEditingController();
  final _expiryController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.itemToEdit != null) {
      _nameController.text = widget.itemToEdit!.name;
    }
    if (widget.initialContent != null) {
      try {
        final data = jsonDecode(widget.initialContent!);
        _nameController.text = data['documentName'] ?? _nameController.text;
        _idNumberController.text = data['idNumber'] ?? '';
        _dobController.text = data['dob'] ?? '';
        _issuedByController.text = data['issuedBy'] ?? '';
        _expiryController.text = data['expiry'] ?? '';
        _notesController.text = data['notes'] ?? '';
      } catch (e) {
        final lines = widget.initialContent!.split('\n');
        for (final line in lines) {
          if (line.startsWith('Document Name: ')) _nameController.text = line.substring(15);
          if (line.startsWith('ID Number: ')) _idNumberController.text = line.substring(11);
          if (line.startsWith('Date of Birth: ')) _dobController.text = line.substring(15);
          if (line.startsWith('Issued By: ')) _issuedByController.text = line.substring(11);
          if (line.startsWith('Expiry Date: ')) _expiryController.text = line.substring(13);
          if (line.startsWith('Notes: ')) _notesController.text = line.substring(7);
        }
      }
    }
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter a document name'),
        backgroundColor: AppColors.destructiveRed,
      ));
      return;
    }

    final data = {
      'documentName': _nameController.text.trim(),
      'idNumber': _idNumberController.text.trim(),
      'dob': _dobController.text.trim(),
      'issuedBy': _issuedByController.text.trim(),
      'expiry': _expiryController.text.trim(),
      'notes': _notesController.text.trim(),
    };

    if (widget.itemToEdit != null) {
      await ref.read(vaultServiceProvider).updateJsonItem(
        widget.itemToEdit!,
        _nameController.text.trim(),
        data,
      );
    } else {
      await ref.read(vaultServiceProvider).importJsonItem(
        _nameController.text.trim(),
        data,
        'identity',
      );
    }
    ref.invalidate(vaultItemsProvider);
    ref.invalidate(categoryCountsProvider);
    ref.invalidate(recentItemsProvider);
    
    if (mounted) {
      _showSaved(context, _nameController.text.trim());
      context.pop();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    _idNumberController.dispose();
    _issuedByController.dispose();
    _expiryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceNeutral,
      appBar: _buildAppBar(
          context, widget.itemToEdit != null ? 'Edit Identity' : 'Add Identity', AppColors.categoryIdentityColor, _save),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.categoryIdentityBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.badge_rounded,
                      size: 16, color: AppColors.categoryIdentityColor),
                  SizedBox(width: 6),
                  Text('Identity Document',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.categoryIdentityColor)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('DOCUMENT INFO',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.textMuted)),
          const SizedBox(height: 8),
          _FormCard(children: [
            _FieldRow(
              icon: Icons.label_outline_rounded,
              iconColor: AppColors.categoryIdentityColor,
              iconBg: AppColors.categoryIdentityBg,
              label: 'DOCUMENT NAME',
              controller: _nameController,
              hint: 'e.g. Passport, Aadhaar Card',
            ),
            _FieldRow(
              icon: Icons.tag_rounded,
              iconColor: AppColors.categoryIdentityColor,
              iconBg: AppColors.categoryIdentityBg,
              label: 'ID / DOCUMENT NUMBER',
              controller: _idNumberController,
              hint: 'Enter document number',
            ),
            _FieldRow(
              icon: Icons.cake_outlined,
              iconColor: AppColors.categoryIdentityColor,
              iconBg: AppColors.categoryIdentityBg,
              label: 'DATE OF BIRTH',
              controller: _dobController,
              keyboardType: TextInputType.datetime,
              hint: 'DD/MM/YYYY',
            ),
            _FieldRow(
              icon: Icons.account_balance_outlined,
              iconColor: AppColors.categoryIdentityColor,
              iconBg: AppColors.categoryIdentityBg,
              label: 'ISSUED BY',
              controller: _issuedByController,
              hint: 'Issuing authority',
            ),
            _FieldRow(
              icon: Icons.event_outlined,
              iconColor: AppColors.categoryIdentityColor,
              iconBg: AppColors.categoryIdentityBg,
              label: 'EXPIRY DATE',
              controller: _expiryController,
              keyboardType: TextInputType.datetime,
              hint: 'DD/MM/YYYY',
              isLast: true,
            ),
          ]),
          const SizedBox(height: 20),
          const Text('NOTES',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.textMuted)),
          const SizedBox(height: 8),
          _FormCard(children: [
            _FieldRow(
              icon: Icons.notes_rounded,
              iconColor: AppColors.categoryIdentityColor,
              iconBg: AppColors.categoryIdentityBg,
              label: 'NOTES',
              controller: _notesController,
              hint: 'Any additional details',
              isLast: true,
            ),
          ]),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─── 3. CARD ──────────────────────────────────────────────────────────────────
class _AddCardScreen extends ConsumerStatefulWidget {
  const _AddCardScreen({this.itemToEdit, this.initialContent});
  final VaultItem? itemToEdit;
  final String? initialContent;

  @override
  ConsumerState<_AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends ConsumerState<_AddCardScreen> {
  final _nameController = TextEditingController();
  final _cardholderController = TextEditingController();
  final _numberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();
  final _pinController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.itemToEdit != null) {
      _nameController.text = widget.itemToEdit!.name;
    }
    if (widget.initialContent != null) {
      try {
        final data = jsonDecode(widget.initialContent!);
        _nameController.text = data['bankName'] ?? data['title'] ?? _nameController.text;
        _cardholderController.text = data['cardHolder'] ?? '';
        _numberController.text = data['cardNumber'] ?? '';
        _expiryController.text = data['expiry'] ?? '';
        _cvvController.text = data['cvv'] ?? '';
        _pinController.text = data['pin'] ?? '';
        _notesController.text = data['notes'] ?? '';
      } catch (e) {
        final lines = widget.initialContent!.split('\n');
        for (final line in lines) {
          if (line.startsWith('Card Label: ')) _nameController.text = line.substring(12);
          if (line.startsWith('Cardholder: ')) _cardholderController.text = line.substring(12);
          if (line.startsWith('Number: ')) _numberController.text = line.substring(8);
          if (line.startsWith('Expiry: ')) _expiryController.text = line.substring(8);
          if (line.startsWith('CVV: ')) _cvvController.text = line.substring(5);
          if (line.startsWith('PIN: ')) _pinController.text = line.substring(5);
          if (line.startsWith('Notes: ')) _notesController.text = line.substring(7);
        }
      }
    }
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter a card label'),
        backgroundColor: AppColors.destructiveRed,
      ));
      return;
    }

    final data = {
      'bankName': _nameController.text.trim(),
      'cardHolder': _cardholderController.text.trim(),
      'cardNumber': _numberController.text.trim(),
      'expiry': _expiryController.text.trim(),
      'cvv': _cvvController.text,
      'pin': _pinController.text,
      'notes': _notesController.text.trim(),
    };

    if (widget.itemToEdit != null) {
      await ref.read(vaultServiceProvider).updateJsonItem(
        widget.itemToEdit!,
        _nameController.text.trim(),
        data,
      );
    } else {
      await ref.read(vaultServiceProvider).importJsonItem(
        _nameController.text.trim(),
        data,
        'cards',
      );
    }
    ref.invalidate(vaultItemsProvider);
    ref.invalidate(categoryCountsProvider);
    ref.invalidate(recentItemsProvider);
    
    if (mounted) {
      _showSaved(context, _nameController.text.trim());
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceNeutral,
      appBar: _buildAppBar(
          context, widget.itemToEdit != null ? 'Edit Card' : 'Add Card', AppColors.categoryCardsColor, _save),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.categoryCardsBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.credit_card_rounded,
                      size: 16, color: AppColors.categoryCardsColor),
                  SizedBox(width: 6),
                  Text('Payment Card',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.categoryCardsColor)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('CARD DETAILS',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.textMuted)),
          const SizedBox(height: 8),
          _FormCard(children: [
            _FieldRow(
              icon: Icons.label_outline_rounded,
              iconColor: AppColors.categoryCardsColor,
              iconBg: AppColors.categoryCardsBg,
              label: 'CARD LABEL',
              controller: _nameController,
              hint: 'e.g. HDFC Credit, SBI Debit',
            ),
            _FieldRow(
              icon: Icons.person_outline_rounded,
              iconColor: AppColors.categoryCardsColor,
              iconBg: AppColors.categoryCardsBg,
              label: 'CARDHOLDER NAME',
              controller: _cardholderController,
              hint: 'Name on card',
            ),
            _FieldRow(
              icon: Icons.credit_card_rounded,
              iconColor: AppColors.categoryCardsColor,
              iconBg: AppColors.categoryCardsBg,
              label: 'CARD NUMBER',
              controller: _numberController,
              keyboardType: TextInputType.number,
              maxLength: 19,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _CardNumberFormatter(),
              ],
              hint: '•••• •••• •••• ••••',
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
              label: 'ATM PIN',
              controller: _pinController,
              isPassword: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              hint: '••••',
              isLast: true,
            ),
          ]),
          const SizedBox(height: 20),
          const Text('NOTES',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.textMuted)),
          const SizedBox(height: 8),
          _FormCard(children: [
            _FieldRow(
              icon: Icons.notes_rounded,
              iconColor: AppColors.categoryCardsColor,
              iconBg: AppColors.categoryCardsBg,
              label: 'NOTES',
              controller: _notesController,
              hint: 'Bank branch, limits, etc.',
              isLast: true,
            ),
          ]),
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
      } catch (e) {
        _contentController.text = widget.initialContent!;
      }
    }
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter a note title'),
        backgroundColor: AppColors.destructiveRed,
      ));
      return;
    }

    final data = {
      'title': _titleController.text.trim(),
      'content': _contentController.text,
    };

    if (widget.itemToEdit != null) {
      await ref.read(vaultServiceProvider).updateJsonItem(
        widget.itemToEdit!,
        _titleController.text.trim(),
        data,
      );
    } else {
      await ref.read(vaultServiceProvider).importJsonItem(
        _titleController.text.trim(),
        data,
        'notes',
      );
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
          context, widget.itemToEdit != null ? 'Edit Note' : 'Secure Note', AppColors.categoryNotesColor, _save),
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
                        color: AppColors.primaryNavy),
                    decoration: const InputDecoration(
                      hintText: 'Note title...',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintStyle: TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w400),
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
                          height: 1.6),
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
                  Icon(Icons.shield_outlined,
                      size: 16, color: AppColors.categoryNotesColor),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This note is encrypted with AES-256-GCM before storage.',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.categoryNotesColor,
                          fontWeight: FontWeight.w500),
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
      TextEditingValue oldValue, TextEditingValue newValue) {
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
      TextEditingValue oldValue, TextEditingValue newValue) {
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