import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:practice/services/background_service.dart';
import 'package:practice/services/user_firestore_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Switchbutton extends StatefulWidget {
  const Switchbutton({super.key});

  @override
  State<Switchbutton> createState() => _SwitchbuttonState();
}

class _SwitchbuttonState extends State<Switchbutton> {
  bool _isEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isEnabled =
          prefs.getBool('budgetAlertEnabled') ?? false;
    });
  }

  Future<void> _toggle(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('budgetAlertEnabled', value);

    if (value) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await BackgroundService.registerPeriodicTask(
            userDocumentIdFor(user));
      }
    } else {
      await BackgroundService.cancelAll();
    }

    if (!mounted) return;
    setState(() => _isEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Switch(
      value: _isEnabled,
      onChanged: _toggle,
      activeThumbColor:
          colorScheme.primary, // Color when ON
      inactiveThumbColor:
          colorScheme.outline, // Knob color when OFF
      inactiveTrackColor: colorScheme
          .surfaceContainerHighest, // Track color when OFF
    );
  }
}
