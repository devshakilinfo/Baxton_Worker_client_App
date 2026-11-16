// ignore: file_names
import 'dart:convert';
import 'dart:io';
import 'package:baxton/features/klant_flow/authentication/auth_service/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:web_socket_channel/io.dart';

class WChatListController extends GetxController {
  late IOWebSocketChannel channel;
  final RxBool isConnected = false.obs;
  final RxList<Map<String, dynamic>> chatList = <Map<String, dynamic>>[].obs;

  @override
  void onInit() {
    super.onInit();
    connectToChatListSocket();
  }

  Future<void> connectToChatListSocket() async {
    try {
      final token = await AuthService.getToken();
      final headers = {HttpHeaders.authorizationHeader: 'Bearer $token'};

      // ✅ Connect to the chat-list WebSocket
      final socket = await WebSocket.connect(
        'wss://freepik.softvenceomega.com/ts/chat-list',
        headers: headers,
      );

      channel = IOWebSocketChannel(socket);
      isConnected.value = true;
      debugPrint('✅ Connected to chat-list socket');

      // ✅ Send event after connection
      channel.sink.add(jsonEncode({"event": "get_chat_list"}));

      // ✅ Listen for responses
      channel.stream.listen(
        (data) {
          debugPrint('📥 Received: $data');
          try {
            final decoded = jsonDecode(data);
            if (decoded['type'] == 'chat_list') {
              final payload = decoded['payload'];
              chatList.value = List<Map<String, dynamic>>.from(payload);
            }
          } catch (e) {
            debugPrint('❌ JSON error: $e');
          }
        },
        onDone: () {
          isConnected.value = false;
          debugPrint('🔌 chat-list socket closed');
        },
        onError: (error) {
          isConnected.value = false;
          debugPrint('❗ chat-list error: $error');
        },
      );
    } catch (e) {
      debugPrint('❗ Connection error: $e');
    }
  }

  void closeSocket() {
    channel.sink.close();
    isConnected.value = false;
  }

  @override
  void onClose() {
    super.onClose();
    closeSocket();
  }
}
