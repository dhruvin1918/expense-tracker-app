import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:practice/services/user_firestore_helper.dart';

class Addcategories extends StatefulWidget {
  const Addcategories({super.key});

  @override
  State<Addcategories> createState() =>
      _AddcategoriesState();
}

class _AddcategoriesState extends State<Addcategories> {
  final TextEditingController _categoryController =
      TextEditingController();
  bool _isAdding = false;

  bool get _canAddCategory =>
      !_isAdding &&
      _categoryController.text.trim().isNotEmpty;

  String _normalizeCategoryName(String input) {
    final text = input.trim();
    if (text.isEmpty) return text;
    return text[0].toUpperCase() +
        text.substring(1).toLowerCase();
  }

  Future<void> _addCategory() async {
    if (_isAdding) return;

    final user = FirebaseAuth.instance.currentUser;
    final normalized =
        _normalizeCategoryName(_categoryController.text);

    if (user == null || normalized.isEmpty) return;

    setState(() => _isAdding = true);

    try {
      final categoriesRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection('categories');

      final existing = await categoriesRef
          .where('name', isEqualTo: normalized)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Category already exists.'),
          ),
        );
        return;
      }

      final createdDoc = await categoriesRef.add({
        'name': normalized,
        'timestamp': FieldValue.serverTimestamp(),
      });

      _categoryController.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('Category added successfully.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              categoriesRef.doc(createdDoc.id).delete();
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('Add category error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Failed to add category. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }

  Future<void> _deleteCategory(
      String docId, String categoryName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          '"$categoryName" will be removed. Existing expenses using this category will not be changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final categoryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userDocumentIdFor(user))
          .collection('categories')
          .doc(docId);

      final beforeDelete = await categoryRef.get();
      final deletedData = beforeDelete.data();

      await categoryRef.delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$categoryName" deleted.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (deletedData == null) return;
              categoryRef.set(deletedData);
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('Delete category error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Failed to delete category. Please try again.'),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _categoryController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Manage Categories',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: colorScheme.primary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create Category',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: _categoryController,
                      maxLength: 30,
                      onSubmitted: (_) {
                        if (_canAddCategory) _addCategory();
                      },
                      style: TextStyle(
                          color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: 'Enter category name',
                        hintStyle: TextStyle(
                            color: colorScheme.outline),
                        filled: true,
                        fillColor: colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        prefixIcon: Icon(
                            Icons.category_outlined,
                            color: colorScheme.primary),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _canAddCategory
                            ? _addCategory
                            : null,
                        icon: _isAdding
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<
                                          Color>(
                                    colorScheme.onPrimary,
                                  ),
                                ),
                              )
                            : const Icon(Icons.add),
                        label: Text(_isAdding
                            ? 'Adding...'
                            : 'Add Category'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'My Categories',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: user == null
                  ? const Center(
                      child: Text(
                          'Please sign in to add categories.'),
                    )
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(userDocumentIdFor(user))
                          .collection('categories')
                          .orderBy('timestamp',
                              descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child:
                                  CircularProgressIndicator());
                        }

                        if (snapshot.hasError) {
                          return const Center(
                            child: Text(
                                'Error loading categories.'),
                          );
                        }

                        final docs =
                            snapshot.data?.docs ?? [];

                        if (docs.isEmpty) {
                          return Center(
                            child: Text(
                              'No categories added yet.\nUse the form above to add one.',
                              textAlign: TextAlign.center,
                              style: theme
                                  .textTheme.bodyMedium
                                  ?.copyWith(
                                color: colorScheme.outline,
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final doc = docs[index];

                            final categoryName = (doc.data()
                                        as Map<String,
                                            dynamic>?)?[
                                    'name'] ??
                                'Unnamed';

                            return Card(
                              color: colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                        12),
                              ),
                              elevation: 1.5,
                              child: ListTile(
                                leading: Icon(
                                    Icons.label_outline,
                                    color: colorScheme
                                        .primary),
                                title: Text(
                                  categoryName,
                                  style: theme
                                      .textTheme.bodyLarge
                                      ?.copyWith(
                                    fontWeight:
                                        FontWeight.bold,
                                    color: colorScheme
                                        .onSurface,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                      Icons.delete_outline,
                                      color: colorScheme
                                          .error),
                                  onPressed: () =>
                                      _deleteCategory(
                                          doc.id,
                                          categoryName),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
