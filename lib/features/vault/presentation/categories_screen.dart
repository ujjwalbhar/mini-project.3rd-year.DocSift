import 'package:flutter/material.dart';
import '../../../core/constants/app_strings.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.categories)),
      body: const Center(
        child: Text('Categories — Phase 2'),
      ),
    );
  }
}
