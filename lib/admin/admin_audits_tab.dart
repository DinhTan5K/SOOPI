import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/admin_api_service.dart';

class AdminAuditsTab extends StatefulWidget {
  const AdminAuditsTab({super.key, required this.api});
  final AdminApiService api;

  @override
  State<AdminAuditsTab> createState() => _AdminAuditsTabState();
}

class _AdminAuditsTabState extends State<AdminAuditsTab> {
  bool _loading = true;
  String? _error;
  List<dynamic> _audits = [];
  final int _page = 1;
  static const int _pageSize = 30;
  String? _filterType; // null, 'Restaurant', 'User'

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.api.getAudits(
        targetType: _filterType,
        page: _page,
        pageSize: _pageSize,
      );

      if (!mounted) return;
      setState(() {
        _audits = res['items'] as List<dynamic>? ?? [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.white,
          child: Row(
            children: [
              const Text('Lọc đối tượng: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Tất cả'),
                selected: _filterType == null,
                onSelected: (_) {
                  setState(() => _filterType = null);
                  _fetch();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Quán ăn'),
                selected: _filterType == 'Restaurant',
                onSelected: (_) {
                  setState(() => _filterType = 'Restaurant');
                  _fetch();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Người dùng'),
                selected: _filterType == 'User',
                onSelected: (_) {
                  setState(() => _filterType = 'User');
                  _fetch();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Colors.deepOrange))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Lỗi: $_error', style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 8),
                          ElevatedButton(onPressed: _fetch, child: const Text('Thử lại')),
                        ],
                      ),
                    )
                  : _audits.isEmpty
                      ? const Center(child: Text('Chưa có lịch sử thao tác nào.', style: TextStyle(color: Colors.grey)))
                      : RefreshIndicator(
                          onRefresh: _fetch,
                          color: Colors.deepOrange,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _audits.length,
                            itemBuilder: (ctx, index) {
                              final a = _audits[index];
                              final action = a['action'] ?? '';
                              final type = a['targetType'] ?? 'Restaurant';
                              final reason = a['reason'] ?? '';
                              final time = a['createdAt'] ?? '';

                              Color badgeColor = Colors.blue;
                              if (action.contains('Approved')) badgeColor = Colors.green;
                              if (action.contains('Rejected') || action.contains('Locked')) badgeColor = Colors.red;
                              if (action.contains('Unlocked')) badgeColor = Colors.teal;

                              String formattedTime = time;
                              final parsedDate = DateTime.tryParse(time);
                              if (parsedDate != null) {
                                formattedTime = DateFormat('dd/MM/yyyy HH:mm').format(parsedDate.toLocal());
                              }

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0.5,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: badgeColor.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              action,
                                              style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                          ),
                                          Text(type == 'Restaurant' ? 'Quán ăn' : 'Tài khoản',
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                      if (reason.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text('Lý do: "$reason"', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                                      ],
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Mục tiêu: ${a['targetId'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                          Text(formattedTime, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}
