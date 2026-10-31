#!/bin/bash
# check-used-macbook.sh - Kiểm tra MacBook cũ trước khi mua.
#
# Không cài gì vào máy: smartctl được tải vào thư mục tạm rồi xoá khi thoát.
# Ngưỡng đánh giá là tiêu chí chọn mua, không phải tiêu chuẩn của Apple.
# Tương thích bash 3.2 mặc định của macOS; không cần python, jq hay Xcode CLT.

# Locale UTF-8 để ${#chuỗi} đếm theo ký tự, giúp căn cột tiếng Việt đúng
export LC_ALL=en_US.UTF-8

QUICK=0
STRESS_SECS=180
PURCHASE=""
TMP_DIR=""
STRESS_PIDS=""
RESULTS=""
ISSUES=""
SMARTCTL=""
SP_JSON=""
REPORT=""
N_BLOCK=0 N_BAD=0 N_WARN=0 N_OK=0 N_UNKNOWN=0
MONTHS=""
STEP=0
TOTAL_STEPS=5
WIDTH=64
NAME_WIDTH=30

if [ -t 1 ]; then
  C_RED=$'\033[1;31m' C_YEL=$'\033[1;33m' C_GRN=$'\033[1;32m' C_BLU=$'\033[1;36m'
  C_BLD=$'\033[1m' C_DIM=$'\033[2m' C_RST=$'\033[0m'
else
  C_RED="" C_YEL="" C_GRN="" C_BLU="" C_BLD="" C_DIM="" C_RST=""
fi

usage() {
  cat <<'EOF'
Cách dùng: bash check-used-macbook.sh [tuỳ chọn]

  (không tuỳ chọn)   chạy đủ: tự động + test tay + test tải nặng (khoảng 10 phút)
  --quick            chỉ phần tự động (khoảng 1 phút)
  --date 2024-11     khai sẵn tháng mua lần đầu
  --stress 300       test tải nặng 300 giây (mặc định 180)
EOF
}

cleanup() {
  [ -n "$STRESS_PIDS" ] && kill $STRESS_PIDS 2>/dev/null
  [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
}

repeat() { # repeat "ký tự" số_lần
  local i=0 out=""
  while [ "$i" -lt "$2" ]; do out="$out$1"; i=$((i + 1)); done
  printf '%s' "$out"
}

banner() { # banner "màu" "dòng 1" ["dòng 2"]
  local color="$1" line pad
  shift
  printf '%s╔%s╗%s\n' "$color" "$(repeat ═ $((WIDTH - 2)))" "$C_RST"
  for line in "$@"; do
    pad=$((WIDTH - 4 - ${#line}))
    [ "$pad" -lt 0 ] && pad=0
    printf '%s║%s %s%s %s║%s\n' "$color" "$C_RST$C_BLD" "$line" "$(repeat ' ' "$pad")$C_RST" "$color" "$C_RST"
  done
  printf '%s╚%s╝%s\n' "$color" "$(repeat ═ $((WIDTH - 2)))" "$C_RST"
}

section() {
  STEP=$((STEP + 1))
  local title="$STEP. $1"
  [ "$STEP" -le "$TOTAL_STEPS" ] && title="Bước $STEP/$TOTAL_STEPS · $1"
  printf '\n%s%s%s\n%s%s%s\n' "$C_BLD$C_BLU" "$title" "$C_RST" "$C_DIM" "$(repeat ─ "$WIDTH")" "$C_RST"
  RESULTS="$RESULTS

$1
$(repeat ─ "$WIDTH")"
}

# add STATUS "Tên" "Giá trị" "Giải thích"
# BLOCK: không nên mua | BAD: trừ giá/dự trù sửa | WARN: cân nhắc | OK | INFO | UNKNOWN
add() {
  local status="$1" name="$2" value="$3" note="${4:-}" color="$C_DIM" icon="•" pad
  case "$status" in
    BLOCK)   color="$C_RED"; icon="✗"; N_BLOCK=$((N_BLOCK + 1)) ;;
    BAD)     color="$C_RED"; icon="✗"; N_BAD=$((N_BAD + 1)) ;;
    WARN)    color="$C_YEL"; icon="!"; N_WARN=$((N_WARN + 1)) ;;
    OK)      color="$C_GRN"; icon="✓"; N_OK=$((N_OK + 1)) ;;
    UNKNOWN) color="$C_YEL"; icon="?"; N_UNKNOWN=$((N_UNKNOWN + 1)) ;;
  esac
  pad=$((NAME_WIDTH - ${#name}))
  [ "$pad" -lt 1 ] && pad=1
  printf ' %s%s%s %s%s%s%s\n' "$color" "$icon" "$C_RST" "$name" "$(repeat ' ' "$pad")" "$C_BLD$value" "$C_RST"
  [ -n "$note" ] && printf '   %s%s%s\n' "$C_DIM" "$note" "$C_RST"
  RESULTS="$RESULTS
 $icon $name$(repeat ' ' "$pad")$value"
  [ -n "$note" ] && RESULTS="$RESULTS
   $note"
  case "$status" in
    BLOCK|BAD|WARN|UNKNOWN)
      ISSUES="$ISSUES
$status|$name: $value${note:+ → $note}" ;;
  esac
}

ask() { # ask "Câu hỏi" -> in câu trả lời
  local reply=""
  printf '%s ' "$1" >/dev/tty
  read -r reply </dev/tty
  printf '%s' "$reply"
}

can_ask() { [ "$QUICK" = 0 ] && (: </dev/tty) 2>/dev/null; }

# jget FILE 'biểu thức JS trên d' - đọc JSON bằng JXA vì máy lạ có thể không có jq/python
jget() {
  osascript -l JavaScript - "$1" "$2" 2>/dev/null <<'JS'
ObjC.import('Foundation');
function run(argv) {
  var s = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
  try {
    var v = new Function('d', 'return (' + argv[1] + ')')(JSON.parse(ObjC.unwrap(s)));
    return (v === undefined || v === null) ? '' : String(v);
  } catch (e) { return ''; }
}
JS
}

sp() { jget "$SP_JSON" "$1"; }

ge() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'; }
gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }

