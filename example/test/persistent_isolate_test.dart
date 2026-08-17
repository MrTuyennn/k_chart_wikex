// Regression test: worker isolate tính indicator (ChartBloc._recalculateState)
// thêm await vào các handler vốn đồng bộ trước đây → nếu không khoá tuần tự
// (_withRecalcLock), 2 event khác type chạy đồng thời (vd toggle main +
// toggle secondary indicator) có thể emit đè lên nhau, làm MẤT hẳn thay đổi
// của bên kia (không chỉ trễ 1 nhịp). Test này bắn nhiều toggle liên tiếp và
// xác nhận state cuối cùng có đủ mọi thay đổi, cộng với close() không treo.
import 'package:example/bloc/chart_bloc.dart';
import 'package:example/bloc/chart_event.dart';
import 'package:example/bloc/chart_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('worker isolate xử lý nhiều toggle liên tiếp không deadlock', () async {
    final bloc = ChartBloc();

    // Đợi state ban đầu ổn định (missing_env vì test không có dart-define).
    await Future.delayed(const Duration(milliseconds: 200));
    expect(bloc.state.error, isNotNull);

    // State mặc định TẮT hết mọi indicator (_kIndicatorsEnabledByDefault =
    // false trong ChartBloc) — nên toggle ở đây nghĩa là BẬT. Vẫn giữ nguyên
    // mục đích regression: bắn nhiều toggle event khác type dồn dập, kiểm
    // tra completer queue khớp đúng thứ tự, không mất thay đổi của nhau.
    bloc.add(const ChartMainIndicatorToggled(MainIndicatorType.boll));
    bloc.add(const ChartMainIndicatorToggled(MainIndicatorType.ema));
    bloc.add(
      const ChartSecondaryIndicatorToggled(SecondaryIndicatorType.stochRsi),
    );

    await bloc.stream.firstWhere(
      (s) =>
          s.mainTypes.contains(MainIndicatorType.ema) &&
          s.secondaryTypes.contains(SecondaryIndicatorType.stochRsi),
    );

    expect(bloc.state.mainTypes, contains(MainIndicatorType.boll));
    expect(bloc.state.mainTypes, contains(MainIndicatorType.ema));
    expect(
      bloc.state.secondaryTypes,
      contains(SecondaryIndicatorType.stochRsi),
    );

    // close() phải hoàn tất trong thời gian hợp lý — không treo do worker
    // isolate/queue.
    await bloc.close().timeout(const Duration(seconds: 5));
  });
}
