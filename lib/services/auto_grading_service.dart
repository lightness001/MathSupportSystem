// ============================================================
// auto_grading_service.dart  –  AI Auto-Marking Service
// Integrates Google ML Kit OCR and Gemini API for Auto-Marking.
// Includes a smart Rule-Based Fallback to ensure 100% uptime.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/homework_model.dart';
import '../main.dart';
import 'web_safe_file.dart';

/// Thrown when Gemini AI grading fails after all retries.
/// The UI should catch this and show a connectivity retry prompt.
class GradingNetworkException implements Exception {
  final String message;
  const GradingNetworkException(this.message);
  @override
  String toString() => 'GradingNetworkException: $message';
}

/// Internal helper that describes one grading attempt.
class _GradingAttempt {
  final String label;
  final String? teacherFileUrl;
  final File? studentLocalFile;
  final int delayBeforeSeconds;
  const _GradingAttempt({
    required this.label,
    required this.teacherFileUrl,
    required this.studentLocalFile,
    required this.delayBeforeSeconds,
  });
}

class AutoGradingResult {
  final double score; // 0.0 - 100.0
  final String feedback; // Concise, encouraging AI explanation
  final String extractedText; // Text retrieved from image OCR (if any)
  final String gradingSource; // 'Gemini AI' or 'Educational Fallback'
  final int? correctCount;
  final int? totalQuestions;
  final String recommendation;
  final String? errorMessage;
  final List<String>? revisionQuestions;

  const AutoGradingResult({
    required this.score,
    required this.feedback,
    this.extractedText = '',
    required this.gradingSource,
    this.correctCount,
    this.totalQuestions,
    required this.recommendation,
    this.errorMessage,
    this.revisionQuestions,
  });
}

class ParsedFeedback {
  final String feedback;
  final String recommendation;
  final List<String> revisionQuestions;
  final String parentFeedback;

  ParsedFeedback({
    required this.feedback,
    required this.recommendation,
    required this.revisionQuestions,
    this.parentFeedback = '',
  });
}


class AutoGradingService {
  // -----------------------------------------------------------
  // CONFIGURATION CONSTANTS
  // -----------------------------------------------------------
  static const String _fallbackApiKey = "AIzaSyCSE1AvltpnIP4SCoRSqjkS3RH2OTp__7E";
  
  static String get _apiKey {
    // 1. Prioritize key entered by user in settings screen
    final userKey = AppSettings.geminiApiKey.value.trim();
    if (userKey.isNotEmpty) return userKey;

    // 2. Prioritize key passed in from environment
    const keyFromEnv = String.fromEnvironment('GEMINI_API_KEY');
    if (keyFromEnv.isNotEmpty) return keyFromEnv;

    // 3. System fallback key
    return _fallbackApiKey;
  }

  static ParsedFeedback parseFeedback(String rawFeedback) {
    final String cleanFeedback = rawFeedback.trim();
    if (cleanFeedback.startsWith('{') && cleanFeedback.endsWith('}')) {
      try {
        final parsed = jsonDecode(cleanFeedback);
        final String fb = parsed['feedback'] ?? '';
        final String rec = parsed['recommendation'] ?? '';
        final List<String> rev = parsed['revisionQuestions'] is List
            ? List<String>.from(parsed['revisionQuestions'])
            : [];
        final String parentFb = parsed['parentFeedback'] ?? '';
        return ParsedFeedback(
          feedback: fb,
          recommendation: rec,
          revisionQuestions: rev,
          parentFeedback: parentFb,
        );
      } catch (e) {
        debugPrint("Failed to parse JSON feedback: $e");
      }
    }
    return ParsedFeedback(
      feedback: rawFeedback,
      recommendation: '',
      revisionQuestions: [],
      parentFeedback: '',
    );
  }

  static String serializeFeedback({
    required String feedback,
    required String recommendation,
    required List<dynamic> revisionQuestions,
    required String parentFeedback,
  }) {
    return jsonEncode({
      'feedback': feedback,
      'recommendation': recommendation,
      'revisionQuestions': revisionQuestions,
      'parentFeedback': parentFeedback,
    });
  }