# ---- Thời gian sử dụng ----------------------------------------------------

set_purchase_months() { # YYYY-MM hoặc MM/YYYY -> MONTHS
  local input="$1" y m start now
  case "$input" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]) y="${input%-*}"; m="${input#*-}" ;;
    [0-9][0-9]/[0-9][0-9][0-9][0-9]) m="${input%/*}"; y="${input#*/}" ;;
    *) return 1 ;;
  esac
  start=$(date -j -f '%Y-%m-%d' "$y-$m-01" +%s 2>/dev/null) || return 1
  now=$(date +%s)
  [ "$start" -lt "$now" ] || return 1
  MONTHS=$(awk -v a="$start" -v b="$now" 'BEGIN { printf "%.1f", (b - a) / 86400 / 30.44 }')
}

ask_purchase_date() {
  if [ -n "$PURCHASE" ]; then
    set_purchase_months "$PURCHASE" || printf '%sNgày mua "%s" sai dạng, bỏ qua phần tính trung bình.%s\n' "$C_YEL" "$PURCHASE" "$C_RST"
  elif can_ask; then
    printf 'Máy được mua mới lần đầu vào tháng nào? Xem trên hoá đơn hoặc hỏi người bán.\n'
    PURCHASE=$(ask "Nhập dạng 2024-11 (không biết thì bấm Enter):")
    [ -z "$PURCHASE" ] || set_purchase_months "$PURCHASE" || printf '%sNhập chưa đúng dạng, bỏ qua phần tính trung bình.%s\n' "$C_YEL" "$C_RST"
  fi
}

# ---- smartctl không cần Homebrew ------------------------------------------

macos_bottle_tags() { # tag từ bản macOS hiện tại trở xuống
  local major prefix="" tag
  major=$(sw_vers -productVersion | cut -d. -f1)
  [ "$(uname -m)" = arm64 ] && prefix="arm64_"
  for tag in 27:golden_gate 26:tahoe 15:sequoia 14:sonoma 13:ventura 12:monterey; do
    [ "$major" -ge "${tag%%:*}" ] && printf '%s ' "$prefix${tag##*:}"
  done
}

fetch_smartctl() {
  local meta="$TMP_DIR/formula.json" dir="$TMP_DIR/smartmontools" tag url sha="" bin
  curl -fsSL --max-time 20 https://formulae.brew.sh/api/formula/smartmontools.json -o "$meta" || return 1
  for tag in $(macos_bottle_tags); do
    url=$(jget "$meta" "d.bottle.stable.files['$tag'].url")
    if [ -n "$url" ]; then
      sha=$(jget "$meta" "d.bottle.stable.files['$tag'].sha256")
      break
    fi
  done
  [ -n "$sha" ] || return 1
  curl -fsSL --max-time 120 -H 'Authorization: Bearer QQ==' "$url" -o "$TMP_DIR/bottle.tgz" || return 1
  [ "$(shasum -a 256 "$TMP_DIR/bottle.tgz" | cut -d' ' -f1)" = "$sha" ] || return 1
  mkdir -p "$dir" && tar -xzf "$TMP_DIR/bottle.tgz" -C "$dir" || return 1
  bin=$(find "$dir" -type f -name smartctl | head -1)
  [ -n "$bin" ] || return 1
  chmod +x "$bin"
  codesign --force --sign - "$bin" 2>/dev/null
  "$bin" --version >/dev/null 2>&1 || return 1
  SMARTCTL="$bin"
}

find_smartctl() {
  local p
  for p in "$(command -v smartctl 2>/dev/null)" /opt/homebrew/bin/smartctl /usr/local/bin/smartctl /usr/local/sbin/smartctl; do
    if [ -n "$p" ] && [ -x "$p" ]; then
      SMARTCTL="$p"
      return 0
    fi
  done
  printf 'Đang tải công cụ đọc SSD (tạm thời, không cài vào máy)...\n'
  fetch_smartctl
}

# ---- Đánh giá theo ngưỡng (tách riêng để test được) -----------------------

rate_max_capacity() {
  if ge "$1" 90; then echo OK; elif ge "$1" 85; then echo WARN; else echo BAD; fi
}
rate_cycles() {
  if [ "$1" -lt 300 ]; then echo OK; elif [ "$1" -le 600 ]; then echo WARN; else echo BAD; fi
}
rate_pct_used() {
  if [ "$1" -le 5 ]; then echo OK; elif [ "$1" -le 10 ]; then echo WARN; else echo BAD; fi
}
rate_battery_condition() {
  case "$1" in
    Good|Normal) echo OK ;;
    "")          echo UNKNOWN ;;
    *)           echo BAD ;;
  esac
}
label_cycles_per_month() {
  if gt 10 "$1"; then echo "ít dùng pin, có thể hay cắm sạc"
  elif ge 20 "$1"; then echo "dùng pin mức vừa"
  else echo "dùng pin thường xuyên"; fi
}
label_tb_per_year() {
  if gt 10 "$1"; then echo "ghi ít"
  elif gt 30 "$1"; then echo "ghi vừa"
  elif gt 60 "$1"; then echo "ghi nhiều"
  else echo "ghi rất nhiều"; fi
}
# profiles status: dòng "Enrolled via DEP: Yes" hoặc "MDM enrollment: Yes ..."
is_mdm_enrolled() { printf '%s\n' "$1" | grep -qE '(Enrolled via DEP|MDM enrollment): *Yes'; }
# profiles show: hồ sơ thật có ConfigurationURL/OrganizationName; máy sạch báo lỗi hoặc rỗng
has_dep_record() { printf '%s\n' "$1" | grep -qiE 'ConfigurationURL|OrganizationName'; }

