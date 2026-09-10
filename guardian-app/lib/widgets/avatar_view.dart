import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

/// 头像展示：服务端存的是 base64 JPEG（设备级共享，DESIGN 5.4）
class AvatarView extends StatelessWidget {
  const AvatarView({super.key, required this.base64, this.size = 48});

  final String? base64;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bytes = _decode();
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFFE8EEFF),
        child: bytes == null
            ? Icon(Icons.person, size: size * 0.6, color: const Color(0xFF7C93CC))
            : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }

  Uint8List? _decode() {
    final raw = base64;
    if (raw == null || raw.isEmpty) return null;
    try {
      final clean = raw.startsWith('data:') ? raw.split(',').last : raw;
      return base64Decode(clean);
    } catch (_) {
      return null;
    }
  }
}

/// 拍照 / 相册 → 本地压缩为 128×128 JPEG → 返回 base64（DESIGN 5.4）
///
/// 服务端会校验解码后 ≤100KB；128px JPEG 通常 10~40KB，余量充足。
Future<String?> pickAndCompressAvatar(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('拍张照片'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('从相册选择'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('取消'),
            onTap: () => Navigator.pop(ctx),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;

  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1024,
    maxHeight: 1024,
    imageQuality: 92,
  );
  if (picked == null) return null;

  final raw = await File(picked.path).readAsBytes();
  final compressed = await FlutterImageCompress.compressWithList(
    raw,
    minWidth: 128,
    minHeight: 128,
    quality: 80,
    format: CompressFormat.jpeg,
  );
  return base64Encode(compressed);
}
