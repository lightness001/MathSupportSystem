import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  const apiKey = "AIzaSyCSE1AvltpnIP4SCoRSqjkS3RH2OTp__7E";
  const model = "gemini-2.0-flash";
  final url = Uri.parse(
      "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey");

  try {
    print("Sending test request to Gemini...");
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "contents": [
          {
            "parts": [
              {"text": "Hello, respond with a JSON object containing a field 'message' saying hello."}
            ]
          }
        ],
        "generationConfig": {
          "responseMimeType": "application/json",
          "temperature": 0.2,
          "maxOutputTokens": 2048,
        }
      }),
    );
    print("Status code: ${response.statusCode}");
    print("Body: ${response.body}");
  } catch (e) {
    print("Error: $e");
  }
}
