import 'api_client.dart';

class NotificationService {
  static Future<List<Map<String, dynamic>>> fetchAll() async {
    final data = await ApiClient.get('/notifications');
    return (data['notifications'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> activeSafetyAlerts() async {
    final data = await ApiClient.get('/notifications/alerts');
    return (data['alerts'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }

  static Future<void> markRead(String id) => ApiClient.put('/notifications/$id/read', {});

  static Future<void> respondToSafetyAlert(String id, String responseStatus) =>
      ApiClient.put('/notifications/$id/response', {'responseStatus': responseStatus});
}