verdict() {
  if [ "$N_BLOCK" -gt 0 ]; then
    echo "KHÔNG NÊN MUA"
  elif [ "$N_BAD" -gt 0 ]; then
    echo "CHỈ MUA NẾU ĐƯỢC GIẢM GIÁ"
  elif [ "$N_UNKNOWN" -gt 0 ]; then
    echo "CHƯA ĐỦ THÔNG TIN ĐỂ KẾT LUẬN"
  elif [ "$N_WARN" -gt 0 ]; then
    echo "CÓ THỂ MUA, XEM CÁC ĐIỂM LƯU Ý"
  else
    echo "MÁY ĐẠT, CÓ THỂ MUA"
  fi
}

verdict_color() {
  if [ "$N_BLOCK" -gt 0 ] || [ "$N_BAD" -gt 0 ]; then printf '%s' "$C_RED"
  elif [ "$N_UNKNOWN" -gt 0 ] || [ "$N_WARN" -gt 0 ]; then printf '%s' "$C_YEL"
  else printf '%s' "$C_GRN"; fi
}

verdict_reason() {
  if [ "$N_BLOCK" -gt 0 ]; then
    echo "Có $N_BLOCK lỗi nghiêm trọng, đừng trả tiền."
  elif [ "$N_BAD" -gt 0 ]; then
    echo "Có $N_BAD mục cần sửa/thay, hãy trừ chi phí vào giá."
  elif [ "$N_UNKNOWN" -gt 0 ]; then
    echo "Còn $N_UNKNOWN mục chưa kiểm tra được."
  elif [ "$N_WARN" -gt 0 ]; then
    echo "Không có lỗi lớn, còn $N_WARN điểm nên cân nhắc."
  else
    echo "Các mục kiểm tra đều tốt."
  fi
}

# ---- Các nhóm kiểm tra ----------------------------------------------------

intel_model_name() {
  case "$1" in
    MacBookPro14,1) echo "MacBook Pro 13 inch, 2017 (2 cổng)" ;;
    MacBookPro14,2) echo "MacBook Pro 13 inch, 2017 (4 cổng)" ;;
    MacBookPro14,3) echo "MacBook Pro 15 inch, 2017" ;;
    MacBookPro15,1) echo "MacBook Pro 15 inch, 2018/2019" ;;
    MacBookPro15,2) echo "MacBook Pro 13 inch, 2018/2019 (4 cổng)" ;;
    MacBookPro15,3) echo "MacBook Pro 15 inch, 2019 (Vega)" ;;
    MacBookPro15,4) echo "MacBook Pro 13 inch, 2019 (2 cổng)" ;;
    MacBookPro16,1|MacBookPro16,4) echo "MacBook Pro 16 inch, 2019" ;;
    MacBookPro16,2) echo "MacBook Pro 13 inch, 2020 (4 cổng)" ;;
    MacBookPro16,3) echo "MacBook Pro 13 inch, 2020 (2 cổng)" ;;
    MacBookAir8,1)  echo "MacBook Air 13 inch, 2018" ;;
    MacBookAir8,2)  echo "MacBook Air 13 inch, 2019" ;;
    MacBookAir9,1)  echo "MacBook Air 13 inch, 2020" ;;
  esac
}

marketing_name() {
  local model="$1" name plist="$TMP_DIR/product.plist"
  ioreg -ar -k product-name >"$plist" 2>/dev/null
  name=$(/usr/libexec/PlistBuddy -c 'print 0:product-name' "$plist" 2>/dev/null | tr -d '\000')
  case "$name" in *" "*) ;; *) name=$(intel_model_name "$model") ;; esac
  [ -n "$name" ] || name="$(sp 'd.SPHardwareDataType[0].machine_name') (tra năm bằng serial)"
  printf '%s' "$name"
}

check_identity() {
  section "Thông tin máy"
  local model serial chip ram
  model=$(sp 'd.SPHardwareDataType[0].machine_model')
  if [ -z "$model" ]; then
    add UNKNOWN "Thông tin phần cứng" "không đọc được" "Xem tay: menu Apple > About This Mac"
    return
  fi
  serial=$(sp 'd.SPHardwareDataType[0].serial_number')
  chip=$(sp 'd.SPHardwareDataType[0].chip_type||d.SPHardwareDataType[0].cpu_type')
  ram=$(sp 'd.SPHardwareDataType[0].physical_memory')

  add INFO "Dòng máy" "$(marketing_name "$model")"
  add INFO "Mã máy" "$model"
  add INFO "Chip" "$chip"
  add INFO "RAM" "$ram"
  add INFO "macOS" "$(sw_vers -productVersion)"

  case "$serial" in
    ""|"Not Available"|*"Default"*|*"To be"*)
      add BLOCK "Số serial" "${serial:-trống}" "Serial bất thường: có thể đã thay main không chuẩn" ;;
    *)
      add OK "Số serial" "$serial" "Đối chiếu với số khắc dưới đáy máy, rồi tra ở checkcoverage.apple.com" ;;
  esac

  if [ "$(uname -m)" = x86_64 ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" != 1 ]; then
    add WARN "Loại chip" "Intel (đời cũ)" "macOS 26 là bản lớn cuối cho máy Intel; muốn dùng lâu nên chọn chip M"
  else
    add OK "Loại chip" "Apple silicon (chip M)"
  fi
  case "$model" in
    MacBookPro13,*|MacBookPro14,*|MacBookPro15,*|MacBookAir8,*)
      add WARN "Bàn phím" "kiểu butterfly" "Dòng này hay kẹt hoặc lặp phím, nhớ thử kỹ từng phím" ;;
  esac
}

