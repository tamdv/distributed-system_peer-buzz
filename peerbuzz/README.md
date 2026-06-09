# PeerBuzz

PeerBuzz là một ứng dụng nhắn tin phi tập trung (Decentralized P2P Chat) đa nền tảng được xây dựng bằng Flutter. Ứng dụng áp dụng kiến trúc mạng lai (Hybrid P2P), trong đó các thiết bị (Peer) kết nối trực tiếp với nhau để nhắn tin và truyền file, đồng thời dựa vào một Bootstrap Server đơn giản để tìm kiếm và khám phá các Peer đang hoạt động (Peer Discovery).

## Tính năng nổi bật

- **Kiến trúc Hybrid P2P**: Trực tiếp kết nối TCP (Socket) giữa các thiết bị mà không cần máy chủ trung tâm để trung chuyển dữ liệu.
- **Mã hóa AES**: Dữ liệu tin nhắn được mã hóa an toàn ở mức ứng dụng trước khi gửi đi. Sử dụng Flutter Isolate (`compute`) để không làm ảnh hưởng đến hiệu năng UI.
- **Chat 1-1 & Nhóm (Broadcast)**: Gửi tin nhắn trực tiếp giữa hai máy hoặc quảng bá tin nhắn tới tất cả thành viên trong mạng.
- **Truyền File Tốc Độ Cao**: Chia nhỏ file (File Chunking) và truyền qua TCP theo thời gian thực. Hỗ trợ thanh tiến trình trực quan trên giao diện.
- **Store-and-forward (Lưu và Chuyển Tiếp)**: Tự động gửi nhờ tin nhắn qua một Peer trung gian nếu đích đến đang offline, đảm bảo tin nhắn không bị thất lạc.
- **Quản lý Trạng thái**: Cập nhật danh sách online/offline real-time, tích hợp Heartbeat và timeout để phát hiện Peer rớt mạng.

## Yêu cầu

- **Flutter SDK**: 3.0.0 trở lên
- Trọng tâm hỗ trợ nền tảng: macOS, Windows, Android, iOS.

## Cài đặt và Chạy

1. Khởi động **Bootstrap Server** (Xem thư mục `bootstrap_server`).
2. Cài đặt các thư viện phụ thuộc cho ứng dụng Flutter:
   ```bash
   flutter pub get
   ```
3. Chạy ứng dụng trên máy ảo hoặc thiết bị thực tế:
   ```bash
   flutter run
   ```

## Kiến trúc thư mục (Clean Architecture)

- `lib/core/`: Các hằng số, cấu hình, xử lý socket, đồng hồ Lamport, thuật toán mã hoá.
- `lib/data/`: Các dịch vụ (Services) như P2PService, quản lý trạng thái kết nối.
- `lib/presentation/`: Giao diện người dùng (Screens & Widgets).

## Cơ chế đồng bộ mạng

Sử dụng Socket `dart:io` và truyền tin JSON. Ứng dụng triển khai đa luồng thông qua `Stream`, `async/await`, và phần cứng thực sự `Isolates` cho các tác vụ tốn kém CPU (băm khối file, mã hóa).
