import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              _buildTitle(),
              _buildSearchBar(),
              _buildBanner(),
              _buildCategories(),
              _buildPopularItems(),
              const SizedBox(height: 40), // Space for bottom nav padding
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: Colors.orange,
        shape: const CircleBorder(),
        child: const Icon(Icons.shopping_cart, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Giao đến',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              Row(
                children: [
                  Icon(Icons.location_on, color: Colors.orange, size: 20),
                  SizedBox(width: 4),
                  Text(
                    'Hà Nội, VN',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
            ],
          ),
          CircleAvatar(
            backgroundColor: Colors.orange.shade200,
            radius: 22,
            child: const CircleAvatar(
              radius: 20,
              backgroundImage: NetworkImage('https://ui-avatars.com/api/?name=User&background=random'),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: const TextSpan(
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: -1),
              children: [
                TextSpan(text: 'SOOPI '),
                TextSpan(text: 'FOOD', style: TextStyle(color: Colors.orange)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Hôm nay bạn muốn ăn gì?',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search, color: Colors.grey),
                  SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Tìm kiếm món ăn, nhà hàng...',
                        hintStyle: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            height: 50,
            width: 50,
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.tune, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Colors.orange, Colors.amber],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            )
          ]
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Khuyến mãi', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Giảm giá 50%\ncho đơn đầu tiên',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, height: 1.2),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.orange,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      minimumSize: Size.zero,
                    ),
                    child: const Text('Đặt ngay', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const Text('🍔', style: TextStyle(fontSize: 60)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategories() {
    final categories = [
      {'icon': '🍔', 'name': 'Burger', 'color': Colors.orange.shade100, 'borderColor': Colors.orange.shade200},
      {'icon': '🍕', 'name': 'Pizza', 'color': Colors.grey.shade100, 'borderColor': Colors.grey.shade200},
      {'icon': '🍣', 'name': 'Sushi', 'color': Colors.grey.shade100, 'borderColor': Colors.grey.shade200},
      {'icon': '🥤', 'name': 'Đồ uống', 'color': Colors.grey.shade100, 'borderColor': Colors.grey.shade200},
      {'icon': '🥗', 'name': 'Healthy', 'color': Colors.grey.shade100, 'borderColor': Colors.grey.shade200},
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Danh mục', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Text('Xem tất cả', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    Container(
                      width: 65,
                      height: 65,
                      decoration: BoxDecoration(
                        color: categories[index]['color'] as Color,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: categories[index]['borderColor'] as Color),
                      ),
                      child: Center(
                        child: Text(categories[index]['icon'] as String, style: const TextStyle(fontSize: 30)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      categories[index]['name'] as String,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: index == 0 ? FontWeight.bold : FontWeight.w500,
                        color: index == 0 ? Colors.black : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPopularItems() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Phổ biến nhất', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Text('Xem thêm', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          _buildFoodItem('🍔', 'Double Cheese Burger', 'Soopi Burger Fastfood', '4.8', '(124+)', '65.000đ', Colors.orange.shade50),
          const SizedBox(height: 16),
          _buildFoodItem('🍕', 'Pepperoni Pizza', 'Italiano Pizza House', '4.6', '(89+)', '120.000đ', Colors.yellow.shade50),
        ],
      ),
    );
  }

  Widget _buildFoodItem(String emoji, String name, String restaurant, String rating, String reviews, String price, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 45))),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                    const Icon(Icons.favorite_border, color: Colors.grey, size: 20),
                  ],
                ),
                const SizedBox(height: 4),
                Text(restaurant, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    const SizedBox(width: 4),
                    Text(rating, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(width: 4),
                    Text(reviews, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(price, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16)),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8.0,
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildNavItem(Icons.home, 'Trang chủ', 0),
            _buildNavItem(Icons.receipt_long, 'Đơn hàng', 1),
            const SizedBox(width: 48), // Space for FAB
            _buildNavItem(Icons.favorite_border, 'Yêu thích', 2),
            _buildNavItem(Icons.person_outline, 'Tài khoản', 3),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    bool isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? Colors.orange : Colors.grey, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.orange : Colors.grey,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