check_ownership() {
  section "Máy có bị khoá hoặc thuộc công ty không"
  local lock enroll accounts icloud fv sip

  lock=$(sp 'd.SPHardwareDataType[0].activation_lock_status')
  case "$lock" in
    activation_lock_disabled) add OK "Khoá kích hoạt" "đã tắt" "Không bị khoá vào iCloud của chủ cũ" ;;
    activation_lock_enabled)  add BLOCK "Khoá kích hoạt" "đang bật" "Chủ cũ phải tắt Find My, nếu không máy có thể thành cục gạch" ;;
    *)                        add UNKNOWN "Khoá kích hoạt" "không đọc được" "Giữ Option, bấm menu Apple > System Information > Hardware" ;;
  esac
  if nvram -p 2>/dev/null | grep -q fmm-mobileme-token-FMM; then
    add WARN "Find My" "đang bật" "Phải tắt trước khi nhận máy"
  fi

  enroll=$(profiles status -type enrollment 2>&1)
  if is_mdm_enrolled "$enroll"; then
    add BLOCK "Máy của công ty (MDM)" "có" "Công ty có thể khoá máy từ xa bất cứ lúc nào"
  elif printf '%s' "$enroll" | grep -q 'MDM enrollment'; then
    add OK "Máy của công ty (MDM)" "không thấy trên máy"
  else
    add UNKNOWN "Máy của công ty (MDM)" "không đọc được"
  fi
  check_dep_with_apple

  accounts=$(dscl . -list /Users UniqueID 2>/dev/null | awk '$2 >= 500 && $1 !~ /^_/ { n++ } END { print n + 0 }')
  [ "$accounts" -gt 1 ] && add WARN "Tài khoản trên máy" "$accounts tài khoản" "Nên xoá trắng máy trước khi nhận"

  icloud=$(defaults read MobileMeAccounts Accounts 2>/dev/null | grep -c AccountID)
  [ "$icloud" -gt 0 ] && add WARN "iCloud" "đang đăng nhập" "Người bán phải đăng xuất rồi mới xoá máy"

  fv=$(fdesetup status 2>/dev/null | head -1)
  case "$fv" in
    *"is On"*)  add INFO "Mã hoá ổ (FileVault)" "bật" ;;
    *"is Off"*) add INFO "Mã hoá ổ (FileVault)" "tắt" ;;
  esac
  sip=$(csrutil status 2>/dev/null)
  case "$sip" in
    *enabled*) add OK "Bảo vệ hệ thống (SIP)" "bật" ;;
    *)         add WARN "Bảo vệ hệ thống (SIP)" "tắt/không rõ" "Có thể máy đã bị can thiệp để né khoá công ty" ;;
  esac
  add INFO "Lần cài macOS gần nhất" "$(stat -f '%Sm' -t '%Y-%m-%d' /private/var/db/.AppleSetupDone 2>/dev/null)" "Là ngày cài/xoá máy, không phải ngày mua"
}

check_dep_with_apple() {
  local out
  if ! can_ask; then
    add UNKNOWN "Hỏi Apple về MDM" "chưa kiểm tra" "Chế độ nhanh bỏ qua. Chạy: sudo profiles show -type enrollment"
    return
  fi
  printf '\n   %sHỏi Apple xem máy này có đăng ký dưới tên công ty/trường không.%s\n' "$C_BLD" "$C_RST"
  printf '   Nhờ người bán gõ mật khẩu máy (gõ sẽ không hiện ký tự, đó là bình thường).\n'
  out=$(sudo profiles show -type enrollment 2>&1 </dev/tty)
  if [ $? -ne 0 ] && printf '%s' "$out" | grep -qiE 'password|sudo:'; then
    add UNKNOWN "Hỏi Apple về MDM" "chưa kiểm tra" "Sai mật khẩu hoặc tài khoản không phải admin"
  elif has_dep_record "$out"; then
    add BLOCK "Hỏi Apple về MDM" "thuộc tổ chức" "$(printf '%s' "$out" | grep -iE 'OrganizationName' | head -1 | tr -s ' ')"
  else
    add OK "Hỏi Apple về MDM" "không thuộc tổ chức nào"
  fi
}

battery_field() { ioreg -rn AppleSmartBattery | awk -F' = ' -v k="\"$1\"" '$1 ~ "^ *" k "$" { print $2; exit }'; }

