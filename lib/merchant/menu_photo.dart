import 'dart:convert';

import 'package:flutter/material.dart';

class MenuPhoto extends StatelessWidget {
  const MenuPhoto({super.key, required this.imageBase64, this.size = 64});
  final String? imageBase64;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget image = const Icon(Icons.lunch_dining, color: Colors.deepOrange);
    if (imageBase64 != null) {
      try {
        image = Image.memory(
          base64Decode(imageBase64!),
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, error, stackTrace) =>
              const Icon(Icons.broken_image_outlined, color: Colors.deepOrange),
        );
      } on FormatException {
        image = const Icon(
          Icons.broken_image_outlined,
          color: Colors.deepOrange,
        );
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFFFFEAD4),
        child: image,
      ),
    );
  }
}
