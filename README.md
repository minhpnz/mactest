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

## Giới hạn

- Script không thay thế bước xoá máy và cài lại có Internet. Chỉ bước đó mới lộ màn hình Remote Management.
- Máy vừa bị xoá sẽ mất lịch sử lỗi hệ thống.
- Nếu pin hoặc main đã thay, số liệu trung bình theo tuổi máy không còn đúng.