check_battery() {
  section "Pin"
  local has max source cycles condition design raw limit pf temp per_month
  has=$(sp "d.SPPowerDataType[0]._name")
  if [ "$has" != spbattery_information ]; then
    add UNKNOWN "Pin" "không đọc được"
    return
  fi

  design=$(battery_field DesignCapacity)
  raw=$(battery_field AppleRawMaxCapacity)
  limit=$(battery_field DesignCycleCount9C)
  pf=$(battery_field PermanentFailureStatus)
  temp=$(battery_field Temperature)

  max=$(sp 'd.SPPowerDataType[0].sppower_battery_health_info.sppower_battery_health_maximum_capacity')
  max="${max%\%}"
  source=""
  if [ -z "$max" ] && [ -n "$raw" ] && [ -n "$design" ] && [ "$design" -gt 0 ]; then
    max=$(awk -v a="$raw" -v b="$design" 'BEGIN { printf "%.0f", a * 100 / b }')
    source=" (tính từ $raw/$design mAh)"
  fi
  if [ -n "$max" ]; then
    add "$(rate_max_capacity "$max")" "Dung lượng pin còn lại" "$max%$source" "Từ 90% là tốt, 85–89% cân nhắc giá, dưới 85% nên tính tiền thay pin"
  else
    add UNKNOWN "Dung lượng pin còn lại" "không đọc được"
  fi

  cycles=$(sp 'd.SPPowerDataType[0].sppower_battery_health_info.sppower_battery_cycle_count')
  if [ -n "$cycles" ]; then
    add "$(rate_cycles "$cycles")" "Số chu kỳ sạc" "$cycles${limit:+ / $limit}" "Dưới 300 là tốt, 300–600 cân nhắc, trên 600 là pin đã dùng nhiều"
    if [ -n "$MONTHS" ]; then
      per_month=$(awk -v a="$cycles" -v b="$MONTHS" 'BEGIN { printf "%.1f", a / b }')
      add INFO "Chu kỳ mỗi tháng" "$per_month ($(label_cycles_per_month "$per_month"))" "Chỉ đúng nếu pin chưa thay. Chu kỳ thấp chưa chắc máy ít dùng"
    fi
  fi

  condition=$(sp 'd.SPPowerDataType[0].sppower_battery_health_info.sppower_battery_health')
  add "$(rate_battery_condition "$condition")" "Tình trạng Apple đánh giá" "${condition:-không rõ}" "Good/Normal là bình thường"
  if [ -n "$pf" ] && [ "$pf" != 0 ]; then
    add BAD "Lỗi mạch pin" "mã $pf" "Pin đã ghi nhận lỗi vĩnh viễn, cần thay"
  fi
  [ -n "$temp" ] && add INFO "Nhiệt độ pin" "$(awk -v t="$temp" 'BEGIN { printf "%.1f", t / 100 }') °C"
}

check_ssd() {
  section "Ổ cứng SSD"
  local json="$TMP_DIR/smart.json" code st model pct spare spare_th crit media duw written read_tb poh unsafe size tb_year times
  model=$(sp 'd.SPNVMeDataType[0]._items[0].device_model')
  size=$(sp 'd.SPNVMeDataType[0]._items[0].size_in_bytes')
  [ -n "$model" ] && add INFO "Ổ cứng" "$model"

  st=$(sp 'd.SPNVMeDataType[0]._items[0].smart_status')
  case "$st" in
    Verified) add OK "macOS kiểm tra ổ" "bình thường" ;;
    "")       ;;
    *)        add BLOCK "macOS kiểm tra ổ" "$st" "SSD hàn liền main, hỏng là tốn tiền thay main" ;;
  esac

  if [ -z "$SMARTCTL" ]; then
    add UNKNOWN "Độ hao mòn SSD" "không đọc được" "Cần có Internet. Kết nối Wi-Fi rồi chạy lại"
    return
  fi
  "$SMARTCTL" -a -j /dev/disk0 >"$json" 2>/dev/null
  code=$?
  # Bit 0-1: không đọc được. Bit 2 hay bật trên SSD Apple do không có Error Log, không phải lỗi ổ.
  pct=$(jget "$json" 'd.nvme_smart_health_information_log.percentage_used')
  if [ $((code & 3)) -ne 0 ] || [ -z "$pct" ]; then
    add UNKNOWN "Độ hao mòn SSD" "không đọc được" "Mã lỗi $code. Chạy tay: smartctl -a /dev/disk0"
    return
  fi

  local log='d.nvme_smart_health_information_log'
  crit=$(jget "$json" "$log.critical_warning")
  media=$(jget "$json" "$log.media_errors")
  spare=$(jget "$json" "$log.available_spare")
  spare_th=$(jget "$json" "$log.available_spare_threshold")
  duw=$(jget "$json" "$log.data_units_written")
  read_tb=$(jget "$json" "$log.data_units_read")
  poh=$(jget "$json" "$log.power_on_hours")
  unsafe=$(jget "$json" "$log.unsafe_shutdowns")

  add "$(rate_pct_used "$pct")" "Độ hao mòn SSD" "$pct%" "Đến 5% là tốt, 6–10% xem xét, trên 10% nên chọn máy khác. Chỉ là ước tính"
  if [ "$crit" = 0 ]; then add OK "Cảnh báo nghiêm trọng" "không có"; else add BLOCK "Cảnh báo nghiêm trọng" "mã $crit" "SSD đang tự báo lỗi"; fi
  if [ "$media" = 0 ]; then add OK "Lỗi dữ liệu" "0 lỗi"; else add BLOCK "Lỗi dữ liệu" "$media lỗi" "Chip nhớ đã có lỗi"; fi
  if [ "$spare" -le "$spare_th" ]; then
    add BLOCK "Vùng dự phòng" "$spare%" "Sắp hết vùng thay thế, SSD gần hỏng"
  elif [ "$spare" -lt 100 ]; then
    add WARN "Vùng dự phòng" "$spare%" "Tốt nhất là 100%"
  else
    add OK "Vùng dự phòng" "$spare%"
  fi

  written=$(awk -v u="$duw" 'BEGIN { printf "%.1f", u * 512000 / 1e12 }')
  add INFO "Tổng dữ liệu đã ghi" "$written TB" "Gồm cả dữ liệu tạm hệ thống, không chỉ file của chủ máy"
  add INFO "Tổng dữ liệu đã đọc" "$(awk -v u="$read_tb" 'BEGIN { printf "%.1f", u * 512000 / 1e12 }') TB"
  if [ -n "$size" ] && [ "$size" -gt 0 ]; then
    times=$(awk -v w="$written" -v s="$size" 'BEGIN { printf "%.0f", w * 1e12 / s }')
    add INFO "Tương đương ghi đầy ổ" "$times lần"
  fi
  if [ -n "$MONTHS" ]; then
    tb_year=$(awk -v w="$written" -v m="$MONTHS" 'BEGIN { printf "%.1f", w * 12 / m }')
    add INFO "Ghi trung bình mỗi năm" "$tb_year TB ($(label_tb_per_year "$tb_year"))" "Chỉ để so sánh giữa các máy, không phải ngưỡng tốt/hỏng"
  fi
  add INFO "Giờ hoạt động của SSD" "$poh giờ" "Chỉ tham khảo, không phải số giờ chủ máy đã dùng"
  [ "${unsafe:-0}" -gt 0 ] && add INFO "Số lần tắt máy đột ngột" "$unsafe"
}

