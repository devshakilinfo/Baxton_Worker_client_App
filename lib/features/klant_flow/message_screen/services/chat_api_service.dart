import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:baxton/features/klant_flow/authentication/auth_service/auth_service.dart';
import 'package:baxton/features/klant_flow/message_screen/models/message_model.dart';

class ChatApiService {
  static const String baseUrl = 'https://freepik.softvenceomega.com/ts';

  // Get messages for a conversation with proper pagination
  static Future<List<MessageModel>> getMessages({
    required String conversationId,
    int take = 20, // How many messages to fetch
    String? cursor, // UUID of the last message (for pagination)
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        throw Exception('No authentication token');
      }

      // Build URL based on pagination flow
      String url =
          '$baseUrl/chat/messages?take=$take&conversationId=$conversationId';

      // Add cursor only if we have one (for subsequent pages)
      if (cursor != null && cursor.isNotEmpty) {
        url += '&cursor=$cursor';
      }

      debugPrint('🔥 ===== API REQUEST =====');
      debugPrint('🔥 URL: $url');
      debugPrint('🔥 Conversation ID: $conversationId');
      debugPrint('🔥 Take: $take');
      debugPrint('🔥 Cursor: ${cursor ?? "null (first page)"}');
      debugPrint('🔥 Is First Page: ${cursor == null}');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $token',
          'accept': '*/*',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('🔥 ===== API RESPONSE =====');
      debugPrint('🔥 Status Code: ${response.statusCode}');
      debugPrint('🔥 Response Headers: ${response.headers}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        debugPrint('🔥 Response Success: ${responseData['success']}');
        debugPrint('🔥 Full Response: ${response.body}');

        if (responseData['success'] == true) {
          final List messagesJson = responseData['data'] ?? [];

          debugPrint('🔥 ===== MESSAGES DATA =====');
          debugPrint('🔥 Messages Count: ${messagesJson.length}');

          if (messagesJson.isEmpty) {
            debugPrint('🔥 ⚠️ No messages returned - end of pagination');
            return [];
          }

          // Log each message for debugging
          debugPrint('🔥 ===== MESSAGE DETAILS =====');
          for (int i = 0; i < messagesJson.length; i++) {
            final msgJson = messagesJson[i];
            debugPrint('🔥 Message [$i]:');
            debugPrint('   ID: ${msgJson['id']}');
            debugPrint('   Content: "${msgJson['content']}"');
            debugPrint('   CreatedAt: ${msgJson['createdAt']}');
            debugPrint('   UserId: ${msgJson['userId']}');
            debugPrint('   Name: ${msgJson['name']}');
            debugPrint('   IsSender: ${msgJson['isSender']}');
            if (msgJson['file'] != null) {
              debugPrint('   File URL: ${msgJson['file']['url']}');
            }
          }

          // Convert to MessageModel objects
          final messages =
              messagesJson.map((json) {
                return MessageModel.fromJson(json);
              }).toList();

          debugPrint('🔥 ===== PAGINATION INFO =====');
          debugPrint('🔥 Converted Messages Count: ${messages.length}');

          if (messages.isNotEmpty) {
            debugPrint(
              '🔥 First Message (newest): ID=${messages.first.id}, CreatedAt=${messages.first.createdAt}',
            );
            debugPrint(
              '🔥 Last Message (oldest): ID=${messages.last.id}, CreatedAt=${messages.last.createdAt}',
            );
            debugPrint('🔥 Next Cursor (for pagination): ${messages.last.id}');
          }

          return messages;
        } else {
          final errorMessage = responseData['message'] ?? 'Unknown error';
          debugPrint('🔥 ❌ API Error: $errorMessage');
          throw Exception('API Error: $errorMessage');
        }
      } else {
        debugPrint('🔥 ❌ HTTP Error: ${response.statusCode}');
        debugPrint('🔥 ❌ Error Body: ${response.body}');
        throw Exception('HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('🔥 ❌ Exception in getMessages: $e');
      debugPrint('🔥 ❌ Exception Type: ${e.runtimeType}');
      rethrow;
    }
  }

  // Send a message
  static Future<MessageModel> sendMessage({
    required String conversationId,
    required String content,
    File? file,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        throw Exception('No authentication token');
      }

      final uri = Uri.parse('$baseUrl/chat/create-message');
      final request = http.MultipartRequest('POST', uri);

      request.headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      request.headers['accept'] = '*/*';

      request.fields['content'] = content;
      request.fields['conversationId'] = conversationId;

      if (file != null) {
        final multipartFile = await http.MultipartFile.fromPath(
          'file',
          file.path,
        );
        request.files.add(multipartFile);
      } else {
        request.fields['file'] = '';
      }

      debugPrint('🔥 ===== SENDING MESSAGE =====');
      debugPrint('🔥 Content: "$content"');
      debugPrint('🔥 Conversation ID: $conversationId');
      debugPrint('🔥 Has File: ${file != null}');

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('🔥 ===== SEND RESPONSE =====');
      debugPrint('🔥 Status: ${response.statusCode}');
      debugPrint('🔥 Body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        if (responseData['success'] == true) {
          final messageData = responseData['data'];

          return MessageModel.fromJson({
            ...messageData,
            'isSender': true,
            'name': 'You',
          });
        } else {
          throw Exception('Send failed: ${responseData['message']}');
        }
      } else {
        throw Exception('HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('🔥 ❌ Send message exception: $e');
      rethrow;
    }
  }
}
