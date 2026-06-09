# Bootstrap Server cho PeerBuzz

Bootstrap Server đóng vai trò là trung tâm liên lạc ban đầu (rendezvous server) cho ứng dụng PeerBuzz. Nó giúp các peer tìm thấy nhau và kết nối trực tiếp (P2P) thay vì phải đi qua server.

## Tính năng

- **Gia nhập mạng (JOIN)**: Khi một peer mới tham gia, nó gửi thông tin (IP, Port) đến bootstrap server.
- **Cập nhật danh sách (UPDATE_LIST)**: Server lưu trữ danh sách các peer đang hoạt động và định kỳ gửi cập nhật cho các client để chúng biết địa chỉ của nhau.
- **Gossip**:
    - **Flood Gossip**: Gửi tin nhắn đến tất cả các peer khác.
    - **Push-Pull Gossip**: Định kỳ kết nối với một peer ngẫu nhiên để trao đổi tin nhắn mới.
- **Hỗ trợ di chuyển (Direct Connect)**: Khi A không thể kết nối trực tiếp đến B (do NAT hoặc tường lửa), A yêu cầu bootstrap server cung cấp thông tin về một peer trung gian (relay) để giúp kết nối. Điều này có thể đạt được thông qua kỹ thuật UPnP hole punching (mặc dù implementation có thể đơn giản hóa cho mục đích demo).

## Yêu cầu

- **Dart SDK**: 3.0.0 trở lên
- **Packages**:
    - `args` - Xử lý tham số dòng lệnh
    - `uuid` - Sinh UUID

## Cài đặt

```bash
# Clone repository (nếu chưa có)
dart pub get
```

## Cách chạy

Để khởi động bootstrap server, sử dụng lệnh sau:

```bash
dart run bin/bootstrap_server.dart --port <số_cổng>
```

**Ví dụ:**

```bash
dart run bin/bootstrap_server.dart --port 3000
```

Bootstrap server sẽ bắt đầu lắng nghe kết nối trên cổng 3000 (hoặc cổng được chỉ định).

### Tham số dòng lệnh

| Tham số | Mô tả | Mặc định |
|---------|---------|----------|
| `--port` | Cổng để server lắng nghe | `3000` |

## Architecture

```
[Peer A] <-----> [Bootstrap Server (3000)] <-----> [Peer B]
   |                  ^      ^                        |
   |__________________|______|________________________|
      P2P Direct Connection (nếu có thể)
```

## Ghi chú quan trọng

- **IP Local**: Server sử dụng `InternetAddress.anyIPv4` để lắng nghe trên tất cả các interface (bao gồm cả WiFi và Ethernet). Điều này cho phép các peer trên cùng một mạng nội bộ kết nối đến server.
- **Không hỗ trợ UPnP**:
    - Để Peer A có thể gửi tin nhắn đến Peer B khi không có kết nối trực tiếp (cross-LAN), cần phải có kỹ thuật UPnP hole punching. 
    - Trong implementation hiện tại, phần UPnP chỉ là giả lập hoặc chưa được tích hợp hoàn chỉnh.
    - Hiện tại, server chủ yếu đóng vai trò là **Gossip Hub** (trung tâm trao đổi tin nhắn) và **Directory Service** (cung cấp danh sách peer).