panic_files() {
  find /Library/Logs/DiagnosticReports -maxdepth 2 \( -name '*.panic' -o -name 'panic-*' -o -name 'Kernel-*' \) ! -name '.*' 2>/dev/null
}

check_stability() {
  section "Độ ổn định và linh kiện"
  local panics cam bt wifi audio therm screen charger
  panics=$(panic_files | wc -l | tr -d ' ')
  if [ "$panics" = 0 ]; then
    add OK "Lỗi sập hệ thống" "chưa ghi nhận" "Nếu máy vừa được xoá thì lịch sử này đã mất, không kết luận được"
  elif [ "$panics" -ge 3 ]; then
    add BAD "Lỗi sập hệ thống" "$panics lần" "Máy từng tự khởi động lại vì lỗi, có thể do phần cứng"
  else
    add WARN "Lỗi sập hệ thống" "$panics lần" "Máy từng tự khởi động lại vì lỗi"
  fi

  therm=$(pmset -g therm 2>/dev/null | awk -F'= *' '/CPU_Speed_Limit/ { print $2 }')
  if [ -n "$therm" ] && [ "$therm" -lt 100 ]; then
    add WARN "Tốc độ CPU" "bị giới hạn $therm%" "Máy nóng ngay cả khi chưa làm gì nặng"
  fi

  cam=$(sp "(d.SPCameraDataType||[]).map(function(c){return c._name}).filter(function(n){return !/iPhone/i.test(n)}).join(', ')")
  if [ -n "$cam" ]; then add OK "Camera" "nhận được"; else add BAD "Camera" "không thấy"; fi

  audio=$(sp "JSON.stringify(d.SPAudioDataType||[])")
  case "$audio" in *"Speakers"*) add OK "Loa" "nhận được" ;; *) add WARN "Loa" "không thấy" ;; esac
  case "$audio" in *"Microphone"*) add OK "Micro" "nhận được" ;; *) add WARN "Micro" "không thấy" ;; esac

  wifi=$(networksetup -listallhardwareports 2>/dev/null | grep -c 'Wi-Fi')
  if [ "$wifi" -gt 0 ]; then add OK "Wi-Fi" "nhận được"; else add BAD "Wi-Fi" "không thấy"; fi
  bt=$(sp "(d.SPBluetoothDataType||[]).length")
  if [ "${bt:-0}" -gt 0 ]; then add OK "Bluetooth" "nhận được"; else add BAD "Bluetooth" "không thấy"; fi

  screen=$(sp "(function(){var r=[];(d.SPDisplaysDataType||[]).forEach(function(g){(g.spdisplays_ndrvs||[]).forEach(function(n){if(n.spdisplays_connection_type==='spdisplays_internal')r.push(n._spdisplays_pixels||n._spdisplays_resolution)})});return r.join(', ')})()")
  [ -n "$screen" ] && add INFO "Màn hình" "$screen"
  charger=$(sp "(function(){var c=d.SPPowerDataType.filter(function(x){return x._name==='sppower_ac_charger_information'})[0];return c&&c.sppower_ac_charger_watts?c.sppower_ac_charger_watts+'W':''})()")
  [ -n "$charger" ] && add INFO "Sạc đang cắm" "$charger"
}

battery_percent() { pmset -g batt 2>/dev/null | grep -o '[0-9]*%' | head -1 | tr -d '%'; }

run_stress() {
  section "Test tải nặng"
  local i ncpu start_pct end_pct min_limit=100 limit elapsed=0 on_batt=0 drop
  printf ' Cho máy chạy hết công suất để xem có nóng quá, sập nguồn hay tụt pin nhanh không.\n'
  if pmset -g batt | grep -q "AC Power"; then
    ask " Rút sạc ra rồi bấm Enter (không rút cũng được, nhưng sẽ không đo được pin):" >/dev/null
  fi
  pmset -g batt | grep -q "Battery Power" && on_batt=1
  ncpu=$(sysctl -n hw.ncpu)
  start_pct=$(battery_percent)
  caffeinate -i -w $$ &
  STRESS_PIDS="$!"
  i=0
  while [ "$i" -lt "$ncpu" ]; do
    yes >/dev/null &
    STRESS_PIDS="$STRESS_PIDS $!"
    i=$((i + 1))
  done
  while [ "$elapsed" -lt "$STRESS_SECS" ]; do
    sleep 5
    elapsed=$((elapsed + 5))
    limit=$(pmset -g therm 2>/dev/null | awk -F'= *' '/CPU_Speed_Limit/ { print $2 }')
    if [ -n "$limit" ] && [ "$limit" -lt "$min_limit" ]; then min_limit="$limit"; fi
    printf '\r Đang chạy %ss/%ss, pin %s%%   ' "$elapsed" "$STRESS_SECS" "$(battery_percent)"
  done
  printf '\n'
  kill $STRESS_PIDS 2>/dev/null
  wait 2>/dev/null
  STRESS_PIDS=""
  end_pct=$(battery_percent)

  add OK "Chịu tải" "không sập nguồn" "Chạy hết công suất trong ${STRESS_SECS} giây"
  if [ "$min_limit" -lt 80 ]; then
    add WARN "Tản nhiệt" "CPU giảm còn $min_limit%" "Nóng quá phải giảm tốc: nghi quạt bẩn hoặc keo tản nhiệt khô"
  elif [ "$(uname -m)" = x86_64 ]; then
    add OK "Tản nhiệt" "CPU giữ từ $min_limit%"
  fi
  if [ "$on_batt" = 1 ]; then
    drop=$((start_pct - end_pct))
    if [ $((drop * 180 / STRESS_SECS)) -gt 15 ]; then
      add WARN "Pin khi chạy nặng" "tụt $drop% trong ${STRESS_SECS} giây" "Tụt nhanh bất thường: pin có thể yếu hơn số liệu"
    else
      add OK "Pin khi chạy nặng" "tụt $drop% trong ${STRESS_SECS} giây"
    fi
  fi
}

