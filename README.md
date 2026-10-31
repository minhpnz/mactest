# Kiểm tra MacBook cũ trước khi mua

Chỉ cần một dòng lệnh là biết MacBook có đáng mua không: pin, SSD, khoá iCloud, máy công ty, màn hình, bàn phím, loa, cổng cắm...

## Cách dùng tại cửa hàng

1. Kết nối máy với Wi-Fi.
2. Bấm `Cmd + Space`, gõ `Terminal`, bấm Enter.
3. Dán dòng này vào rồi bấm Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/minhpnz/mactest/main/check-used-macbook.sh | bash
```

4. Làm theo hướng dẫn trên màn hình (khoảng 10 phút). Khi được hỏi mật khẩu, nhờ người bán gõ.
5. Đọc phần **KẾT LUẬN** ở cuối. Báo cáo cũng được lưu ra Desktop.

Chỉ có 1 phút? Dùng bản nhanh, bỏ qua phần test tay:

```bash
curl -fsSL https://raw.githubusercontent.com/minhpnz/mactest/main/check-used-macbook.sh | bash -s -- --quick
```

Khai sẵn tháng mua để tính mức dùng trung bình:

```bash
curl -fsSL https://raw.githubusercontent.com/minhpnz/mactest/main/check-used-macbook.sh | bash -s -- --date 2024-11
```

## Script kiểm tra những gì

| Bước | Nội dung |
|---|---|
| 1. Thông tin máy | Dòng máy, năm, chip, RAM, serial; cảnh báo máy Intel và bàn phím butterfly |
| 2. Khoá và quyền sở hữu | Khoá kích hoạt (Activation Lock), máy thuộc công ty (MDM, có hỏi trực tiếp Apple), Find My, iCloud |
| 3. Pin | Dung lượng còn lại, số chu kỳ, chu kỳ mỗi tháng, tình trạng Apple đánh giá |
| 4. SSD | Độ hao mòn, các lỗi, tổng dữ liệu đã ghi, TB/năm |
| 5. Độ ổn định | Lịch sử sập hệ thống, camera, loa, micro, Wi-Fi, Bluetooth |
| 6. Test tay | Điểm chết màn hình, từng phím, trackpad, loa, cổng cắm, vỏ máy, lịch sử sửa chữa |
| 7. Test tải nặng | Chạy CPU hết công suất 3 phút, xem máy có sập nguồn, quá nóng hay tụt pin nhanh không |

Bản `--quick` chỉ chạy bước 1 đến 5 và bỏ qua phần hỏi Apple về MDM.

## Đọc kết quả

| Ký hiệu | Nghĩa |
|---|---|
| ✓ | Tốt |
| ! | Nên cân nhắc, có thể dùng để trả giá |
| ✗ | Có vấn đề |
| ? | Chưa kiểm tra được |
| • | Thông tin tham khảo |

| Kết luận | Nên làm gì |
|---|---|
| KHÔNG NÊN MUA | Máy bị khoá, thuộc công ty, hoặc SSD có lỗi. Đừng trả tiền |
| CHỈ MUA NẾU ĐƯỢC GIẢM GIÁ | Trừ chi phí thay pin/sửa chữa vào giá |
| CHƯA ĐỦ THÔNG TIN ĐỂ KẾT LUẬN | Xem mục `?` rồi kiểm tra lại |
| CÓ THỂ MUA, XEM CÁC ĐIỂM LƯU Ý | Không có lỗi lớn |
| MÁY ĐẠT, CÓ THỂ MUA | Các mục kiểm tra đều tốt |

## Ngưỡng đánh giá

Đây là tiêu chí chọn mua, không phải tiêu chuẩn của Apple.

| Mục | Tốt | Cân nhắc | Cần trừ giá |
|---|---|---|---|
| Pin còn lại (Maximum Capacity) | từ 90% | 85–89% | dưới 85% |
| Chu kỳ sạc (Cycle Count) | dưới 300 | 300–600 | trên 600 |
| Độ hao mòn SSD (Percentage Used) | đến 5% | 6–10% | trên 10% |

Lỗi khiến script kết luận không nên mua: khoá kích hoạt đang bật, máy thuộc tổ chức (MDM), serial bất thường, SSD có Critical Warning, lỗi dữ liệu hoặc hết vùng dự phòng.

## Script làm gì trên máy

- Chỉ đọc thông tin, không cài đặt và không sửa dữ liệu của máy.
- Công cụ đọc SSD (`smartctl`) được tải vào thư mục tạm từ Homebrew, kiểm tra SHA-256, rồi xoá khi xong.
- Phần test tải nặng chạy CPU hết công suất vài phút, máy sẽ nóng và quạt quay to.
- Phần duy nhất cần mật khẩu là hỏi Apple xem máy có thuộc tổ chức nào không.
- Script chỉ để lại một file báo cáo trên Desktop.

## Trước khi trả tiền

1. Nhờ người bán xoá sạch máy (System Settings > General > Transfer or Reset).
2. Tự cài lại có Wi-Fi. Thấy màn hình "Remote Management" thì không mua.
3. Chạy Apple Diagnostics: chip M giữ nút nguồn rồi bấm Cmd+D; Intel giữ phím D khi bật máy.
4. Lấy hoá đơn hoặc giấy bảo hành và thoả thuận đổi trả rõ ràng.

## Giới hạn

- Script không thay thế bước xoá máy và cài lại có Internet. Chỉ bước đó mới lộ màn hình Remote Management.
- Máy vừa bị xoá sẽ mất lịch sử lỗi hệ thống, nên kết quả "chưa ghi nhận" lúc đó không có ý nghĩa.
- Nếu pin hoặc main đã thay, số liệu trung bình theo tuổi máy không còn đúng.
- Máy không có Internet sẽ không đọc được chi tiết SSD và không hỏi được Apple.

## Tình trạng test

- Đã chạy thử trên MacBook Pro Intel (macOS 26), gồm cả lệnh `curl` từ GitHub.
- Chưa chạy trên máy chip M thật. Nếu mục SSD hiện `?`, đừng coi là SSD đã đạt; hãy chạy lệnh `smartctl` mà script gợi ý.
- Bước hỏi Apple về MDM chưa được test với `sudo` thật.
- Trang test, Photo Booth và giọng đọc mới được test bằng bản giả, chưa mở thật.
