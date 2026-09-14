/// Where the SafetyU backend (backend_SafetyU, the Node/Express + MongoDB
/// server) lives. The backend must actually be running (`npm run dev` or
/// `npm start` inside backend_SafetyU) for anything using this to work.
///
/// Uncomment the ONE line below that matches how you're testing right now,
/// and comment out the others. This is the single place you need to edit
/// when you change how/where you run things.
class ApiConfig {
  /// Android emulator, backend running on the SAME computer:
  /// 10.0.2.2 is the emulator's special alias for your computer's own
  /// localhost. This is the default.
  static const String baseUrl = 'http://10.0.2.2:5000/api';

  /// iOS Simulator, backend running on the SAME computer (the simulator
  /// shares your Mac's network stack, so plain localhost works):
  // static const String baseUrl = 'http://localhost:5000/api';

  /// A physical phone (Android or iOS) on the SAME Wi-Fi network as the
  /// computer running the backend. Replace with that computer's LAN IP —
  /// find it with `ipconfig` (Windows) or `ifconfig` / `ip addr` (Mac/
  /// Linux); it looks like 192.168.x.x. The phone and computer must be on
  /// the same network, and nothing (like a firewall) can be blocking port
  /// 5000.
  // static const String baseUrl = 'http://192.168.1.42:5000/api';

  /// Backend deployed somewhere reachable over the internet (Render,
  /// Railway, an EC2 box, etc.) — use its public URL. Should be https in
  /// production.
  // static const String baseUrl = 'https://your-deployed-backend.example.com/api';
}