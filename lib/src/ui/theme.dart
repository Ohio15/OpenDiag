import 'package:flutter/material.dart';

class AppTheme {
  static const primaryColor = Color(0xFF1565C0);
  static const secondaryColor = Color(0xFF42A5F5);
  static const errorColor = Color(0xFFD32F2F);
  static const warningColor = Color(0xFFFFA000);
  static const successColor = Color(0xFF388E3C);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
      ),
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
      ),
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
      ),
    );
  }
}

class AppIcons {
  static const IconData connect = Icons.bluetooth_searching;
  static const IconData disconnect = Icons.bluetooth_disabled;
  static const IconData connected = Icons.bluetooth_connected;
  static const IconData scan = Icons.search;
  static const IconData dtc = Icons.warning_amber;
  static const IconData clearDtc = Icons.delete_sweep;
  static const IconData liveData = Icons.show_chart;
  static const IconData vehicle = Icons.directions_car;
  static const IconData readiness = Icons.checklist;
  static const IconData freezeFrame = Icons.ac_unit;
  static const IconData settings = Icons.settings;
  static const IconData info = Icons.info_outline;

  // Module / ECU icons
  static const IconData modules = Icons.developer_board;
  static const IconData engine = Icons.local_gas_station;
  static const IconData transmission = Icons.settings_applications;
  static const IconData abs = Icons.remove_circle_outline;
  static const IconData airbag = Icons.airline_seat_legroom_extra;
  static const IconData bcm = Icons.electrical_services;
  static const IconData hvac = Icons.thermostat;
  static const IconData instrument = Icons.speed;
  static const IconData steering = Icons.radio_button_checked;
  static const IconData tpms = Icons.tire_repair;
  static const IconData unknown = Icons.memory;

  // Control icons
  static const IconData actuator = Icons.build;
  static const IconData routine = Icons.play_circle;
  static const IconData security = Icons.lock_open;
  static const IconData locked = Icons.lock;
  static const IconData ioControl = Icons.toggle_on;
  static const IconData reset = Icons.restart_alt;
  static const IconData refresh = Icons.refresh;
  static const IconData expand = Icons.expand_more;
  static const IconData collapse = Icons.expand_less;
}