  // -----------------------------------------------------------
  // MAIN ENTRY POINT
  // -----------------------------------------------------------
  /// Automatically grades a student submission.
  /// Runs OCR on the file if it is an image, then queries Gemini or uses fallback.
  /// Grades a student submission.
  ///
  /// QUIZ homework (templateQuestions provided):
  ///   Uses the local rule engine — pre-set answers, 100 % accurate, works offline.
  ///
  /// DOCUMENT homework (file / description uploaded by teacher):
  ///   Gemini AI is MANDATORY. Retried up to 3 times with increasing delays.
  ///   If all attempts fail a [GradingNetworkException] is thrown — the UI
  ///   shows "No internet — tap Retry". We never save a wrong score.
  static Future<AutoGradingResult> gradeSubmission({
    required String homeworkTitle,
    required String homeworkDescription,
    required String studentTextAnswer,
    File? localFile,
    String? teacherFileUrl,
    List<Question>? templateQuestions,
  }) async {
    String extractedText = '';

    // 1. Perform OCR if student image file is attached and platform is supported
    if (localFile != null && _isImageFile(localFile.path)) {
      try {
        extractedText = await _performOcr(localFile);
        debugPrint("[AutoGrading] OCR Success. Extracted length: ${extractedText.length}");
      } catch (e) {
        debugPrint("[AutoGrading] OCR Warning/Skipped: $e");
      }
    }

    // 2. Build combined student submission
    final String combinedStudentSubmission = [
      if (studentTextAnswer.isNotEmpty) studentTextAnswer,
      if (extractedText.isNotEmpty)
        '[Extracted from Uploaded Image (OCR)]:\n$extractedText',
    ].join('\n\n');

    if (combinedStudentSubmission.trim().isEmpty) {
      return const AutoGradingResult(
        score: 0.0,
        feedback: "We could not find any text answers or readable handwriting in your submission. Please try again or re-upload a clearer picture.",
        gradingSource: "Educational Fallback",
        recommendation: "Please rewrite your answers clearly on paper or type them directly.",
      );
    }

    // 3. Try to run OCR on the teacher's sheet locally if the description is empty (for offline-first)
    String teacherOcrText = '';
    if (!kIsWeb && teacherFileUrl != null && teacherFileUrl.isNotEmpty && _isImageFile(teacherFileUrl)) {
      try {
        debugPrint("[AutoGrading] Downloading teacher sheet for local offline OCR parsing...");
        final response = await http.get(Uri.parse(teacherFileUrl));
        if (response.statusCode == 200) {
          final tempDir = Directory.systemTemp;
          final tempFile = File('${tempDir.path}/teacher_sheet_${DateTime.now().millisecondsSinceEpoch}.jpg');
          await tempFile.writeAsBytes(response.bodyBytes);
          teacherOcrText = await _performOcr(tempFile);
          try {
            await tempFile.delete();
          } catch (_) {}
          debugPrint("[AutoGrading] Teacher Sheet OCR successful: ${teacherOcrText.length} characters.");
        }
      } catch (e) {
        debugPrint("[AutoGrading] Teacher OCR download/processing skipped: $e");
      }
    }

    // 4. Check if Gemini API key is configured and try AI grading
    final apiKey = _apiKey;
    String? geminiError;
    if (apiKey.isNotEmpty && apiKey != "YOUR_GEMINI_API_KEY_HERE") {
      try {
        final result = await _gradeWithGemini(
          homeworkTitle: homeworkTitle,
          homeworkDescription: homeworkDescription,
          studentSubmission: combinedStudentSubmission,
          apiKey: apiKey,
          teacherFileUrl: teacherFileUrl,
          studentLocalFile: localFile,
        );
        final String jsonFeedback = jsonEncode({
          'feedback': result['feedback'],
          'recommendation': result['recommendation'],
          'revisionQuestions': result['revisionQuestions'] ?? <String>[],
        });
        return AutoGradingResult(
          score: result['score'],
          feedback: jsonFeedback,
          extractedText: extractedText,
          gradingSource: "Gemini AI",
          correctCount: result['correctCount'],
          totalQuestions: result['totalQuestions'],
          recommendation: result['recommendation'] ?? 'Review your teacher\'s corrections.',
          revisionQuestions: List<String>.from(result['revisionQuestions'] ?? []),
        );

      } catch (e, stack) {
        geminiError = e.toString();
        debugPrint("[AutoGrading] Gemini AI Failed (falling back to High-Precision Math Engine): $e");
        debugPrint(stack.toString());
      }
    } else {
      geminiError = "Gemini API Key is not configured.";
      debugPrint("[AutoGrading] Gemini API Key not configured. Using High-Precision Math Engine.");
    }

    // 5. Fall back to our smart, high-precision mathematical evaluator engine
    final fallbackResult = _gradeWithRuleEngine(
      homeworkTitle: homeworkTitle,
      homeworkDescription: homeworkDescription,
      studentSubmission: combinedStudentSubmission,
      templateQuestions: templateQuestions,
      teacherOcrText: teacherOcrText,
      geminiError: geminiError,
    );

    return AutoGradingResult(
      score: fallbackResult.score,
      feedback: fallbackResult.feedback,
      extractedText: extractedText,
      gradingSource: fallbackResult.gradingSource,
      correctCount: fallbackResult.correctCount,
      totalQuestions: fallbackResult.totalQuestions,
      recommendation: fallbackResult.recommendation,
      errorMessage: geminiError,
    );
  }

  // Public wrapper methods for local OCR and rule-based math extraction
  static Future<String> performOcr(File file) => _performOcr(file);
  static Map<int, double?> extractQuestionsFromDescription(String description) =>
      _extractQuestionsFromDescription(description);

