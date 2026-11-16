import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:baxton/features/klant_flow/authentication/auth_service/auth_service.dart';
import 'package:baxton/features/klant_flow/message_screen/models/message_model.dart';

class ChatWebSocketService {
  final String conversationId;
  final Function(MessageModel) onMessageReceived;
  final Function(bool) onConnectionChanged;

  IOWebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  bool _isConnected = false;
  bool _isDisposed = false;
  bool _isConnecting = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 3);
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  ChatWebSocketService({
    required this.conversationId,
    required this.onMessageReceived,
    required this.onConnectionChanged,
  });

  Future<void> connect() async {
    if (_isDisposed || _isConnecting || _isConnected) {
      debugPrint(
        '⚠️ Skipping WebSocket connection - disposed: $_isDisposed, connecting: $_isConnecting, connected: $_isConnected',
      );
      return;
    }

    _isConnecting = true;

    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('❌ No auth token for WebSocket');
        _isConnecting = false;
        return;
      }

      debugPrint('🔌 Connecting WebSocket for conversation: $conversationId');

      // Close existing connection if any
      await _closeConnection();

      // Create WebSocket connection using the same method as your working code
      final socket = await WebSocket.connect(
        'wss://freepik.softvenceomega.com/ts/chat',
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      );

      _channel = IOWebSocketChannel(socket);
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;

      debugPrint('✅ WebSocket connected for conversation: $conversationId');

      // Subscribe to conversation
      _channel!.sink.add(
        jsonEncode({
          "event": "subscribe_to_conversation",
          "data": {"conversationId": conversationId},
        }),
      );

      // Start heartbeat
      _startHeartbeat();

      // Listen to messages
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onDone: _handleDisconnection,
        onError: _handleError,
        cancelOnError: false,
      );

      // Notify connection change
      if (!_isDisposed) {
        onConnectionChanged(_isConnected);
      }
    } catch (e) {
      debugPrint('❌ WebSocket connection failed for $conversationId: $e');
      _isConnected = false;
      _isConnecting = false;

      if (!_isDisposed) {
        onConnectionChanged(_isConnected);
        _scheduleReconnect();
      }
    }
  }

  void _handleMessage(dynamic data) {
    if (_isDisposed) return;

    debugPrint('📥 WebSocket message received: $data');

    try {
      final decoded = jsonDecode(data);
      _handleIncomingMessage(decoded);
    } catch (e) {
      debugPrint('❌ Error decoding WebSocket message: $e');
    }
  }

  Future<String?> _getUserId() async {
    try {
      final String? userId = await AuthService.getUserId();
      return userId;
    } catch (e) {
      debugPrint('❌ [ConversationController] Failed to get userId: $e');
      return null;
    }
  }

  void _handleIncomingMessage(Map<String, dynamic> message) async {
    if (_isDisposed) return;

    final type = message['type'] ?? message['event'];
    final status = message['status'];

    debugPrint('🔍 Handling message type: $type, status: $status');

    // Handle subscription confirmation
    if (status == 'subscribed') {
      debugPrint('✅ Subscription confirmed for conversation: $conversationId');
      return;
    }

    // Handle ping/pong
    if (type == 'ping') {
      _channel?.sink.add(jsonEncode({"event": "pong"}));
      return;
    }
    if (type == 'pong') {
      debugPrint('💓 Pong received for: $conversationId');

      return;
    }

    // Handle new messages (add "create" type)
    if (type == 'create' ||
        type == 'new_message' ||
        type == 'message' ||
        type == 'message_created' ||
        message.containsKey('content') ||
        message.containsKey('conversationId')) {
      final payload = message['payload'] ?? message['data'] ?? message;
      final msgConversationId = payload['conversationId'];

      if (msgConversationId == conversationId) {
        final messageId = payload['id'];
        if (messageId != null) {
          try {
            final transformedMessage = await _transformToMessageModel(payload);
            onMessageReceived(transformedMessage);
            debugPrint(
              '✅ New message processed: ${transformedMessage.content}',
            );
          } catch (e) {
            debugPrint('❌ Error transforming message: $e');
          }
        }
      }
    }
  }

  Future<MessageModel> _transformToMessageModel(
    Map<String, dynamic> payload,
  ) async {
    // ✅ Your logged-in userId
    final currentUserId = await _getUserId();

    // ✅ Sender of this message
    final senderId = payload['userId'];

    // ✅ True if this message was sent by you
    final isSender = senderId == currentUserId;

    debugPrint('🔍 WebSocket isSender logic:');
    debugPrint('🔍 currentUserId: $currentUserId');
    debugPrint('🔍 senderId: $senderId');
    debugPrint('🔍 calculated isSender: $isSender');

    return MessageModel(
      id: payload['id'] ?? '',
      conversationId: payload['conversationId'] ?? conversationId,
      content: payload['content'] ?? '',
      createdAt:
          payload['createdAt'] != null
              ? DateTime.parse(payload['createdAt'])
              : DateTime.now(),
      updatedAt:
          payload['updatedAt'] != null
              ? DateTime.parse(payload['updatedAt'])
              : DateTime.now(),
      userId: senderId ?? '',
      file:
          payload['file'] != null ? FileModel.fromJson(payload['file']) : null,
      name: payload['name'] ?? 'User',
      senderProfilePic: payload['senderProfilePic'],
      isSender: isSender,
    );
  }

  void _handleError(error) {
    debugPrint('❌ WebSocket error for $conversationId: $error');
    _isConnected = false;
    _isConnecting = false;
    _stopHeartbeat();

    if (!_isDisposed) {
      onConnectionChanged(_isConnected);
      _scheduleReconnect();
    }
  }

  void _handleDisconnection() {
    debugPrint('🔌 WebSocket connection closed for: $conversationId');
    _isConnected = false;
    _isConnecting = false;
    _stopHeartbeat();

    if (!_isDisposed) {
      onConnectionChanged(_isConnected);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_isDisposed || _reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('🚫 Max reconnection attempts reached or service disposed');
      return;
    }

    _reconnectAttempts++;
    debugPrint(
      '🔄 Scheduling reconnection attempt $_reconnectAttempts/$_maxReconnectAttempts',
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (!_isDisposed) {
        connect();
      }
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      if (_isDisposed || !_isConnected || _channel == null) {
        timer.cancel();
        return;
      }

      try {
        _channel!.sink.add(jsonEncode({"event": "ping"}));
        debugPrint('💓 Heartbeat sent for: $conversationId');
      } catch (e) {
        debugPrint('❌ Heartbeat failed: $e');
        timer.cancel();
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> sendMessage(String content) async {
    if (_isDisposed || !_isConnected || _channel == null) {
      debugPrint('❌ Cannot send message: WebSocket not connected');
      return;
    }

    try {
      final message = jsonEncode({
        'event': 'send_message',
        'data': {
          'conversationId': conversationId,
          'content': content,
          'timestamp': DateTime.now().toIso8601String(),
        },
      });

      _channel!.sink.add(message);
      debugPrint('📤 Sent message via WebSocket');
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
    }
  }

  Future<void> _closeConnection() async {
    try {
      // Cancel timers
      _heartbeatTimer?.cancel();
      _reconnectTimer?.cancel();

      // Cancel subscription
      await _subscription?.cancel();
      _subscription = null;

      // Close WebSocket channel
      if (_channel != null) {
        try {
          // Use status.goingAway (1001) like in your working code
          await _channel!.sink.close(status.goingAway);
        } catch (e) {
          debugPrint('❌ Error closing WebSocket channel: $e');
          // Force close if normal close fails
          try {
            _channel!.sink.close();
          } catch (forceCloseError) {
            debugPrint('❌ Error force closing WebSocket: $forceCloseError');
          }
        }
        _channel = null;
      }

      _isConnected = false;
    } catch (e) {
      debugPrint('❌ Error in _closeConnection: $e');
    }
  }

  Future<void> dispose() async {
    if (_isDisposed) return;

    debugPrint('🗑️ Disposing ChatWebSocketService');
    _isDisposed = true;

    // Cancel all timers first
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _stopHeartbeat();

    // Close connection
    await _closeConnection();

    debugPrint('✅ ChatWebSocketService disposed');
  }

  // Getters
  bool get isConnected => _isConnected && !_isDisposed;
  bool get isDisposed => _isDisposed;
}
