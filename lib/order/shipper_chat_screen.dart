import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'order_data.dart';

class ChatMessage {
  final String text;
  final bool isMe;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isMe,
    required this.timestamp,
  });
}

class ShipperChatScreen extends StatefulWidget {
  final OrderModel order;
  final ShipperInfo shipper;

  const ShipperChatScreen({
    super.key,
    required this.order,
    required this.shipper,
  });

  @override
  State<ShipperChatScreen> createState() => _ShipperChatScreenState();
}

class _ShipperChatScreenState extends State<ShipperChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  final List<String> _quickReplies = [
    'Đến nơi gọi mình nhé 📞',
    'Cho mình xin thêm đũa & thìa 🥢',
    'Cho mình xin thêm tương ớt 🌶️',
    'Để ở bàn bảo vệ giúp mình 🏢',
    'Mình đang đợi ở sảnh nhé 🚪',
    'Tài xế đi đường cẩn thận nhé 🛵',
  ];

  @override
  void initState() {
    super.initState();
    // Khởi tạo lời chào mở đầu từ tài xế
    _messages.add(
      ChatMessage(
        text: 'Chào bạn! Tôi là ${widget.shipper.name}, tài xế nhận giao đơn #${widget.order.id}.',
        isMe: false,
        timestamp: DateTime.now().subtract(const Duration(minutes: 3)),
      ),
    );
    _messages.add(
      ChatMessage(
        text: 'Tôi đang di chuyển đến quán lấy món. Bạn có dặn dò gì thêm cứ nhắn cho tôi nhé!',
        isMe: false,
        timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _makePhoneCall() async {
    final rawPhone = widget.shipper.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$rawPhone');
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể mở ứng dụng cuộc gọi cho số $rawPhone'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi gọi điện: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _sendSms() async {
    final rawPhone = widget.shipper.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('sms:$rawPhone');
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể mở ứng dụng tin nhắn SMS cho số $rawPhone'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi mở SMS: $e'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    }
  }

  void _sendMessage([String? customText]) {
    final content = (customText ?? _textController.text).trim();
    if (content.isEmpty) return;

    if (customText == null) {
      _textController.clear();
    }

    setState(() {
      _messages.add(
        ChatMessage(
          text: content,
          isMe: true,
          timestamp: DateTime.now(),
        ),
      );
    });
    _scrollToBottom();

    // Mô phỏng tài xế phản hồi tự động sau 1.2s
    Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;

      String reply;
      final lower = content.toLowerCase();

      if (lower.contains('gọi') || lower.contains('đến') || lower.contains('tới')) {
        reply = 'Dạ vâng bạn yên tâm, khi tới nơi tôi sẽ gọi điện báo bạn ngay ạ!';
      } else if (lower.contains('đũa') || lower.contains('thìa') || lower.contains('muỗng')) {
        reply = 'Dạ tôi đã dặn quán bỏ thêm đũa thìa đầy đủ cho bạn rồi nhé!';
      } else if (lower.contains('ớt') || lower.contains('tương') || lower.contains('nước sốt')) {
        reply = 'Dạ vâng, tôi đã xin thêm tương ớt và gia vị cho bạn rồi ạ.';
      } else if (lower.contains('cửa') || lower.contains('cổng') || lower.contains('bảo vệ')) {
        reply = 'Dạ tôi nhớ rồi, tôi sẽ giao đúng chỗ bạn dặn.';
      } else if (lower.contains('cẩn thận') || lower.contains('cảm ơn') || lower.contains('cam on')) {
        reply = 'Cảm ơn bạn nhiều nhé! Tôi đang giao tới đây ạ.';
      } else {
        reply = 'Dạ vâng tôi đã nhận được tin nhắn! Tôi đang trên đường giao đơn #${widget.order.id} tới bạn.';
      }

      setState(() {
        _messages.add(
          ChatMessage(
            text: reply,
            isMe: false,
            timestamp: DateTime.now(),
          ),
        );
      });
      _scrollToBottom();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: NetworkImage(widget.shipper.avatarUrl),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.shipper.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.star, color: Colors.amber, size: 14),
                      Text(
                        '${widget.shipper.rating}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
                      ),
                    ],
                  ),
                  Text(
                    '${widget.shipper.bikeType} • ${widget.shipper.bikePlate}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Gửi SMS',
            icon: const Icon(Icons.sms_outlined, color: Colors.black87, size: 22),
            onPressed: _sendSms,
          ),
          IconButton(
            tooltip: 'Gọi điện',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.phone, color: Colors.green, size: 18),
            ),
            onPressed: _makePhoneCall,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Thanh tóm tắt đơn hàng ghim trên cùng
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.orange.shade50,
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Đơn #${widget.order.id} • ${widget.order.restaurantName}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.deepOrange,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    money(widget.order.totalPrice),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrange,
                    ),
                  ),
                ],
              ),
            ),

            // Danh sách tin nhắn
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return _buildMessageBubble(msg);
                },
              ),
            ),

            // Danh sách tin nhắn nhanh (Quick Replies)
            Container(
              height: 40,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _quickReplies.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final quickText = _quickReplies[index];
                  return ActionChip(
                    backgroundColor: Colors.white,
                    side: BorderSide(color: Colors.orange.shade200),
                    label: Text(
                      quickText,
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    onPressed: () => _sendMessage(quickText),
                  );
                },
              ),
            ),

            // Khung nhập tin nhắn
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    offset: const Offset(0, -2),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F3F5),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _textController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: const InputDecoration(
                          hintText: 'Nhập tin nhắn cho tài xế...',
                          hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.orange,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _sendMessage(),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final timeStr =
        '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: msg.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!msg.isMe) ...[
            CircleAvatar(
              radius: 14,
              backgroundImage: NetworkImage(widget.shipper.avatarUrl),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: msg.isMe ? Colors.orange : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(msg.isMe ? 16 : 4),
                  bottomRight: Radius.circular(msg.isMe ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.text,
                    style: TextStyle(
                      fontSize: 14,
                      color: msg.isMe ? Colors.white : Colors.black87,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 10,
                      color: msg.isMe ? Colors.white70 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (msg.isMe) ...[
            const SizedBox(width: 4),
            const Icon(Icons.done_all, size: 14, color: Colors.orange),
          ],
        ],
      ),
    );
  }
}