write_test_page() {
  cat >"$TMP_DIR/test.html" <<'HTML'
<!doctype html><html lang="vi"><meta charset="utf-8"><title>Test màn hình và bàn phím</title>
<style>
body{font:15px -apple-system,sans-serif;margin:24px;background:#fff;color:#111}
button{font-size:16px;padding:10px 16px}
#s{position:fixed;inset:0;display:none;cursor:none}
.r{display:flex;gap:4px;margin:4px 0}
.k{flex:1 1 0;min-width:0;padding:10px 2px;border:1px solid #bbb;border-radius:6px;text-align:center;font-size:12px}
.k.w{flex:2 1 0}.k.x{flex:6 1 0}.k.on{background:#2a9d4a;color:#fff;border-color:#2a9d4a}
</style>
<h2>1. Màn hình</h2>
<p>Bấm nút để toàn màn hình. Click để đổi màu, phím Esc để thoát. Tìm chấm chết, ám màu, hở sáng (ở nền đen), vệt ở mép dưới.</p>
<button id="b">Bắt đầu test màn hình</button>
<h2>2. Bàn phím</h2>
<p>Bấm từng phím: sáng xanh là phím nhận. <b id="c"></b></p>
<div id="kb"></div>
<div id="s"></div>
<script>
var colors=['#000','#fff','#f00','#0f0','#00f','#808080','linear-gradient(90deg,#000,#fff)'],i=0,s=document.getElementById('s');
function paint(){s.style.background=colors[i%colors.length]}
document.getElementById('b').onclick=function(){i=0;paint();s.style.display='block';s.requestFullscreen()};
s.onclick=function(){i++;paint()};
document.addEventListener('fullscreenchange',function(){if(!document.fullscreenElement)s.style.display='none'});
var rows=[['Escape','F1','F2','F3','F4','F5','F6','F7','F8','F9','F10','F11','F12'],
['Backquote','Digit1','Digit2','Digit3','Digit4','Digit5','Digit6','Digit7','Digit8','Digit9','Digit0','Minus','Equal','Backspace:w'],
['Tab:w','KeyQ','KeyW','KeyE','KeyR','KeyT','KeyY','KeyU','KeyI','KeyO','KeyP','BracketLeft','BracketRight','Backslash'],
['CapsLock:w','KeyA','KeyS','KeyD','KeyF','KeyG','KeyH','KeyJ','KeyK','KeyL','Semicolon','Quote','Enter:w'],
['ShiftLeft:w','KeyZ','KeyX','KeyC','KeyV','KeyB','KeyN','KeyM','Comma','Period','Slash','ShiftRight:w'],
['ControlLeft','AltLeft','MetaLeft:w','Space:x','MetaRight:w','AltRight','ArrowLeft','ArrowUp','ArrowDown','ArrowRight']];
var kb=document.getElementById('kb'),total=0;
rows.forEach(function(r){var d=document.createElement('div');d.className='r';r.forEach(function(k){var p=k.split(':'),e=document.createElement('div');
e.className='k '+(p[1]||'');e.id=p[0];e.textContent=p[0].replace(/^(Key|Digit)/,'');d.appendChild(e);total++});kb.appendChild(d)});
function count(){document.getElementById('c').textContent=document.querySelectorAll('.k.on').length+'/'+total}count();
function hit(e){e.preventDefault();var k=document.getElementById(e.code);if(k){k.classList.add('on');count()}}
addEventListener('keydown',hit);addEventListener('keyup',hit);
</script></html>
HTML
}

manual() { # manual "Mục" "Hướng dẫn" [BLOCK|BAD|WARN khi trượt]
  local reply fail="${3:-BAD}"
  printf '\n %s%s%s\n %s\n' "$C_BLD" "$1" "$C_RST" "$2"
  reply=$(ask " → Có ổn không? y = ổn, n = có lỗi, Enter = bỏ qua:")
  case "$reply" in
    y|Y) add OK "$1" "ổn" ;;
    n|N) add "$fail" "$1" "có lỗi" ;;
    *)   add UNKNOWN "$1" "chưa kiểm tra" ;;
  esac
}

