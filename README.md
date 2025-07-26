# RFID U300 Flutter Project

A modern, cross-platform Flutter application for configuring, controlling, and monitoring the RFID U300 device. This project provides a robust, user-friendly interface for antenna and group configuration, tag reading/writing, and real-time status monitoring. It integrates seamlessly with native Android code for hardware access and supports HTTP APIs for event reporting and tag validation.

---

## ✨ Features

- **Antenna & Group Configuration**
  - Select number of antennas (4 or 8)
  - Assign antennas as input/output for groups
  - Configure limit switches, alarm outputs, API addresses, read time, and output duration per group
  - All configurations are saved persistently

- **Tag Read & Write**
  - Read RFID tag IDs using the configured antenna
  - Write new IDs/data to tags with instant feedback

- **Run & Monitor**
  - Start/stop RFID reading process
  - Real-time group and antenna status display
  - Fetch and display unauthorized tags from a JSON URL
  - Send HTTP events to API endpoints on tag reads

- **Permissions & Native Integration**
  - Handles Bluetooth and location permissions
  - Uses platform channels for native Android RFID hardware access

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- Android Studio or VS Code
- An Android device with RFID U300 hardware (for full functionality)

### Setup
1. Clone this repository:
   ```bash
   git clone https://github.com/Hanie9/RFID.git
   cd rfid_project
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Connect your Android device and run:
   ```bash
   flutter run
   ```

### Usage
- On first launch, grant all requested permissions.
- Use the **Config** tab to set up antennas and groups as needed.
- Use the **Run** tab to start/stop reading and monitor status.
- Use the **Read Write** tab to read or write tag data.

---

## 🗂 Project Structure

- `lib/main.dart` — Main app logic, UI, and state management
- `lib/gpio_output.dart` — GPIO output operations
- `lib/status_card.dart` — Status display widget
- `android/` — Native Android integration for RFID hardware

---

## ⚙️ Technical Details
- **Flutter**: Material 3 UI, stateful widgets, persistent storage
- **Native Android**: Platform channels for hardware access
- **HTTP**: Uses `http` package for API calls
- **Permissions**: Uses `permission_handler` for runtime permissions

---

## 🛠 Troubleshooting
- If the app does not detect the RFID hardware, ensure all permissions are granted and the device is properly connected.
- For API errors, check your endpoint URLs and network connection.
- For development issues, consult the [Flutter documentation](https://docs.flutter.dev/).

---

## 📄 License

This project is for academic and demonstration purposes. Please contact the author for other uses.

---

## 👩‍💻 Credits
- Developed by Hanie (and contributors)
- Special thanks to the professor and all open-source package authors