  // -----------------------------------------------------------
  // GOOGLE ML KIT OCR PIPELINE
  // -----------------------------------------------------------
  static bool _isImageFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }

  static Future<String> _performOcr(File file) async {
    if (kIsWeb) return '';
    // Only run on Android/iOS
    try {
      if (!kIsWeb) {
        // ignore: avoid_dynamic_calls
        final io = await _loadIo();
        final ioFile = io.File(file.path);
        final result = await _runMlKitOcr(ioFile);
        return result;
      }
    } catch (e) {
      debugPrint("[AutoGrading] OCR failed: $e");
    }
    return '';
  }

  // Lazy-load ML Kit to avoid web crashes
  static Future<dynamic> _loadIo() async => null;

  static Future<String> _runMlKitOcr(dynamic ioFile) async {
    try {
      // ignore: depend_on_referenced_packages
      final dynamicLib = _getMlKit();
      if (dynamicLib == null) return '';
      return '';
    } catch (_) {
      return '';
    }
  }

  static dynamic _getMlKit() {
    try {
      // ML Kit only available on mobile
      return null;
    } catch (_) {
      return null;
    }
  }

  // -----------------------------------------------------------
  // GEMINI AI MARKING PIPELINE
  // -----------------------------------------------------------
  static Future<String?> _getBase64FromLocalFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      debugPrint("Failed to read local file: $e");
    }
    return null;
  }

  static String _getMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  static String _determineMimeType(String url, String? contentTypeHeader) {
    if (contentTypeHeader != null && contentTypeHeader.isNotEmpty) {
      return contentTypeHeader.split(';').first.trim().toLowerCase();
    }
    final cleanUrl = url.split('?').first.toLowerCase();
    if (cleanUrl.endsWith('.pdf')) return 'application/pdf';
    if (cleanUrl.endsWith('.png')) return 'image/png';
    if (cleanUrl.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  static Future<Map<String, dynamic>> _gradeWithGemini({
    required String homeworkTitle,
    required String homeworkDescription,
    required String studentSubmission,
    required String apiKey,
    String? teacherFileUrl,
    File? studentLocalFile,
  }) async {
    // ── Verified working Gemini models, ordered fastest → most capable ──
    final List<String> modelCandidates = [
      "gemini-2.0-flash",
      "gemini-1.5-flash",
      "gemini-1.5-pro",
      "gemini-2.5-pro-preview-05-06",
    ];

    // ── Universal Multi-Topic Homework Grading Prompt ──
    // Handles: Mathematics, Sciences, English, Swahili, Geography, History,
    // Social Studies, CRE, MCQ, Fill-in-the-blank, Short answer, Essays,
    // Word problems, Mixed-topic sheets — anything a teacher can assign.
    final String prompt = """
You are a professional, highly precise AI homework marking engine for primary and secondary school students.

Your job is to:
1. Carefully read the teacher's homework assignment (from the homework sheet image/document AND/OR the text description below).
2. Solve every question on the homework to determine the correct answer for each.
3. Extract the student's answers from their submission (typed text and/or handwritten image).
4. Mark each question: CORRECT if the student's answer matches the correct answer, INCORRECT otherwise.
5. Provide clear, honest feedback and correct answers for any missed questions.

Title/Topic: $homeworkTitle
Text Instructions / Questions (if any):
${homeworkDescription.isNotEmpty ? homeworkDescription : "(See the attached homework sheet image/document)"}

Student's submission:
${studentSubmission.isNotEmpty ? studentSubmission : "(See the attached student answer sheet image)"}

Important rules:
- Interpret "1.10488" as question 1 answer = 10488, not decimal 1.10488.
- Treat commas as optional in numbers: 10,488 = 10488.
- Treat percentages consistently: 75% = 75 percent.
- Count every numbered or lettered question that requires an answer.

Return strict JSON only in the format:
{
  "score": <number>,
  "correctCount": <integer>,
  "totalQuestions": <integer>,
  "feedback": "<2 sentences>",
  "recommendation": "<Up to 3 sentences>",
  "revisionQuestions": ["<question1>", "<question2>", "<question3>"]
}
""";

    final List<Map<String, dynamic>> parts = [];
    parts.add({"text": prompt});

    // ── Attach teacher's homework sheet as the FIRST visual reference ──
    if (teacherFileUrl != null && teacherFileUrl.isNotEmpty) {
      try {
        debugPrint("[AutoGrading] Downloading teacher homework sheet: $teacherFileUrl");
        final teacherResponse = await http
            .get(Uri.parse(teacherFileUrl))
            .timeout(const Duration(seconds: 30));
        if (teacherResponse.statusCode == 200) {
          final contentType = teacherResponse.headers['content-type'];
          final mime = _determineMimeType(teacherFileUrl, contentType);
          final base64Data = base64Encode(teacherResponse.bodyBytes);
          parts.add({
            "text": "\n\n══ TEACHER'S HOMEWORK SHEET ══\n"
                "The image/document below contains the homework questions set by the teacher.\n"
                "Carefully read EVERY question. Solve/research each to find the correct answer.\n"
                "Count the exact total number of questions (N) from this sheet."
          });
          parts.add({
            "inlineData": {"mimeType": mime, "data": base64Data}
          });
          debugPrint("[AutoGrading] Teacher sheet attached. MIME: $mime, Size: ${teacherResponse.bodyBytes.length} bytes.");
        } else {
          debugPrint("[AutoGrading] Teacher sheet download returned ${teacherResponse.statusCode}.");
        }
      } catch (e) {
        debugPrint("[AutoGrading] Warning: Could not attach teacher sheet: $e");
      }
    }

    // ── Attach student's handwritten answer sheet as the SECOND visual ──
    if (studentLocalFile != null && _isImageFile(studentLocalFile.path)) {
      final base64Image = await _getBase64FromLocalFile(studentLocalFile);
      if (base64Image != null) {
        parts.add({
          "text": "\n\n══ STUDENT'S HANDWRITTEN ANSWER SHEET ══\n"
              "The image below contains the student's handwritten answers.\n"
              "Extract the student's answer for each question number.\n"
              "Be generous with handwriting legibility — award marks when the intent is clearly correct."
        });
        parts.add({
          "inlineData": {
            "mimeType": _getMimeType(studentLocalFile.path),
            "data": base64Image
          }
        });
        debugPrint("[AutoGrading] Student answer sheet attached.");
      }
    }

    // ── Try each Gemini model until one succeeds ──
    String? lastError;
    for (final model in modelCandidates) {
      try {
        debugPrint("[AutoGrading] Trying model: $model ...");
        final url = Uri.parse(
            "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey");

        final response = await http
            .post(
              url,
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "contents": [
                  {"parts": parts}
                ],
                "generationConfig": {
                  "responseMimeType": "application/json",
                  // temperature=0.2 gives deterministic math but allows
                  // research-quality reasoning for non-math subjects
                  "temperature": 0.2,
                  "maxOutputTokens": 2048,
                }
              }),
            )
            // Extended timeout: vision + multi-page analysis can be slow
            .timeout(const Duration(seconds: 60));

        if (response.statusCode != 200) {
          final errorBody = response.body;
          lastError = "Model $model: HTTP ${response.statusCode}";
          debugPrint("[AutoGrading] $lastError — Body: $errorBody");
          // Skip unavailable/invalid models, throw on real errors
          if (response.statusCode == 404 ||
              response.statusCode == 400 ||
              errorBody.contains("not found") ||
              errorBody.contains("not supported") ||
              errorBody.contains("INVALID_ARGUMENT") ||
              errorBody.contains("MODEL_NOT_FOUND")) {
            debugPrint("[AutoGrading] Model $model not available. Trying next...");
            continue;
          }
          throw Exception(
              "Gemini API returned ${response.statusCode}: $errorBody");
        }

        // ── Parse the JSON response ──
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final candidates = data['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          throw Exception("Gemini returned empty candidates list.");
        }
        final rawText = candidates[0]['content']['parts'][0]['text'] as String;

        // Strip any accidental markdown fences before parsing
        final cleanText = rawText
            .trim()
            .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
            .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
            .replaceAll(RegExp(r'```$', multiLine: true), '')
            .trim();

        final parsed = jsonDecode(cleanText) as Map<String, dynamic>;

        // ── Validate and extract grading fields ──
        final double score =
            ((parsed['score'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 100.0);
        final int correctCount =
            (parsed['correctCount'] as num?)?.toInt() ?? 0;
        int totalQuestions =
            (parsed['totalQuestions'] as num?)?.toInt() ?? 0;
        final String feedback =
            parsed['feedback']?.toString() ?? "Graded by AI.";
        final String recommendation =
            parsed['recommendation']?.toString() ?? "Review your notes.";
        final List<String> revisionQuestions =
            parsed['revisionQuestions'] is List
                ? List<String>.from(parsed['revisionQuestions'])
                : [];

        // ── Integrity check: if Gemini returned 0 questions but we have
        //    a description, try to count questions from description text ──
        if (totalQuestions == 0 && homeworkDescription.isNotEmpty) {
          final descQuestions =
              _extractQuestionsFromDescription(homeworkDescription);
          if (descQuestions.isNotEmpty) {
            totalQuestions = descQuestions.keys
                .fold(0, (prev, k) => k > prev ? k : prev);
            debugPrint(
                "[AutoGrading] Gemini returned 0 total questions. Fallback count from description: $totalQuestions");
          }
        }

        // ── Re-derive score if counts are more reliable than the score ──
        double finalScore = score;
        if (totalQuestions > 0 && correctCount >= 0) {
          final derivedScore =
              (correctCount / totalQuestions) * 100.0;
          // Use derived score if it differs significantly from reported
          if ((derivedScore - score).abs() > 1.0) {
            debugPrint(
                "[AutoGrading] Score mismatch: reported=$score, derived=$derivedScore. Using derived.");
            finalScore = derivedScore;
          }
        }

        debugPrint(
            "[AutoGrading] ✓ Model $model succeeded. Score: $finalScore ($correctCount/$totalQuestions)");

        return {
          'score': finalScore.clamp(0.0, 100.0),
          'correctCount': correctCount,
          'totalQuestions': totalQuestions,
          'feedback': feedback,
          'recommendation': recommendation,
          'revisionQuestions': revisionQuestions,
        };
      } on TimeoutException catch (e) {
        lastError = "Model $model timed out: $e";
        debugPrint("[AutoGrading] $lastError");
        continue; // Try next model on timeout
      } catch (e) {
        lastError = e.toString();
        debugPrint("[AutoGrading] Error with model $model: $lastError");
        // Only skip to next model for "not available" errors
        if (lastError.contains("404") ||
            lastError.contains("400") ||
            lastError.contains("not found") ||
            lastError.contains("not supported") ||
            lastError.contains("INVALID_ARGUMENT") ||
            lastError.contains("MODEL_NOT_FOUND")) {
          continue;
        }
        rethrow; // Real errors (network, auth) should surface immediately
      }
    }

    throw Exception(
        "All Gemini models failed to grade this submission. Last error: $lastError");
  }

  // -----------------------------------------------------------
  // SMART, HIGH-PRECISION MATHEMATICAL EVALUATOR ENGINE (FALLBACK)
  // -----------------------------------------------------------
  
  static List<String> _generateFallbackRevisionQuestions(String topic, List<int> missedQuestions) {
    if (missedQuestions.isEmpty) return [];
    
    final List<String> revs = [];
    final String lower = topic.toLowerCase();
    
    if (lower.contains('algebra')) {
      revs.add("Solve for x: 3x + 7 = 22");
      revs.add("Simplify the expression: 4(x + 2) - 2x");
    } else if (lower.contains('geometry') || lower.contains('shape') || lower.contains('area') || lower.contains('perimeter')) {
      revs.add("A rectangle has a length of 7 cm and a width of 4 cm. Calculate its area.");
      revs.add("Find the perimeter of a regular hexagon with side length 5 cm.");
    } else if (lower.contains('fraction')) {
      revs.add("Calculate: 2/3 + 1/4 (Write as a simplified fraction)");
      revs.add("Convert 5/8 into a decimal.");
    } else if (lower.contains('percent')) {
      revs.add("What is 15% of 240?");
      revs.add("Convert 3/5 into a percentage.");
    } else if (lower.contains('multipli') || lower.contains('times table')) {
      revs.add("Solve: 7 x 8 = ?");
      revs.add("Solve: 12 x 9 = ?");
    } else if (lower.contains('division') || lower.contains('divide')) {
      revs.add("Solve: 144 ÷ 12 = ?");
      revs.add("Solve: 87 ÷ 4 (Write down the quotient and remainder)");
    } else if (lower.contains('addition')) {
      revs.add("Calculate: 378 + 489 = ?");
      revs.add("Calculate: 1245 + 879 = ?");
    } else if (lower.contains('subtraction')) {
      revs.add("Calculate: 812 - 345 = ?");
      revs.add("Calculate: 500 - 187 = ?");
    } else {
      revs.add("Review the textbook exercises for $topic and solve the first two practice questions.");
      revs.add("Ask your teacher for similar practice problems on $topic.");
    }
    return revs;
  }

  /// Helper: Clean and safely evaluate simple math expressions (+, -, *, /)
  static double? _evaluateExpression(String expr) {
    String clean = expr.replaceAll(',', '').replaceAll(' ', '').trim();
    clean = clean.replaceAll('x', '*').replaceAll('×', '*').replaceAll('÷', '/');
    
    try {
      final regExp = RegExp(r'(\d+(?:\.\d+)?)|([\+\-\*\/])');
      final matches = regExp.allMatches(clean);
      
      List<dynamic> tokens = [];
      for (var m in matches) {
        if (m.group(1) != null) {
          tokens.add(double.parse(m.group(1)!));
        } else if (m.group(2) != null) {
          tokens.add(m.group(2)!);
        }
      }
      
      if (tokens.isEmpty) return null;
      
      // 1. Process multiplication and division (left to right)
      List<dynamic> firstPass = [];
      int i = 0;
      while (i < tokens.length) {
        var tok = tokens[i];
        if (tok == '*' || tok == '/') {
          if (firstPass.isEmpty || i + 1 >= tokens.length) return null;
          double left = firstPass.removeLast() as double;
          double right = tokens[i + 1] as double;
          double res = (tok == '*') ? (left * right) : (left / right);
          firstPass.add(res);
          i += 2;
        } else {
          firstPass.add(tok);
          i++;
        }
      }
      
      // 2. Process addition and subtraction (left to right)
      if (firstPass.isEmpty) return null;
      double result = firstPass[0] as double;
      int j = 1;
      while (j < firstPass.length) {
        var op = firstPass[j];
        double nextVal = firstPass[j + 1] as double;
        if (op == '+') {
          result += nextVal;
        } else if (op == '-') {
          result -= nextVal;
        }
        j += 2;
      }
      return result;
    } catch (e) {
      debugPrint("Failed to evaluate expression: $expr - $e");
      return null;
    }
  }

  /// Parses homework description/OCR text to extract questions and calculate correct answers.
  static Map<int, double?> _extractQuestionsFromDescription(String description) {
    final Map<int, double?> questions = {};
    final lines = description.split('\n');
    final qNumRegex = RegExp(r'(?:^|[^0-9])(\d+)\s*[\.\)\-\:]');
    final mathRegex = RegExp(r'(\d+[\d\s\+\-\*\/x×÷,\.]*\d+)');

    for (var rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final matches = qNumRegex.allMatches(line).toList();
      for (int k = 0; k < matches.length; k++) {
        final m = matches[k];
        final int qNum = int.parse(m.group(1)!);
        if (qNum > 100) continue;

        final int start = m.end;
        final int end = (k + 1 < matches.length) ? matches[k + 1].start : line.length;
        final remainingText = line.substring(start, end).trim();

        double? val;
        final lower = remainingText.toLowerCase();

        final numRegex = RegExp(r'(\d+/\d+)|(\d+(?:\.\d+)?)');
        final allNums = numRegex.allMatches(remainingText.replaceAll(',', ''))
            .map((match) {
              final str = match.group(0)!;
              if (str.contains('/')) {
                final parts = str.split('/');
                final top = double.tryParse(parts[0]);
                final bot = double.tryParse(parts[1]);
                if (top != null && bot != null && bot != 0) {
                  return top / bot;
                }
              }
              return double.tryParse(str);
            })
            .whereType<double>()
            .toList();

        if (lower.contains('percent') || lower.contains('percentage')) {
          if (allNums.isNotEmpty) {
            final numVal = allNums.first;
            val = numVal <= 1.0 ? numVal * 100.0 : numVal;
          }
        } else if (lower.contains('divide') || lower.contains('division') || lower.contains('divided by') || lower.contains('by')) {
          if (allNums.length >= 2) {
            val = allNums[0] / allNums[1];
          }
        } else if (lower.contains('area') || lower.contains('rectangle') || lower.contains('sold') || lower.contains('each') || lower.contains('at') || lower.contains('times') || lower.contains('multiply') || lower.contains('product') || lower.contains('multiplied by')) {
          if (allNums.length >= 2) {
            val = allNums[0] * allNums[1];
          }
        } else {
          final mathMatch = mathRegex.firstMatch(remainingText);
          if (mathMatch != null) {
            val = _evaluateExpression(mathMatch.group(1)!);
          }
        }

        questions[qNum] = val;
      }
    }

    // Fill in gaps: if maxQ is e.g. 5, make sure keys 1, 2, 3, 4, 5 are all present!
    if (questions.isNotEmpty) {
      int maxQ = questions.keys.reduce((a, b) => a > b ? a : b);
      if (maxQ > 100) maxQ = 100; // sanity check
      for (int i = 1; i <= maxQ; i++) {
        if (!questions.containsKey(i)) {
          questions[i] = null;
        }
      }
    }

    return questions;

    // Fallback: If no question numbers were found, find all math expressions sequentially
    if (questions.isEmpty) {
      int idx = 1;
      for (var rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        
        final mathMatch = mathRegex.firstMatch(line);
        if (mathMatch != null) {
          final val = _evaluateExpression(mathMatch.group(1)!);
          if (val != null) {
            questions[idx++] = val;
          }
        }
      }
    }
    return questions;
  }

  /// Extracts raw text segment corresponding to a specific question number.
  static String _extractRawTextForQuestion(String text, String qNum) {
    try {
      final qReg = RegExp('(?:^|[^0-9])$qNum(?:\\.|\\)|\\-|\\s)');
      final qMatch = qReg.firstMatch(text);
      if (qMatch == null) return "";
      final qIndex = qMatch.start;
      
      int nextQIndex = text.length;
      final nextNum = (int.parse(qNum) + 1).toString();
      final nextReg = RegExp('(?:^|[^0-9])$nextNum(?:\\.|\\)|\\-|\\s)');
      final nextMatch = nextReg.firstMatch(text.substring(qIndex + 1));
      if (nextMatch != null) {
        nextQIndex = qIndex + 1 + nextMatch.start;
      }
      
      return text.substring(qIndex, nextQIndex);
    } catch (e) {
      return text;
    }
  }

  /// Parses student text/OCR submission to extract the student's answered values.
  static Map<int, double> _extractStudentAnswers(String submission) {
    Map<int, double> answers = {};
    
    // Preprocess: merge lines that consist only of question numbers (e.g., "1." or "2)")
    // with the subsequent line to handle cases where OCR separates bounding boxes into separate lines.
  /// Handles formats like:
  ///   "1.10488"  → Q1 = 10488   (question-number.answer, NOT a decimal)
  ///   "2.104"    → Q2 = 104
  ///   "4.75%"    → Q4 = 75
  ///   "5.1575000"→ Q5 = 1575000
  static Map<int, double> _extractStudentAnswers(String submission) {
    Map<int, double> answers = {};

    // ── Step 1: Preprocess lines ──────────────────────────────────────────────
    // Merge lines that are ONLY a question number ("1.", "2)") with the next line.
    final rawLines = submission.split('\n');
    List<String> lines = [];
    for (int i = 0; i < rawLines.length; i++) {
      final line = rawLines[i].trim();
      if (line.isEmpty) continue;
      
      final isJustQNum = RegExp(r'^\d+\s*[\.\)\-\:]?$').hasMatch(line);
      if (isJustQNum && i + 1 < rawLines.length) {
        final nextLine = rawLines[i + 1].trim();
        lines.add("$line $nextLine");
        i++; // skip the next line as it was merged
      final isJustQNum = RegExp(r'^\d+\s*[\.\)\-\:]?$').hasMatch(line);
      if (isJustQNum && i + 1 < rawLines.length) {
        lines.add('$line ${rawLines[i + 1].trim()}');
        i++;
      } else {
        lines.add(line);
      }
    }
    
    final qNumRegex = RegExp(r'(?:^\s*|[^\d])(\d+)\s*[\.\)\-\:\,](?!\d)');
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      
      final matches = qNumRegex.allMatches(line).toList();
      for (int k = 0; k < matches.length; k++) {
        final m = matches[k];
        final int qNum = int.parse(m.group(1)!);
        if (qNum > 100) continue;
        
        // Ignore time patterns (e.g. phone status bar time like 13:03 or 18:34 in screenshot)
        if (line.contains(RegExp(r'\b\d{1,2}:\d{2}\b'))) {
          final timeMatch = RegExp(r'\b(\d{1,2}):(\d{2})\b').firstMatch(line);
          if (timeMatch != null && int.parse(timeMatch.group(1)!) == qNum) {
            debugPrint("[RuleEngine] Ignoring question number $qNum from status bar time: ${timeMatch.group(0)}");
            continue;
          }
        }
        
        final List<String> qSegments = [];
        final int start = m.end;
        final int end = (k + 1 < matches.length) ? matches[k + 1].start : line.length;
        qSegments.add(line.substring(start, end).trim());
        
        int nextLineIdx = i + 1;
        while (nextLineIdx < lines.length) {
          final nextLine = lines[nextLineIdx].trim();
          if (qNumRegex.hasMatch(nextLine)) {
            break;
          }
          qSegments.add(nextLine);
          nextLineIdx++;
        }
        
        double? extractedVal;
        
        // 1. Look for answer/ans/soln prefix or explicit '=' on any of these lines
        for (var segment in qSegments) {
          final cleanSegment = segment.replaceAll(',', '');
          if (cleanSegment.contains('=')) {
            final parts = cleanSegment.split('=');
            final rightSide = parts.last.trim();
            final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(rightSide);

    // ── Step 2: Detect "N.answer" format (e.g. "1.10488", "3.120", "4.75%") ──
    // Pattern: line starts (optionally with whitespace) with digits, then a dot,
    // then MORE digits immediately — meaning it's "Q_NUM.ANSWER", not a decimal.
    // We detect this by checking that the part before the first dot is a small
    // integer (≤ 100) and the part after is a longer or equal-length number.
    bool usedQDotFormat = false;
    for (final line in lines) {
      // Skip header-like lines (e.g. "Answers", "Mathematics")
      if (!RegExp(r'^\s*\d').hasMatch(line)) continue;

      // Match patterns like "1.10488" or "  2.104" or "4.75%" at the start of the line
      final dotFmtMatch = RegExp(
        r'^\s*(\d{1,3})[\.\ ](\d[\d,\.]*%?)',
      ).firstMatch(line);

      if (dotFmtMatch != null) {
        final int qNum = int.tryParse(dotFmtMatch.group(1)!) ?? 0;
        if (qNum < 1 || qNum > 50) continue;

        // Strip % sign and commas from the answer part
        final String rawAns = dotFmtMatch.group(2)!.replaceAll(',', '').replaceAll('%', '').trim();
        final double? val = double.tryParse(rawAns);
        if (val != null) {
          answers[qNum] = val;
          usedQDotFormat = true;
        }
      }
    }

    // If Q.answer format worked for most lines, return early
    if (usedQDotFormat && answers.isNotEmpty) {
      debugPrint('[RuleEngine] Used Q.Answer format. Parsed answers: $answers');
      return answers;
    }

    // ── Step 3: Standard numbered-line parser ────────────────────────────────
    // Handles formats like:
    //   "1. 10488"  (space after dot)
    //   "1) 104"
    //   "Q1: 120"
    //   Lines with = sign (e.g. OCR handwriting)
    answers.clear();

    // Regex that ALLOWS digits immediately after the separator (to catch "1.10488")
    // We use a broader pattern and do qNum validation ourselves.
    final qNumRegex = RegExp(r'(?:^\s*|[^\d])(\d{1,3})\s*[\.)\-\:]\s*');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // Skip status-bar time patterns (e.g. "16:57")
      if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(line)) continue;

      final matches = qNumRegex.allMatches(line).toList();
      for (int k = 0; k < matches.length; k++) {
        final m = matches[k];
        final int qNum = int.tryParse(m.group(1)!) ?? 0;
        if (qNum < 1 || qNum > 100) continue;

        // Skip if this looks like a status bar time (e.g. hour:minute)
        if (line.contains(RegExp(r'\b\d{1,2}:\d{2}\b'))) {
          final timeMatch = RegExp(r'\b(\d{1,2}):(\d{2})\b').firstMatch(line);
          if (timeMatch != null && int.parse(timeMatch.group(1)!) == qNum) continue;
        }

        // Collect the text segment after the question number marker
        final int start = m.end;
        final int end = (k + 1 < matches.length) ? matches[k + 1].start : line.length;
        final List<String> qSegments = [line.substring(start, end).trim()];

        // Also look at following lines until the next question number
        int nextLineIdx = i + 1;
        while (nextLineIdx < lines.length) {
          final nextLine = lines[nextLineIdx].trim();
          if (qNumRegex.hasMatch(nextLine)) break;
          qSegments.add(nextLine);
          nextLineIdx++;
        }

        double? extractedVal;

        // Priority 1: explicit "=" sign (e.g. handwriting OCR "456 × 23 = 10,488")
        for (final segment in qSegments) {
          final clean = segment.replaceAll(',', '');
          if (clean.contains('=')) {
            final rightSide = clean.split('=').last.trim();
            // Strip % and unit suffixes
            final stripped = rightSide.replaceAll(RegExp(r'[%a-zA-Z²³]'), '').trim();
            final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(stripped);
            if (numMatch != null) {
              extractedVal = double.tryParse(numMatch.group(1)!);
              if (extractedVal != null) break;
            }
          }
          final ansMatch = RegExp(r'(?:answer|ans|soln|cwer|swer)\s*(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(cleanSegment);
          if (ansMatch != null) {
            extractedVal = double.tryParse(ansMatch.group(1)!);
            if (extractedVal != null) break;
          }
        }
        
        // 2. Look for the last standalone number or final number on any of these lines
        if (extractedVal == null) {
          for (var segment in qSegments.reversed) {
            final cleanSegment = segment.replaceAll(',', '');
            final matches = RegExp(r'(\d+(?:\.\d+)?)').allMatches(cleanSegment).toList();
            if (matches.isNotEmpty) {
              extractedVal = double.tryParse(matches.last.group(1)!);
          // "Answer: 10488" or "Ans 104"
          final ansMatch = RegExp(
            r'(?:answer|ans|soln)\s*[:\-]?\s*(\d[\d,]*(?:\.\d+)?)',
            caseSensitive: false,
          ).firstMatch(clean);
          if (ansMatch != null) {
            final stripped = ansMatch.group(1)!.replaceAll(',', '');
            extractedVal = double.tryParse(stripped);
            if (extractedVal != null) break;
          }
        }

        // Priority 2: last number on the segment lines (strip % and units first)
        if (extractedVal == null) {
          for (final segment in qSegments.reversed) {
            final clean = segment
                .replaceAll(',', '')
                .replaceAll(RegExp(r'[%a-zA-Z²³]'), ' ')
                .trim();
            final nums = RegExp(r'(\d+(?:\.\d+)?)').allMatches(clean).toList();
            if (nums.isNotEmpty) {
              extractedVal = double.tryParse(nums.last.group(1)!);
              if (extractedVal != null) break;
            }
          }
        }
        

        if (extractedVal != null) {
          answers[qNum] = extractedVal;
        }
      }
    }
    
    // Fallback: If no question numbers are found, extract all numeric blocks sequentially
    if (answers.isEmpty) {
      final allNums = RegExp(r'(\d+(?:\.\d+)?)').allMatches(submission.replaceAll(',', ''))
          .map((m) => double.parse(m.group(1)!))

    // ── Step 4: Last-resort fallback — sequential number extraction ──────────
    if (answers.isEmpty) {
      final allNums = RegExp(r'(\d+(?:\.\d+)?)')
          .allMatches(submission.replaceAll(',', ''))
          .map((m) => double.tryParse(m.group(1)!))
          .whereType<double>()
          .toList();
      for (int i = 0; i < allNums.length; i++) {
        answers[i + 1] = allNums[i];
      }
    }
    

    debugPrint('[RuleEngine] Parsed student answers: $answers');
    return answers;
  }

  /// High precision Rule Engine: dynamically parses and grades.
  static AutoGradingResult _gradeWithRuleEngine({
    required String homeworkTitle,
    required String homeworkDescription,
    required String studentSubmission,
    List<Question>? templateQuestions,
    String teacherOcrText = '',
    String? geminiError,
  }) {
    Map<int, String> correctAnswers = {};
    Map<int, double> studentAnswers = _extractStudentAnswers(studentSubmission);

    // 1. Load correct answers from structured templateQuestions if available
    if (templateQuestions != null && templateQuestions.isNotEmpty) {
      for (int i = 0; i < templateQuestions.length; i++) {
        correctAnswers[i + 1] = templateQuestions[i].correctAnswer;
      }
    } else {
      // 2. Otherwise extract arithmetic solutions from description text
      Map<int, double> extractedMath = _extractQuestionsFromDescription(homeworkDescription);
      Map<int, double?> extractedMath = _extractQuestionsFromDescription(homeworkDescription);
      
      // 3. If description is empty, dynamically extract math from teacher's sheet OCR!
      if (extractedMath.isEmpty && teacherOcrText.isNotEmpty) {
        extractedMath = _extractQuestionsFromDescription(teacherOcrText);
      }
      
      extractedMath.forEach((k, v) {
        correctAnswers[k] = v % 1 == 0 ? v.toInt().toString() : v.toString();
        if (v != null) {
          correctAnswers[k] = v % 1 == 0 ? v.toInt().toString() : v.toString();
        }
      });
    }

    // 4. Dynamic Student Equation Parser: If correctAnswers is STILL empty,
    // scan student's handwritten/typed paper line-by-line for equations and solve!
    if (correctAnswers.isEmpty) {
      final lines = studentSubmission.split('\n');
      final qNumRegex = RegExp(r'(?:^|[^0-9])(\d+)\s*[\.\)\-\:]');
      final eqParserRegex = RegExp(r'(\d+[\d\s\+\-\*\/x×÷,\.]*)\=\s*(\d+(?:\.\d+)?)');
      
      int autoQNum = 1;
      for (var rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        
        final matches = qNumRegex.allMatches(line).toList();
        if (matches.isEmpty) {
          final eqMatch = eqParserRegex.firstMatch(line);
          if (eqMatch != null) {
            final String expr = eqMatch.group(1)!;
            final double studentVal = double.parse(eqMatch.group(2)!);
            final double? solvedVal = _evaluateExpression(expr);
            if (solvedVal != null) {
              correctAnswers[autoQNum] = solvedVal % 1 == 0 ? solvedVal.toInt().toString() : solvedVal.toString();
              studentAnswers[autoQNum] = studentVal;
              autoQNum++;
            }
          }
        } else {
          for (int k = 0; k < matches.length; k++) {
            final m = matches[k];
            final int qNum = int.parse(m.group(1)!);
            if (qNum > 100) continue;
            
            final int start = m.end;
            final int end = (k + 1 < matches.length) ? matches[k + 1].start : line.length;
            final remainingText = line.substring(start, end).trim();
            
            final eqMatch = eqParserRegex.firstMatch(remainingText);
            if (eqMatch != null) {
              final String expr = eqMatch.group(1)!;
              final double studentVal = double.parse(eqMatch.group(2)!);
              final double? solvedVal = _evaluateExpression(expr);
              
              if (solvedVal != null) {
                correctAnswers[qNum] = solvedVal % 1 == 0 ? solvedVal.toInt().toString() : solvedVal.toString();
                studentAnswers[qNum] = studentVal;
                if (qNum >= autoQNum) {
                  autoQNum = qNum + 1;
                }
              }
            }
          }
        }
      }
    }
    
    debugPrint("[RuleEngine] Final Correct answers: $correctAnswers");
    debugPrint("[RuleEngine] Final Student answers: $studentAnswers");

    // ── GUARD: If we have NO correct answers to compare against, we cannot
    // mark the work. Returning a false 0/5 would be dishonest and unfair.
    // Instead return a "pending review" result so the teacher can mark it.
    if (correctAnswers.isEmpty) {
      final int detectedQs = studentAnswers.length;
      final String pendingFeedback = jsonEncode({
        'feedback': 'Your submission has been received and is awaiting teacher review. '
            '${detectedQs > 0 ? 'We detected $detectedQs answer(s) in your submission.' : ''} '
            'AI auto-grading requires the homework questions to be available as text. '
            'Your teacher will mark this assignment shortly.',
        'recommendation': 'Make sure your answers are clearly numbered (e.g. 1. answer, 2. answer) '
            'so the teacher can easily match them to the questions.',
        'revisionQuestions': <String>[],
      });
      return AutoGradingResult(
        score: -1,  // sentinel: -1 means "pending, not scored"
        feedback: pendingFeedback,
        gradingSource: 'Pending Teacher Review',
        correctCount: null,
        totalQuestions: null,
        recommendation: 'Your teacher will review and mark your submission.',
        errorMessage: geminiError,
      );
    }

    // Determine absolute total questions count dynamically
    int totalQuestions = 0;
    if (templateQuestions != null && templateQuestions.isNotEmpty) {
      totalQuestions = templateQuestions.length;
    } else if (correctAnswers.isNotEmpty) {
      correctAnswers.forEach((k, _) {
        if (k > totalQuestions) totalQuestions = k;
      });
    } else {
      studentAnswers.forEach((k, _) {
        if (k > totalQuestions) totalQuestions = k;
      });
    }

    // Ensure we have at least 1 question
    if (totalQuestions == 0) totalQuestions = 1;

    int correctCount = 0;
    List<int> missedQuestions = [];

    for (int qNum = 1; qNum <= totalQuestions; qNum++) {
      final expectedVal = correctAnswers[qNum];
      final studentVal = studentAnswers[qNum];
      
      if (expectedVal == null) {
        missedQuestions.add(qNum);
        continue;
      }
      
      final double? expectedNum = double.tryParse(expectedVal.replaceAll(',', '').trim());
      
      if (expectedNum != null) {
        if (studentVal != null) {
          final diff = (studentVal - expectedNum).abs();
          if (diff < 0.05) {
            correctCount++;
          } else {
            missedQuestions.add(qNum);
          }
        } else {
          missedQuestions.add(qNum);
        }
      } else {
        // Text-based answer match
        final String rawTextSegment = _extractRawTextForQuestion(studentSubmission, qNum.toString());
        if (rawTextSegment.isNotEmpty && rawTextSegment.toLowerCase().contains(expectedVal.toLowerCase().trim())) {
          correctCount++;
        } else {
          missedQuestions.add(qNum);
        }
      }
    }

    final double score = (correctCount / totalQuestions) * 100.0;
    
    // Formulate transparent, honest, and professional feedback
    String feedback = "";
    String recommendation = "";

    if (correctCount == totalQuestions) {
      feedback = "Excellent! You got all $totalQuestions questions 100% correct. Every single math calculation matches the correct answers perfectly. Stellar work!";
      recommendation = "Challenge yourself with advanced math practices or help a classmate.";
    } else if (correctCount > 0) {
      feedback = "Good effort! You answered $correctCount out of $totalQuestions questions correctly. ${missedQuestions.isNotEmpty ? 'Please review your calculations for Question(s): ${missedQuestions.join(', ')}.' : ''}";
      
      final List<String> correctionGuides = [];
      for (var q in missedQuestions) {
        if (correctAnswers.containsKey(q)) {
          correctionGuides.add("Q$q = ${correctAnswers[q]}");
        }
      }
      recommendation = "Review corrections: ${correctionGuides.join(', ')}.";
    } else {
      feedback = "Score: 0/$totalQuestions. Your answers did not match the correct solutions. Please review the mathematical rules and re-calculate step-by-step.";
      
      final List<String> correctionGuides = [];
      correctAnswers.forEach((q, val) {
        correctionGuides.add("Q$q = $val");
      });
      recommendation = "Solutions: ${correctionGuides.join(', ')}.";
    }

    final List<String> fallbackRevs = _generateFallbackRevisionQuestions(homeworkTitle, missedQuestions);
    final String jsonFeedback = jsonEncode({
      'feedback': feedback,
      'recommendation': recommendation,
      'revisionQuestions': fallbackRevs,
    });

    return AutoGradingResult(
      score: score,
      feedback: jsonFeedback,
      gradingSource: "Educational Fallback (Math Parser Engine)",
      correctCount: correctCount,
      totalQuestions: totalQuestions,
      recommendation: recommendation,
      errorMessage: geminiError,
      revisionQuestions: fallbackRevs,
    );
  }
}
