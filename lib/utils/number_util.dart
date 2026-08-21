import 'package:decimal/decimal.dart';

class NumberUtil {
  static String formatCompact(double n, [int precision = 2]) {
    try {
      if (n >= 1e9) {
        n /= 1e9;
        return "${n.toStringAsFixed(precision)}B";
      } else if (n >= 1e6) {
        n /= 1e6;
        return "${n.toStringAsFixed(precision)}M";
      } else if (n >= 1e4) {
        n /= 1e3;
        return "${n.toStringAsFixed(precision)}K";
      } else {
        return n.toStringAsFixed(precision);
      }
    } catch (e) {
      return n.toString();
    }
  }

  // static int getDecimalLength(double b) {
  //   String s = b.toString();
  //   int dotIndex = s.indexOf(".");
  //   if (dotIndex < 0) {
  //     return 0;
  //   } else {
  //     return s.length - dotIndex - 1;
  //   }
  // }
  //
  // static int getMaxDecimalLength(double a, double b, double c, double d) {
  //   int result = max(getDecimalLength(a), getDecimalLength(b));
  //   result = max(result, getDecimalLength(c));
  //   result = max(result, getDecimalLength(d));
  //   return result;
  // }

  static bool checkNotNullOrZero(double? a) {
    if (a == null || a == 0) {
      return false;
    } else if (a.abs().toStringAsFixed(4) == "0.0000") {
      return false;
    } else {
      return true;
    }
  }

  // Ký tự ngăn hàng nghìn/thập phân dùng CHUNG cho `formatFixed`/`format` —
  // đây là STYLE HIỂN THỊ SỐ cố định của app (yêu cầu trực tiếp "check giá
  // như hình cho axis Y", mẫu Binance-style VN: "76.018,52"), KHÔNG phải i18n
  // theo ngôn ngữ user — cố tình không mượn tên 1 locale cụ thể nào (vd
  // 'vi_VN') để khỏi gây hiểu lầm với hệ i18n thật của app (package `slang`,
  // xem CLAUDE.md). Muốn đổi sang style US (`76,018.52`) chỉ cần gán lại 2
  // field này (`groupSeparator = ','`, `decimalSeparator = '.'`), không đụng
  // logic format bên dưới. Tự group hàng nghìn bằng string thuần (không qua
  // `NumberFormat`+locale của package `intl`) — không phụ thuộc bảng locale
  // của `intl` (không phải mọi locale đều được `intl` hỗ trợ ở mọi version).
  static String groupSeparator = '.';
  static String decimalSeparator = ',';

  static String? formatFixed(
    dynamic value,
    int precision, [
    String pattern = '#,##0',
  ]) {
    try {
      String number = Decimal.parse(
        value.toString(),
      ).toString(); // avoid scientific notation format e-10
      List<String> parts = number.split('.');
      String integerPart = _groupThousands(parts.first);
      if (precision == 0) {
        return integerPart;
      }
      String fractionalPart = (parts.length <= 1 ? '' : parts.last).padRight(
        precision,
        '0',
      );
      fractionalPart = fractionalPart.substring(0, precision);
      return '$integerPart$decimalSeparator$fractionalPart';
    } catch (e) {
      return null;
    }
  }

  static String? format(
    dynamic value,
    int precision, [
    String pattern = '#,##0',
  ]) {
    try {
      // avoid scientific notation format e-10
      String number = Decimal.parse(
        value.toString(),
      ).floor(scale: precision).toString();
      List<String> parts = number.split('.');
      String integerPart = _groupThousands(parts.first);
      if (precision == 0 && parts.length == 1) {
        return integerPart;
      }
      String fractionalPart = parts.last;
      return '$integerPart$decimalSeparator$fractionalPart';
    } catch (e) {
      return null;
    }
  }

  /// Chèn [groupSeparator] mỗi 3 chữ số kể từ phải sang, giữ dấu `-` (số âm)
  /// đứng ngoài phần group. [integer] là chuỗi số nguyên thuần (không dấu
  /// phân cách) từ `Decimal.toString()`.
  static String _groupThousands(String integer) {
    final bool negative = integer.startsWith('-');
    final String digits = negative ? integer.substring(1) : integer;
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(groupSeparator);
      buffer.write(digits[i]);
    }
    return negative ? '-$buffer' : buffer.toString();
  }
}