run_manual_tests() {
  section "Tự kiểm tra bằng tay"
  printf ' Script hỏi từng mục, bạn tự thử rồi trả lời.\n'
  write_test_page
  open "$TMP_DIR/test.html"
  manual "Màn hình" "Trang test vừa mở trong trình duyệt. Bấm nút rồi click qua hết các màu."
  manual "Bàn phím" "Bấm hết các phím trên trang test. Thử cả đèn nền bàn phím."
  manual "Trackpad" "Click 4 góc, kéo thả, cuộn bằng 2 ngón."
  say "Testing speakers" 2>/dev/null
  manual "Loa" "Vừa phát giọng đọc. Tăng âm lượng tối đa, nghe có rè không?" WARN
  open -a "Photo Booth" 2>/dev/null
  manual "Camera và micro" "Photo Booth vừa mở. Xem hình rõ không, quay thử đoạn có tiếng." WARN
  manual "Vân tay (Touch ID)" "System Settings > Touch ID: thêm thử một vân tay rồi xoá đi." WARN
  manual "Cổng cắm và sạc" "Cắm sạc và thiết bị vào từng cổng, có sạc và nhận không? Thử cả tai nghe." BAD
  manual "Vỏ máy" "Xem móp, cong, ốc bị toét, bản lề lỏng, lớp phủ màn hình bong." WARN
  manual "Lịch sử sửa chữa" "Chip M + macOS 26: System Settings > General > About > Parts & Service (chỉ hiện nếu từng sửa). Không thấy mục đó, hoặc linh kiện ghi Genuine là ổn." BAD
}

print_issues() {
  local line status text color icon
  [ -n "$ISSUES" ] || return 0
  printf '\n %sCác điểm cần chú ý%s\n' "$C_BLD" "$C_RST"
  printf '%s\n' "$ISSUES" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    status="${line%%|*}"
    text="${line#*|}"
    case "$status" in
      BLOCK|BAD) color="$C_RED"; icon="✗" ;;
      WARN)      color="$C_YEL"; icon="!" ;;
      *)         color="$C_YEL"; icon="?" ;;
    esac
    printf ' %s%s%s %s\n' "$color" "$icon" "$C_RST" "$text"
  done
}

print_final_steps() {
  printf '\n %sTrước khi trả tiền%s\n' "$C_BLD" "$C_RST"
  printf ' 1. Nhờ người bán xoá sạch máy (System Settings > General > Transfer or Reset).\n'
  printf ' 2. Tự cài lại có Wi-Fi. Thấy màn hình "Remote Management" thì KHÔNG mua.\n'
  printf ' 3. Chạy Apple Diagnostics: chip M giữ nút nguồn rồi Cmd+D; Intel giữ phím D khi bật.\n'
  printf ' 4. Lấy hoá đơn/giấy bảo hành và thoả thuận đổi trả rõ ràng.\n'
}

write_report() {
  local dir="$HOME/Desktop" saved_red="$C_RED" saved_yel="$C_YEL" saved_bld="$C_BLD" saved_rst="$C_RST"
  [ -d "$dir" ] || dir="$HOME"
  REPORT="$dir/macbook-report-$(date +%Y%m%d-%H%M).txt"
  C_RED="" C_YEL="" C_BLD="" C_RST=""
  {
    printf 'BÁO CÁO KIỂM TRA MACBOOK - %s\n' "$(date '+%d/%m/%Y %H:%M')"
    [ -n "$MONTHS" ] && printf 'Tháng mua khai báo: %s (%s tháng)\n' "$PURCHASE" "$MONTHS"
    printf 'KẾT LUẬN: %s. %s\n' "$(verdict)" "$(verdict_reason)"
    print_issues
    printf '%s\n' "$RESULTS"
  } >"$REPORT"
  C_RED="$saved_red" C_YEL="$saved_yel" C_BLD="$saved_bld" C_RST="$saved_rst"
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --quick)  QUICK=1 ;;
      --date)   PURCHASE="${2:-}"; shift ;;
      --stress) STRESS_SECS="${2:-180}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) printf 'Tuỳ chọn không hợp lệ: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
  done
  case "$STRESS_SECS" in
    ''|*[!0-9]*|0) printf -- '--stress cần số giây lớn hơn 0\n' >&2; exit 2 ;;
  esac
  if [ "$(uname -s)" != Darwin ]; then
    printf 'Script này chỉ chạy trên máy Mac.\n' >&2
    exit 1
  fi

  TMP_DIR=$(mktemp -d /tmp/macbook-check.XXXXXX) || exit 1
  trap cleanup EXIT
  trap 'exit 130' INT TERM
  SP_JSON="$TMP_DIR/sp.json"
  can_ask && TOTAL_STEPS=7

  printf '\n'
  banner "$C_BLU" "KIỂM TRA MACBOOK CŨ TRƯỚC KHI MUA" "Không cài gì vào máy, không đụng tới dữ liệu"
  printf '\n %s✓%s tốt   %s!%s nên cân nhắc   %s✗%s có vấn đề   %s?%s chưa rõ   %s•%s thông tin\n\n' \
    "$C_GRN" "$C_RST" "$C_YEL" "$C_RST" "$C_RED" "$C_RST" "$C_YEL" "$C_RST" "$C_DIM" "$C_RST"
  ask_purchase_date
  printf 'Đang đọc thông tin máy, chờ khoảng 30 giây...\n'
  system_profiler -json SPHardwareDataType SPPowerDataType SPNVMeDataType SPCameraDataType \
    SPDisplaysDataType SPAudioDataType SPBluetoothDataType >"$SP_JSON" 2>/dev/null
  find_smartctl || printf '%sKhông tải được công cụ đọc SSD, kiểm tra lại Wi-Fi.%s\n' "$C_YEL" "$C_RST"

  check_identity
  check_ownership
  check_battery
  check_ssd
  check_stability
  if can_ask; then
    run_manual_tests
    run_stress
  fi

  write_report
  printf '\n'
  banner "$(verdict_color)" "KẾT LUẬN: $(verdict)" "$(verdict_reason)"
  print_issues
  print_final_steps
  printf '\n %sBáo cáo đã lưu:%s %s\n\n' "$C_BLD" "$C_RST" "$REPORT"
}

# Cho phép source file để test các hàm đánh giá
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
